"""Background audio capture to a WAV file.

Designed to run on a CLI thread: ``start()`` returns immediately, ``stop()``
flushes and closes the file. Optionally captures two streams in parallel
(mic + system loopback) and mixes them.
"""

from __future__ import annotations

import queue
import threading
from contextlib import suppress
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import numpy as np


@dataclass
class CaptureConfig:
    sample_rate: int = 16000
    channels: int = 1
    mic_device: Optional[int] = None
    system_device: Optional[int] = None  # BlackHole / Stereo Mix / monitor source
    block_seconds: float = 0.5


class AudioRecorder:
    """Records mic (+ optional system-audio) to a WAV file in the background."""

    def __init__(self, output_path: Path, config: CaptureConfig):
        self.output_path = Path(output_path)
        self.config = config
        self._mic_q: queue.Queue[np.ndarray] = queue.Queue()
        self._sys_q: queue.Queue[np.ndarray] = queue.Queue()
        self._writer_thread: threading.Thread | None = None
        self._stop_event = threading.Event()
        self._mic_stream = None
        self._sys_stream = None
        self._frames_written = 0

    # ---- public API -------------------------------------------------------

    def start(self) -> None:
        import sounddevice as sd

        sr = self.config.sample_rate
        block = max(1, int(self.config.block_seconds * sr))

        def mic_cb(indata, frames, time_info, status):  # noqa: ARG001
            if status:
                # Drop xruns silently; warn to stderr would spam during capture.
                pass
            self._mic_q.put(indata.copy())

        def sys_cb(indata, frames, time_info, status):  # noqa: ARG001
            if status:
                pass
            self._sys_q.put(indata.copy())

        self._mic_stream = sd.InputStream(
            samplerate=sr,
            channels=1,
            blocksize=block,
            device=self.config.mic_device,
            dtype="float32",
            callback=mic_cb,
        )
        self._mic_stream.start()

        if self.config.system_device is not None:
            self._sys_stream = sd.InputStream(
                samplerate=sr,
                channels=1,
                blocksize=block,
                device=self.config.system_device,
                dtype="float32",
                callback=sys_cb,
            )
            self._sys_stream.start()

        self._writer_thread = threading.Thread(target=self._writer_loop, daemon=True)
        self._writer_thread.start()

    def stop(self) -> Path:
        self._stop_event.set()
        for s in (self._mic_stream, self._sys_stream):
            if s is not None:
                with suppress(Exception):
                    s.stop()
                    s.close()
        if self._writer_thread:
            self._writer_thread.join(timeout=5)
        return self.output_path

    @property
    def seconds_recorded(self) -> float:
        return self._frames_written / float(self.config.sample_rate)

    # ---- internals --------------------------------------------------------

    def _writer_loop(self) -> None:
        import soundfile as sf

        sr = self.config.sample_rate
        with sf.SoundFile(
            str(self.output_path),
            mode="w",
            samplerate=sr,
            channels=1,
            subtype="PCM_16",
        ) as f:
            while not (self._stop_event.is_set() and self._mic_q.empty() and self._sys_q.empty()):
                try:
                    mic_block = self._mic_q.get(timeout=0.2)
                except queue.Empty:
                    continue
                if self._sys_stream is not None:
                    try:
                        sys_block = self._sys_q.get(timeout=0.2)
                    except queue.Empty:
                        sys_block = np.zeros_like(mic_block)
                    n = min(len(mic_block), len(sys_block))
                    mixed = (mic_block[:n].flatten() + sys_block[:n].flatten()) * 0.5
                else:
                    mixed = mic_block.flatten()
                # Light clip protection.
                np.clip(mixed, -1.0, 1.0, out=mixed)
                f.write(mixed.astype(np.float32))
                self._frames_written += len(mixed)
