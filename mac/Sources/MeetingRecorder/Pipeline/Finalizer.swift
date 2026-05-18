import Foundation

/// Runs after the recording stops: transcribe → diarize → align → summarize → save.
struct Finalizer {
    let config: AppConfig
    let store: MeetingStore

    func finalize(session: RecordingSession, doSummary: Bool = true) async throws -> Meeting {
        let endedAt = Date()
        let transcriber = Transcriber(modelName: config.transcription.model, useANE: config.transcription.useANE)
        let segments = try await transcriber.transcribe(audioURL: session.audioURL)

        let diarSegments = await runDiarization(audioURL: session.audioURL)
        let utterances = align(transcribed: segments, diarized: diarSegments)
        let speakers = Dictionary(uniqueKeysWithValues: Set(utterances.map { $0.speaker }).map { ($0, "") })

        var meeting = Meeting(
            id: session.id,
            title: await session.title,
            startedAt: await session.startedAt,
            endedAt: endedAt,
            speakers: speakers,
            utterances: utterances,
            audioPath: "\(session.id)/audio.wav"
        )

        if doSummary && config.llm.enabled,
           let apiKey = AnthropicClient.resolveAPIKey(from: config) {
            let client = AnthropicClient(apiKey: apiKey, model: config.llm.model)
            try? await Summarizer(client: client).summarize(&meeting)
        }

        try store.save(meeting)
        return meeting
    }

    private func runDiarization(audioURL: URL) async -> [DiarizationSegment] {
        guard config.diarization.enabled,
              let service = DiarizationService.bundled(pythonPath: config.diarization.pythonPath)
        else { return [] }
        do {
            return try await service.diarize(
                audioURL: audioURL,
                minSpeakers: config.diarization.minSpeakers,
                maxSpeakers: config.diarization.maxSpeakers
            )
        } catch {
            FileHandle.standardError.write(Data("[diarization] failed, falling back to single speaker: \(error.localizedDescription)\n".utf8))
            return []
        }
    }

    /// Assigns a diarization speaker label to each whisper segment based on
    /// maximum temporal overlap. Falls back to a single ``A`` speaker when
    /// no diarization is available.
    private func align(transcribed: [TranscribedSegment], diarized: [DiarizationSegment]) -> [Utterance] {
        if diarized.isEmpty {
            return transcribed.map { Utterance(start: $0.start, end: $0.end, speaker: "A", text: $0.text) }
        }
        return transcribed.map { seg in
            var bestLabel = "A"
            var bestOverlap = 0.0
            for d in diarized {
                let overlap = max(0, min(seg.end, d.end) - max(seg.start, d.start))
                if overlap > bestOverlap {
                    bestOverlap = overlap
                    bestLabel = d.speaker
                }
            }
            return Utterance(start: seg.start, end: seg.end, speaker: bestLabel, text: seg.text)
        }
    }
}
