import Foundation

/// One contiguous run of speech from a single speaker.
struct Utterance: Codable, Identifiable, Hashable {
    /// Seconds from the start of the recording.
    var start: Double
    var end: Double
    /// Anonymous diarization label (``A``, ``B``, …). Mapped to a display
    /// name via ``Meeting.speakers``.
    var speaker: String
    var text: String

    var id: String { "\(speaker)@\(start)" }

    func displaySpeaker(in speakers: [String: String]) -> String {
        if let name = speakers[speaker], !name.isEmpty { return name }
        return "Speaker \(speaker)"
    }
}

/// A single recorded meeting. Round-trippable to a markdown file via
/// ``MeetingStore``. The YAML frontmatter is the source of truth.
struct Meeting: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var tags: [String] = []
    /// Maps raw diarization label → display name. Empty values are kept so
    /// the UI can prompt the user to fill them in.
    var speakers: [String: String] = [:]
    var summary: String = ""
    var actionItems: [String] = []
    var notes: String = ""
    var utterances: [Utterance] = []
    var summaryModel: String?
    /// Audio path relative to the storage root (e.g. ``id/audio.wav``).
    var audioPath: String?

    var durationSeconds: Double {
        guard let endedAt else { return 0 }
        return endedAt.timeIntervalSince(startedAt)
    }
}

extension Meeting {
    /// Filename-safe identifier built from the meeting's start time and title.
    static func makeID(title: String, when: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd-HHmm"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let stamp = fmt.string(from: when)
        return "\(stamp)-\(slugify(title))"
    }

    private static func slugify(_ text: String) -> String {
        let lowered = text.lowercased()
        var out = ""
        var lastDash = false
        for scalar in lowered.unicodeScalars {
            let ch = Character(scalar)
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                lastDash = false
            } else if !lastDash {
                out.append("-")
                lastDash = true
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let capped = String(trimmed.prefix(40))
        return capped.isEmpty ? "meeting" : capped
    }
}
