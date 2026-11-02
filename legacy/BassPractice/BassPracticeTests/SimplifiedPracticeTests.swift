import AVFoundation
import Foundation
import Testing
@testable import BassPractice

@Suite("Simplified practice workflow")
struct SimplifiedPracticeTests {
    @Test("Record starts audio, stops playback and publishes a finished take")
    @MainActor func recordFromStopped() async throws {
        let engine = FakeAudio()
        let model = SessionModel(engine: engine, session: engine, permission: Permission(allowed: true), files: Files())
        await engine.play(Fixtures.recording)
        await model.toggleRecording()
        #expect(await engine.actions == ["play", "start", "stopPlayback", "record"])
        #expect(model.isRecording)
        await model.toggleRecording()
        #expect(!model.isRecording)
        #expect(model.latestRecording?.duration == 1)
        #expect(model.playbackState == .playing(try #require(model.latestRecording).id))
        #expect(await engine.actions.last == "play")
        await model.stopPlayback()
        #expect(model.playbackState == .stopped)
        #expect(model.errorMessage == nil)
    }

    @Test("Denied microphone permission cannot start recording, playback or monitoring", arguments: ["record", "play", "monitor"])
    @MainActor func permissionDenied(action: String) async {
        let engine = FakeAudio()
        let model = SessionModel(engine: engine, session: engine, permission: Permission(allowed: false), files: Files())
        switch action {
        case "record": await model.toggleRecording()
        case "play": await model.playRecording(Fixtures.recording)
        default: await model.toggleLiveMonitoring()
        }
        #expect(await engine.actions.isEmpty)
        #expect(model.errorMessage != nil)
        #expect(!model.isBusy)
        #expect(!model.isRecording)
    }

    @Test("Failed audio startup cannot begin capture")
    @MainActor func startupFailure() async {
        let engine = FakeAudio(failStart: true)
        let model = SessionModel(engine: engine, session: engine, permission: Permission(allowed: true), files: Files())
        await model.toggleRecording()
        #expect(await engine.actions == ["start"])
        #expect(!model.isRecording)
        #expect(model.errorMessage?.contains("could not start") == true)
    }

    @Test("Listening starts playback from stopped; capture prevents playback replacement")
    @MainActor func listenAndCaptureGuard() async {
        let engine = FakeAudio()
        let model = SessionModel(engine: engine, session: engine, permission: Permission(allowed: true), files: Files())
        await model.playRecording(Fixtures.recording)
        #expect(await engine.actions == ["start", "play"])
        #expect(model.playbackState == .playing(Fixtures.recording.id))
        await model.toggleRecording()
        await model.playRecording(Fixtures.recording)
        #expect(model.isRecording)
        #expect(model.playbackState == .stopped)
        #expect(model.errorMessage?.contains("Finish recording") == true)
        #expect(await engine.actions.filter { $0 == "play" }.count == 1)
    }

    @Test("Internal microphone/speaker monitoring needs confirmation and starts conservatively")
    @MainActor func confirmInternalMonitoring() async {
        let engine = FakeAudio(route: Fixtures.internalRoute)
        let model = SessionModel(engine: engine, session: engine, permission: Permission(allowed: true))
        await model.toggleLiveMonitoring()
        #expect(model.needsMonitoringConfirmation)
        #expect(!model.monitoringEnabled)
        model.cancelMonitoringConfirmation()
        #expect(!model.needsMonitoringConfirmation)
        await model.toggleLiveMonitoring(confirmBuiltInOutput: true)
        #expect(model.monitoringEnabled)
        #expect(model.monitoringGain == 0.1)
        await model.toggleLiveMonitoring()
        #expect(!model.monitoringEnabled)
        #expect(await engine.actions.filter { $0 == "start" }.count == 1)
    }

