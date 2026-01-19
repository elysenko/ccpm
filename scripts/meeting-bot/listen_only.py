#!/usr/bin/env python3
"""
Listen-Only Meeting Bot

Joins a meeting, transcribes in real-time, and logs when it WOULD respond.
Does NOT actually speak - this is for testing the trigger logic.

Usage:
    python listen_only.py --url "https://meet.google.com/xxx-yyyy-zzz"

    # With custom trigger threshold
    python listen_only.py --url "..." --threshold 0.6

    # Test mode (no meeting, just microphone)
    python listen_only.py --test
"""

import os
import sys
import asyncio
import argparse
import time
import threading
from datetime import datetime
from pathlib import Path

# Add parent to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from stream_asr_ffmpeg import VoskStreamingASR, TranscriptBuffer, TranscriptSegment, VOSK_AVAILABLE
from trigger import TriggerClient, TriggerDecision, OLLAMA_URL, TRIGGER_MODEL

# Configuration
TRIGGER_INTERVAL = float(os.getenv("TRIGGER_INTERVAL", "5.0"))  # Check every 5 seconds
LOG_FILE = os.getenv("LOG_FILE", "/tmp/meeting-bot-listen.log")


class ListenOnlyBot:
    """
    Meeting bot that listens and logs trigger decisions without speaking.
    """

    def __init__(
        self,
        meeting_url: str = None,
        trigger_threshold: float = 0.7,
        trigger_interval: float = TRIGGER_INTERVAL,
        vosk_model_path: str = None,
    ):
        self.meeting_url = meeting_url
        self.trigger_threshold = trigger_threshold
        self.trigger_interval = trigger_interval

        # Components
        self.asr: VoskStreamingASR = None
        self.buffer = TranscriptBuffer(max_chars=2000)
        self.trigger = TriggerClient(threshold=trigger_threshold)

        # State
        self._running = False
        self._trigger_thread: threading.Thread = None
        self._decisions: list[dict] = []

        # Vosk model path
        self.vosk_model_path = vosk_model_path or os.getenv(
            "VOSK_MODEL_PATH", "/app/models/vosk-model-small-en-us-0.15"
        )

    def _log(self, message: str, level: str = "INFO"):
        """Log message to console and file."""
        timestamp = datetime.now().strftime("%H:%M:%S")
        line = f"[{timestamp}] [{level}] {message}"
        print(line)

        # Also write to log file
        try:
            with open(LOG_FILE, "a") as f:
                f.write(line + "\n")
        except Exception:
            pass

    def _on_transcript(self, segment: TranscriptSegment):
        """Handle incoming transcript segment."""
        if segment.is_final:
            self._log(f"TRANSCRIPT: {segment.text}", "ASR")
        self.buffer.add(segment)

    def _trigger_loop(self):
        """Periodically check if bot should respond."""
        last_check = time.time()

        while self._running:
            time.sleep(0.5)  # Check every 500ms if it's time

            now = time.time()
            if now - last_check < self.trigger_interval:
                continue

            last_check = now

            # Get current transcript buffer
            transcript = self.buffer.get_text()
            if not transcript or len(transcript) < 20:
                continue  # Not enough text yet

            # Check trigger
            try:
                decision = self.trigger.should_respond(transcript)
                self._log_decision(decision, transcript)
            except Exception as e:
                self._log(f"Trigger error: {e}", "ERROR")

    def _log_decision(self, decision: TriggerDecision, transcript: str):
        """Log trigger decision."""
        record = {
            "timestamp": datetime.now().isoformat(),
            "should_respond": decision.should_respond,
            "confidence": decision.confidence,
            "latency_ms": decision.latency_ms,
            "transcript_snippet": transcript[-200:] if len(transcript) > 200 else transcript,
        }
        self._decisions.append(record)

        if decision.should_respond:
            self._log(
                f">>> WOULD RESPOND (confidence: {decision.confidence:.2f}, "
                f"latency: {decision.latency_ms:.0f}ms)",
                "TRIGGER"
            )
            self._log(f"    Context: ...{transcript[-150:]}", "TRIGGER")
        else:
            self._log(
                f"    Silent (confidence: {decision.confidence:.2f}, "
                f"latency: {decision.latency_ms:.0f}ms)",
                "TRIGGER"
            )

    def start_listening(self, audio_source: str = "default"):
        """Start ASR and trigger checking (no meeting join)."""
        self._log("Starting listen-only mode...")

        # Initialize ASR
        if not VOSK_AVAILABLE:
            self._log("Vosk not available. Install with: pip install vosk", "ERROR")
            return False

        try:
            self.asr = VoskStreamingASR(model_path=self.vosk_model_path)
        except FileNotFoundError as e:
            self._log(str(e), "ERROR")
            self._log("Download model from: https://alphacephei.com/vosk/models", "ERROR")
            return False

        # Check Ollama connection
        self._log(f"Checking Ollama at {OLLAMA_URL}...")
        if not self.trigger.health_check():
            self._log(f"Ollama not reachable or model not loaded", "WARN")
            self._log("Trigger decisions will fail. Continue anyway.", "WARN")
            # In automated mode, continue anyway
        else:
            self._log(f"Ollama OK (model: {TRIGGER_MODEL})")
            warmup = self.trigger.warm_up()
            self._log(f"Trigger warmup: {warmup:.0f}ms")

        # Start ASR
        self._running = True
        self.asr.start(on_transcript=self._on_transcript, audio_source=audio_source)

        # Start trigger loop
        self._trigger_thread = threading.Thread(target=self._trigger_loop, daemon=True)
        self._trigger_thread.start()

        self._log("Listening... Press Ctrl+C to stop.")
        return True

    def stop_listening(self):
        """Stop ASR and trigger checking."""
        self._running = False
        if self.asr:
            self.asr.stop()
        if self._trigger_thread:
            self._trigger_thread.join(timeout=2.0)
        self._log("Stopped listening.")

    def print_summary(self):
        """Print summary of trigger decisions."""
        print("\n" + "=" * 60)
        print("SESSION SUMMARY")
        print("=" * 60)

        total = len(self._decisions)
        would_respond = sum(1 for d in self._decisions if d["should_respond"])
        avg_latency = (
            sum(d["latency_ms"] for d in self._decisions) / total
            if total > 0 else 0
        )

        print(f"Total trigger checks: {total}")
        print(f"Would have responded: {would_respond} times")
        print(f"Average trigger latency: {avg_latency:.0f}ms")

        if would_respond > 0:
            print("\nRespond moments:")
            for d in self._decisions:
                if d["should_respond"]:
                    print(f"  [{d['timestamp'][11:19]}] conf={d['confidence']:.2f}")
                    print(f"    \"{d['transcript_snippet'][-80:]}...\"")

        print("=" * 60)

    async def join_meeting_and_listen(self, audio_source: str = "default"):
        """Join meeting with Playwright and listen."""
        from playwright.async_api import async_playwright

        self._log(f"Joining meeting: {self.meeting_url}")

        async with async_playwright() as p:
            browser = await p.chromium.launch(
                headless=False,  # Need real browser for audio
                args=[
                    '--use-fake-ui-for-media-stream',
                    '--autoplay-policy=no-user-gesture-required',
                    '--disable-blink-features=AutomationControlled',
                ]
            )
            context = await browser.new_context(
                permissions=['microphone', 'camera'],
            )
            page = await context.new_page()

            # Navigate to meeting
            await page.goto(self.meeting_url)
            self._log("Page loaded, attempting to join...")

            # Platform-specific join logic
            if "meet.google.com" in self.meeting_url:
                await self._join_google_meet(page)
            elif "teams.microsoft.com" in self.meeting_url:
                await self._join_teams(page)
            else:
                self._log(f"Unknown platform, trying generic join", "WARN")

            # Start ASR listening
            if not self.start_listening(audio_source):
                await browser.close()
                return

            # Wait until meeting ends or interrupted
            try:
                while self._running:
                    await asyncio.sleep(1)
                    # Check if we've left the meeting
                    if await self._check_meeting_ended(page):
                        self._log("Meeting ended.")
                        break
            except asyncio.CancelledError:
                self._log("Cancelled.")

            self.stop_listening()
            await browser.close()

        self.print_summary()

    async def _join_google_meet(self, page):
        """Join Google Meet."""
        try:
            # Dismiss popups
            await page.click('button:has-text("Got it")', timeout=3000)
        except:
            pass

        try:
            # Turn off camera and mic
            await page.click('[aria-label*="camera"]', timeout=5000)
            await page.click('[aria-label*="microphone"]', timeout=5000)
        except:
            self._log("Could not toggle camera/mic", "WARN")

        # Enter name if prompted
        try:
            name_input = page.locator('input[aria-label="Your name"]')
            if await name_input.is_visible(timeout=3000):
                await name_input.fill("CCPM Bot (Listen-Only)")
        except:
            pass

        # Click join
        try:
            await page.click('button:has-text("Join now")', timeout=10000)
            self._log("Joined Google Meet!")
        except:
            await page.click('button:has-text("Ask to join")', timeout=5000)
            self._log("Requested to join (waiting for approval)...")

        # Wait for meeting UI
        await asyncio.sleep(3)

    async def _join_teams(self, page):
        """Join Microsoft Teams."""
        # Use web version params
        if "?" in self.meeting_url:
            self.meeting_url += "&msLaunch=false&directDl=true&suppressPrompt=true"
        else:
            self.meeting_url += "?msLaunch=false&directDl=true&suppressPrompt=true"

        await page.goto(self.meeting_url)

        try:
            await page.click('button:has-text("Continue on this browser")', timeout=10000)
        except:
            pass

        try:
            name_input = page.locator('input[data-tid="prejoin-display-name-input"]')
            if await name_input.is_visible(timeout=5000):
                await name_input.fill("CCPM Bot (Listen-Only)")
        except:
            pass

        try:
            await page.click('button:has-text("Join now")', timeout=10000)
            self._log("Joined Teams!")
        except:
            self._log("Could not find Join button", "WARN")

    async def _check_meeting_ended(self, page) -> bool:
        """Check if meeting has ended."""
        try:
            # Google Meet
            ended = await page.locator('text="You left the meeting"').is_visible(timeout=100)
            if ended:
                return True
            ended = await page.locator('text="Call ended"').is_visible(timeout=100)
            if ended:
                return True
        except:
            pass
        return False


