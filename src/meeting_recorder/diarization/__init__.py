"""Speaker diarization (who-spoke-when).

Optional. Requires ``pip install -e ".[diarization]"`` and a Hugging Face
token (``HF_TOKEN``) plus accepting the pyannote license once. If disabled or
unavailable, the pipeline assigns a single speaker label.
"""

from .pyannote_diar import DiarizationSegment, PyannoteDiarizer, NullDiarizer, build_diarizer

__all__ = [
    "DiarizationSegment",
    "PyannoteDiarizer",
    "NullDiarizer",
    "build_diarizer",
]
