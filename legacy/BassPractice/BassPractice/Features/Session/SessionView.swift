import SwiftUI

struct SessionView: View {
    let model: SessionModel
    let toneController: any AudioToneControlling
    let profileRepository: any InputProfileRepository
    @State private var showTone: Bool

    init(model: SessionModel, toneController: any AudioToneControlling, profileRepository: any InputProfileRepository, showToneInitially: Bool = false) {
        self.model = model
        self.toneController = toneController
        self.profileRepository = profileRepository
        _showTone = State(initialValue: showToneInitially)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(model.sessionName).font(.headline)
                    Spacer()
                    SessionSaveLabel(model: model)
                }
                NavigationLink {
                    AudioSettingsView(model: model)
                } label: {
                    Label(model.state == .stopped ? "Output not yet confirmed" : model.route.outputDescription, systemImage: "speaker.wave.2")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }.accessibilityIdentifier("practice.audioSettings")

                VStack(spacing: 16) {
                    transportStatus
                    Button {
                        Task {
                            if model.isRecording { await model.toggleRecording() }
                            else if case .playing = model.playbackState { await model.stopPlayback() }
                            else if let recording = model.latestRecording { await model.playRecording(recording) }
                            else { await model.toggleRecording() }
                        }
                    } label: {
                        Label(transportLabel, systemImage: model.isRecording ? "stop.fill" : "repeat")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.isRecording ? .red : .accentColor)
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("practice.record")

                    if model.latestRecording != nil && !model.isRecording {
                        Button("Record New Loop", systemImage: "record.circle") {
                            Task { await model.toggleRecording() }
                        }.buttonStyle(.bordered).disabled(model.isBusy)
                    }
                    Text("Record a phrase, finish it, and it repeats until you stop.")
                        .font(.caption).foregroundStyle(.secondary)

                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Latest Recording").font(.headline)
                    if let recording = model.latestRecording {
                        RecordingRow(recording: recording, model: model)
                    } else {
                        Text("Your finished phrase will loop automatically.").foregroundStyle(.secondary)
                    }
                }
                PlaybackNotice(model: model)
                WorkspaceNotices(model: model)
                if model.state != .stopped && !model.isRecording {
                    Button("End Audio", systemImage: "power") { Task { await model.stop() } }
                        .disabled(model.isBusy)
                }
            }
            .padding()
        }
        .navigationTitle("Practice")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Tone", systemImage: "slider.horizontal.3") { showTone = true }
                    .disabled(model.isRecording)
                    .accessibilityIdentifier("practice.tone")
            }
        }
        .sheet(isPresented: $showTone) {
            NavigationStack {
                ToneView(controller: toneController, profileRepository: profileRepository)
                    .id(model.practiceSessionID)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showTone = false } } }
            }
        }
    }

    private var transportLabel: String {
        if model.isRecording { return "Finish & Loop" }
        if case .playing = model.playbackState { return "Stop Loop" }
        return model.latestRecording == nil ? "Record Loop" : "Play Loop"
    }

    @ViewBuilder private var transportStatus: some View {
        if case let .recording(_, _, startedAt) = model.recordingState {
            HStack {
                Label("Recording", systemImage: "record.circle.fill").foregroundStyle(.red)
                Text(startedAt, style: .timer).monospacedDigit()
            }.accessibilityIdentifier("practice.recordingStatus")
        } else if case .playing = model.playbackState {
            Label("Looping", systemImage: "play.fill")
        } else if model.isBusy {
            ProgressView("Preparing…")
        } else if model.state == .interrupted {
            Text("Audio Interrupted").foregroundStyle(.secondary)
        } else if model.monitoringEnabled && model.state == .running {
            Label("Listening Live", systemImage: "waveform")
        } else {
            Text("Ready to Record").foregroundStyle(.secondary)
        }
    }
}

struct RecordingRow: View {
    let recording: Recording
    let model: SessionModel
    private var isPlaying: Bool { model.playbackState == .playing(recording.id) }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                Text(String(format: "%.1f s", recording.duration)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task {
                    if isPlaying { await model.stopPlayback() }
                    else { await model.playRecording(recording) }
                }
            } label: {
                Label(isPlaying ? "Stop" : "Play Loop", systemImage: isPlaying ? "stop.fill" : "play.fill")
                    .frame(minHeight: 44)
            }.buttonStyle(.bordered)
                .disabled(model.isBusy || model.isRecording)
                .accessibilityIdentifier("recording.\(recording.id.uuidString).play")
        }
    }
}

struct SessionSaveLabel: View {
    let model: SessionModel
    var body: some View {
        Group {
            if model.isRecording {
                Text("Recording…")
            } else {
                switch model.saveStatus {
                case .unsaved: Text("Not Saved")
                case .pending, .saving: Text("Saving…")
                case .failed: Text("Save Failed").foregroundStyle(.red)
                case .saved:
                    if let date = model.lastSavedAt { Text("Saved \(date, style: .time)") }
                }
            }
        }.font(.caption).foregroundStyle(.secondary)
    }
}

struct PlaybackNotice: View {
    let model: SessionModel
    var body: some View {
        if model.playbackMix.muted || model.playbackMix.volume == 0 {
            VStack(alignment: .leading, spacing: 8) {
                Label("Recording playback is silent", systemImage: "speaker.slash")
                Button("Restore Playback Sound") {
                    Task { await model.updatePlaybackMix(MixerChannelConfiguration(volume: model.playbackMix.volume == 0 ? 1 : model.playbackMix.volume, muted: false)) }
                }.disabled(model.isBusy)
            }
        }
        if model.monitoringEnabled && model.state == .running, case .playing = model.playbackState {
            Text("Live monitoring is also on.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct WorkspaceNotices: View {
    let model: SessionModel
    var body: some View {
        if let error = model.errorMessage {
            Text(error).foregroundStyle(.red).accessibilityIdentifier("workspace.error")
        }
        if let notice = model.storageNotice {
            VStack(alignment: .leading, spacing: 8) {
                Text(notice).foregroundStyle(.secondary)
                if model.saveStatus == .failed {
                    Button("Retry Save") { Task { await model.saveCurrentSession() } }.disabled(model.isBusy)
                }
            }
        }
    }
}
