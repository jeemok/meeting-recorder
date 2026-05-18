import CoreAudio
import Foundation

/// Lightweight CoreAudio HAL probe: is *any* input device on the system
/// currently running (i.e. some other process is reading the mic)?
///
/// Used by ``MeetingWatcher`` to suppress the "Detected …" prompt when
/// the meeting app is merely open but not actually in a call. Microsoft
/// Teams in particular keeps a long-lived process around between calls,
/// so the app-name check alone is a known false-positive source.
enum MicrophoneActivity {
    /// Returns true when at least one input device reports it is running
    /// somewhere on the system. Returns false on any HAL error (safer to
    /// under-prompt than to flap on transient errors).
    static func isInUse() -> Bool {
        let deviceIDs = inputDevices()
        for dev in deviceIDs {
            if isDeviceRunning(dev) { return true }
        }
        return false
    }

    private static func inputDevices() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size
        ) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devices
        ) == noErr else { return [] }
        return devices.filter(hasInputStream)
    }

    private static func hasInputStream(_ device: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr else {
            return false
        }
        return size > 0
    }

    private static func isDeviceRunning(_ device: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running) == noErr else {
            return false
        }
        return running != 0
    }
}
