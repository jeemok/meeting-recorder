import AppKit
import SwiftUI

/// Owns long-lived services (config, storage, menubar) and the top-level
/// view model. The SwiftUI ``App`` reads ``environment`` for DI.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment: AppEnvironment

    override init() {
        self.environment = AppEnvironment()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment.menuBar.install()
        environment.watcher.start()
        // Activate dock icon on launch but don't steal focus from the
        // user's current meeting app.
        NSApp.setActivationPolicy(.regular)
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.watcher.stop()
        environment.appViewModel.stopRecordingIfNeeded(reason: "app quit")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in the menubar after the window closes.
        false
    }
}

/// Lightweight DI container. Construct once in ``AppDelegate``; pass downward
/// via ``EnvironmentObject``.
@MainActor
final class AppEnvironment {
    let configStore: ConfigStore
    let meetingStore: MeetingStore
    let appViewModel: AppViewModel
    let menuBar: MenuBarController
    let watcher: MeetingWatcher

    init() {
        let configStore = ConfigStore()
        let config = configStore.load()
        let meetingStore = MeetingStore(rootURL: URL(fileURLWithPath: config.storage.directoryPath))
        let vm = AppViewModel(config: config, configStore: configStore, meetingStore: meetingStore)

        self.configStore = configStore
        self.meetingStore = meetingStore
        self.appViewModel = vm
        self.menuBar = MenuBarController(viewModel: vm)
        self.watcher = MeetingWatcher(viewModel: vm)
    }
}
