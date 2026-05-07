"""Real-time question suggestions while a meeting is in progress.

Strategy: keep a rolling window of recent transcript text, ask Claude every N
seconds for the most useful follow-up questions you (the user) could ask
right now. Cheap, stateless, easy to interrupt.

Used by ``meeting-recorder suggest --watch`` and the in-recording HUD.
"""

from __future__ import annotations

import threading
import time
from collections import deque
from dataclasses import dataclass

from .client import LLMClient

SYSTEM = """You sit beside the user during a live meeting. They show you a
rolling transcript and you suggest the *most useful* follow-up questions they
could ask right now to (a) clarify ambiguity, (b) surface risk or assumptions,
or (c) move toward a decision.

Rules:
- Output exactly 3 questions, one per line, no numbering, no preamble.
- Each question must be answerable in <=30 seconds.
- Skip questions whose answer is already obvious in the transcript.
- Prefer specific over generic ("How will Jane validate the migration?" beats
  "How will we validate this?").
- If the transcript is too thin to suggest anything, output a single line:
  "(listening...)"
"""


@dataclass
class TranscriptChunk:
    timestamp: float    # epoch seconds
    speaker: str
    text: str


class RealtimeSuggester:
    """Background thread that periodically refreshes question suggestions."""

    def __init__(
        self,
        client: LLMClient,
        interval_seconds: int = 30,
        context_window_seconds: int = 180,
    ):
        self.client = client
        self.interval = interval_seconds
        self.window = context_window_seconds
        self._buffer: deque[TranscriptChunk] = deque(maxlen=2048)
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._last: list[str] = []
        self._last_at: float = 0.0
        self._listeners: list = []

    # -- producer side ------------------------------------------------------

    def add_chunk(self, chunk: TranscriptChunk) -> None:
        with self._lock:
            self._buffer.append(chunk)

    # -- consumer side ------------------------------------------------------

    def latest(self) -> tuple[list[str], float]:
        return list(self._last), self._last_at

    def on_update(self, callback) -> None:
        self._listeners.append(callback)

    # -- lifecycle ----------------------------------------------------------

    def start(self) -> None:
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=self.interval + 5)

    # -- internals ----------------------------------------------------------

    def _recent_transcript(self) -> str:
        cutoff = time.time() - self.window
        with self._lock:
            chunks = [c for c in self._buffer if c.timestamp >= cutoff]
        return "\n".join(f"{c.speaker}: {c.text}" for c in chunks)

    def _loop(self) -> None:
        while not self._stop.wait(self.interval):
            transcript = self._recent_transcript()
            if not transcript.strip():
                continue
            try:
                raw = self.client.complete(SYSTEM, transcript, max_tokens=400)
            except Exception as e:  # noqa: BLE001
                print(f"realtime suggester error: {e}")
                continue
            qs = [line.strip("-• \t") for line in raw.splitlines() if line.strip()]
            self._last = qs
            self._last_at = time.time()
            for cb in self._listeners:
                try:
                    cb(qs)
                except Exception:  # noqa: BLE001
                    pass
