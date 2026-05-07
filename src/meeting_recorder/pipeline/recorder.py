"""Recording session orchestrator.

A ``RecordingSession`` owns the audio file lifecycle and a Meeting object that
gets progressively filled in (audio → transcription → diarization → summary).
"""

from __future__ import annotations

import re
from datetime import datetime
from pathlib import Path

from ..audio.capture import AudioRecorder, CaptureConfig
from ..config import Config
from ..diarization import build_diarizer
from ..llm import build_client, summarize_meeting
from ..speakers.identify import align
from ..storage.markdown import Meeting, save_meeting
from ..transcription import WhisperTranscriber


def _slugify(text: str) -> str:
    text = re.sub(r"[^a-zA-Z0-9]+", "-", text.strip().lower())
    return text.strip("-")[:40] or "meeting"


def make_id(title: str, when: datetime) -> str:
    return f"{when.strftime('%Y-%m-%d-%H%M')}-{_slugify(title)}"


class RecordingSession:
    def __init__(self, title: str, config: Config):
        self.config = config
        self.started_at = datetime.now().astimezone()
        self.id = make_id(title, self.started_at)
        self.folder = config.storage_dir / self.id
        self.folder.mkdir(parents=True, exist_ok=True)
        self.audio_path = self.folder / "audio.wav"
        self.title = title

        self.recorder = AudioRecorder(
            self.audio_path,
            CaptureConfig(
                sample_rate=int(config.audio["sample_rate"]),
                channels=int(config.audio["channels"]),
                mic_device=config.audio["mic_device"],
                system_device=config.audio["system_device"],
            ),
        )

    def start(self) -> None:
        self.recorder.start()

    def stop(self) -> Path:
        return self.recorder.stop()

    @property
    def seconds_recorded(self) -> float:
        return self.recorder.seconds_recorded


def finalize_meeting(
    session: RecordingSession,
    do_summary: bool = True,
) -> Meeting:
    """Run transcription, diarization, alignment, optional summary, then save."""
    cfg = session.config
    ended_at = datetime.now().astimezone()

    transcriber = WhisperTranscriber(
        model=cfg.transcription["model"],
        device=cfg.transcription["device"],
        compute_type=cfg.transcription["compute_type"],
    )
    segments = transcriber.transcribe(session.audio_path)

    diarizer = build_diarizer(cfg.diarization)
    diar_segs = diarizer.diarize(session.audio_path)
    utterances = align(segments, diar_segs)

    # Seed speaker map with raw labels -> blank, the user fills in via UI/edit.
    speakers = {u.speaker: "" for u in utterances}

    meeting = Meeting(
        id=session.id,
        title=session.title,
        started_at=session.started_at,
        ended_at=ended_at,
        utterances=utterances,
        speakers=speakers,
        audio_path=str(session.audio_path.relative_to(cfg.storage_dir)),
    )

    if do_summary and cfg.llm.get("enabled"):
        client = build_client(cfg.llm)
        if client is not None:
            summarize_meeting(meeting, client)

    save_meeting(meeting, cfg.storage_dir)
    return meeting
