import Foundation
import Observation

enum SessionSaveStatus: Equatable {
    case unsaved, pending, saving, saved, failed
}

@MainActor @Observable
final class SessionModel {
    private let engine: any AudioEngineProtocol
    private let session: any AudioSessionManaging
    private let permission: any AudioRecordingPermission
    private let files: (any AudioFileStore)?
    private let recordingController: (any AudioRecordingControlling)?
    private let playbackController: (any AudioPlaybackControlling)?
    private let mixer: (any AudioMixerControlling)?
    private(set) var practiceSessionID = UUID()
    private let repository: (any SessionRepository)?
    private let workspace: (any AudioWorkspaceControlling)?
    private let autosaveDelay: @Sendable () async throws -> Void
    private var autosaveTask: Task<Void, Never>?
    private var saveRevision = UUID()
    private var loadedSession: PracticeSession?
    private var didPrepareWorkspace = false
    private(set) var sessionName = "Practice"
    private(set) var isWorkspaceReady: Bool
    private(set) var lastSavedAt: Date?
    private(set) var saveStatus: SessionSaveStatus = .unsaved
    private(set) var storageNotice: String?
    private(set) var state: AudioEngineState = .stopped
    private(set) var inputs: [AudioInput] = []
    private(set) var selectedInputID: String?
    private(set) var route: AudioRoute = .empty
    private(set) var diagnostics: AudioEngineDiagnostics?
    private(set) var monitoringEnabled = false
    private(set) var monitoringGain: Float = 1
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var recordingState: AudioRecordingState = .idle
    private(set) var recordings: [Recording] = []
    private(set) var playbackState: AudioPlaybackState = .stopped
    private(set) var playbackMix = MixerChannelConfiguration(volume: 1, muted: false)
    private(set) var instrumentLevel: AudioLevel?
    private(set) var playbackLevel: AudioLevel?
    private(set) var needsMonitoringConfirmation = false

    var isRecording: Bool {
        if case .recording = recordingState { return true }
        return false
    }

    var latestRecording: Recording? { recordings.max { $0.createdAt < $1.createdAt } }

