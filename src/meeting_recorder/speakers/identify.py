"""Align transcription segments with diarization segments.

For each transcribed segment we pick the diarization speaker whose interval
overlaps it the most. If there's no overlap (rare), we pick the closest by
midpoint. Output is a list of ``Utterance`` records keyed by raw label.
"""

from __future__ import annotations

from ..diarization import DiarizationSegment
from ..storage.markdown import Meeting, Utterance
from ..transcription import TranscribedSegment


def _best_speaker(seg: TranscribedSegment, diar: list[DiarizationSegment]) -> str:
    if not diar:
        return "A"
    best_label = diar[0].speaker
    best_overlap = -1.0
    for d in diar:
        overlap = max(0.0, min(seg.end, d.end) - max(seg.start, d.start))
        if overlap > best_overlap:
            best_overlap = overlap
            best_label = d.speaker
    if best_overlap > 0:
        return best_label
    # No overlap -- nearest by midpoint distance.
    mid = (seg.start + seg.end) / 2
    return min(diar, key=lambda d: abs(((d.start + d.end) / 2) - mid)).speaker


def align(
    transcription: list[TranscribedSegment],
    diarization: list[DiarizationSegment],
) -> list[Utterance]:
    return [
        Utterance(
            start=t.start,
            end=t.end,
            speaker=_best_speaker(t, diarization),
            text=t.text,
        )
        for t in transcription
    ]


def rename_speaker(meeting: Meeting, label: str, name: str) -> Meeting:
    """In-place: set ``meeting.speakers[label] = name``."""
    meeting.speakers[label] = name.strip()
    return meeting
