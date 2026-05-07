"""FastAPI editing UI.

Endpoints:
    GET  /                     -- list of meetings
    GET  /m/{id}                -- view + edit form for one meeting
    POST /m/{id}                -- save edits
    POST /m/{id}/summarize      -- (re-)run summary
"""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, Form, Request, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

from ..config import Config
from ..llm import build_client, summarize_meeting
from ..storage import list_meetings, load_meeting, save_meeting

TEMPLATES_DIR = Path(__file__).parent / "templates"


def build_app(config: Config) -> FastAPI:
    app = FastAPI(title="meeting-recorder")
    templates = Jinja2Templates(directory=str(TEMPLATES_DIR))

    def _md_path(meeting_id: str) -> Path:
        return config.storage_dir / meeting_id / f"{meeting_id}.md"

    @app.get("/", response_class=HTMLResponse)
    def index(request: Request):
        meetings = list_meetings(config.storage_dir)
        meetings.sort(key=lambda m: m.started_at, reverse=True)
        return templates.TemplateResponse(
            request,
            "index.html",
            {"meetings": meetings, "storage_dir": str(config.storage_dir)},
        )

    @app.get("/m/{meeting_id}", response_class=HTMLResponse)
    def view(meeting_id: str, request: Request):
        path = _md_path(meeting_id)
        if not path.exists():
            raise HTTPException(404)
        meeting = load_meeting(path)
        return templates.TemplateResponse(
            request,
            "meeting.html",
            {"m": meeting},
        )

    @app.post("/m/{meeting_id}")
    async def save(meeting_id: str, request: Request):
        path = _md_path(meeting_id)
        if not path.exists():
            raise HTTPException(404)
        meeting = load_meeting(path)
        form = await request.form()

        meeting.title = form.get("title", meeting.title).strip() or meeting.title
        meeting.tags = [t.strip() for t in form.get("tags", "").split(",") if t.strip()]
        started = form.get("started_at", "").strip()
        ended = form.get("ended_at", "").strip()
        if started:
            meeting.started_at = datetime.fromisoformat(started)
        if ended:
            meeting.ended_at = datetime.fromisoformat(ended)
        meeting.summary = form.get("summary", meeting.summary)
        meeting.notes = form.get("notes", meeting.notes)
        meeting.action_items = [
            a.strip() for a in form.get("action_items", "").splitlines() if a.strip()
        ]

        # Speaker renames: form fields look like ``speaker_A``, ``speaker_B``...
        for key in list(meeting.speakers.keys()):
            field_name = f"speaker_{key}"
            if field_name in form:
                meeting.speakers[key] = form[field_name].strip()

        save_meeting(meeting, config.storage_dir)
        return RedirectResponse(f"/m/{meeting_id}", status_code=303)

    @app.post("/m/{meeting_id}/summarize")
    def resummarize(meeting_id: str):
        path = _md_path(meeting_id)
        if not path.exists():
            raise HTTPException(404)
        client = build_client(config.llm)
        if client is None:
            raise HTTPException(400, "llm.enabled is false in config.yaml")
        meeting = load_meeting(path)
        summarize_meeting(meeting, client)
        save_meeting(meeting, config.storage_dir)
        return RedirectResponse(f"/m/{meeting_id}", status_code=303)

    return app
