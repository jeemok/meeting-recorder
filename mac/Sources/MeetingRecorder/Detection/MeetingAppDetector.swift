import AppKit
import Foundation

/// Detects whether a known meeting app is currently running. Mirrors the
/// Python ``detect_meeting_app`` heuristics: case-insensitive substring
/// match against running process names. Browser-based meetings (Google
/// Meet, Slack huddles in the web app) are *not* detected — start those
/// manually from the menubar.
struct MeetingAppDetector {
    let patterns: [String]

    init(patterns: [String]) {
        self.patterns = patterns.map { $0.lowercased() }
    }

    /// Returns the matching process name, or nil if none of the patterns
    /// hit. Reads the live running-apps list; cheap to call on a 5 s tick.
    func detect() -> String? {
        let needles = patterns.filter { !$0.isEmpty }
        guard !needles.isEmpty else { return nil }
        for app in NSWorkspace.shared.runningApplications {
            let name = (app.localizedName ?? app.bundleIdentifier ?? "").lowercased()
            let exe = app.executableURL?.lastPathComponent.lowercased() ?? ""
            for needle in needles {
                if name.contains(needle) || exe.contains(needle) {
                    return app.localizedName ?? exe
                }
            }
        }
        return nil
    }
}
