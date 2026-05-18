import Foundation

/// Owns the audio recorder + meeting metadata for one in-progress recording.
@MainActor
final class RecordingSession: ObservableObject {
    @Published private(set) var startedAt: Date
    @Published private(set) var elapsedSeconds: Double = 0
    @Published var title: String

    let id: String
    let audioURL: URL
    private let recorder: AudioRecorder
    private let config: AppConfig
    private var tickTask: Task<Void, Never>?

    init(title: String, config: AppConfig, store: MeetingStore) throws {
        let now = Date()
        let id = Meeting.makeID(title: title, when: now)
        let audioURL = store.audioURL(for: id)
        try FileManager.default.createDirectory(at: audioURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        self.title = title
        self.startedAt = now
        self.id = id
        self.audioURL = audioURL
        self.config = config
        self.recorder = AudioRecorder(
            outputURL: audioURL,
            config: AudioRecorder.Config(
                sampleRate: Double(config.audio.sampleRate),
                captureSystemAudio: config.audio.captureSystemAudio
            )
        )
    }

    func start() throws {
        try recorder.start()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self else { return }
                await MainActor.run {
                    // Wall-clock elapsed; independent of how many frames the
                    // audio pipeline has flushed to disk so the UI keeps
                    // ticking even when system-audio capture stalls.
                    self.elapsedSeconds = Date().timeIntervalSince(self.startedAt)
                }
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        recorder.stop()
    }

    func secondsSilent(threshold: Double) -> Double {
        recorder.secondsSilent(threshold: threshold)
    }
}
