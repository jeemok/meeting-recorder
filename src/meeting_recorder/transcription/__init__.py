"""Local speech-to-text via faster-whisper."""

from .whisper import WhisperTranscriber, TranscribedSegment

__all__ = ["WhisperTranscriber", "TranscribedSegment"]
