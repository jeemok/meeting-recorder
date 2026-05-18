import AppKit
import Combine
import SwiftUI

/// Owns the ``NSStatusItem`` in the menubar. Status icon reflects the
/// current ``AppViewModel.mode`` and the menu items wire directly to the
/// view-model's start/stop/open-last callbacks.
@MainActor
final class MenuBarController {
    private let viewModel: AppViewModel
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []
    private var elapsedTimer: Timer?

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "●"
        self.statusItem = item
        rebuildMenu()

        viewModel.$mode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)
        viewModel.$lastFinalizedMeetingID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)
        viewModel.$processingItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)

        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rebuildMenu() }
        }
    }

    func rebuildMenu() {
        guard let item = statusItem else { return }
        item.button?.title = icon(for: viewModel.mode)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: statusLabel(), action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let startItem = NSMenuItem(title: "Start recording…", action: #selector(onStart(_:)), keyEquivalent: "n")
        startItem.target = self
        startItem.isEnabled = viewModel.mode == .idle

        let stopItem = NSMenuItem(title: "Stop recording", action: #selector(onStop(_:)), keyEquivalent: ".")
        stopItem.target = self
        stopItem.isEnabled = viewModel.mode == .recording

        let openLastItem = NSMenuItem(title: "Open last meeting", action: #selector(onOpenLast(_:)), keyEquivalent: "o")
        openLastItem.target = self
        openLastItem.isEnabled = viewModel.lastFinalizedMeetingID != nil

        let showWindow = NSMenuItem(title: "Show Meetings…", action: #selector(onShowMain(_:)), keyEquivalent: "m")
        showWindow.target = self

        let settings = NSMenuItem(title: "Settings…", action: #selector(onSettings(_:)), keyEquivalent: ",")
        settings.target = self

        let quit = NSMenuItem(title: "Quit", action: #selector(onQuit(_:)), keyEquivalent: "q")
        quit.target = self

        menu.addItem(startItem)
        menu.addItem(stopItem)
        menu.addItem(openLastItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(showWindow)
        menu.addItem(settings)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quit)
        item.menu = menu
    }

    private func icon(for mode: AppViewModel.Mode) -> String {
        switch mode {
        case .idle:
            return viewModel.processingItems.isEmpty ? "●" : "⏳"
        case .recording:
            return "🔴"
        }
    }

    private func statusLabel() -> String {
        switch viewModel.mode {
        case .idle:
            if viewModel.processingItems.isEmpty { return "Idle" }
            let n = viewModel.processingItems.count
            return n == 1 ? "Processing 1 recording…" : "Processing \(n) recordings…"
        case .recording:
            if let session = viewModel.session {
                let mins = Int(session.elapsedSeconds) / 60
                let secs = Int(session.elapsedSeconds) % 60
                return String(format: "Recording %02d:%02d — %@", mins, secs, session.title as CVarArg)
            }
            return "Recording…"
        }
    }

    // MARK: - Actions

    @objc private func onStart(_ sender: Any?) {
        viewModel.startRecordingFlow()
    }

    @objc private func onStop(_ sender: Any?) {
        if let session = viewModel.session {
            viewModel.stopRecording(session: session, reason: "menubar stop")
        }
    }

    @objc private func onOpenLast(_ sender: Any?) {
        if let id = viewModel.lastFinalizedMeetingID, let meeting = viewModel.meeting(for: id) {
            viewModel.openMarkdown(meeting)
        }
    }

    @objc private func onShowMain(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }

    @objc private func onSettings(_ sender: Any?) {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func onQuit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
