"""Round-trip a Meeting through markdown and back."""

from datetime import datetime, timezone
from pathlib import Path

from meeting_recorder.storage import Meeting, Utterance, save_meeting, load_meeting


def test_roundtrip(tmp_path: Path):
    started = datetime(2026, 5, 7, 14, 30, tzinfo=timezone.utc)
    ended = datetime(2026, 5, 7, 15, 2, 11, tzinfo=timezone.utc)
    m = Meeting(
        id="2026-05-07-1430-test",
        title="Round-trip test",
        started_at=started,
        ended_at=ended,
        tags=["test", "roundtrip"],
        speakers={"A": "Me", "B": "Jane"},
        summary="Short summary.",
        action_items=["Ship it", "Tell ops"],
        notes="Side notes.",
        utterances=[
            Utterance(start=0.0, end=2.5, speaker="A", text="Hi Jane."),
            Utterance(start=2.6, end=5.0, speaker="B", text="Hello."),
        ],
        summary_model="claude-opus-4-7",
    )

    save_meeting(m, tmp_path)
    md_path = tmp_path / m.id / f"{m.id}.md"
    assert md_path.exists()

    loaded = load_meeting(md_path)
    assert loaded.id == m.id
    assert loaded.title == m.title
    assert loaded.tags == m.tags
    assert loaded.speakers == m.speakers
    assert loaded.summary.startswith("Short summary")
    assert loaded.action_items == m.action_items
    assert loaded.notes == m.notes
    assert len(loaded.utterances) == 2
    assert loaded.utterances[0].text == "Hi Jane."
    assert loaded.utterances[1].speaker == "B"


def test_speaker_rename_re_renders(tmp_path: Path):
    m = Meeting(
        id="2026-05-07-1430-rename",
        title="Rename",
        started_at=datetime(2026, 5, 7, 14, 30, tzinfo=timezone.utc),
        speakers={"A": ""},
        utterances=[Utterance(start=0.0, end=1.0, speaker="A", text="Hi.")],
    )
    save_meeting(m, tmp_path)
    md = tmp_path / m.id / f"{m.id}.md"
    loaded = load_meeting(md)
    loaded.speakers["A"] = "Yunliu"
    save_meeting(loaded, tmp_path)
    text = md.read_text()
    assert "Yunliu" in text
