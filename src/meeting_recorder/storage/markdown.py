"""Markdown <-> Meeting round-trip.

The frontmatter is the source of truth: ``speakers`` maps anonymous diarization
labels (``A``, ``B``, ...) to display names. The transcript body is rendered
from the stored utterances on save, so editing frontmatter speaker names and
re-saving is a clean operation.
"""

from __future__ import annotations

import re
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Iterable

import frontmatter
import yaml

UTTERANCE_RE = re.compile(
    r"^\*\*\[(?P<ts>\d{2}:\d{2}:\d{2})\]\s+(?P<speaker>[^:]+):\*\*\s+(?P<text>.+)$"
)


@dataclass
class Utterance:
    start: float           # seconds from recording start
    end: float
    speaker: str           # raw label, e.g. "A"
    text: str

    def display_speaker(self, speakers: dict[str, str]) -> str:
        return speakers.get(self.speaker, f"Speaker {self.speaker}")


@dataclass
class Meeting:
    id: str
    title: str
    started_at: datetime
    ended_at: datetime | None = None
    tags: list[str] = field(default_factory=list)
    speakers: dict[str, str] = field(default_factory=dict)   # "A" -> "Jane"
    summary: str = ""
    action_items: list[str] = field(default_factory=list)
    notes: str = ""
    utterances: list[Utterance] = field(default_factory=list)
    summary_model: str | None = None
    audio_path: str | None = None

    @property
    def duration_seconds(self) -> float:
        if not self.ended_at:
            return 0.0
        return (self.ended_at - self.started_at).total_seconds()


# ---------------------------------------------------------------------------
# Render
# ---------------------------------------------------------------------------

def _format_ts(seconds: float) -> str:
    seconds = max(0, int(seconds))
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    return f"{h:02d}:{m:02d}:{s:02d}"


def _render_body(m: Meeting) -> str:
    parts: list[str] = []
    if m.summary:
        parts.append("## Summary\n\n" + m.summary.strip() + "\n")
    if m.action_items:
        parts.append("## Action items\n\n" + "\n".join(f"- [ ] {a}" for a in m.action_items) + "\n")
    if m.notes.strip():
        parts.append("## Notes\n\n" + m.notes.strip() + "\n")
    parts.append("## Transcript\n")
    for u in m.utterances:
        ts = _format_ts(u.start)
        speaker = m.speakers.get(u.speaker, f"Speaker {u.speaker}")
        parts.append(f"**[{ts}] {speaker}:** {u.text.strip()}")
    return "\n\n".join(parts) + "\n"


def _frontmatter_dict(m: Meeting) -> dict:
    return {
        "id": m.id,
        "title": m.title,
        "started_at": m.started_at.isoformat(),
        "ended_at": m.ended_at.isoformat() if m.ended_at else None,
        "tags": list(m.tags),
        "speakers": dict(m.speakers),
        "summary_model": m.summary_model,
        "audio_path": m.audio_path,
    }


def save_meeting(m: Meeting, root: Path) -> Path:
    """Write ``<root>/<id>/<id>.md``. Returns the path."""
    folder = root / m.id
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"{m.id}.md"
    post = frontmatter.Post(_render_body(m), **_frontmatter_dict(m))
    # Embed raw utterance timing as a YAML block at end of body so re-load is
    # lossless even after the user renames speakers.
    raw = "\n\n<!-- meeting-recorder:utterances -->\n```yaml\n"
    raw += yaml.safe_dump([asdict(u) for u in m.utterances], sort_keys=False)
    raw += "```\n"
    post.content = post.content + raw
    path.write_text(frontmatter.dumps(post), encoding="utf-8")
    return path


# ---------------------------------------------------------------------------
# Load
# ---------------------------------------------------------------------------

_RAW_BLOCK_RE = re.compile(
    r"<!--\s*meeting-recorder:utterances\s*-->\s*```yaml\s*(?P<yaml>.*?)```",
    re.DOTALL,
)


def load_meeting(path: Path) -> Meeting:
    post = frontmatter.load(path)
    fm = post.metadata
    body = post.content

    started = _parse_dt(fm.get("started_at"))
    ended = _parse_dt(fm.get("ended_at")) if fm.get("ended_at") else None

    raw_match = _RAW_BLOCK_RE.search(body)
    utterances: list[Utterance] = []
    if raw_match:
        data = yaml.safe_load(raw_match.group("yaml")) or []
        utterances = [Utterance(**u) for u in data]
        body = body[: raw_match.start()].rstrip()

    summary, action_items, notes = _parse_sections(body)

    return Meeting(
        id=fm["id"],
        title=fm.get("title", fm["id"]),
        started_at=started,
        ended_at=ended,
        tags=list(fm.get("tags") or []),
        speakers=dict(fm.get("speakers") or {}),
        summary=summary,
        action_items=action_items,
        notes=notes,
        utterances=utterances,
        summary_model=fm.get("summary_model"),
        audio_path=fm.get("audio_path"),
    )


def _parse_dt(value) -> datetime:
    if isinstance(value, datetime):
        return value
    return datetime.fromisoformat(str(value))


def _parse_sections(body: str) -> tuple[str, list[str], str]:
    summary, notes = "", ""
    action_items: list[str] = []
    current = None
    buf: list[str] = []

    def flush():
        nonlocal summary, notes
        if current == "summary":
            summary = "\n".join(buf).strip()
        elif current == "notes":
            notes = "\n".join(buf).strip()

    for line in body.splitlines():
        if line.startswith("## "):
            flush()
            buf = []
            heading = line[3:].strip().lower()
            if heading.startswith("summary"):
                current = "summary"
            elif heading.startswith("action"):
                current = "actions"
            elif heading.startswith("notes"):
                current = "notes"
            elif heading.startswith("transcript"):
                current = "transcript"
            else:
                current = None
            continue
        if current == "actions":
            stripped = line.strip()
            if stripped.startswith(("- [ ]", "- [x]", "- [X]", "* ", "- ")):
                # Accept either checkbox or plain bullets.
                text = re.sub(r"^[-*]\s*(\[.\]\s*)?", "", stripped)
                if text:
                    action_items.append(text)
        elif current in ("summary", "notes"):
            buf.append(line)
    flush()
    return summary, action_items, notes


def list_meetings(root: Path) -> list[Meeting]:
    if not root.exists():
        return []
    out: list[Meeting] = []
    for child in sorted(root.iterdir()):
        if not child.is_dir():
            continue
        md = child / f"{child.name}.md"
        if md.exists():
            try:
                out.append(load_meeting(md))
            except Exception as e:  # noqa: BLE001
                print(f"warning: failed to load {md}: {e}")
    return out
