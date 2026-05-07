"""``meeting-recorder`` CLI."""

from __future__ import annotations

import shutil
import signal
import sys
import time
from pathlib import Path

import typer
from rich.console import Console
from rich.live import Live
from rich.table import Table
from rich.panel import Panel

from .audio import list_input_devices
from .config import Config
from .llm import build_client, summarize_meeting
from .pipeline import RecordingSession, finalize_meeting
from .storage import list_meetings, load_meeting, save_meeting

app = typer.Typer(add_completion=False, help="Local meeting recorder.")
console = Console()


@app.command()
def devices() -> None:
    """List audio input devices (use indices in config.yaml)."""
    table = Table(title="Audio input devices")
    table.add_column("idx", justify="right")
    table.add_column("name")
    table.add_column("ch", justify="right")
    table.add_column("sr", justify="right")
    table.add_column("notes")
    for d in list_input_devices():
        notes = []
        if d.is_default:
            notes.append("default")
        if d.is_loopback_candidate():
            notes.append("loopback?")
        table.add_row(
            str(d.index),
            d.name,
            str(d.max_input_channels),
            f"{int(d.default_sample_rate)}",
            ", ".join(notes),
        )
    console.print(table)


@app.command()
def record(
    title: str = typer.Option("Untitled meeting", "--title", "-t"),
    no_summary: bool = typer.Option(False, "--no-summary"),
    config: str = typer.Option("config.yaml", "--config", "-c"),
) -> None:
    """Record audio. Press Ctrl+C to stop."""
    cfg = Config.load(config)
    session = RecordingSession(title=title, config=cfg)
    session.start()

    console.print(
        Panel.fit(
            f"[bold]Recording[/bold]\n"
            f"id: [cyan]{session.id}[/cyan]\n"
            f"title: {title}\n"
            f"audio: {session.audio_path}\n"
            f"[dim]Press Ctrl+C to stop.[/dim]",
            border_style="green",
        )
    )

    stop_requested = {"flag": False}

    def _handle_sigint(signum, frame):  # noqa: ARG001
        stop_requested["flag"] = True

    signal.signal(signal.SIGINT, _handle_sigint)

    try:
        with Live(console=console, refresh_per_second=4, transient=True) as live:
            while not stop_requested["flag"]:
                mins, secs = divmod(int(session.seconds_recorded), 60)
                live.update(f"[dim]elapsed[/dim] {mins:02d}:{secs:02d}")
                time.sleep(0.25)
    finally:
        console.print("[yellow]stopping…[/yellow]")
        session.stop()

    console.print("[bold]Transcribing & diarizing…[/bold] (this can take a minute)")
    meeting = finalize_meeting(session, do_summary=not no_summary)

    md_path = cfg.storage_dir / meeting.id / f"{meeting.id}.md"
    console.print(f"[green]done[/green] → {md_path}")
    if meeting.summary:
        console.print(Panel(meeting.summary, title="Summary", border_style="cyan"))
    if meeting.action_items:
        items = "\n".join(f"- {a}" for a in meeting.action_items)
        console.print(Panel(items, title="Action items", border_style="magenta"))


@app.command()
def summarize(meeting_id: str, config: str = typer.Option("config.yaml", "--config", "-c")) -> None:
    """(Re-)run summarization on an existing meeting."""
    cfg = Config.load(config)
    md = cfg.storage_dir / meeting_id / f"{meeting_id}.md"
    if not md.exists():
        console.print(f"[red]not found:[/red] {md}")
        raise typer.Exit(1)
    meeting = load_meeting(md)
    client = build_client(cfg.llm)
    if client is None:
        console.print("[red]llm.enabled is false in config.yaml[/red]")
        raise typer.Exit(1)
    summarize_meeting(meeting, client)
    save_meeting(meeting, cfg.storage_dir)
    console.print(f"[green]updated[/green] → {md}")


