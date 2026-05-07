"""Diarization backend.

The ``Diarizer`` protocol is intentionally tiny: ``diarize(path) -> list[Segment]``.
``NullDiarizer`` is the default; ``PyannoteDiarizer`` is opt-in.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol


@dataclass
class DiarizationSegment:
    start: float
    end: float
    speaker: str  # "A", "B", ...


class Diarizer(Protocol):
    def diarize(self, audio_path: Path) -> list[DiarizationSegment]: ...


class NullDiarizer:
    """No diarization: a single speaker covers the whole recording."""

    def diarize(self, audio_path: Path) -> list[DiarizationSegment]:
        import soundfile as sf

        with sf.SoundFile(str(audio_path)) as f:
            duration = len(f) / f.samplerate
        return [DiarizationSegment(start=0.0, end=float(duration), speaker="A")]


class PyannoteDiarizer:
    def __init__(
        self,
        model: str = "pyannote/speaker-diarization-3.1",
        min_speakers: int = 1,
        max_speakers: int = 6,
        hf_token: str | None = None,
    ):
        self.model = model
        self.min_speakers = min_speakers
        self.max_speakers = max_speakers
        self.hf_token = hf_token or os.environ.get("HF_TOKEN")
        self._pipeline = None

    def _ensure_pipeline(self):
        if self._pipeline is None:
            from pyannote.audio import Pipeline

            if not self.hf_token:
                raise RuntimeError(
                    "Pyannote diarization requires HF_TOKEN. Set it in .env or "
                    "disable diarization in config.yaml."
                )
            self._pipeline = Pipeline.from_pretrained(self.model, use_auth_token=self.hf_token)
        return self._pipeline

    def diarize(self, audio_path: Path) -> list[DiarizationSegment]:
        pipeline = self._ensure_pipeline()
        annotation = pipeline(
            str(audio_path),
            min_speakers=self.min_speakers,
            max_speakers=self.max_speakers,
        )
        # Map pyannote's "SPEAKER_00", "SPEAKER_01", ... to "A", "B", ...
        label_map: dict[str, str] = {}
        next_idx = 0
        out: list[DiarizationSegment] = []
        for turn, _, speaker in annotation.itertracks(yield_label=True):
            if speaker not in label_map:
                label_map[speaker] = chr(ord("A") + next_idx)
                next_idx += 1
            out.append(
                DiarizationSegment(
                    start=float(turn.start),
                    end=float(turn.end),
                    speaker=label_map[speaker],
                )
            )
        return out


def build_diarizer(cfg: dict) -> Diarizer:
    """Factory honoring the config block."""
    if not cfg.get("enabled"):
        return NullDiarizer()
    try:
        return PyannoteDiarizer(
            model=cfg.get("model", "pyannote/speaker-diarization-3.1"),
            min_speakers=int(cfg.get("min_speakers", 1)),
            max_speakers=int(cfg.get("max_speakers", 6)),
        )
    except ImportError:
        print("warning: pyannote.audio not installed; falling back to single speaker.")
        return NullDiarizer()
