#!/usr/bin/env python3
"""
Whisper Transcription Module

Uses faster-whisper for CPU-optimized speech-to-text.
"""

from pathlib import Path
from typing import Optional


def transcribe_audio(audio_path: Path, model_size: str = "small") -> dict:
    """
    Transcribe audio file using faster-whisper.

    Args:
        audio_path: Path to WAV file
        model_size: whisper model (tiny, base, small, medium, large)

    Returns:
        Dict with segments and full text
    """
    from faster_whisper import WhisperModel

    print(f"Loading Whisper model: {model_size}")

    # CPU mode for ARM64 - use int8 for speed
    model = WhisperModel(model_size, device="cpu", compute_type="int8")

    print(f"Transcribing: {audio_path}")
    segments, info = model.transcribe(
        str(audio_path),
        beam_size=1,  # Faster on CPU
        language="en",
        vad_filter=True,  # Skip silence
    )

    result = {
        "language": info.language,
        "duration": info.duration,
        "segments": []
    }

    full_text = []
    for segment in segments:
        seg_data = {
            "start": segment.start,
            "end": segment.end,
            "text": segment.text.strip()
        }
        result["segments"].append(seg_data)
        full_text.append(segment.text.strip())
        print(f"[{segment.start:.1f}s -> {segment.end:.1f}s] {segment.text.strip()}")

    result["text"] = " ".join(full_text)
    return result


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        result = transcribe_audio(Path(sys.argv[1]))
        print(f"\nFull transcript:\n{result['text']}")