@app.command("list")
def list_cmd(config: str = typer.Option("config.yaml", "--config", "-c")) -> None:
    """List saved meetings."""
    cfg = Config.load(config)
    meetings = list_meetings(cfg.storage_dir)
    if not meetings:
        console.print("[dim]no meetings yet[/dim]")
        return
    table = Table(title=f"Meetings in {cfg.storage_dir}")
    table.add_column("id")
    table.add_column("title")
    table.add_column("started")
    table.add_column("dur")
    table.add_column("tags")
    for m in meetings:
        dur = int(m.duration_seconds)
        mins, secs = divmod(dur, 60)
        table.add_row(
            m.id,
            m.title,
            m.started_at.strftime("%Y-%m-%d %H:%M"),
            f"{mins}m{secs:02d}s",
            ",".join(m.tags),
        )
    console.print(table)


@app.command()
def suggest(
    meeting_id: str = typer.Argument(None, help="Existing meeting to analyze. Omit for help."),
    config: str = typer.Option("config.yaml", "--config", "-c"),
) -> None:
    """Generate follow-up questions for an existing transcript.

    For *live* suggestions during a recording, see the web UI (`serve`).
    """
    cfg = Config.load(config)
    if not meeting_id:
        console.print(
            "Pass a meeting id, or open the web UI ([cyan]meeting-recorder serve[/cyan])"
            " for live in-recording suggestions."
        )
        raise typer.Exit(0)
    md = cfg.storage_dir / meeting_id / f"{meeting_id}.md"
    if not md.exists():
        console.print(f"[red]not found:[/red] {md}")
        raise typer.Exit(1)
    meeting = load_meeting(md)
    client = build_client(cfg.llm)
    if client is None:
        console.print("[red]llm.enabled is false[/red]")
        raise typer.Exit(1)
    transcript = "\n".join(
        f"{meeting.speakers.get(u.speaker, u.speaker)}: {u.text}" for u in meeting.utterances
    )
    from .llm.realtime import SYSTEM as RT_SYSTEM

    raw = client.complete(RT_SYSTEM, transcript, max_tokens=400)
    console.print(Panel(raw, title="Follow-up questions", border_style="cyan"))


@app.command()
def serve(
    config: str = typer.Option("config.yaml", "--config", "-c"),
    host: str = typer.Option(None, "--host"),
    port: int = typer.Option(None, "--port"),
) -> None:
    """Run the local web UI for browsing and editing meetings."""
    import uvicorn

    cfg = Config.load(config)
    h = host or cfg.ui["host"]
    p = port or cfg.ui["port"]
    # Lazy import so plain CLI use does not require fastapi at import time.
    from .ui.server import build_app

    fastapi_app = build_app(cfg)
    console.print(f"[green]→ http://{h}:{p}[/green]")
    uvicorn.run(fastapi_app, host=h, port=p, log_level="warning")


@app.command()
def doctor(config: str = typer.Option("config.yaml", "--config", "-c")) -> None:
    """Check that ffmpeg, audio devices, and the LLM key are usable."""
    cfg = Config.load(config)
    ok = True

    def check(label: str, cond: bool, hint: str = ""):
        nonlocal ok
        mark = "[green]✓[/green]" if cond else "[red]✗[/red]"
        ok = ok and cond
        line = f"{mark} {label}"
        if not cond and hint:
            line += f"\n   [dim]{hint}[/dim]"
        console.print(line)

    check("ffmpeg on PATH", shutil.which("ffmpeg") is not None,
          "brew install ffmpeg  # or apt install ffmpeg")
    try:
        from .audio import list_input_devices as _l
        check("audio devices visible", len(_l()) > 0, "no input devices found")
    except Exception as e:  # noqa: BLE001
        check("audio devices visible", False, str(e))

    if cfg.llm.get("enabled"):
        try:
            client = build_client(cfg.llm)
            check("LLM client constructible", client is not None,
                  "set ANTHROPIC_API_KEY in .env")
        except Exception as e:  # noqa: BLE001
            check("LLM client constructible", False, str(e))
    else:
        console.print("[dim]llm.enabled is false; skipping[/dim]")

    check("storage dir writable", cfg.storage_dir.parent.exists() or cfg.storage_dir.exists(),
          f"check {cfg.storage_dir}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    app()
