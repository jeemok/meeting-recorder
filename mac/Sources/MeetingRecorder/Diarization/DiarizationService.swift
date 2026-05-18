import Foundation

struct DiarizationSegment: Hashable {
    var start: Double
    var end: Double
    var speaker: String
}

/// Runs the bundled Python diarization sidecar. The script is shipped in
/// ``Contents/Resources/diarize_sidecar.py`` of the app bundle.
struct DiarizationService {
    let pythonPath: String
    let scriptURL: URL

    static func bundled(pythonPath: String? = nil) -> DiarizationService? {
        guard let url = scriptURL() else { return nil }
        let python = pythonPath ?? findPython() ?? "/usr/bin/env"
        return DiarizationService(pythonPath: python, scriptURL: url)
    }

    static func scriptURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "diarize_sidecar", withExtension: "py") {
            return bundled
        }
        // Dev-mode fallback: relative to the source tree.
        let candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/diarize_sidecar.py")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private static func findPython() -> String? {
        for path in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// Returns segments grouped by raw label (``A``, ``B``, …). Throws on
    /// non-zero exit so the caller can fall back to single-speaker mode.
    func diarize(audioURL: URL, minSpeakers: Int, maxSpeakers: Int) async throws -> [DiarizationSegment] {
        let payload: [String: Any] = [
            "audio_path": audioURL.path,
            "min_speakers": minSpeakers,
            "max_speakers": maxSpeakers,
        ]
        let stdoutData = try await run(arguments: [scriptURL.path], stdin: try JSONSerialization.data(withJSONObject: payload))
        let json = try JSONSerialization.jsonObject(with: stdoutData) as? [String: Any]
        let raw = (json?["segments"] as? [[String: Any]]) ?? []
        return raw.compactMap { dict in
            guard let start = dict["start"] as? Double,
                  let end = dict["end"] as? Double,
                  let speaker = dict["speaker"] as? String
            else { return nil }
            return DiarizationSegment(start: start, end: end, speaker: speaker)
        }
    }

    /// Verifies that the configured Python has pyannote installed.
    func check() async -> Bool {
        do {
            _ = try await run(arguments: [scriptURL.path, "--check"], stdin: Data())
            return true
        } catch {
            return false
        }
    }

    private func run(arguments: [String], stdin: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = arguments
            let stdout = Pipe()
            let stderr = Pipe()
            let stdinPipe = Pipe()
            process.standardOutput = stdout
            process.standardInput = stdinPipe
            process.standardError = stderr

            process.terminationHandler = { proc in
                let data = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
                if proc.terminationStatus != 0 {
                    let err = (try? stderr.fileHandleForReading.readToEnd()).flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    continuation.resume(throwing: NSError(domain: "Diarization", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: err]))
                } else {
                    continuation.resume(returning: data)
                }
            }
            do {
                try process.run()
                if !stdin.isEmpty {
                    try stdinPipe.fileHandleForWriting.write(contentsOf: stdin)
                }
                try? stdinPipe.fileHandleForWriting.close()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
