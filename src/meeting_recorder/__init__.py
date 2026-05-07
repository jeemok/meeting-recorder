"""Local meeting recorder with diarization, AI summary, and real-time questions.

Sub-packages map 1:1 to capabilities:

    audio/          mic + system-audio capture
    transcription/  speech-to-text (faster-whisper)
    diarization/    speaker segmentation (pyannote, optional)
    speakers/       speaker label management
    llm/            Claude client, summary, real-time questions
    storage/        markdown <-> Meeting dataclass round-trip
    pipeline/       end-to-end recording orchestrator
    ui/             tiny FastAPI editing UI
"""

__version__ = "0.1.0"