def main():
    parser = argparse.ArgumentParser(description="Listen-only meeting bot")
    parser.add_argument("--url", help="Meeting URL (Google Meet, Teams, Zoom)")
    parser.add_argument("--test", action="store_true", help="Test mode (no meeting, just mic)")
    parser.add_argument("--threshold", type=float, default=0.7, help="Trigger threshold (0-1)")
    parser.add_argument("--interval", type=float, default=5.0, help="Trigger check interval (seconds)")
    parser.add_argument("--device", type=int, default=None, help="Audio device index")
    parser.add_argument("--list-devices", action="store_true", help="List audio devices")
    parser.add_argument("--model", help="Path to Vosk model")
    parser.add_argument("--file", help="Test with audio file instead of live mic")
    args = parser.parse_args()

    if args.list_devices:
        try:
            import sounddevice as sd
            print(sd.query_devices())
        except ImportError:
            print("sounddevice not installed")
        return

    bot = ListenOnlyBot(
        meeting_url=args.url,
        trigger_threshold=args.threshold,
        trigger_interval=args.interval,
        vosk_model_path=args.model,
    )

    if args.test or args.file:
        # Test mode - listen to microphone or audio file
        print("=" * 60)
        if args.file:
            print(f"TEST MODE - Processing audio file: {args.file}")
        else:
            print("TEST MODE - Listening to microphone (no meeting)")
        print(f"Trigger threshold: {args.threshold}")
        print(f"Check interval: {args.interval}s")
        print("=" * 60)

        # Use file as audio source if provided
        audio_source = args.file if args.file else "default"
        if not bot.start_listening(audio_source=audio_source):
            sys.exit(1)

        try:
            if args.file:
                # For file, wait until processing completes
                while bot._running and bot.asr._ffmpeg_proc and bot.asr._ffmpeg_proc.poll() is None:
                    time.sleep(0.5)
                time.sleep(2)  # Let final transcripts process
            else:
                while True:
                    time.sleep(1)
        except KeyboardInterrupt:
            print("\nStopping...")

        bot.stop_listening()
        bot.print_summary()

    elif args.url:
        # Join meeting and listen
        asyncio.run(bot.join_meeting_and_listen(audio_source="default"))

    else:
        parser.print_help()
        print("\nExamples:")
        print("  python listen_only.py --test                    # Test with microphone")
        print("  python listen_only.py --url https://meet.google.com/xxx")
        print("  python listen_only.py --list-devices            # Show audio devices")


if __name__ == "__main__":
    main()
