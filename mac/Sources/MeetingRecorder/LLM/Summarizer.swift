import Foundation

/// Post-call summarization. Mutates ``meeting.summary``, ``action_items``,
/// and ``summary_model``.
struct Summarizer {
    let client: AnthropicClient

    private static let systemPrompt = """
    You are a meeting assistant. You receive a verbatim transcript with
    speaker labels and produce a tight, factual summary plus action items.

    Rules:
    - Be concrete. Name people, decisions, dates, numbers.
    - Never invent details that aren't in the transcript.
    - If the transcript is too short or has no substance, say so plainly.
    - Prefer present tense and active voice.
    - Action items must be assigned to a specific person if the transcript names one.

    Return strict JSON with this shape (no prose around it):

    {
      "summary": "3-6 sentence prose summary",
      "action_items": ["...", "..."],
      "decisions": ["...", "..."],
      "open_questions": ["...", "..."]
    }
    """

    func summarize(_ meeting: inout Meeting) async throws {
        let transcript = meeting.utterances.map { u in
            "\(u.displaySpeaker(in: meeting.speakers)): \(u.text)"
        }.joined(separator: "\n")

        if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            meeting.summary = "_(empty transcript)_"
            meeting.summaryModel = client.model
            return
        }

        let user = """
        Meeting title: \(meeting.title)
        Started: \(ISO8601DateFormatter().string(from: meeting.startedAt))
        Duration: \(Int(meeting.durationSeconds))s
        Speakers: \(meeting.speakers.values.joined(separator: ", ").isEmpty ? "unlabeled" : meeting.speakers.values.joined(separator: ", "))

        Transcript:
        ---
        \(transcript)
        ---
        """

        let raw = try await client.complete(system: Self.systemPrompt, user: user, maxTokens: 2048)
        if let parsed = Self.extractJSON(raw) {
            var parts: [String] = []
            if let s = parsed["summary"] as? String, !s.isEmpty { parts.append(s) }
            if let decisions = parsed["decisions"] as? [String], !decisions.isEmpty {
                parts.append("**Decisions:**\n" + decisions.map { "- \($0)" }.joined(separator: "\n"))
            }
            if let opens = parsed["open_questions"] as? [String], !opens.isEmpty {
                parts.append("**Open questions:**\n" + opens.map { "- \($0)" }.joined(separator: "\n"))
            }
            meeting.summary = parts.joined(separator: "\n\n")
            meeting.actionItems = (parsed["action_items"] as? [String]) ?? []
        } else {
            meeting.summary = raw
        }
        meeting.summaryModel = client.model
    }

    private static func extractJSON(_ text: String) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        if let open = trimmed.firstIndex(of: "{"),
           let close = trimmed.lastIndex(of: "}"),
           open < close {
            let candidate = String(trimmed[open...close])
            if let data = candidate.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
        }
        return nil
    }
}

/// Real-time question suggester. Background task polls Anthropic every N
/// seconds with a rolling transcript window.
@MainActor
final class RealtimeSuggester: ObservableObject {
    @Published private(set) var questions: [String] = []
    @Published private(set) var lastUpdatedAt: Date?

    private let client: AnthropicClient
    private let intervalSeconds: Double
    private let windowSeconds: Double
    private var task: Task<Void, Never>?
    private var buffer: [(time: Date, speaker: String, text: String)] = []

    private static let systemPrompt = """
    You sit beside the user during a live meeting. They show you a rolling
    transcript and you suggest the *most useful* follow-up questions they
    could ask right now to (a) clarify ambiguity, (b) surface risk or
    assumptions, or (c) move toward a decision.

    Rules:
    - Output exactly 3 questions, one per line, no numbering, no preamble.
    - Each question must be answerable in <=30 seconds.
    - Skip questions whose answer is already obvious in the transcript.
    - Prefer specific over generic.
    - If the transcript is too thin to suggest anything, output a single line:
      "(listening...)"
    """

    init(client: AnthropicClient, intervalSeconds: Double, windowSeconds: Double) {
        self.client = client
        self.intervalSeconds = intervalSeconds
        self.windowSeconds = windowSeconds
    }

    func add(speaker: String, text: String) {
        buffer.append((Date(), speaker, text))
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
                if Task.isCancelled { break }
                await self.refresh()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func refresh() async {
        let cutoff = Date().addingTimeInterval(-windowSeconds)
        let recent = buffer.filter { $0.time >= cutoff }
        let transcript = recent.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let raw = try await client.complete(system: Self.systemPrompt, user: transcript, maxTokens: 400)
            let qs = raw.split(separator: "\n")
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-•* \t")) }
                .filter { !$0.isEmpty }
            self.questions = qs
            self.lastUpdatedAt = Date()
        } catch {
            // Stay silent on transient API failures; the next tick retries.
        }
    }
}
