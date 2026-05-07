"""Speaker label management.

Diarization yields anonymous labels (``A``, ``B``, ...). This module aligns
transcription segments with diarization segments and provides helpers for
re-labeling those tags to real names.
"""

from .identify import align, rename_speaker

__all__ = ["align", "rename_speaker"]
