"""faster-whisper wrapper.

Wraps the WhisperModel with a stable interface so the rest of the app does
not depend on faster-whisper's specifics. Swap with another implementation
(OpenAI hosted, whisper.cpp via subprocess, etc.) by providing the same
``transcribe(path) -> list[TranscribedSegment]`` shape.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass
class TranscribedSegment:
    start: float
    end: float
    text: str


class WhisperTranscriber:
    def __init__(
        self,
        model: str = "small.en",
        device: str = "auto",
        compute_type: str = "int8",
    ):
        self.model_name = model
        self.device = device
        self.compute_type = compute_type
        self._model = None

    def _ensure_model(self):
        if self._model is None:
            from faster_whisper import WhisperModel

            self._model = WhisperModel(
                self.model_name,
                device=self.device,
                compute_type=self.compute_type,
            )
        return self._model

    def transcribe(self, audio_path: Path, language: str = "en") -> list[TranscribedSegment]:
        model = self._ensure_model()
        segments, _info = model.transcribe(
            str(audio_path),
            language=language,
            vad_filter=True,
            vad_parameters=dict(min_silence_duration_ms=500),
        )
        out: list[TranscribedSegment] = []
        for s in segments:
            text = s.text.strip()
            if not text:
                continue
            out.append(TranscribedSegment(start=float(s.start), end=float(s.end), text=text))
        return out
