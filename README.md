# Meeting Recorder

A local, privacy-first meeting recorder that **does not join your meetings**.
It captures audio from your machine (microphone + system audio), transcribes it
locally with Whisper, identifies speakers, and uses **your own LLM provider**
(Claude by default) for summarization and real-time question suggestions.

Recordings are stored as plain Markdown files with YAML frontmatter, so they're
easy to grep, version, edit by hand, or sync to your notes app.

## Features

| Capability | Module | Notes |
|---|---|---|
| Mic + system audio capture | `audio/` | Cross-platform mic; macOS system audio via BlackHole |
| Local speech-to-text | `transcription/` | `faster-whisper`, runs offline |
| Speaker diarization | `diarization/` | `pyannote.audio` (optional, gracefully degrades) |
| Speaker re-labeling | `speakers/` | Map `Speaker A` → real names; persists across re-opens |
| Real-time question suggestions | `llm/realtime.py` | Streams rolling transcript to Claude during the call |
| Post-call AI summary | `llm/summarize.py` | Decisions, action items, follow-ups |
| Markdown storage | `storage/` | Editable: title, datetime range, tags, speaker map, notes |
| Web UI for editing | `ui/` | Tiny FastAPI app to browse/edit meeting markdown files |
| CLI | `cli.py` | `record`, `summarize`, `list`, `serve` |

Everything runs on your machine. The only outbound network call is to your
chosen LLM provider, and only if you opt into summarization / real-time
suggestions.

## Quickstart

### 1. Install

Requires Python 3.11+. `ffmpeg` is recommended (the `doctor` command checks
for it), but not strictly required: audio capture writes WAV directly via
`soundfile`, and `faster-whisper` 1.x decodes audio with `pyav`. Install
`ffmpeg` if you plan to feed in non-WAV recordings.

```bash
# from the project root
make install                     # creates .venv and installs the package

# Optional but useful:
make install-dev                 # adds pytest, ruff
make install-diarization         # adds pyannote.audio + torch

# Optional ffmpeg (only needed for non-WAV inputs):
brew install ffmpeg              # macOS
# or: sudo apt install ffmpeg
```

> Prefer raw commands? `python -m venv .venv && source .venv/bin/activate && pip install -e .` works too. Run `make help` to see all targets.

### 2. Configure

```bash
cp .env.example .env
# edit .env and set ANTHROPIC_API_KEY=...
cp config.example.yaml config.yaml
```

### 2a. Verify the install

```bash
make doctor                      # checks ffmpeg, audio devices, API key
make test                        # runs the storage round-trip tests
```

`doctor` will flag `ffmpeg` as missing if you skipped it; that's fine for
the default capture-to-WAV path.

### 3. (macOS) Enable system-audio capture (optional)

By default the recorder listens to your microphone only. To also capture the
**other side** of a meeting (Zoom, Meet, Teams) without joining as a bot:

1. Install [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole)
   (`brew install blackhole-2ch`).
2. Open **Audio MIDI Setup** → create a *Multi-Output Device* combining your
   speakers + BlackHole, set it as system output during meetings.
3. Run `make devices` and note the BlackHole input index.
4. Set `audio.system_device` in `config.yaml`.

Linux users can use `pactl` loopback or `pavucontrol` to route a monitor source.
Windows users can enable "Stereo Mix" or use VB-CABLE.

### 4. Record

```bash
# Start a recording. Press Ctrl+C to stop.
make record TITLE="Weekly sync with Jane"

# Post-hoc question suggestions for an existing meeting (optional):
make suggest ID=2026-05-07-1430-weekly-sync
```

When you stop, the recorder will:

1. Save raw audio to `meetings/<id>/audio.wav`
2. Transcribe locally
3. Diarize and label speakers (`Speaker A`, `Speaker B`, ...)
4. Generate a summary with Claude
5. Write `meetings/<id>/<id>.md` with editable frontmatter

### 5. Edit & browse

```bash
# Open the local web UI to rename speakers, fix titles, add tags, etc.
make serve
# → http://localhost:8765
```

Or just edit the markdown file directly in your editor of choice.

## Markdown format

```markdown
---
id: 2026-05-07-1430-weekly-sync
title: Weekly sync with Jane
started_at: 2026-05-07T14:30:00-04:00
ended_at:   2026-05-07T15:02:11-04:00
tags: [1on1, planning]
speakers:
  A: Me
  B: Jane Doe
summary_model: claude-opus-4-7
---

## Summary

…AI-generated summary…

## Action items

- [ ] …

## Transcript

**[14:30:02] Me:** Hey, thanks for hopping on…
**[14:30:08] Jane Doe:** No problem…
```

The frontmatter is the source of truth. Renaming `B: Jane Doe` and saving will
re-render the transcript on next load.

## Project layout

```
src/meeting_recorder/
├── audio/          # capture + device enumeration
├── transcription/  # faster-whisper wrapper
├── diarization/    # pyannote wrapper (optional)
├── speakers/       # speaker label management
├── llm/            # Claude client, summarize, real-time questions
├── storage/        # markdown <-> dataclass round-trip
├── pipeline/       # orchestrates capture → transcribe → diarize → store
├── ui/             # FastAPI editing UI
└── cli.py          # entry point
```

Each subpackage has a single, narrow responsibility and a small public
interface (see its `__init__.py`). Swap any of them — e.g., point
`transcription/` at OpenAI's hosted Whisper, or replace `llm/` with a local
model — without touching the rest.

## Command reference

```
make devices                  # list audio inputs
make record TITLE="..."       # record a meeting
make suggest ID=<id>          # post-hoc questions for an existing meeting
make summarize ID=<id>        # (re-)generate summary for a meeting
make list                     # list saved meetings
make serve                    # web UI for editing (http://localhost:8765)
make dev                      # web UI with --reload
make doctor                   # check ffmpeg / models / API key
```

`make help` lists every target. Each one shells out to `.venv/bin/meeting-recorder`,
so the underlying CLI is still available if you'd rather call it directly.

## Troubleshooting

- **`make serve` returns HTTP 500 with `TypeError: unhashable
  type: 'dict'`** — your `starlette` is on the new `TemplateResponse(request,
  name, context)` signature. The shipped UI (`ui/server.py`) already uses it;
  if you're on an older checkout, pass `request` as the first positional arg
  to every `templates.TemplateResponse(...)` call.
- **`pip install` fails on `pyannote.audio` / `torch`** — diarization is an
  optional extra. Skip it (`pip install -e .` without `[diarization]`); the
  recorder falls back to `Speaker A`, `Speaker B`, ... labels.
- **Whisper model download is slow on first run** — `faster-whisper` lazily
  downloads the model (`small.en` ≈ 466 MB) into the Hugging Face cache the
  first time you `record` or `summarize`. Subsequent runs are offline.
- **Quick repo smoke check** — `python scripts/check_setup.py` imports every
  submodule and reports failures without touching audio devices or the LLM.

## Privacy notes

- Audio never leaves your machine unless you opt into LLM summarization.
- Transcription is fully local (`faster-whisper`).
- Diarization is fully local (`pyannote.audio`, requires accepting their
  Hugging Face license once).
- The LLM module sends **transcript text only** — never raw audio.
- Set `llm.enabled: false` in `config.yaml` to disable all outbound calls.

## License

MIT. See `LICENSE`.