    init(engine: any AudioEngineProtocol, session: any AudioSessionManaging, permission: any AudioRecordingPermission = SystemAudioRecordingPermission(), files: (any AudioFileStore)? = nil, repository: (any SessionRepository)? = nil, autosaveDelay: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .milliseconds(300)) }) {
        self.engine = engine
        self.session = session
        self.permission = permission
        self.files = files
        recordingController = engine as? any AudioRecordingControlling
        playbackController = engine as? any AudioPlaybackControlling
        mixer = engine as? any AudioMixerControlling
        self.repository = repository
        workspace = engine as? any AudioWorkspaceControlling
        self.autosaveDelay = autosaveDelay
        isWorkspaceReady = repository == nil
    }

    func observe() async {
        let events = await session.events()
        await prepareWorkspace()
        await refresh()
        for await event in events {
            guard !Task.isCancelled else { return }
            await refresh()
            if event == .enteredBackground { await saveCurrentSession() }
            else if event == .toneChanged || event == .mixerChanged || event == .mediaChanged { scheduleAutosave() }
        }
    }

    func prepareWorkspace() async {
        guard !didPrepareWorkspace else { return }
        didPrepareWorkspace = true
        guard let repository, let workspace else { isWorkspaceReady = true; return }
        isBusy = true
        defer { isBusy = false; isWorkspaceReady = true }
        do {
            let sessions = try await repository.sessions()
            let stored: PracticeSession
            if let latest = sessions.first { stored = latest }
            else { stored = try await repository.create(name: "Practice") }
            try await workspace.restoreWorkspace(AudioWorkspaceSnapshot(audio: stored.audio, recordings: stored.recordings))
            adopt(stored)
        } catch { storageNotice = "Stored sessions could not be reopened. Existing data was left unchanged. You can create a new session." }
    }

    func renameDraft(_ name: String) {
        sessionName = name
        scheduleAutosave()
    }

    func scheduleAutosave() {
        guard repository != nil, workspace != nil, didPrepareWorkspace else { return }
        autosaveTask?.cancel()
        saveRevision = UUID()
        saveStatus = .pending
        let id = practiceSessionID
        let delay = autosaveDelay
        autosaveTask = Task { @MainActor [weak self] in
            do { try await delay() } catch { return }
            guard !Task.isCancelled, let self, self.practiceSessionID == id else { return }
            do { try await self.persistSnapshot(allowNameFallback: true) }
            catch {
                guard !Task.isCancelled, self.practiceSessionID == id else { return }
                self.saveStatus = .failed
                self.storageNotice = "Automatic save failed. Audio files were left in place. Retry saving."
            }
        }
    }

    func saveCurrentSession() async {
        autosaveTask?.cancel()
        do { try await persistSnapshot(allowNameFallback: false) }
        catch { saveStatus = .failed; storageNotice = "Could not save this session. Enter a name and check available storage. Audio files were left in place." }
    }

    private func persistSnapshot(allowNameFallback: Bool) async throws {
        guard let repository, let workspace else { return }
        let id = practiceSessionID
        let revision = saveRevision
        let snapshot = await workspace.workspaceSnapshot()
        // A session switch after the await must never save the previous audio under a new ID.
        guard id == practiceSessionID else { return }
        let draftIsEmpty = sessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let name = draftIsEmpty && allowNameFallback ? (loadedSession?.name ?? "Practice") : sessionName
        let now = Date()
        let stored = try PracticeSession(id: id, name: name, audio: snapshot.audio, recordings: snapshot.recordings, effectPresetID: loadedSession?.effectPresetID, createdAt: loadedSession?.createdAt ?? now, updatedAt: now, recoveryNotice: loadedSession?.recoveryNotice)
        if revision == saveRevision { saveStatus = .saving }
        do { try await repository.save(stored) }
        catch {
            if id == practiceSessionID && revision == saveRevision && !Task.isCancelled { saveStatus = .failed }
            throw error
        }
        guard id == practiceSessionID else { return }
        loadedSession = stored
        lastSavedAt = now
        saveStatus = revision == saveRevision ? .saved : .pending
        storageNotice = draftIsEmpty ? "Audio was saved under the previous session name. Enter a name to rename the session." : stored.recoveryNotice
    }

    private func adopt(_ stored: PracticeSession) {
        saveRevision = UUID()
        practiceSessionID = stored.id
        sessionName = stored.name
        loadedSession = stored
        lastSavedAt = stored.updatedAt
        saveStatus = .saved
        storageNotice = stored.recoveryNotice
    }

    func openSession(id: UUID) async {
        guard !isBusy, let repository, let workspace else { return }
        isBusy = true
        defer { isBusy = false }
        if case .recording = await recordingController?.recordingState { errorMessage = "Stop recording before opening another session."; return }
        autosaveTask?.cancel()
        do {
            try await persistSnapshot(allowNameFallback: true)
            let stored = try await repository.load(id: id)
            try await engine.stop()
            try await workspace.restoreWorkspace(AudioWorkspaceSnapshot(audio: stored.audio, recordings: stored.recordings))
            adopt(stored)
            try await persistSnapshot(allowNameFallback: true)
            errorMessage = nil
        } catch { errorMessage = "Could not open this session. Check its saved tone and storage. Audio files were left in place." }
        await refresh()
    }

    func newSession() async {
        guard !isBusy, let repository, let workspace else { return }
        isBusy = true
        defer { isBusy = false }
        if case .recording = await recordingController?.recordingState { errorMessage = "Stop recording before creating another session."; return }
        autosaveTask?.cancel()
        do {
            try await persistSnapshot(allowNameFallback: true)
            let stored = try await repository.create(name: "Practice")
            try await engine.stop()
            try await workspace.restoreWorkspace(AudioWorkspaceSnapshot(audio: stored.audio, recordings: []))
            adopt(stored)
            errorMessage = nil
        } catch { errorMessage = "Could not create a session. Existing sessions were left in place." }
        await refresh()
    }

    func renameSession(id: UUID, name: String) async {
        guard !isBusy, let repository else { return }
        if id == practiceSessionID { renameDraft(name); await saveCurrentSession(); return }
        do {
            let stored = try await repository.load(id: id)
            let renamed = try PracticeSession(id: id, name: name, audio: stored.audio, recordings: stored.recordings, effectPresetID: stored.effectPresetID, createdAt: stored.createdAt, updatedAt: Date(), recoveryNotice: stored.recoveryNotice)
            try await repository.save(renamed)
            errorMessage = nil
        } catch { errorMessage = "Could not rename this session. Enter a name and check storage." }
    }

    func deleteSession(id: UUID) async {
        guard !isBusy, let repository, let workspace else { return }
        isBusy = true
        defer { isBusy = false }
        if id == practiceSessionID, case .recording = await recordingController?.recordingState { errorMessage = "Stop recording before deleting this session."; return }
        do {
            if id == practiceSessionID {
                autosaveTask?.cancel()
                let replacement = try await repository.create(name: "Practice")
                try await engine.stop()
                try await workspace.restoreWorkspace(AudioWorkspaceSnapshot(audio: replacement.audio, recordings: []))
                adopt(replacement)
            }
            try await repository.delete(id: id)
            errorMessage = nil
        } catch { errorMessage = "The session could not be fully deleted. Check storage and retry." }
        await refresh()
    }

    func refresh() async {
        state = await engine.state
        inputs = await session.availableInputs
        selectedInputID = await session.preferredInput?.id
        route = await session.currentRoute
        diagnostics = await engine.diagnostics
        monitoringEnabled = await engine.monitoringEnabled
        monitoringGain = await engine.monitoringGain
        recordingState = await recordingController?.recordingState ?? .idle
        recordings = await recordingController?.recordings ?? []
        playbackState = await playbackController?.playbackState ?? .stopped
        playbackMix = await mixer?.mixerConfiguration(for: .playback) ?? MixerChannelConfiguration(volume: 1, muted: false)
    }

    func toggleRecording() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        guard let recordingController, let files else { errorMessage = "Recording storage is unavailable."; return }
        do {
            if case .recording = await recordingController.recordingState {
                let recording = try await recordingController.stopRecording()
                scheduleAutosave()
                // A playback failure must not discard a successfully captured take.
                do { try await playbackController?.play(recording) }
                catch { errorMessage = error.message }
            }
            else {
                try await persistSnapshot(allowNameFallback: true)
                guard await startAudioIfNeeded() else { return }
                await playbackController?.stopPlayback()
                let id = UUID()
                let fileURL = try files.recordingURL(sessionID: practiceSessionID, recordingID: id)
                try await recordingController.startRecording(id: id, to: fileURL)
            }
        } catch { errorMessage = (error as? AudioRecordingFailure)?.message ?? "Recording storage is unavailable. Check available storage and try again." }
        await refresh()
    }

    func playRecording(_ recording: Recording) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        if case .recording = await recordingController?.recordingState {
            errorMessage = "Finish recording before listening to a saved take."
            return
        }
        guard let playbackController else { errorMessage = "Playback is unavailable."; return }
        do {
            guard await startAudioIfNeeded() else { return }
            try await playbackController.play(recording)
        } catch { errorMessage = error.message }
        await refresh()
    }

    func stopPlayback() async {
        await playbackController?.stopPlayback()
        await refresh()
    }

    func updatePlaybackMix(_ configuration: MixerChannelConfiguration) async {
        guard !isBusy, let mixer else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do { try await mixer.setMixerConfiguration(configuration, for: .playback) }
        catch { errorMessage = "Could not change playback volume. The previous setting was retained." }
        await refresh()
    }

    func refreshLevels() async {
        instrumentLevel = await mixer?.level(for: .instrument)
        playbackLevel = await mixer?.level(for: .playback)
    }

    func toggleRunning() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            if state == .running { try await engine.stop() }
            else {
                guard await startAudioIfNeeded() else { return }
            }
        } catch { errorMessage = String(describing: error) }
        await refresh()
    }

    func stop() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do { try await engine.stop() }
        catch { errorMessage = String(describing: error) }
        await refresh()
    }

    func selectInput(_ id: String?) async {
        guard !isBusy, state != .running else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do { try await session.selectPreferredInput(id: id) }
        catch { errorMessage = String(describing: error) }
        await refresh()
    }

    func setMonitoring(enabled: Bool, gain: Float) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do { try await engine.setMonitoring(enabled: enabled, gain: gain) }
        catch { errorMessage = String(describing: error) }
        await refresh()
    }

    /// User-facing monitoring action owns startup and confirms potentially feeding a mic into a speaker.
    func toggleLiveMonitoring(confirmBuiltInOutput: Bool = false) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            let running = await engine.state == .running
            let monitoring = await engine.monitoringEnabled
            if running && monitoring {
                try await engine.setMonitoring(enabled: false, gain: monitoringGain)
            } else {
                guard await startAudioIfNeeded() else { return }
                let currentRoute = await session.currentRoute
                if currentRoute.needsMonitoringConfirmation && !confirmBuiltInOutput {
                    needsMonitoringConfirmation = true
                    await refresh()
                    return
                }
                // Start conservatively when the user explicitly chooses built-in output.
                let gain = currentRoute.needsMonitoringConfirmation ? min(monitoringGain, 0.1) : monitoringGain
                try await engine.setMonitoring(enabled: true, gain: gain)
            }
        } catch { errorMessage = "Could not change live monitoring. Check the audio connection and try again." }
        needsMonitoringConfirmation = false
        await refresh()
    }

    func cancelMonitoringConfirmation() { needsMonitoringConfirmation = false }

    private func startAudioIfNeeded() async -> Bool {
        guard await engine.state != .running else { return true }
        guard await permission.request() else {
            errorMessage = "Microphone access is required. Enable it in Settings to start audio."
            return false
        }
        do {
            // A saved mixer setting must not activate microphone feedback before an explicit Listen Live action.
            let gain = await engine.monitoringGain
            try await engine.setMonitoring(enabled: false, gain: gain)
            try await engine.start()
            return true
        }
        catch { errorMessage = "The audio engine could not start. Check the connection and try again."; await refresh(); return false }
    }
}
