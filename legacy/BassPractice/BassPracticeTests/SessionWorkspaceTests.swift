import Foundation
import Testing
@testable import BassPractice

@Suite("Session workspace")
struct SessionWorkspaceTests {
    @Test("Opening saved sessions restores audio and never starts monitoring automatically")
    @MainActor func saveAndReopen() async throws {
        // Arrange
        let root = Fixtures.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootDirectory: root)
        let engine = TestDoubles.Workspace()
        let model = SessionModel(engine: engine, session: engine, repository: repository)
        await model.prepareWorkspace()
        let originalID = model.practiceSessionID
        await engine.change(Fixtures.snapshot)
        model.renameDraft("Saved bass")

        // Act
        await model.saveCurrentSession()
        await model.newSession()
        let replacementID = model.practiceSessionID
        await model.openSession(id: originalID)
        let reopened = await engine.workspaceSnapshot()

        // Assert
        #expect(replacementID != originalID)
        #expect(model.practiceSessionID == originalID)
        #expect(model.sessionName == "Saved bass")
        #expect(reopened == Fixtures.snapshot)
        #expect(await engine.starts == 0)
        #expect(model.errorMessage == nil)
    }

    @Test("Deleting the current session creates a replacement and preserves other sessions")
    @MainActor func deleteCurrent() async throws {
        // Arrange
        let root = Fixtures.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootDirectory: root)
        let sibling = try await repository.create(name: "Sibling")
        let engine = TestDoubles.Workspace()
        let model = SessionModel(engine: engine, session: engine, repository: repository)
        await model.prepareWorkspace()
        await model.newSession()
        let deleted = model.practiceSessionID

        // Act
        await model.deleteSession(id: deleted)
        await model.saveCurrentSession()
        let remaining = try await repository.sessions()

        // Assert
        #expect(model.practiceSessionID != deleted)
        #expect(!remaining.contains { $0.id == deleted })
        #expect(remaining.contains { $0.id == sibling.id })
        #expect(remaining.contains { $0.id == model.practiceSessionID })
    }

    @Test("Debounced name edits save the latest draft through an injected delay")
    @MainActor func autosaveDraft() async throws {
        // Arrange
        let repository = TestDoubles.Repository()
        let gate = TestDoubles.Delay()
        let engine = TestDoubles.Workspace()
        let model = SessionModel(engine: engine, session: engine, repository: repository, autosaveDelay: { await gate.wait() })
        await model.prepareWorkspace()
        var requests = gate.requests.makeAsyncIterator()
        var saves = repository.saves.makeAsyncIterator()

        // Act
        model.renameDraft("First")
        let first = try #require(await requests.next())
        model.renameDraft("Final name")
        let second = try #require(await requests.next())
        await gate.release(first)
        await gate.release(second)
        let saved = try #require(await saves.next())

        // Assert
        #expect(saved.name == "Final name")
        #expect(saved.id == model.practiceSessionID)
    }
}

private enum Fixtures {
    static func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    static let snapshot = AudioWorkspaceSnapshot(audio: WorkspaceAudioConfiguration(inputGain: GainConfiguration(decibels: 5, bypassed: false), outputGain: GainConfiguration(decibels: -2, bypassed: true), equalizer: .flat, instrumentMix: MixerChannelConfiguration(volume: 0.7, muted: false), playbackMix: MixerChannelConfiguration(volume: 0.3, muted: true), inputProfileID: BuiltInInputProfiles.bassID), recordings: [])
}

private enum TestDoubles {
    actor Workspace: AudioEngineProtocol, AudioSessionManaging, AudioWorkspaceControlling {
        var state: AudioEngineState = .stopped
        var monitoringEnabled = false
        var monitoringGain: Float = 1
        var starts = 0
        let snapshot = AudioSessionSnapshot(requestedSampleRate: 48_000, requestedIOBufferDuration: 0.00533, actualSampleRate: nil, actualIOBufferDuration: nil, isActive: false)
        let currentRoute = AudioRoute.empty
        let availableInputs: [AudioInput] = []
        let preferredInput: AudioInput? = nil
        private var stored = AudioWorkspaceSnapshot(audio: .initial, recordings: [])
        func start() { starts += 1; state = .running }
        func stop() { state = .stopped }
        func setMonitoring(enabled: Bool, gain: Float) { monitoringEnabled = enabled; monitoringGain = gain }
        func activate() -> AudioSessionSnapshot { snapshot }
        func deactivate() {}
        func selectPreferredInput(id: String?) {}
        func events() -> AsyncStream<AudioSessionEvent> { AsyncStream { $0.finish() } }
        func workspaceSnapshot() -> AudioWorkspaceSnapshot { stored }
        func restoreWorkspace(_ value: AudioWorkspaceSnapshot) { stored = value }
        func change(_ value: AudioWorkspaceSnapshot) { stored = value }
    }
    actor Delay {
        nonisolated let requests: AsyncStream<UUID>
        private let continuation: AsyncStream<UUID>.Continuation
        private var waiting: [UUID: CheckedContinuation<Void, Never>] = [:]
        init() { let stream = AsyncStream<UUID>.makeStream(); requests = stream.stream; continuation = stream.continuation }
        func wait() async {
            let id = UUID()
            await withCheckedContinuation { waiting[id] = $0; continuation.yield(id) }
        }
        func release(_ id: UUID) { waiting.removeValue(forKey: id)?.resume() }
    }
    actor Repository: SessionRepository {
        nonisolated let saves: AsyncStream<PracticeSession>
        private let continuation: AsyncStream<PracticeSession>.Continuation
        private var stored: [PracticeSession] = []
        init() { let stream = AsyncStream<PracticeSession>.makeStream(); saves = stream.stream; continuation = stream.continuation }
        func sessions() -> [PracticeSession] { stored }
        func create(name: String) throws(SessionRepositoryError) -> PracticeSession {
            do { let session = try PracticeSession(name: name); stored.append(session); return session }
            catch { throw .invalidStore }
        }
        func load(id: UUID) throws(SessionRepositoryError) -> PracticeSession {
            guard let session = stored.first(where: { $0.id == id }) else { throw .notFound }; return session
        }
        func save(_ session: PracticeSession) { stored.removeAll { $0.id == session.id }; stored.append(session); continuation.yield(session) }
        func delete(id: UUID) { stored.removeAll { $0.id == id } }
    }
}
