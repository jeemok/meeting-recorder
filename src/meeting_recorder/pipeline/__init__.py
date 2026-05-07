"""End-to-end orchestration: capture → transcribe → diarize → align → store."""

from .recorder import RecordingSession, finalize_meeting

__all__ = ["RecordingSession", "finalize_meeting"]
