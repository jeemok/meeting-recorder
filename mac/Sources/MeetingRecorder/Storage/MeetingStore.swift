import Foundation

/// Disk persistence for meetings. Each meeting lives in its own folder
/// ``<root>/<id>/`` containing ``<id>.md`` and ``audio.wav``.
///
/// The markdown format matches the legacy Python implementation so existing
/// recordings load unchanged. YAML frontmatter is the source of truth; the
/// transcript body is regenerated from ``utterances`` on save.
final class MeetingStore {
    let rootURL: URL
    private let queue = DispatchQueue(label: "ai.checkbox.MeetingRecorder.store", attributes: .concurrent)
    private let utteranceMarker = "<!-- meeting-recorder:utterances -->"

    init(rootURL: URL) {
        self.rootURL = rootURL
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func folder(for id: String) -> URL {
        rootURL.appendingPathComponent(id, isDirectory: true)
    }

    func markdownURL(for id: String) -> URL {
        folder(for: id).appendingPathComponent("\(id).md")
    }

    func audioURL(for id: String) -> URL {
        folder(for: id).appendingPathComponent("audio.wav")
    }

    // MARK: - Save

    func save(_ meeting: Meeting) throws {
        try queue.sync(flags: .barrier) {
            try FileManager.default.createDirectory(at: folder(for: meeting.id), withIntermediateDirectories: true)
            let text = render(meeting)
            try text.write(to: markdownURL(for: meeting.id), atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Load

    func load(id: String) throws -> Meeting {
        let url = markdownURL(for: id)
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parse(text, id: id)
    }

    func listAll() -> [Meeting] {
        queue.sync {
            guard let entries = try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
            else { return [] }
            let sorted = entries.sorted { $0.lastPathComponent > $1.lastPathComponent }
            var out: [Meeting] = []
            for url in sorted {
                let name = url.lastPathComponent
                let md = url.appendingPathComponent("\(name).md")
                guard FileManager.default.fileExists(atPath: md.path) else { continue }
                if let text = try? String(contentsOf: md, encoding: .utf8),
                   let meeting = try? parse(text, id: name) {
                    out.append(meeting)
                }
            }
            return out
        }
    }

    func delete(id: String) throws {
        try queue.sync(flags: .barrier) {
            try FileManager.default.removeItem(at: folder(for: id))
        }
    }

    // MARK: - Render

    private func render(_ m: Meeting) -> String {
        var out = "---\n"
        out += "id: \(yamlString(m.id))\n"
        out += "title: \(yamlString(m.title))\n"
        out += "started_at: \(isoFormatter.string(from: m.startedAt))\n"
        if let endedAt = m.endedAt {
            out += "ended_at: \(isoFormatter.string(from: endedAt))\n"
        } else {
            out += "ended_at: null\n"
        }
        out += "tags: [\(m.tags.map(yamlString).joined(separator: ", "))]\n"
        out += "speakers:\n"
        if m.speakers.isEmpty {
            out += "  {}\n"
        } else {
            for key in m.speakers.keys.sorted() {
                out += "  \(yamlString(key)): \(yamlString(m.speakers[key] ?? ""))\n"
            }
        }
        out += "summary_model: \(m.summaryModel.map(yamlString) ?? "null")\n"
        out += "audio_path: \(m.audioPath.map(yamlString) ?? "null")\n"
        out += "---\n\n"

        if !m.summary.isEmpty {
            out += "## Summary\n\n\(m.summary.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
        }
        if !m.actionItems.isEmpty {
            out += "## Action items\n\n"
            for a in m.actionItems { out += "- [ ] \(a)\n" }
            out += "\n"
        }
        let trimmedNotes = m.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            out += "## Notes\n\n\(trimmedNotes)\n\n"
        }
        out += "## Transcript\n\n"
        for u in m.utterances {
            let speaker = u.displaySpeaker(in: m.speakers)
            out += "**[\(formatTimestamp(u.start))] \(speaker):** \(u.text.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
        }

        out += "\n\(utteranceMarker)\n```yaml\n"
        for u in m.utterances {
            out += "- start: \(u.start)\n"
            out += "  end: \(u.end)\n"
            out += "  speaker: \(yamlString(u.speaker))\n"
            out += "  text: \(yamlString(u.text))\n"
        }
        out += "```\n"
        return out
    }

    // MARK: - Parse

    private func parse(_ text: String, id: String) throws -> Meeting {
        guard text.hasPrefix("---") else {
            throw NSError(domain: "MeetingStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing frontmatter"])
        }
        let rest = text.dropFirst(3)
        guard let endRange = rest.range(of: "\n---") else {
            throw NSError(domain: "MeetingStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "unterminated frontmatter"])
        }
        let frontmatter = String(rest[..<endRange.lowerBound])
        let body = String(rest[endRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        let fm = parseFrontmatter(frontmatter)
        let utterances = parseUtteranceBlock(in: body)
        let bodyWithoutBlock = stripUtteranceBlock(from: body)
        let (summary, actionItems, notes) = parseSections(bodyWithoutBlock)

        let startedAt = (fm["started_at"] as? String).flatMap(isoFormatter.date(from:))
            ?? Date()
        let endedAt = (fm["ended_at"] as? String).flatMap(isoFormatter.date(from:))

        return Meeting(
            id: (fm["id"] as? String) ?? id,
            title: (fm["title"] as? String) ?? id,
            startedAt: startedAt,
            endedAt: endedAt,
            tags: (fm["tags"] as? [String]) ?? [],
            speakers: (fm["speakers"] as? [String: String]) ?? [:],
            summary: summary,
            actionItems: actionItems,
            notes: notes,
            utterances: utterances,
            summaryModel: fm["summary_model"] as? String,
            audioPath: fm["audio_path"] as? String
        )
    }

    /// Minimal YAML parser sufficient for the schema we emit: scalar
    /// strings, ``null``, inline ``[a, b]`` lists, and a single nested
    /// string→string map under ``speakers:``. The shipped Python loader
    /// uses the same conventions, so we don't need a full YAML parser.
    private func parseFrontmatter(_ text: String) -> [String: Any] {
        var out: [String: Any] = [:]
        var pendingMapKey: String?
        var pendingMap: [String: String] = [:]

        func flushMap() {
            if let key = pendingMapKey {
                out[key] = pendingMap
                pendingMapKey = nil
                pendingMap = [:]
            }
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if line.hasPrefix("  ") && pendingMapKey != nil {
                let kv = line.drop { $0 == " " }
                if let colon = kv.firstIndex(of: ":") {
                    let k = unquote(String(kv[..<colon]).trimmingCharacters(in: .whitespaces))
                    let v = unquote(String(kv[kv.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
                    pendingMap[k] = v == "null" ? "" : v
                }
                continue
            }
            flushMap()
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if value.isEmpty || value == "{}" {
                if key == "speakers" { pendingMapKey = key }
                continue
            }
            if key == "speakers" {
                // Inline ``speakers: {A: Me, B: Jane}`` is rare but valid.
                out[key] = parseInlineMap(value)
                continue
            }
            if value.hasPrefix("[") && value.hasSuffix("]") {
                let inner = value.dropFirst().dropLast()
                out[key] = inner
                    .split(separator: ",")
                    .map { unquote(String($0).trimmingCharacters(in: .whitespaces)) }
                    .filter { !$0.isEmpty }
                continue
            }
            if value == "null" || value == "~" {
                continue
            }
            out[key] = unquote(value)
        }
        flushMap()
        return out
    }

    private func parseInlineMap(_ text: String) -> [String: String] {
        guard text.hasPrefix("{") && text.hasSuffix("}") else { return [:] }
        let inner = text.dropFirst().dropLast()
        var out: [String: String] = [:]
        for pair in inner.split(separator: ",") {
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let k = unquote(String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces))
            let v = unquote(String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
            out[k] = v
        }
        return out
    }

    private func parseUtteranceBlock(in body: String) -> [Utterance] {
        guard let markerRange = body.range(of: utteranceMarker) else { return [] }
        let after = body[markerRange.upperBound...]
        guard let openFence = after.range(of: "```yaml") else { return [] }
        let postFence = after[openFence.upperBound...]
        guard let closeFence = postFence.range(of: "```") else { return [] }
        let yaml = String(postFence[..<closeFence.lowerBound])
        return parseUtterancesYAML(yaml)
    }

    private func stripUtteranceBlock(from body: String) -> String {
        guard let markerRange = body.range(of: utteranceMarker) else { return body }
        return String(body[..<markerRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseUtterancesYAML(_ yaml: String) -> [Utterance] {
        var items: [Utterance] = []
        var current: [String: String] = [:]
        func flush() {
            guard !current.isEmpty,
                  let speaker = current["speaker"],
                  let text = current["text"]
            else { current.removeAll(); return }
            let start = Double(current["start"] ?? "") ?? 0
            let end = Double(current["end"] ?? "") ?? start
            items.append(Utterance(start: start, end: end, speaker: speaker, text: text))
            current.removeAll()
        }
        for rawLine in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("- ") {
                flush()
                let kv = line.dropFirst(2)
                if let colon = kv.firstIndex(of: ":") {
                    let k = String(kv[..<colon]).trimmingCharacters(in: .whitespaces)
                    let v = unquote(String(kv[kv.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
                    current[k] = v
                }
            } else if let colon = line.firstIndex(of: ":") {
                let k = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let v = unquote(String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
                if !k.isEmpty { current[k] = v }
            }
        }
        flush()
        return items
    }

    private func parseSections(_ body: String) -> (summary: String, actions: [String], notes: String) {
        var summary = ""
        var notes = ""
        var actions: [String] = []
        var current: String? = nil
        var buf: [String] = []

        func flush() {
            switch current {
            case "summary": summary = buf.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            case "notes": notes = buf.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            default: break
            }
        }

        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("## ") {
                flush()
                buf.removeAll()
                let heading = line.dropFirst(3).lowercased().trimmingCharacters(in: .whitespaces)
                if heading.hasPrefix("summary") { current = "summary" }
                else if heading.hasPrefix("action") { current = "actions" }
                else if heading.hasPrefix("notes") { current = "notes" }
                else if heading.hasPrefix("transcript") { current = "transcript" }
                else { current = nil }
                continue
            }
            if current == "actions" {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    var rest = String(trimmed.dropFirst(2))
                    if rest.hasPrefix("[ ] ") { rest = String(rest.dropFirst(4)) }
                    else if rest.hasPrefix("[x] ") || rest.hasPrefix("[X] ") { rest = String(rest.dropFirst(4)) }
                    if !rest.isEmpty { actions.append(rest) }
                }
            } else if current == "summary" || current == "notes" {
                buf.append(line)
            }
        }
        flush()
        return (summary, actions, notes)
    }

    // MARK: - YAML helpers

    private func yamlString(_ s: String) -> String {
        if s.isEmpty { return "\"\"" }
        if s.contains(":") || s.contains("#") || s.contains("\"") || s.contains("'") ||
            s.hasPrefix(" ") || s.hasSuffix(" ") || s.contains("\n") {
            let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            return "\"\(escaped)\""
        }
        return s
    }

    private func unquote(_ s: String) -> String {
        var t = s
        if (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
            t.removeFirst()
            t.removeLast()
        }
        return t.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\"", with: "\"")
    }

    private var isoFormatter: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
