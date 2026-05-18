import SwiftUI

/// Root window: sidebar with the meeting list, detail pane on the right.
/// While a recording is active the detail pane swaps for the live
/// recording view. Background finalizers do not block the UI — they
/// surface as processing rows in the sidebar instead.
struct MainWindow: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            MeetingListView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            detailPane
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.openMeetingsFolder()
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
                .help("Reveal the meetings folder in Finder")

                if viewModel.mode == .recording {
                    Button(role: .destructive) {
                        if let s = viewModel.session {
                            viewModel.stopRecording(session: s, reason: "toolbar stop")
                        }
                    } label: {
                        Label("Stop", systemImage: "stop.circle.fill")
                    }
                    .help("Stop the current recording")
                } else {
                    Button {
                        viewModel.startRecordingFlow()
                    } label: {
                        Label("Record", systemImage: "record.circle")
                    }
                    .help("Start a new recording (⌘N)")
                }
            }
        }
        .onAppear { viewModel.refreshMeetings() }
    }

    @ViewBuilder
    private var detailPane: some View {
        if viewModel.mode == .recording {
            RecordingView()
        } else if let id = viewModel.selectedMeetingID,
                  let pending = viewModel.processingItem(for: id) {
            ProcessingDetailView(item: pending)
        } else if let id = viewModel.selectedMeetingID, let meeting = viewModel.meeting(for: id) {
            MeetingDetailView(meeting: meeting)
                .id(meeting.id)
        } else {
            EmptyDetailView()
        }
    }
}

private struct ProcessingDetailView: View {
    let item: AppViewModel.ProcessingItem

    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text(item.title)
                .font(.title2)
            Text(item.status)
                .foregroundStyle(.secondary)
            Text("Audio is captured. You can start a new recording while this finishes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyDetailView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No meeting selected")
                .font(.title2)
                .foregroundStyle(.secondary)
            Button("New Recording") {
                viewModel.startRecordingFlow()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
