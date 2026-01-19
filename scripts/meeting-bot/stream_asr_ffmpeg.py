"""
Streaming ASR using Vosk with FFmpeg audio capture.

Uses ffmpeg to capture from PipeWire/PulseAudio and pipes to Vosk.
Works on ARM64 without PortAudio.
"""

import os
import json
import queue
import subprocess
import threading
from typing import Callable, Optional
from dataclasses import dataclass
from pathlib import Path

try:
    import vosk
    VOSK_AVAILABLE = True
except ImportError:
    VOSK_AVAILABLE = False
    print("Warning: vosk not installed. Run: pip install vosk")


VOSK_MODEL_PATH = os.getenv("VOSK_MODEL_PATH", "/home/ubuntu/ccpm/scripts/meeting-bot/models/vosk-model-small-en-us-0.15")
SAMPLE_RATE = 16000


@dataclass
class TranscriptSegment:
    """A transcribed segment of speech."""
    text: str
    is_final: bool
    confidence: float = 0.0


class VoskStreamingASR:
    """
    Real-time speech recognition using Vosk + FFmpeg.

    Captures audio from PulseAudio/PipeWire using ffmpeg and transcribes with Vosk.
    """

    def __init__(self, model_path: str = VOSK_MODEL_PATH, sample_rate: int = SAMPLE_RATE):
        if not VOSK_AVAILABLE:
            raise RuntimeError("Vosk not installed. Run: pip install vosk")

        self.sample_rate = sample_rate
        self.model_path = model_path
        self.model: Optional[vosk.Model] = None
        self.recognizer: Optional[vosk.KaldiRecognizer] = None
        self._running = False
        self._ffmpeg_proc: Optional[subprocess.Popen] = None
        self._process_thread: Optional[threading.Thread] = None
        self._callback: Optional[Callable[[TranscriptSegment], None]] = None

    def _load_model(self):
        """Load Vosk model (lazy loading)."""
        if self.model is None:
            if not Path(self.model_path).exists():
                raise FileNotFoundError(
                    f"Vosk model not found at {self.model_path}. "
                    f"Download from https://alphacephei.com/vosk/models"
                )
            print(f"Loading Vosk model from {self.model_path}...")
            vosk.SetLogLevel(-1)  # Suppress Vosk logs
            self.model = vosk.Model(self.model_path)
            self.recognizer = vosk.KaldiRecognizer(self.model, self.sample_rate)
            self.recognizer.SetWords(True)
            print("Vosk model loaded.")

    def _process_audio(self):
        """Read audio from ffmpeg and transcribe."""
        while self._running and self._ffmpeg_proc:
            # Read chunk from ffmpeg stdout
            data = self._ffmpeg_proc.stdout.read(8000)  # 0.5s at 16kHz, 16-bit
            if not data:
                break

            if self.recognizer.AcceptWaveform(data):
                # Final result for this utterance
                result = json.loads(self.recognizer.Result())
                text = result.get("text", "").strip()
                if text and self._callback:
                    self._callback(TranscriptSegment(
                        text=text,
                        is_final=True,
                        confidence=1.0
                    ))
            else:
                # Partial result
                partial = json.loads(self.recognizer.PartialResult())
                text = partial.get("partial", "").strip()
                if text and self._callback:
                    self._callback(TranscriptSegment(
                        text=text,
                        is_final=False,
                        confidence=0.5
                    ))

    def start(self, on_transcript: Callable[[TranscriptSegment], None], audio_source: str = "default"):
        """
        Start streaming ASR.

        Args:
            on_transcript: Callback for each transcript segment
            audio_source: PulseAudio source name, or path to audio file for testing
        """
        self._load_model()
        self._callback = on_transcript
        self._running = True

        # Check if audio_source is a file (for testing)
        if Path(audio_source).exists():
            # Read from audio file
            print(f"Reading from audio file: {audio_source}")
            self._ffmpeg_proc = subprocess.Popen([
                "ffmpeg",
                "-i", audio_source,       # Input file
                "-ac", "1",               # Mono
                "-ar", str(self.sample_rate),  # 16kHz
                "-f", "s16le",            # Raw 16-bit PCM
                "-acodec", "pcm_s16le",
                "-loglevel", "error",
                "-"                       # Output to stdout
            ], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        else:
            # Start ffmpeg to capture audio from PulseAudio/PipeWire
            # Output: 16kHz mono 16-bit PCM to stdout
            self._ffmpeg_proc = subprocess.Popen([
                "ffmpeg",
                "-f", "pulse",           # PulseAudio/PipeWire input
                "-i", audio_source,      # Source (default = system default)
                "-ac", "1",              # Mono
                "-ar", str(self.sample_rate),  # 16kHz
                "-f", "s16le",           # Raw 16-bit PCM
                "-acodec", "pcm_s16le",
                "-loglevel", "error",    # Suppress ffmpeg output
                "-"                      # Output to stdout
            ], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

        # Start processing thread
        self._process_thread = threading.Thread(target=self._process_audio, daemon=True)
        self._process_thread.start()

        print(f"Streaming ASR started (source: {audio_source})")

    def stop(self):
        """Stop streaming ASR."""
        self._running = False
        if self._ffmpeg_proc:
            self._ffmpeg_proc.terminate()
            self._ffmpeg_proc.wait()
        if self._process_thread:
            self._process_thread.join(timeout=2.0)
        print("Streaming ASR stopped.")


class TranscriptBuffer:
    """
    Rolling buffer of recent transcript text.
    """

    def __init__(self, max_chars: int = 2000, max_segments: int = 50):
        self.max_chars = max_chars
        self.max_segments = max_segments
        self._segments: list[str] = []
        self._lock = threading.Lock()

    def add(self, segment: TranscriptSegment):
        """Add a transcript segment (only final segments are kept)."""
        if not segment.is_final:
            return

        with self._lock:
            self._segments.append(segment.text)
            while len(self._segments) > self.max_segments:
                self._segments.pop(0)

    def get_text(self) -> str:
        """Get the full transcript buffer as text."""
        with self._lock:
            text = " ".join(self._segments)
            if len(text) > self.max_chars:
                text = text[-self.max_chars:]
            return text

    def clear(self):
        """Clear the buffer."""
        with self._lock:
            self._segments.clear()


# --- CLI for testing ---

if __name__ == "__main__":
    import argparse
    import time

    parser = argparse.ArgumentParser(description="Test Vosk streaming ASR with FFmpeg")
    parser.add_argument("--model", default=VOSK_MODEL_PATH, help="Path to Vosk model")
    parser.add_argument("--source", default="default", help="PulseAudio source name")
    parser.add_argument("--duration", type=int, default=30, help="Recording duration in seconds")
    parser.add_argument("--list-sources", action="store_true", help="List PulseAudio sources")
    args = parser.parse_args()

    if args.list_sources:
        print("\nPulseAudio sources:")
        subprocess.run(["pactl", "list", "sources", "short"])
        exit(0)

    # Create ASR and buffer
    asr = VoskStreamingASR(model_path=args.model)
    buffer = TranscriptBuffer()

    def on_transcript(seg: TranscriptSegment):
        buffer.add(seg)
        marker = "✓" if seg.is_final else "..."
        print(f"[{marker}] {seg.text}")

    print(f"\nListening for {args.duration} seconds...")
    print("Speak into your microphone.\n")

    asr.start(on_transcript=on_transcript, audio_source=args.source)

    try:
        time.sleep(args.duration)
    except KeyboardInterrupt:
        print("\nInterrupted.")

    asr.stop()

    print("\n" + "=" * 50)
    print("TRANSCRIPT BUFFER:")
    print("=" * 50)
    print(buffer.get_text())