    @Test("Headphones start live monitoring in one action")
    @MainActor func headphonesMonitoring() async {
        let engine = FakeAudio(route: AudioRoute(inputs: Fixtures.internalRoute.inputs, outputs: [AudioDevice(id: "headphones", name: "Headphones", portType: AVAudioSession.Port.headphones.rawValue)]))
        let model = SessionModel(engine: engine, session: engine, permission: Permission(allowed: true))
        await model.toggleLiveMonitoring()
        #expect(model.monitoringEnabled)
        #expect(!model.needsMonitoringConfirmation)
        #expect(model.monitoringGain == 1)
    }

    @Test("Restored monitoring cannot become audible during recording startup or before confirmation")
    @MainActor func restoredMonitoring() async {
        let engine = FakeAudio(route: Fixtures.internalRoute, monitoringEnabled: true)
        let model = SessionModel(engine: engine, session: engine, permission: Permission(allowed: true), files: Files())
        await model.toggleRecording()
        #expect(model.isRecording)
        #expect(!model.monitoringEnabled)
        await model.toggleRecording()
        await model.stop()
        await engine.setMonitoring(enabled: true, gain: 1)
        await model.toggleLiveMonitoring()
        #expect(model.needsMonitoringConfirmation)
        #expect(!model.monitoringEnabled)
    }

    @Test("A failed metadata save stays visible and retry confirms a successful save")
    @MainActor func saveStatusAndRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = FakeAudio()
        let model = SessionModel(engine: engine, session: engine, repository: FileSessionRepository(rootDirectory: root), autosaveDelay: { try await Task.sleep(for: .seconds(30)) })
        await model.prepareWorkspace()
        #expect(model.saveStatus == .saved)
        model.renameDraft("")
        #expect(model.saveStatus == .pending)
        await model.saveCurrentSession()
        #expect(model.saveStatus == .failed)
        #expect(model.storageNotice != nil)
        model.renameDraft("Practice again")
        await model.saveCurrentSession()
        #expect(model.saveStatus == .saved)
        #expect(model.storageNotice == nil)
    }

    @Test("Route labels distinguish receiver from speaker and unknown routes remain cautious")
    func routeDescriptions() {
        #expect(Fixtures.internalRoute.outputDescription == "iPhone Speaker")
        let receiver = AudioRoute(inputs: Fixtures.internalRoute.inputs, outputs: [AudioDevice(id: "receiver", name: "iPhone", portType: AVAudioSession.Port.builtInReceiver.rawValue)])
        #expect(receiver.outputDescription == "iPhone Receiver")
        #expect(receiver.needsMonitoringConfirmation)
        #expect(AudioRoute.empty.needsMonitoringConfirmation)
        #expect(AudioRoute.empty.outputDescription == "Output not yet confirmed")
    }

    @Test("An older completed save cannot mark a newer edit as saved")
    @MainActor func saveDuringEdit() async throws {
        let repository = HeldSaveRepository()
        let engine = FakeAudio()
        let model = SessionModel(engine: engine, session: engine, repository: repository, autosaveDelay: { try await Task.sleep(for: .seconds(30)) })
        await model.prepareWorkspace()
        await repository.holdNextSave()
        var saves = repository.started.makeAsyncIterator()
        let save = Task { await model.saveCurrentSession() }
        _ = try #require(await saves.next())
        #expect(model.saveStatus == .saving)
        model.renameDraft("New edit")
        await repository.releaseSave()
        await save.value
        #expect(model.saveStatus == .pending)
        await model.saveCurrentSession()
        #expect(model.saveStatus == .saved)
        #expect(try await repository.load(id: model.practiceSessionID).name == "New edit")
    }
}

