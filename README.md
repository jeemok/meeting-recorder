# Meeting Recorder

A native macOS meeting recorder that **does not join your meetings**. It
captures audio from your machine (microphone + system audio), transcribes
it locally on-device, identifies speakers, and uses **your own LLM
provider** (Claude by default) for summaries and follow-up question
suggestions.

Recordings are stored as plain Markdown with YAML frontmatter — easy to
grep, version, edit by hand, or sync to your notes app.

## What's in the box

| Capability | Implementation |
|---|---|
| Mic capture | `AVAudioEngine` (mono 16 kHz PCM WAV) |
| System-audio capture | `ScreenCaptureKit` (macOS 13+, no BlackHole needed) |
| On-device transcription | `WhisperKit` (Core ML / Neural Engine) |
| Speaker diarization (optional) | Bundled Python sidecar around `pyannote.audio` |
| Summaries + question suggestions | Anthropic API (`URLSession`, no SDK) |
| Menubar control | `NSStatusItem` + auto-detect of Zoom/Teams/Webex |
| Browser & editor | SwiftUI window with live transcript view + speaker rename |
| Storage | Markdown + YAML frontmatter under `~/Library/Application Support/MeetingRecorder/meetings/` |

The only outbound network call is to Anthropic, and only if you opt into
LLM summaries.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ **or** Swift 5.9+ command-line toolchain
- An Anthropic API key (optional, only for summaries / suggestions)
- Python 3.11+ with `pyannote.audio` (optional, only for diarization)

## Quickstart

```bash
# 1. Build the app
make build-release

# 2. Open it
open mac/MeetingRecorder.app
```

That's it. On first launch the app will:

1. Ask for microphone permission.
2. Ask for screen-recording permission (used for system audio).
3. Drop a status icon in the menubar and open the main window.

The Whisper model (~150 MB for `small.en`, the default) downloads the
first time you finalize a recording.

### Anthropic API key

Set the key one of three ways:

1. **Settings → LLM → API key** (stored in the app's config file).
2. Export `ANTHROPIC_API_KEY` in your shell, then launch the app from
   that terminal.
3. Put `ANTHROPIC_API_KEY=sk-…` in
   `~/Library/Application Support/MeetingRecorder/.env`.

If no key is found, the app still records and transcribes — it just
skips the summary step.

### Diarization (optional)

Speaker diarization is the one piece without a good native Swift
equivalent, so it runs as a small Python sidecar. Skip it if you don't
need speaker labels.

```bash
make install-diarization        # creates .venv, installs pyannote.audio + torch
```

Then in **Settings → Transcription → Diarization**:

1. Enable diarization.
2. Set the Python interpreter path to
   `<project-root>/.venv/bin/python3` (or leave blank to use system
   Python).

The first diarization run downloads the `pyannote/speaker-diarization-3.1`
model and requires a one-time
[license acceptance on Hugging Face](https://huggingface.co/pyannote/speaker-diarization-3.1).
Set `HUGGING_FACE_HUB_TOKEN` in your `.env` after accepting.

Without diarization, the transcript collapses to a single speaker. You
can still rename it in the detail view.

## Day-to-day use

- **Click the menubar icon** to start, stop, or open the last meeting.
- **`⌘N`** anywhere in the app starts a new recording.
- **`⌘,`** opens Settings.
- The watcher auto-prompts when a meeting app appears, and auto-stops
  recording after 60 s of sustained silence (configurable).
- Browser-based meetings (Google Meet, Slack huddles) aren't
  auto-detected — start those manually from the menubar.

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
audio_path: 2026-05-07-1430-weekly-sync/audio.wav
---

## Summary

…AI-generated summary…

## Action items

- [ ] …

## Transcript

**[00:30:02] Me:** Hey, thanks for hopping on…
**[00:30:08] Jane Doe:** No problem…

<!-- meeting-recorder:utterances -->
```yaml
- start: 1802.5
  end: 1804.7
  speaker: A
  text: Hey, thanks for hopping on
…
```
```

The frontmatter is the source of truth. Editing speaker names in the
markdown (or the SwiftUI detail view) and saving re-renders the
transcript.

## Building from source

```bash
make build              # debug
make build-release      # optimized
make build-release-signed   # release + ad-hoc codesign for local Gatekeeper
make dmg                # release-signed + package as mac/MeetingRecorder-<version>.dmg
make run                # build and launch
make clean              # remove build artifacts
```

`make build*` runs `swift build` and assembles a `MeetingRecorder.app`
bundle in `mac/`. WhisperKit and any other SwiftPM dependencies are
fetched into `mac/.build/` on first build.

If you'd rather develop in Xcode, open `mac/Package.swift` — Xcode
treats SwiftPM packages as first-class projects (`open mac/Package.swift`).

## Configuration

User settings live in
`~/Library/Application Support/MeetingRecorder/config.json` and are
managed through **Settings**. The full schema is in
[`mac/Sources/MeetingRecorder/Config/AppConfig.swift`](mac/Sources/MeetingRecorder/Config/AppConfig.swift).
Defaults work for most setups; you only need to touch this file if you
prefer editing JSON to clicking through tabs.

Meetings are written to
`~/Library/Application Support/MeetingRecorder/meetings/` by default.
Override in **Settings → Storage**.

## Project layout

```
mac/
├── Package.swift                       # SwiftPM manifest (depends on WhisperKit)
├── Sources/MeetingRecorder/
│   ├── MeetingRecorderApp.swift        # @main
│   ├── AppDelegate.swift               # menubar install, lifecycle
│   ├── Audio/                          # AVAudioEngine + ScreenCaptureKit
│   ├── Config/                         # AppConfig + ConfigStore (JSON)
│   ├── Detection/                      # NSWorkspace-based app detection
│   ├── Diarization/                    # Python sidecar wrapper
│   ├── LLM/                            # Anthropic client + summarizer
│   ├── MenuBar/                        # NSStatusItem + watcher
│   ├── Models/                         # Meeting / Utterance Codable
│   ├── Pipeline/                       # RecordingSession + Finalizer
│   ├── Storage/                        # Markdown read/write
│   ├── Transcription/                  # WhisperKit wrapper
│   ├── ViewModels/                     # AppViewModel
│   └── Views/                          # SwiftUI screens
├── Resources/
│   ├── Info.plist                      # App metadata + permission strings
│   └── diarize_sidecar.py              # The one Python file we still need
└── build.sh                            # SwiftPM → .app bundle
```

## Privacy notes

- Audio never leaves your machine unless you opt into LLM summarization.
- Transcription is fully local (WhisperKit / Core ML).
- Diarization, when enabled, is fully local (pyannote.audio).
- The LLM module sends **transcript text only** — never raw audio.
- Disable LLM summaries entirely in Settings → LLM.

## Troubleshooting

- **"Operation not permitted" when starting a recording** — grant
  microphone and screen-recording access in **System Settings → Privacy
  & Security**. The app prompts on first launch but macOS sometimes
  swallows the prompt; re-launch after granting.
- **Whisper download is slow** — WhisperKit lazily fetches the model on
  first transcription. `small.en` is ~150 MB. Subsequent runs are offline.
- **Diarization fails with "pyannote not importable"** — install
  `pyannote.audio` into the Python you pointed Settings at, and accept
  the model license on Hugging Face.
- **System audio is silent on the recording** — make sure you granted
  screen-recording permission. Check by running
  `tccutil reset ScreenCapture ai.checkbox.MeetingRecorder` then
  relaunch.

## License

MIT. See `LICENSE`.
