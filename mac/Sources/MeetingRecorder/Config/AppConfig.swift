import Foundation

/// All persisted user-facing settings. Mirrors the legacy ``config.yaml``
/// structure so existing recordings keep working.
struct AppConfig: Codable, Equatable {
    var audio: AudioConfig = .init()
    var transcription: TranscriptionConfig = .init()
    var diarization: DiarizationConfig = .init()
    var llm: LLMConfig = .init()
    var storage: StorageConfig = .init()
    var watch: WatchConfig = .init()

    struct AudioConfig: Codable, Equatable {
        var sampleRate: Int = 16_000
        var channels: Int = 1
        /// AVAudioEngine input device UID. nil = system default mic.
        var micDeviceUID: String? = nil
        /// If true, also capture system audio via ScreenCaptureKit (macOS 13+).
        var captureSystemAudio: Bool = true
    }

    struct TranscriptionConfig: Codable, Equatable {
        /// WhisperKit model variant. Larger = slower but more accurate.
        var model: String = "openai_whisper-small.en"
        /// Use Apple Neural Engine when available.
        var useANE: Bool = true
    }

    struct DiarizationConfig: Codable, Equatable {
        var enabled: Bool = false
        var minSpeakers: Int = 1
        var maxSpeakers: Int = 6
        /// Absolute path to a python interpreter that has pyannote installed.
        /// nil = look for ``python3`` on PATH.
        var pythonPath: String? = nil
    }

    struct LLMConfig: Codable, Equatable {
        var enabled: Bool = true
        var model: String = "claude-opus-4-7"
        /// nil = read ANTHROPIC_API_KEY from environment / keychain.
        var apiKey: String? = nil
        var realtimeEnabled: Bool = true
        var realtimeIntervalSeconds: Double = 30
        var realtimeContextSeconds: Double = 180
    }

    struct StorageConfig: Codable, Equatable {
        /// Where meeting markdown folders are written. Default is
        /// ``~/Library/Application Support/MeetingRecorder/meetings``.
        var directoryPath: String = defaultStorageDir().path
    }

    struct WatchConfig: Codable, Equatable {
        var enabled: Bool = true
        var pollSeconds: Double = 5.0
        var dismissCooldownSeconds: Double = 300
        var silenceRMSThreshold: Double = 0.005
        var silenceGraceSeconds: Double = 60
        var meetingProcesses: [String] = [
            "CptHost",
            "zoom.us",
            "FaceTime",
            "Microsoft Teams",
            "Webex",
        ]
    }
}

/// On-disk config storage. JSON, lives under
/// ``~/Library/Application Support/MeetingRecorder/config.json``.
final class ConfigStore {
    private let url: URL
    private let queue = DispatchQueue(label: "ai.checkbox.MeetingRecorder.config")

    init(url: URL = ConfigStore.defaultURL) {
        self.url = url
    }

    static var defaultURL: URL {
        appSupportDir().appendingPathComponent("config.json")
    }

    func load() -> AppConfig {
        queue.sync {
            guard let data = try? Data(contentsOf: url),
                  let cfg = try? JSONDecoder().decode(AppConfig.self, from: data)
            else { return AppConfig() }
            return cfg
        }
    }

    func save(_ config: AppConfig) throws {
        try queue.sync {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: url, options: .atomic)
        }
    }
}

func appSupportDir() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = base.appendingPathComponent("MeetingRecorder", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

func defaultStorageDir() -> URL {
    let dir = appSupportDir().appendingPathComponent("meetings", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