private enum Fixtures {
    static let recording = Recording(id: UUID(), fileURL: URL(fileURLWithPath: "/tmp/practice-fixture.caf"), createdAt: Date(), frameCount: 48_000, sampleRate: 48_000, channelCount: 1)
    static let internalRoute = AudioRoute(inputs: [AudioDevice(id: "mic", name: "Microphone", portType: AVAudioSession.Port.builtInMic.rawValue)], outputs: [AudioDevice(id: "speaker", name: "iPhone", portType: AVAudioSession.Port.builtInSpeaker.rawValue)])
}
private struct Permission: AudioRecordingPermission {
    let allowed: Bool
    func request() async -> Bool { allowed }
}
private struct Files: AudioFileStore {
    let rootDirectory: URL? = nil
    func recordingURL(sessionID: UUID, recordingID: UUID) -> URL { URL(fileURLWithPath: "/tmp/\(recordingID).caf") }
}
private actor HeldSaveRepository: SessionRepository {
    nonisolated let started: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private var stored: [PracticeSession] = []
    private var hold = false
    private var waiting: CheckedContinuation<Void, Never>?
    init() { (started, continuation) = AsyncStream.makeStream() }
    func holdNextSave() { hold = true }
    func releaseSave() { waiting?.resume(); waiting = nil }
    func sessions() -> [PracticeSession] { stored }
    func create(name: String) throws(SessionRepositoryError) -> PracticeSession {
        do { let session = try PracticeSession(name: name); stored.append(session); return session }
        catch { throw .invalidStore }
    }
    func load(id: UUID) throws(SessionRepositoryError) -> PracticeSession {
        guard let value = stored.first(where: { $0.id == id }) else { throw .notFound }
        return value
    }
    func save(_ session: PracticeSession) async {
        if hold {
            hold = false
            await withCheckedContinuation { waiting = $0; continuation.yield(()) }
        }
        stored.removeAll { $0.id == session.id }
        stored.append(session)
    }
    func delete(id: UUID) { stored.removeAll { $0.id == id } }
}
private actor FakeAudio: AudioEngineProtocol, AudioSessionManaging, AudioRecordingControlling, AudioPlaybackControlling, AudioWorkspaceControlling {
    var state: AudioEngineState = .stopped
    var monitoringEnabled = false
    var monitoringGain: Float = 1
    var recordingState: AudioRecordingState = .idle
    var recordings: [Recording] = []
    var playbackState: AudioPlaybackState = .stopped
    var actions: [String] = []
    let failStart: Bool
    let currentRoute: AudioRoute
    let snapshot = AudioSessionSnapshot(requestedSampleRate: 48_000, requestedIOBufferDuration: 0.00533, actualSampleRate: nil, actualIOBufferDuration: nil, isActive: false)
    let availableInputs: [AudioInput] = []
    let preferredInput: AudioInput? = nil
    init(route: AudioRoute = .empty, failStart: Bool = false, monitoringEnabled: Bool = false) {
        currentRoute = route
        self.failStart = failStart
        self.monitoringEnabled = monitoringEnabled
    }
    func start() throws(AudioEngineFailure) {
        actions.append("start")
        if failStart { throw .startFailed }
        state = .running
    }
    func stop() { state = .stopped }
    func setMonitoring(enabled: Bool, gain: Float) { monitoringEnabled = enabled; monitoringGain = gain }
    func activate() -> AudioSessionSnapshot { snapshot }
    func deactivate() {}
    func selectPreferredInput(id: String?) {}
    func events() -> AsyncStream<AudioSessionEvent> { AsyncStream { $0.finish() } }
    func startRecording(id: UUID, to fileURL: URL) throws(AudioRecordingFailure) {
        guard state == .running else { throw .engineNotRunning }
        actions.append("record")
        recordingState = .recording(id: id, fileURL: fileURL, startedAt: Date())
    }
    func stopRecording() throws(AudioRecordingFailure) -> Recording {
        guard case let .recording(id, url, date) = recordingState else { throw .notRecording }
        let result = Recording(id: id, fileURL: url, createdAt: date, frameCount: 48_000, sampleRate: 48_000, channelCount: 1)
        recordings.append(result)
        recordingState = .idle
        return result
    }
    func play(_ recording: Recording) { actions.append("play"); playbackState = .playing(recording.id) }
    func stopPlayback() { actions.append("stopPlayback"); playbackState = .stopped }
    func workspaceSnapshot() -> AudioWorkspaceSnapshot { AudioWorkspaceSnapshot(audio: .initial, recordings: recordings) }
    func restoreWorkspace(_ snapshot: AudioWorkspaceSnapshot) { recordings = snapshot.recordings }
}
