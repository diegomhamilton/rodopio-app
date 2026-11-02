import SwiftUI

struct AudioSettingsView: View {
    let model: SessionModel
    var body: some View {
        Form {
            Section("Input and Output") {
                LabeledContent("Input", value: names(model.route.inputs))
                LabeledContent("Output", value: model.state == .stopped ? "Not yet confirmed" : model.route.outputDescription)
                Picker("Input", selection: Binding(get: { model.selectedInputID }, set: { id in Task { await model.selectInput(id) } })) {
                    Text("System Default").tag(String?.none)
                    ForEach(model.inputs) { Text($0.name).tag(Optional($0.id)) }
                }.disabled(model.isBusy || model.state == .running)
                if model.state == .running {
                    Button("End Audio to Change Input") { Task { await model.stop() } }.disabled(model.isBusy || model.isRecording)
                } else {
                    Button("Discover Inputs") { Task { await model.toggleRunning() } }.disabled(model.isBusy)
                }
                Text("Start audio to discover inputs, then end audio before selecting a different input. Connect your output and use the iPhone volume controls to adjust device volume.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Recording Playback") {
                Toggle("Mute Playback", isOn: Binding(get: { model.playbackMix.muted }, set: { muted in
                    Task { await model.updatePlaybackMix(MixerChannelConfiguration(volume: model.playbackMix.volume, muted: muted)) }
                }))
                MixVolumeSlider(title: "Playback Volume", volume: model.playbackMix.volume) { volume in
                    await model.updatePlaybackMix(MixerChannelConfiguration(volume: volume, muted: model.playbackMix.muted))
                    return model.playbackMix.volume
                }
            }.disabled(model.isBusy)
            Section("Live Monitoring") {
                Button(model.monitoringEnabled ? "Turn Off Input Monitoring" : "Monitor Input", systemImage: "headphones") {
                    Task { await model.toggleLiveMonitoring() }
                }.disabled(model.isRecording && !model.monitoringEnabled)
                LabeledContent("Monitoring", value: model.monitoringEnabled ? "On" : "Off")
                MixVolumeSlider(title: "Monitoring Volume", volume: model.monitoringGain) { gain in
                    await model.setMonitoring(enabled: model.monitoringEnabled, gain: gain)
                    return model.monitoringGain
                }
                Text("Hear your microphone while you play. Use headphones to avoid microphone feedback.").font(.caption).foregroundStyle(.secondary)
            }.disabled(model.isBusy)
            Section {
                NavigationLink("Audio Diagnostics") { AudioDiagnosticsView(model: model) }
            }
            WorkspaceNotices(model: model)
        }.navigationTitle("Audio Settings")
        .confirmationDialog("Listen through the iPhone microphone and speaker?", isPresented: Binding(
            get: { model.needsMonitoringConfirmation },
            set: { if !$0 { model.cancelMonitoringConfirmation() } }
        ), titleVisibility: .visible) {
            Button("Continue at Low Volume") { Task { await model.toggleLiveMonitoring(confirmBuiltInOutput: true) } }
            Button("Cancel", role: .cancel) { model.cancelMonitoringConfirmation() }
        } message: {
            Text("Use headphones to avoid feedback. Live monitoring will start at a low volume if you continue.")
        }
    }
    private func names(_ devices: [AudioDevice]) -> String { devices.isEmpty ? "Not yet confirmed" : devices.map(\.name).joined(separator: ", ") }
}

private struct MixVolumeSlider: View {
    let title: String
    let volume: Float
    let commit: (Float) async -> Float
    @State private var draft: Float = 1
    var body: some View {
        VStack {
            LabeledContent(title, value: "\(Int(draft * 100))%")
            Slider(value: $draft, in: 0...1) { editing in
                if !editing { Task { draft = await commit(draft) } }
            }.accessibilityLabel(title)
        }
        .onAppear { draft = volume }
        .onChange(of: volume) { _, value in draft = value }
    }
}

struct AudioDiagnosticsView: View {
    let model: SessionModel
    var body: some View {
        Form {
            Section("Engine") {
                LabeledContent("State", value: String(describing: model.state))
                if let value = model.diagnostics {
                    LabeledContent("Session Sample Rate", value: String(format: "%.0f Hz", value.actualSessionSampleRate))
                    LabeledContent("Input Channels", value: String(value.inputChannelCount))
                    LabeledContent("Input Format", value: format(value.inputFormat))
                    LabeledContent("Output Format", value: format(value.outputFormat))
                    LabeledContent("IO Buffer", value: String(format: "%.2f ms", value.actualIOBufferDuration * 1000))
                } else { Text("Start audio to read actual hardware formats.") }
                Button("Refresh Diagnostics") { Task { await model.refresh() } }.disabled(model.isBusy)
            }
            Section("Route") {
                ForEach(model.route.inputs) { Text("Input: \($0.name) · \($0.portType)") }
                ForEach(model.route.outputs) { Text("Output: \($0.name) · \($0.portType)") }
            }
            Section("Source Levels") {
                TimelineView(.periodic(from: .now, by: 0.2)) { context in
                    VStack(alignment: .leading) {
                        levelRow("Instrument", level: model.instrumentLevel)
                        levelRow("Playback", level: model.playbackLevel)
                    }.task(id: context.date) { await model.refreshLevels() }
                }
                Text("Measured before source volume/mute. Signal does not guarantee audible output.").font(.caption).foregroundStyle(.secondary)
            }
            WorkspaceNotices(model: model)
        }.navigationTitle("Diagnostics")
    }
    private func levelRow(_ title: String, level: AudioLevel?) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: level.map { $0.clipping ? "Clipping" : ($0.peak > 0.0001 ? "Signal" : "No Signal") } ?? "Unavailable")
            ProgressView(value: Double(min(level?.peak ?? 0, 1)))
        }
    }
    private func format(_ value: AudioFormatDiagnostics) -> String {
        "\(Int(value.sampleRate)) Hz · \(value.channelCount) ch · \(value.sampleEncoding) · \(value.isInterleaved ? "interleaved" : "noninterleaved")"
    }
}
