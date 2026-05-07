"""Quick smoke check: imports the package and prints what's available.

    python scripts/check_setup.py
"""

from __future__ import annotations

import importlib
import sys


MODULES = [
    "meeting_recorder",
    "meeting_recorder.config",
    "meeting_recorder.audio",
    "meeting_recorder.audio.devices",
    "meeting_recorder.audio.capture",
    "meeting_recorder.transcription",
    "meeting_recorder.transcription.whisper",
    "meeting_recorder.diarization",
    "meeting_recorder.diarization.pyannote_diar",
    "meeting_recorder.speakers",
    "meeting_recorder.speakers.identify",
    "meeting_recorder.llm",
    "meeting_recorder.llm.client",
    "meeting_recorder.llm.summarize",
    "meeting_recorder.llm.realtime",
    "meeting_recorder.storage",
    "meeting_recorder.storage.markdown",
    "meeting_recorder.pipeline",
    "meeting_recorder.pipeline.recorder",
    "meeting_recorder.ui",
    "meeting_recorder.ui.server",
    "meeting_recorder.cli",
]


def main() -> int:
    failed = []
    for name in MODULES:
        try:
            importlib.import_module(name)
            print(f"  ok  {name}")
        except Exception as e:  # noqa: BLE001
            print(f"  FAIL {name}: {e}")
            failed.append(name)
    if failed:
        print(f"\n{len(failed)} module(s) failed to import")
        return 1
    print("\nall modules import cleanly")
    return 0


if __name__ == "__main__":
    sys.exit(main())
