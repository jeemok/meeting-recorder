import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var draft: AppConfig

    init() {
        // Initialised in ``onAppear`` from the environment-injected view model.
        self._draft = State(initialValue: AppConfig())
    }

    var body: some View {
        TabView {
            audioTab.tabItem { Label("Audio", systemImage: "waveform") }
            transcriptionTab.tabItem { Label("Transcription", systemImage: "text.bubble") }
            llmTab.tabItem { Label("LLM", systemImage: "sparkles") }
            watcherTab.tabItem { Label("Watcher", systemImage: "eye") }
            storageTab.tabItem { Label("Storage", systemImage: "folder") }
        }
        .padding(20)
        .onAppear { draft = viewModel.config }
        .onChange(of: draft) { _, new in viewModel.saveConfig(new) }
    }

    // MARK: - Audio

    private var audioTab: some View {
        Form {
            Section("Capture") {
                Toggle("Capture system audio (the other side of the call)", isOn: $draft.audio.captureSystemAudio)
                Stepper(value: $draft.audio.sampleRate, in: 8_000...48_000, step: 8_000) {
                    Text("Sample rate: \(draft.audio.sampleRate) Hz")
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Transcription

    private var transcriptionTab: some View {
        Form {
            Section("Model") {
                Picker("WhisperKit model", selection: $draft.transcription.model) {
                    ForEach(whisperModels, id: \.self) { Text($0).tag($0) }
                }
                Toggle("Use Apple Neural Engine when available", isOn: $draft.transcription.useANE)
            }
            Section("Diarization (optional)") {
                Toggle("Enable speaker diarization (Python sidecar)", isOn: $draft.diarization.enabled)
                Stepper("Min speakers: \(draft.diarization.minSpeakers)", value: $draft.diarization.minSpeakers, in: 1...10)
                Stepper("Max speakers: \(draft.diarization.maxSpeakers)", value: $draft.diarization.maxSpeakers, in: 1...20)
                TextField("Python interpreter path (optional)", text: Binding(
                    get: { draft.diarization.pythonPath ?? "" },
                    set: { draft.diarization.pythonPath = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
        }
        .formStyle(.grouped)
    }

    private let whisperModels: [String] = [
        "openai_whisper-tiny.en",
        "openai_whisper-base.en",
        "openai_whisper-small.en",
        "openai_whisper-medium.en",
        "openai_whisper-large-v3",
    ]

    // MARK: - LLM

    private var llmTab: some View {
        Form {
            Section("Anthropic") {
                Toggle("Enable LLM summaries", isOn: $draft.llm.enabled)
                TextField("Model", text: $draft.llm.model)
                SecureField("API key (or set ANTHROPIC_API_KEY)", text: Binding(
                    get: { draft.llm.apiKey ?? "" },
                    set: { draft.llm.apiKey = $0.isEmpty ? nil : $0 }
                ))
            }
            Section("Real-time suggestions") {
                Toggle("Suggest follow-up questions during recording", isOn: $draft.llm.realtimeEnabled)
                Stepper("Refresh every: \(Int(draft.llm.realtimeIntervalSeconds))s", value: $draft.llm.realtimeIntervalSeconds, in: 5...600, step: 5)
                Stepper("Context window: \(Int(draft.llm.realtimeContextSeconds))s", value: $draft.llm.realtimeContextSeconds, in: 30...1_800, step: 30)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Watcher

    private var watcherTab: some View {
        Form {
            Section("Auto-detect meetings") {
                Toggle("Watch for known meeting apps", isOn: $draft.watch.enabled)
                Stepper("Poll every \(Int(draft.watch.pollSeconds))s", value: $draft.watch.pollSeconds, in: 1...60, step: 1)
                Stepper("Re-prompt cooldown: \(Int(draft.watch.dismissCooldownSeconds))s", value: $draft.watch.dismissCooldownSeconds, in: 0...3_600, step: 30)
            }
            Section("Silence watchdog") {
                Stepper("Auto-stop after \(Int(draft.watch.silenceGraceSeconds))s of silence", value: $draft.watch.silenceGraceSeconds, in: 0...600, step: 10)
                Text("Threshold (RMS): \(String(format: "%.4f", draft.watch.silenceRMSThreshold))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Tracked processes") {
                ForEach(Array(draft.watch.meetingProcesses.enumerated()), id: \.offset) { index, _ in
                    TextField("Process name", text: Binding(
                        get: { draft.watch.meetingProcesses[index] },
                        set: { draft.watch.meetingProcesses[index] = $0 }
                    ))
                }
                .onDelete { draft.watch.meetingProcesses.remove(atOffsets: $0) }
                Button("Add process") { draft.watch.meetingProcesses.append("") }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Storage

    private var storageTab: some View {
        Form {
            Section("Meeting folder") {
                HStack {
                    Text(draft.storage.directoryPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { chooseStorageDir() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseStorageDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            draft.storage.directoryPath = url.path
        }
    }
}
