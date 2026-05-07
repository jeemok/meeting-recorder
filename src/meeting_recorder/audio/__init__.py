"""Audio capture.

Two streams can be active at once: the microphone and a system-audio loopback
device (e.g. BlackHole on macOS). They are mixed down to mono and written to a
single WAV file. The recorder is non-blocking; ``stop()`` flushes the buffer.
"""

from .capture import AudioRecorder
from .devices import list_input_devices, default_input_device

__all__ = ["AudioRecorder", "list_input_devices", "default_input_device"]
