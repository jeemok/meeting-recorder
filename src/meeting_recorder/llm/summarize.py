"""Generate a post-call summary + action items for a Meeting."""

from __future__ import annotations

import json
import re

from ..storage.markdown import Meeting
from .client import LLMClient

SYSTEM = """You are a meeting assistant. You receive a verbatim transcript with
speaker labels and produce a tight, factual summary plus action items.

Rules:
- Be concrete. Name people, decisions, dates, numbers.
- Never invent details that aren't in the transcript.
- If the transcript is too short or has no substance, say so plainly.
- Prefer present tense and active voice.
- Action items must be assigned to a specific person if the transcript names one.

Return strict JSON with this shape (no prose around it):

{
  "summary": "3-6 sentence prose summary",
  "action_items": ["...", "..."],
  "decisions": ["...", "..."],
  "open_questions": ["...", "..."]
}
"""


def _format_transcript(meeting: Meeting) -> str:
    lines: list[str] = []
    for u in meeting.utterances:
        speaker = meeting.speakers.get(u.speaker, f"Speaker {u.speaker}")
        lines.append(f"{speaker}: {u.text}")
    return "\n".join(lines)


def _extract_json(text: str) -> dict:
    # Tolerate models that wrap JSON in code fences.
    fence = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
    candidate = fence.group(1) if fence else text
    try:
        return json.loads(candidate)
    except json.JSONDecodeError:
        # Last-ditch: grab the outermost {...}.
        start = candidate.find("{")
        end = candidate.rfind("}")
        if start >= 0 and end > start:
            return json.loads(candidate[start : end + 1])
        raise


def summarize_meeting(meeting: Meeting, client: LLMClient) -> Meeting:
    """Mutates ``meeting`` in-place with summary + action_items, returns it."""
    transcript = _format_transcript(meeting)
    if not transcript.strip():
        meeting.summary = "_(empty transcript)_"
        meeting.summary_model = client.model
        return meeting

    user = (
        f"Meeting title: {meeting.title}\n"
        f"Started: {meeting.started_at.isoformat()}\n"
        f"Duration: {int(meeting.duration_seconds)}s\n"
        f"Speakers: {', '.join(meeting.speakers.values()) or 'unlabeled'}\n\n"
        f"Transcript:\n---\n{transcript}\n---"
    )
    raw = client.complete(SYSTEM, user, max_tokens=2048)
    try:
        data = _extract_json(raw)
    except Exception:
        meeting.summary = raw
        meeting.summary_model = client.model
        return meeting

    summary_parts = [data.get("summary", "").strip()]
    if data.get("decisions"):
        summary_parts.append("**Decisions:**\n" + "\n".join(f"- {d}" for d in data["decisions"]))
    if data.get("open_questions"):
        summary_parts.append(
            "**Open questions:**\n" + "\n".join(f"- {q}" for q in data["open_questions"])
        )
    meeting.summary = "\n\n".join(p for p in summary_parts if p)
    meeting.action_items = list(data.get("action_items") or [])
    meeting.summary_model = client.model
    return meeting
