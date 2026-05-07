"""Enumerate audio input devices via PortAudio (sounddevice)."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class AudioDevice:
    index: int
    name: str
    max_input_channels: int
    default_sample_rate: float
    is_default: bool = False

    def is_loopback_candidate(self) -> bool:
        n = self.name.lower()
        return any(k in n for k in ("blackhole", "loopback", "stereo mix", "vb-cable", "monitor"))


def list_input_devices() -> list[AudioDevice]:
    import sounddevice as sd

    default_in = sd.default.device[0] if sd.default.device else -1
    devices: list[AudioDevice] = []
    for i, d in enumerate(sd.query_devices()):
        if d.get("max_input_channels", 0) <= 0:
            continue
        devices.append(
            AudioDevice(
                index=i,
                name=d["name"],
                max_input_channels=int(d["max_input_channels"]),
                default_sample_rate=float(d["default_samplerate"]),
                is_default=(i == default_in),
            )
        )
    return devices


def default_input_device() -> AudioDevice | None:
    for d in list_input_devices():
        if d.is_default:
            return d
    return None
