"""
Streaming ASR using Vosk for real-time meeting transcription.

Captures audio from PipeWire/PulseAudio and transcribes in real-time.
Designed for ARM64 with low latency.
"""

import os
import json
import queue
import threading
from pathlib import Path
from typing import Callable, Optional
from dataclasses import dataclass

# Vosk imports
try:
    import vosk
    VOSK_AVAILABLE = True
except ImportError:
    VOSK_AVAILABLE = False
    print("Warning: vosk not installed. Run: pip install vosk")

# Audio capture
try:
    import sounddevice as sd
    SOUNDDEVICE_AVAILABLE = True
except ImportError:
    SOUNDDEVICE_AVAILABLE = False
    print("Warning: sounddevice not installed. Run: pip install sounddevice")


# Model paths - download from https://alphacephei.com/vosk/models
VOSK_MODEL_PATH = os.getenv("VOSK_MODEL_PATH", "/app/models/vosk-model-small-en-us-0.15")
SAMPLE_RATE = 16000


@dataclass
class TranscriptSegment:
    """A transcribed segment of speech."""
    text: str
    is_final: bool
    confidence: float = 0.0


class VoskStreamingASR:
    """
    Real-time speech recognition using Vosk.

    Usage:
        asr = VoskStreamingASR()
        asr.start(on_transcript=lambda seg: print(seg.text))
        # ... meeting happens ...
        asr.stop()
    """

    def __init__(self, model_path: str = VOSK_MODEL_PATH, sample_rate: int = SAMPLE_RATE):
        if not VOSK_AVAILABLE:
            raise RuntimeError("Vosk not installed. Run: pip install vosk")
        if not SOUNDDEVICE_AVAILABLE:
            raise RuntimeError("sounddevice not installed. Run: pip install sounddevice")

        self.sample_rate = sample_rate
        self.model_path = model_path
        self.model: Optional[vosk.Model] = None
        self.recognizer: Optional[vosk.KaldiRecognizer] = None
        self._audio_queue: queue.Queue = queue.Queue()
        self._running = False
        self._stream: Optional[sd.InputStream] = None
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

    def _audio_callback(self, indata, frames, time, status):
        """Called by sounddevice for each audio chunk."""
        if status:
            print(f"Audio status: {status}")
        self._audio_queue.put(bytes(indata))

    def _process_audio(self):
        """Process audio from queue and emit transcripts."""
        while self._running:
            try:
                data = self._audio_queue.get(timeout=0.1)
            except queue.Empty:
                continue

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

    def start(self, on_transcript: Callable[[TranscriptSegment], None], device: Optional[int] = None):
        """
        Start streaming ASR.

        Args:
            on_transcript: Callback for each transcript segment
            device: Audio input device index (None for default)
        """
        self._load_model()
        self._callback = on_transcript
        self._running = True

        # Start audio capture
        self._stream = sd.InputStream(
            samplerate=self.sample_rate,
            blocksize=8000,  # 0.5 seconds at 16kHz
            device=device,
            dtype='int16',
            channels=1,
            callback=self._audio_callback
        )
        self._stream.start()

        # Start processing thread
        self._process_thread = threading.Thread(target=self._process_audio, daemon=True)
        self._process_thread.start()

        print(f"Streaming ASR started (device: {device or 'default'})")

    def stop(self):
        """Stop streaming ASR."""
        self._running = False
        if self._stream:
            self._stream.stop()
            self._stream.close()
        if self._process_thread:
            self._process_thread.join(timeout=2.0)
        print("Streaming ASR stopped.")

    def list_devices(self):
        """List available audio input devices."""
        print("\nAvailable audio devices:")
        print(sd.query_devices())


class TranscriptBuffer:
    """
    Rolling buffer of recent transcript text.

    Keeps the last N seconds of transcript for trigger decisions.
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
            # Trim old segments
            while len(self._segments) > self.max_segments:
                self._segments.pop(0)

    def get_text(self) -> str:
        """Get the full transcript buffer as text."""
        with self._lock:
            text = " ".join(self._segments)
            # Trim to max chars (keep recent)
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

    parser = argparse.ArgumentParser(description="Test Vosk streaming ASR")
    parser.add_argument("--model", default=VOSK_MODEL_PATH, help="Path to Vosk model")
    parser.add_argument("--device", type=int, default=None, help="Audio device index")
    parser.add_argument("--list-devices", action="store_true", help="List audio devices")
    parser.add_argument("--duration", type=int, default=30, help="Recording duration in seconds")
    args = parser.parse_args()

    if args.list_devices:
        if SOUNDDEVICE_AVAILABLE:
            print(sd.query_devices())
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

    asr.start(on_transcript=on_transcript, device=args.device)

    try:
        time.sleep(args.duration)
    except KeyboardInterrupt:
        print("\nInterrupted.")

    asr.stop()

    print("\n" + "=" * 50)
    print("TRANSCRIPT BUFFER:")
    print("=" * 50)
    print(buffer.get_text())
