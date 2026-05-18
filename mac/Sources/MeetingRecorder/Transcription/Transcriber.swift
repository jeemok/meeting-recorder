import Foundation
import WhisperKit

struct TranscribedSegment: Hashable {
    var start: Double
    var end: Double
    var text: String
}

/// Wraps WhisperKit for one-shot transcription of a WAV file.
actor Transcriber {
    private var pipeline: WhisperKit?
    private let modelName: String
    private let useANE: Bool

    init(modelName: String, useANE: Bool) {
        self.modelName = modelName
        self.useANE = useANE
    }

    /// Loads the model if not already loaded. First call downloads the
    /// chosen model variant into the system cache (a few hundred MB).
    private func ensureLoaded() async throws -> WhisperKit {
        if let pipeline { return pipeline }
        let cfg = WhisperKitConfig(
            model: modelName,
            computeOptions: ModelComputeOptions(
                audioEncoderCompute: useANE ? .cpuAndNeuralEngine : .cpuAndGPU,
                textDecoderCompute: useANE ? .cpuAndNeuralEngine : .cpuAndGPU
            ),
            verbose: false,
            logLevel: .none,
            prewarm: true,
            load: true,
            download: true
        )
        let pipeline = try await WhisperKit(cfg)
        self.pipeline = pipeline
        return pipeline
    }

    func transcribe(audioURL: URL) async throws -> [TranscribedSegment] {
        let pipeline = try await ensureLoaded()
        let results = try await pipeline.transcribe(audioPath: audioURL.path)
        var out: [TranscribedSegment] = []
        for result in results {
            for seg in result.segments {
                let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                out.append(TranscribedSegment(start: Double(seg.start), end: Double(seg.end), text: text))
            }
        }
        return out
    }
}
