#!/usr/bin/env python3
"""Speaker diarization sidecar.

The Swift app shells out to this script for the one piece of the pipeline
that has no good native equivalent: pyannote.audio's speaker diarization
model. Everything else (capture, transcription, summarization, storage,
UI) lives in Swift.

Contract
--------
* stdin: a single JSON object: ``{"audio_path": str, "min_speakers": int, "max_speakers": int}``
* stdout: a single JSON object: ``{"segments": [{"start": float, "end": float, "speaker": "A"|"B"|…}]}``
* exit 0 on success, non-zero with a human-readable error on stderr otherwise.

The script accepts ``--check`` to verify pyannote is importable without
loading the model — used by the Settings → Diagnostics screen.

Requires ``pyannote.audio`` and a Hugging Face token in
``HUGGING_FACE_HUB_TOKEN`` (one-time license acceptance for
``pyannote/speaker-diarization-3.1``).
"""

from __future__ import annotations

import json
import os
import string
import sys


def _check() -> int:
    try:
        import pyannote.audio  # noqa: F401
    except Exception as e:  # noqa: BLE001
        sys.stderr.write(f"pyannote.audio not importable: {e}\n")
        return 1
    print(json.dumps({"ok": True}))
    return 0


def _diarize(payload: dict) -> int:
    audio_path = payload["audio_path"]
    min_speakers = int(payload.get("min_speakers", 1))
    max_speakers = int(payload.get("max_speakers", 6))

    if not os.path.exists(audio_path):
        sys.stderr.write(f"audio not found: {audio_path}\n")
        return 2

    try:
        from pyannote.audio import Pipeline
    except Exception as e:  # noqa: BLE001
        sys.stderr.write(f"pyannote import failed: {e}\n")
        return 3

    hf_token = os.environ.get("HUGGING_FACE_HUB_TOKEN") or os.environ.get("HF_TOKEN")
    pipeline = Pipeline.from_pretrained(
        "pyannote/speaker-diarization-3.1",
        use_auth_token=hf_token,
    )

    diarization = pipeline(
        audio_path,
        min_speakers=min_speakers,
        max_speakers=max_speakers,
    )

    # Map raw pyannote speaker IDs to A, B, C, …
    label_map: dict[str, str] = {}
    alphabet = string.ascii_uppercase
    segments: list[dict] = []
    for turn, _, speaker in diarization.itertracks(yield_label=True):
        if speaker not in label_map:
            label_map[speaker] = alphabet[len(label_map) % len(alphabet)]
        segments.append({
            "start": float(turn.start),
            "end": float(turn.end),
            "speaker": label_map[speaker],
        })
    print(json.dumps({"segments": segments}))
    return 0


def main() -> int:
    if "--check" in sys.argv:
        return _check()
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as e:
        sys.stderr.write(f"invalid JSON on stdin: {e}\n")
        return 64
    return _diarize(payload)


if __name__ == "__main__":
    sys.exit(main())
