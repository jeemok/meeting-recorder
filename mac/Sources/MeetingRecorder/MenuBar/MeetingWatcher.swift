import AppKit
import Foundation

/// Background poller that mirrors the Python ``watch`` command:
///
/// * If a known meeting app appears while we're idle → prompt to record.
/// * If the meeting app disappears while recording → prompt to stop.
/// * If the recording is silent for ``silenceGraceSeconds`` → auto-stop.
@MainActor
final class MeetingWatcher {
    private let viewModel: AppViewModel
    private var detectTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?

    private var lastPromptedAt: [String: Date] = [:]
    private var dismissedAt: [String: Date] = [:]
    private var lastSeenApp: String?
    private var askedStopForDisappearance = false

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    func start() {
        stop()
        guard viewModel.config.watch.enabled else { return }
        let detector = MeetingAppDetector(patterns: viewModel.config.watch.meetingProcesses)
        let pollSeconds = viewModel.config.watch.pollSeconds
        let cooldown = viewModel.config.watch.dismissCooldownSeconds

        detectTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(pollSeconds * 1_000_000_000))
                guard let self else { return }
                await self.detectTick(detector: detector, cooldown: cooldown)
            }
        }

        let graceSeconds = viewModel.config.watch.silenceGraceSeconds
        let threshold = viewModel.config.watch.silenceRMSThreshold
        if graceSeconds > 0 {
            silenceTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard let self else { return }
                    await self.silenceTick(threshold: threshold, grace: graceSeconds)
                }
            }
        }
    }

    func stop() {
        detectTask?.cancel()
        detectTask = nil
        silenceTask?.cancel()
        silenceTask = nil
    }

    // MARK: - Ticks

    private func detectTick(detector: MeetingAppDetector, cooldown: Double) async {
        let found = detector.detect()
        let now = Date()

        // Require that *some* process is actively reading the mic before we
        // prompt. A meeting app being merely open (Teams in particular keeps
        // its process resident between calls) is not enough.
        if let found, viewModel.mode == .idle, MicrophoneActivity.isInUse() {
            let blockUntil = max(
                lastPromptedAt[found] ?? .distantPast,
                dismissedAt[found] ?? .distantPast
            )
            if now.timeIntervalSince(blockUntil) > cooldown {
                lastPromptedAt[found] = now
                promptStart(for: found)
            }
        }

        if lastSeenApp != nil, found == nil,
           viewModel.mode == .recording, !askedStopForDisappearance {
            askedStopForDisappearance = true
            promptStop()
        }
        if found != nil { askedStopForDisappearance = false }
        lastSeenApp = found
    }

    private func silenceTick(threshold: Double, grace: Double) async {
        guard viewModel.mode == .recording, let session = viewModel.session else { return }
        let silent = session.secondsSilent(threshold: threshold)
        if silent >= grace {
            viewModel.stopRecording(session: session, reason: String(format: "silence > %.0fs", grace))
            viewModel.notify(title: "Recording stopped", body: "no sound for \(Int(silent))s")
        }
    }

    // MARK: - UI prompts

    private func promptStart(for appName: String) {
        let alert = NSAlert()
        alert.messageText = "Meeting detected"
        alert.informativeText = "Detected \(appName). Start recording?"
        alert.addButton(withTitle: "Record")
        alert.addButton(withTitle: "Skip")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            viewModel.startRecording(title: appName)
        } else {
            dismissedAt[appName] = Date()
        }
    }

    private func promptStop() {
        let alert = NSAlert()
        alert.messageText = "Meeting app closed"
        alert.informativeText = "The meeting app is no longer running. Stop recording?"
        alert.addButton(withTitle: "Stop")
        alert.addButton(withTitle: "Keep going")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let session = viewModel.session {
            viewModel.stopRecording(session: session, reason: "meeting app closed")
        }
    }
}
