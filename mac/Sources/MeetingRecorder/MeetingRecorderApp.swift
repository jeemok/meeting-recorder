import SwiftUI

@main
struct MeetingRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Meeting Recorder", id: "main") {
            MainWindow()
                .environmentObject(appDelegate.environment.appViewModel)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Recording…") {
                    appDelegate.environment.appViewModel.startRecordingFlow()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appDelegate.environment.appViewModel)
                .frame(width: 520, height: 480)
        }
    }
}
