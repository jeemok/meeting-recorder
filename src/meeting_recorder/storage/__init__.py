"""Markdown-on-disk storage for meetings.

Each meeting lives in ``<storage_dir>/<id>/`` and contains:

    audio.wav          raw capture (kept until you delete it)
    <id>.md            transcript + summary + frontmatter (the source of truth)

The markdown frontmatter is the only metadata store -- editing it by hand
is a fully supported workflow.
"""

from .markdown import Meeting, Utterance, load_meeting, save_meeting, list_meetings

__all__ = ["Meeting", "Utterance", "load_meeting", "save_meeting", "list_meetings"]
