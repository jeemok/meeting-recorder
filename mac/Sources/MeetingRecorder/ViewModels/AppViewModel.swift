import AppKit
import Combine
import Foundation
import SwiftUI
import UserNotifications

/// Top-level app state. One instance lives in ``AppEnvironment``; it is
/// passed into every view as an ``EnvironmentObject``.
@MainActor
final class AppViewModel: ObservableObject {
    enum Mode: Equatable {
        case idle
        case recording
    }

    /// A recording whose audio is captured but whose transcript/summary
    /// is still being produced. Lives in ``processingItems`` so the UI can
    /// show progress without blocking new recordings.
    struct ProcessingItem: Identifiable, Equatable {
        let id: String
        let title: String
        let startedAt: Date
        var status: String
    }

    @Published var config: AppConfig
    @Published private(set) var mode: Mode = .idle
    @Published private(set) var meetings: [Meeting] = []
    @Published var selectedMeetingID: String?
    @Published private(set) var session: RecordingSession?
    @Published private(set) var lastFinalizedMeetingID: String?
    @Published private(set) var processingItems: [ProcessingItem] = []

    let configStore: ConfigStore
    let store: MeetingStore

    init(config: AppConfig, configStore: ConfigStore, meetingStore: MeetingStore) {
        self.config = config
        self.configStore = configStore
        self.store = meetingStore
        self.meetings = meetingStore.listAll()
        self.selectedMeetingID = meetings.first?.id
    }

    // MARK: - Recording

    /// Open the "New recording" prompt and begin a recording on confirm.
    func startRecordingFlow(title suggested: String? = nil) {
        guard mode == .idle else { return }
        let alert = NSAlert()
        alert.messageText = "New recording"
        alert.informativeText = "Title for this meeting:"
        alert.alertStyle = .informational
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = suggested ?? "Untitled meeting"
        alert.accessoryView = field
        alert.addButton(withTitle: "Record")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        // Make the field first responder so the user can type immediately
        // and so its editor commits before runModal returns.
        DispatchQueue.main.async {
            alert.window.makeFirstResponder(field)
            field.selectText(nil)
        }
        let response = alert.runModal()
        // Force the field editor to commit any pending text before we read it.
        alert.window.makeFirstResponder(nil)
        guard response == .alertFirstButtonReturn else { return }
        let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        startRecording(title: title.isEmpty ? "Untitled meeting" : title)
    }

    /// Start a recording without prompting (used by the auto-detect watcher).
    func startRecording(title: String) {
        guard mode == .idle else { return }
        do {
            let session = try RecordingSession(title: title, config: config, store: store)
            try session.start()
            self.session = session
            self.mode = .recording
        } catch {
            presentError("Recording failed to start", error: error)
        }
    }

    func stopRecordingIfNeeded(reason: String) {
        guard mode == .recording, let session else { return }
        stopRecording(session: session, reason: reason)
    }

    func stopRecording(session: RecordingSession, reason: String) {
        session.stop()
        let id = session.id
        let title = session.title
        let startedAt = session.startedAt
        self.session = nil
        self.mode = .idle
        let item = ProcessingItem(id: id, title: title, startedAt: startedAt, status: "Transcribing…")
        processingItems.append(item)

        Task { [config, store] in
            let finalizer = Finalizer(config: config, store: store)
            do {
                let meeting = try await finalizer.finalize(session: session)
                await MainActor.run {
                    self.processingItems.removeAll { $0.id == id }
                    self.lastFinalizedMeetingID = meeting.id
                    self.refreshMeetings()
                    if self.selectedMeetingID == nil || self.selectedMeetingID == id {
                        self.selectedMeetingID = meeting.id
                    }
                    self.notify(title: "Recording saved", body: "\(meeting.title) — \(reason)")
                }
            } catch {
                await MainActor.run {
                    self.processingItems.removeAll { $0.id == id }
                    self.presentError("Finalize failed", error: error)
                }
            }
        }
    }

    // MARK: - Meeting management

    func refreshMeetings() {
        meetings = store.listAll()
    }

    func meeting(for id: String) -> Meeting? {
        meetings.first { $0.id == id }
    }

    func processingItem(for id: String) -> ProcessingItem? {
        processingItems.first { $0.id == id }
    }

    func update(_ meeting: Meeting) {
        do {
            try store.save(meeting)
            refreshMeetings()
        } catch {
            presentError("Failed to save changes", error: error)
        }
    }

    func delete(_ meeting: Meeting) {
        do {
            try store.delete(id: meeting.id)
            if selectedMeetingID == meeting.id { selectedMeetingID = nil }
            refreshMeetings()
        } catch {
            presentError("Failed to delete meeting", error: error)
        }
    }

    func openInFinder(_ meeting: Meeting) {
        let url = store.markdownURL(for: meeting.id)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openMarkdown(_ meeting: Meeting) {
        let url = store.markdownURL(for: meeting.id)
        NSWorkspace.shared.open(url)
    }

    func openMeetingsFolder() {
        try? FileManager.default.createDirectory(at: store.rootURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(store.rootURL)
    }

    func audioURL(for meeting: Meeting) -> URL? {
        let url = store.audioURL(for: meeting.id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Settings

    func saveConfig(_ updated: AppConfig) {
        config = updated
        try? configStore.save(updated)
    }

    // MARK: - Notifications / errors

    func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }

    private func presentError(_ title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
