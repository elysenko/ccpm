#!/usr/bin/env python3
"""
Meeting Bot - Main Bot Class

Joins meetings, records audio, and transcribes using Whisper.
"""

import asyncio
import os
import subprocess
import json
from datetime import datetime
from pathlib import Path
from playwright.async_api import async_playwright

from platforms import google_meet, teams, zoom
from capture.transcribe import transcribe_audio

# Optional PostgreSQL support
try:
    import psycopg2
    from psycopg2.extras import Json
    HAS_POSTGRES = True
except ImportError:
    HAS_POSTGRES = False


class MeetingBot:
    """Bot that joins meetings, records audio, and transcribes."""

    def __init__(self, meeting_url: str, project: str, output_dir: str = "/app/output",
                 meeting_id: int = None, database_url: str = None):
        self.url = meeting_url
        self.project = project
        self.platform = self._detect_platform(meeting_url)
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.audio_file = self.output_dir / "recording.wav"
        self.ffmpeg_process = None
        self.page = None

        # Database configuration
        self.meeting_id = meeting_id
        self.database_url = database_url
        self.use_postgres = bool(database_url and meeting_id and HAS_POSTGRES)

    def _detect_platform(self, url: str) -> str:
        """Detect meeting platform from URL."""
        if "meet.google.com" in url:
            return "google_meet"
        elif "teams.microsoft.com" in url or "teams.live.com" in url:
            return "teams"
        elif "zoom.us" in url:
            return "zoom"
        raise ValueError(f"Unknown meeting platform: {url}")

    def save_transcript_to_db(self, transcript: dict) -> bool:
        """Save transcript to PostgreSQL transcriptions table."""
        if not self.use_postgres:
            print("Database not configured, skipping DB save")
            return False

        try:
            conn = psycopg2.connect(self.database_url)
            cur = conn.cursor()

            cur.execute("""
                INSERT INTO transcriptions
                    (meeting_id, full_text, segments, duration_seconds, model_used, language)
                VALUES (%s, %s, %s, %s, %s, %s)
                RETURNING id
            """, (
                self.meeting_id,
                transcript.get('text', ''),
                Json(transcript.get('segments', [])),
                transcript.get('duration', 0),
                transcript.get('model', 'small'),
                transcript.get('language', 'en')
            ))

            transcript_id = cur.fetchone()[0]
            conn.commit()
            cur.close()
            conn.close()

            print(f"Transcript saved to database (id: {transcript_id})")
            return True

        except Exception as e:
            print(f"Error saving transcript to database: {e}")
            import traceback
            traceback.print_exc()
            return False

    def start_audio_recording(self):
        """Start recording system audio via PulseAudio null-sink monitor."""
        print("Starting audio recording...")

        # Use VirtualSpeaker.monitor - this is our null-sink that captures all browser audio
        # The entrypoint.sh sets this up and exports AUDIO_SOURCE
        monitor_source = os.environ.get("AUDIO_SOURCE", "VirtualSpeaker.monitor")

        # Verify the source exists
        try:
            result = subprocess.run(
                ["pactl", "list", "short", "sources"],
                capture_output=True,
                text=True
            )
            sources = result.stdout.strip()
            print(f"  Available sources:\n{sources}")

            if monitor_source not in sources:
                print(f"  WARNING: {monitor_source} not found in sources!")
                # Try common monitor names
                for candidate in ["VirtualSpeaker.monitor", "browser_audio.monitor"]:
                    if candidate in sources:
                        monitor_source = candidate
                        print(f"  Found alternative: {monitor_source}")
                        break
                else:
                    print("  ERROR: No known monitor source available!")
                    print("  Falling back to any available monitor...")
                    # Find any monitor as last resort
                    for line in sources.split('\n'):
                        if '.monitor' in line.lower():
                            monitor_source = line.split()[1]
                            print(f"  Using fallback: {monitor_source}")
                            break
        except Exception as e:
            print(f"  Warning: Could not verify audio source: {e}")

        print(f"  Audio source: {monitor_source}")

        self.ffmpeg_process = subprocess.Popen([
            "ffmpeg", "-y",
            "-f", "pulse",
            "-i", monitor_source,
            "-ac", "1",              # Mono
            "-ar", "16000",          # 16kHz for Whisper
            "-acodec", "pcm_s16le",  # WAV format
            str(self.audio_file)
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        print(f"  Recording to: {self.audio_file}")

    def stop_audio_recording(self):
        """Stop ffmpeg recording."""
        if self.ffmpeg_process:
            self.ffmpeg_process.terminate()
            try:
                self.ffmpeg_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.ffmpeg_process.kill()

            if self.audio_file.exists():
                size = self.audio_file.stat().st_size
                print(f"Recording stopped. File size: {size:,} bytes")
            else:
                print("Warning: Recording file not found")

    async def join_and_record(self, max_duration_hours: float = 2.0) -> dict:
        """
        Join meeting, record audio, and transcribe.

        Args:
            max_duration_hours: Maximum meeting duration before auto-leaving

        Returns:
            Transcript dict with segments and full text
        """
        async with async_playwright() as p:
            # Launch browser with audio permissions
            browser = await p.chromium.launch(
                headless=False,  # Required for audio (headless mutes audio)
                args=[
                    '--no-sandbox',
                    '--disable-dev-shm-usage',
                    '--disable-gpu',
                    '--autoplay-policy=no-user-gesture-required',
                    '--use-fake-ui-for-media-stream',
                    '--disable-blink-features=AutomationControlled',
                    '--disable-features=GlobalMediaControls',
                    '--disable-notifications',
                    '--disable-setuid-sandbox',
                ]
            )

            context = await browser.new_context(
                permissions=['microphone', 'camera'],
                viewport={'width': 1920, 'height': 1080},
            )

            self.page = await context.new_page()

            # Join meeting based on platform
            print(f"\n{'='*60}")
            print(f"Joining {self.platform} meeting...")
            print(f"URL: {self.url}")
            print(f"Project: {self.project}")
            print(f"{'='*60}\n")

            if self.platform == "google_meet":
                await google_meet.join(self.page, self.url)
            elif self.platform == "teams":
                await teams.join(self.page, self.url)
            elif self.platform == "zoom":
                await zoom.join(self.page, self.url)

            # Start audio recording
            self.start_audio_recording()

            # Wait for meeting to end or timeout
            await self._wait_for_meeting_end(max_duration_hours)

            # Stop recording
            self.stop_audio_recording()

            # Leave meeting gracefully
            if self.platform == "google_meet":
                await google_meet.leave(self.page)
            elif self.platform == "teams":
                await teams.leave(self.page)
            elif self.platform == "zoom":
                await zoom.leave(self.page)

            await browser.close()

        # Transcribe with Whisper
        if self.audio_file.exists() and self.audio_file.stat().st_size > 1000:
            print("\nTranscribing with Whisper...")
            transcript = transcribe_audio(self.audio_file)

            # Save to PostgreSQL if configured
            if self.use_postgres:
                self.save_transcript_to_db(transcript)
            else:
                # Fallback: Save transcript to local files
                transcript_file = self.output_dir / "transcript.json"
                with open(transcript_file, "w") as f:
                    json.dump(transcript, f, indent=2)
                print(f"Transcript saved: {transcript_file}")

                # Also save as readable markdown
                md_file = self.output_dir / "transcript.md"
                with open(md_file, "w") as f:
                    f.write(f"# Meeting Transcript\n\n")
                    f.write(f"- **Project**: {self.project}\n")
                    f.write(f"- **Platform**: {self.platform}\n")
                    f.write(f"- **Duration**: {transcript['duration']:.1f} seconds\n")
                    f.write(f"- **Date**: {datetime.now().isoformat()}\n\n")
                    f.write("## Transcript\n\n")
                    f.write(transcript['text'])
                print(f"Markdown saved: {md_file}")

            return transcript
        else:
            print("Warning: No audio recorded or file too small")
            return {"text": "", "segments": [], "duration": 0}

    async def _wait_for_meeting_end(self, max_hours: float):
        """Wait for meeting to end or timeout."""
        check_interval = 10  # seconds
        max_checks = int(max_hours * 3600 / check_interval)

        print(f"Waiting for meeting to end (max {max_hours} hours)...")

        for i in range(max_checks):
            await asyncio.sleep(check_interval)

            # Check if meeting ended
            ended = False
            if self.platform == "google_meet":
                ended = await google_meet.is_meeting_ended(self.page)
            elif self.platform == "teams":
                ended = await teams.is_meeting_ended(self.page)
            elif self.platform == "zoom":
                ended = await zoom.is_meeting_ended(self.page)

            if ended:
                print("Meeting ended by host")
                return

            # Print progress every 5 minutes
            if i > 0 and i % 30 == 0:
                elapsed = i * check_interval / 60
                print(f"  Still in meeting... ({elapsed:.0f} min elapsed)")

        print(f"Timeout reached ({max_hours} hours)")
