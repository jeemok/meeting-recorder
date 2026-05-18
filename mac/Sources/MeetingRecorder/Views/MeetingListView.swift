import SwiftUI

struct MeetingListView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var search = ""

    var body: some View {
        List(selection: $viewModel.selectedMeetingID) {
            if !viewModel.processingItems.isEmpty {
                Section("Processing") {
                    ForEach(viewModel.processingItems) { item in
                        ProcessingRow(item: item)
                            .tag(item.id)
                    }
                }
            }
            Section(viewModel.processingItems.isEmpty ? "" : "Meetings") {
                ForEach(filtered) { meeting in
                    MeetingRow(meeting: meeting)
                        .tag(meeting.id)
                        .contextMenu {
                            Button("Open Markdown") { viewModel.openMarkdown(meeting) }
                            Button("Reveal in Finder") { viewModel.openInFinder(meeting) }
                            Divider()
                            Button("Delete", role: .destructive) { viewModel.delete(meeting) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $search, placement: .sidebar, prompt: "Search title or tag")
        .navigationTitle("Meetings")
    }

    private var filtered: [Meeting] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if needle.isEmpty { return viewModel.meetings }
        return viewModel.meetings.filter { m in
            m.title.lowercased().contains(needle) ||
            m.tags.contains(where: { $0.lowercased().contains(needle) }) ||
            m.id.contains(needle)
        }
    }
}

private struct ProcessingRow: View {
    let item: AppViewModel.ProcessingItem

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(item.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.title)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(meeting.startedAt, format: .dateTime.month().day().hour().minute())
                if meeting.durationSeconds > 0 {
                    Text("·")
                    Text(formatDuration(meeting.durationSeconds))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !meeting.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(meeting.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return m > 0 ? "\(m)m\(String(format: "%02d", s))s" : "\(s)s"
    }
}
