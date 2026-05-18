import SwiftUI

/// Read/edit one meeting: title, tags, speakers, summary, action items,
/// and transcript. Mutations save through ``AppViewModel.update``.
struct MeetingDetailView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var draft: Meeting
    @State private var isResummarizing = false

    init(meeting: Meeting) {
        self._draft = State(initialValue: meeting)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                if let audioURL = viewModel.audioURL(for: draft) {
                    AudioPlayerView(url: audioURL)
                }
                Divider()
                summarySection
                actionItemsSection
                speakersSection
                Divider()
                transcriptSection
            }
            .padding(24)
        }
        .navigationTitle(draft.title)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await resummarize() }
                } label: {
                    Label("Re-summarize", systemImage: "wand.and.stars")
                }
                .disabled(isResummarizing || draft.utterances.isEmpty)
                .help("Re-run the LLM summary from the current transcript")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.openInFinder(draft)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .help("Show this meeting's folder in Finder")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.openMarkdown(draft)
                } label: {
                    Label("Open Markdown", systemImage: "doc.text")
                }
                .help("Open the meeting's markdown file in your default editor")
            }
        }
        .onChange(of: draft) { _, new in viewModel.update(new) }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $draft.title, prompt: Text("Untitled"))
                .font(.title)
                .textFieldStyle(.plain)
            HStack(spacing: 12) {
                Label(draft.startedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                if draft.durationSeconds > 0 {
                    Label(formatDuration(draft.durationSeconds), systemImage: "clock")
                }
                if let model = draft.summaryModel {
                    Label(model, systemImage: "sparkles")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            TagEditor(tags: $draft.tags)
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private var summarySection: some View {
        if !draft.summary.isEmpty || isResummarizing {
            VStack(alignment: .leading, spacing: 8) {
                Text("Summary").font(.headline)
                if isResummarizing {
                    ProgressView().controlSize(.small)
                }
                TextEditor(text: $draft.summary)
                    .font(.body)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
            }
        }
    }

    // MARK: - Action items

    @ViewBuilder
    private var actionItemsSection: some View {
        if !draft.actionItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Action items").font(.headline)
                ForEach(Array(draft.actionItems.enumerated()), id: \.offset) { index, _ in
                    HStack(alignment: .top) {
                        Image(systemName: "square")
                            .foregroundStyle(.secondary)
                        TextField("", text: Binding(
                            get: { draft.actionItems[index] },
                            set: { draft.actionItems[index] = $0 }
                        ))
                        .textFieldStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Speakers

    private var speakersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speakers").font(.headline)
            if draft.speakers.isEmpty {
                Text("No speakers detected.").foregroundStyle(.secondary).font(.subheadline)
            } else {
                ForEach(draft.speakers.keys.sorted(), id: \.self) { label in
                    HStack {
                        Text("Speaker \(label)")
                            .frame(width: 100, alignment: .leading)
                            .foregroundStyle(.secondary)
                        TextField("Display name", text: Binding(
                            get: { draft.speakers[label] ?? "" },
                            set: { draft.speakers[label] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }

    // MARK: - Transcript

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript").font(.headline)
            if draft.utterances.isEmpty {
                Text("(no transcript)").foregroundStyle(.secondary).font(.subheadline)
            } else {
                ForEach(draft.utterances) { utterance in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(formatTimestamp(utterance.start))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(utterance.displaySpeaker(in: draft.speakers))
                                .font(.subheadline.bold())
                            Text(utterance.text)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }

    // MARK: - Actions

    private func resummarize() async {
        isResummarizing = true
        defer { isResummarizing = false }
        guard viewModel.config.llm.enabled,
              let apiKey = AnthropicClient.resolveAPIKey(from: viewModel.config) else { return }
        let client = AnthropicClient(apiKey: apiKey, model: viewModel.config.llm.model)
        var copy = draft
        do {
            try await Summarizer(client: client).summarize(&copy)
            self.draft = copy
        } catch {
            // Surface via the view-model's standard error path.
            viewModel.notify(title: "Summary failed", body: error.localizedDescription)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%02d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}

private struct TagEditor: View {
    @Binding var tags: [String]
    @State private var newTag: String = ""

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text(tag).font(.caption)
                    Button {
                        tags.removeAll { $0 == tag }
                    } label: {
                        Image(systemName: "xmark.circle.fill").imageScale(.small)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
            TextField("Add tag", text: $newTag)
                .textFieldStyle(.plain)
                .frame(width: 100)
                .onSubmit {
                    let v = newTag.trimmingCharacters(in: .whitespaces)
                    if !v.isEmpty && !tags.contains(v) { tags.append(v) }
                    newTag = ""
                }
        }
    }
}
