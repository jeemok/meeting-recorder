"""Config loading. Reads ``config.yaml`` (if present) and ``.env`` from CWD."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml
from dotenv import load_dotenv

DEFAULTS: dict[str, Any] = {
    "audio": {
        "sample_rate": 16000,
        "channels": 1,
        "mic_device": None,
        "system_device": None,
    },
    "transcription": {
        "model": "small.en",
        "device": "auto",
        "compute_type": "int8",
    },
    "diarization": {
        "enabled": False,
        "model": "pyannote/speaker-diarization-3.1",
        "min_speakers": 1,
        "max_speakers": 6,
    },
    "llm": {
        "enabled": True,
        "provider": "anthropic",
        "model": "claude-opus-4-7",
        "realtime": {
            "enabled": True,
            "interval_seconds": 30,
            "context_window_seconds": 180,
        },
    },
    "storage": {"dir": "./meetings"},
    "ui": {"host": "127.0.0.1", "port": 8765},
}


def _deep_merge(base: dict, overrides: dict) -> dict:
    out = dict(base)
    for k, v in overrides.items():
        if k in out and isinstance(out[k], dict) and isinstance(v, dict):
            out[k] = _deep_merge(out[k], v)
        else:
            out[k] = v
    return out


@dataclass
class Config:
    raw: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def load(cls, path: str | Path | None = None) -> "Config":
        load_dotenv()
        cfg = dict(DEFAULTS)
        candidate = Path(path) if path else Path("config.yaml")
        if candidate.exists():
            with candidate.open() as f:
                user = yaml.safe_load(f) or {}
            cfg = _deep_merge(cfg, user)
        env_dir = os.environ.get("MEETING_RECORDER_DIR")
        if env_dir:
            cfg["storage"]["dir"] = env_dir
        env_model = os.environ.get("MEETING_RECORDER_MODEL")
        if env_model:
            cfg["llm"]["model"] = env_model
        return cls(raw=cfg)

    # Convenience accessors -------------------------------------------------
    @property
    def audio(self) -> dict[str, Any]:
        return self.raw["audio"]

    @property
    def transcription(self) -> dict[str, Any]:
        return self.raw["transcription"]

    @property
    def diarization(self) -> dict[str, Any]:
        return self.raw["diarization"]

    @property
    def llm(self) -> dict[str, Any]:
        return self.raw["llm"]

    @property
    def storage_dir(self) -> Path:
        return Path(self.raw["storage"]["dir"]).expanduser().resolve()

    @property
    def ui(self) -> dict[str, Any]:
        return self.raw["ui"]
