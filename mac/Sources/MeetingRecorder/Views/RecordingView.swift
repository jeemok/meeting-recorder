import SwiftUI

/// Shown in the detail pane while a recording is active. Big elapsed-time
/// readout, editable title, a stop button.
struct RecordingView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        if let session = viewModel.session {
            // Hand the session to a nested view so its @Published properties
            // (elapsedSeconds, title) drive SwiftUI invalidations. Without the
            // explicit @ObservedObject the parent only re-renders when the
            // session reference itself changes, freezing the timer.
            RecordingContent(session: session)
        } else {
            Color.clear
        }
    }
}

private struct RecordingContent: View {
    @ObservedObject var session: RecordingSession
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 160, height: 160)
                Circle()
                    .stroke(Color.red, lineWidth: 4)
                    .frame(width: 120, height: 120)
                Image(systemName: "mic.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
            }
            VStack(spacing: 8) {
                Text(elapsedString(session.elapsedSeconds))
                    .font(.system(size: 56, weight: .semibold, design: .monospaced))
                TextField("Title", text: $session.title)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.title2)
                    .frame(maxWidth: 360)
                Text("Started \(session.startedAt, format: .dateTime.hour().minute())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                viewModel.stopRecording(session: session, reason: "stop button")
            } label: {
                Label("Stop recording", systemImage: "stop.circle.fill")
                    .font(.title3)
                    .padding(.horizontal, 8)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .help("Stop recording and start transcription")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func elapsedString(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}
