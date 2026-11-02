import Foundation
import Testing
@testable import BassPractice

@Suite("Atomic audio workspace restoration")
struct AudioWorkspaceTests {
    @Test("Stopped audio restores tone, mixer and recording metadata without starting")
    func restoresSnapshot() async throws {
        // Arrange
        let backend = TestDoubles.Engine(fails: false)
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: backend)
        let snapshot = Fixtures.snapshot

        // Act
        try await control.restoreWorkspace(snapshot)
        let restored = await control.workspaceSnapshot()

        // Assert
        #expect(restored == snapshot)
        #expect(await control.state == .stopped)
        #expect(backend.writes == 1)
    }

    @Test("Backend rejection retains the complete committed snapshot")
    func rejectedBackendRetainsState() async throws {
        // Arrange
        let backend = TestDoubles.Engine(fails: true)
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: backend)
        let before = await control.workspaceSnapshot()

        // Act
        var failure: AudioWorkspaceFailure?
        do { try await control.restoreWorkspace(Fixtures.snapshot) } catch { failure = error }
        let after = await control.workspaceSnapshot()

        // Assert
        #expect(failure == .backendFailure)
        #expect(after == before)
        #expect(backend.writes == 0)
    }

    @Test("Unsupported gain and nonfinite mixer values fail before backend writes", arguments: [true, false])
    func validatesBeforeWrite(invalidGain: Bool) async {
        // Arrange
        let backend = TestDoubles.Engine(fails: false)
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: backend)
        let initial = WorkspaceAudioConfiguration.initial
        let invalid = WorkspaceAudioConfiguration(inputGain: GainConfiguration(decibels: invalidGain ? 100 : 0, bypassed: false), outputGain: initial.outputGain, equalizer: initial.equalizer, instrumentMix: initial.instrumentMix, playbackMix: MixerChannelConfiguration(volume: invalidGain ? 1 : .nan, muted: false), inputProfileID: nil)

        // Act
        var failure: AudioWorkspaceFailure?
        do { try await control.restoreWorkspace(AudioWorkspaceSnapshot(audio: invalid, recordings: [])) } catch { failure = error }

        // Assert
        #expect(failure == .invalidConfiguration)
        #expect(backend.writes == 0)
        #expect(await control.workspaceSnapshot().audio == .initial)
    }

    @Test("Restoring a workspace while audio runs is rejected without changing state")
    func runningGuard() async throws {
        // Arrange
        let backend = TestDoubles.Engine(fails: false)
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: backend)
        try await control.start()
        let before = await control.workspaceSnapshot()

        // Act
        var failure: AudioWorkspaceFailure?
        do { try await control.restoreWorkspace(Fixtures.snapshot) } catch { failure = error }

        // Assert
        #expect(failure == .engineRunning)
        #expect(await control.workspaceSnapshot() == before)
        #expect(backend.writes == 0)
        try await control.stop()
    }
}

private enum Fixtures {
    static let snapshot = AudioWorkspaceSnapshot(audio: WorkspaceAudioConfiguration(inputGain: GainConfiguration(decibels: 3, bypassed: true), outputGain: GainConfiguration(decibels: -6, bypassed: false), equalizer: .flat, instrumentMix: MixerChannelConfiguration(volume: 0.5, muted: false), playbackMix: MixerChannelConfiguration(volume: 0.2, muted: true), inputProfileID: BuiltInInputProfiles.bassID), recordings: [Recording(id: UUID(), fileURL: URL(fileURLWithPath: "/tmp/recording.caf"), createdAt: Date(timeIntervalSince1970: 1_700_000_000), frameCount: 512, sampleRate: 48_000, channelCount: 1)])
}

private enum TestDoubles {
    struct Session: AudioSessionBackend {
        let sampleRate = 48_000.0
        let ioBufferDuration = 0.00533
        let currentRoute = AudioRoute.empty
        let availableInputs: [AudioInput] = []
        let events = AsyncStream<AudioSessionBackendEvent> { $0.finish() }
        func configureForMeasurement() {}
        func setPreferredSampleRate(_ sampleRate: Double) {}
        func setPreferredIOBufferDuration(_ duration: TimeInterval) {}
        func setActive(_ active: Bool, notifyOthersOnDeactivation: Bool) {}
        func setPreferredInput(id: String?) {}
    }
    final class Engine: AudioWorkspaceBackend, @unchecked Sendable {
        enum Failure: Error { case requested }
        private let lock = NSLock()
        private var count = 0
        let fails: Bool
        init(fails: Bool) { self.fails = fails }
        var writes: Int { lock.withLock { count } }
        let inputFormat = AudioEngineInputFormat(sampleRate: 48_000, channelCount: 1)
        func applyWorkspace(_ configuration: WorkspaceAudioConfiguration, sampleRate: Double) throws {
            if fails { throw Failure.requested }
            lock.withLock { count += 1 }
        }
        func resetGraph() {}
        func attachInstrumentMixer() {}
        func connectInputToInstrument(format: AudioEngineInputFormat) {}
        func connectInstrumentToMain() {}
        func connectMainToOutput() {}
        func setInstrumentMixerVolume(_ volume: Float) {}
        func setGain(_ configuration: GainConfiguration, for stage: GainStage) {}
        func setTone(inputGain: GainConfiguration, equalizer: EQConfiguration, sampleRate: Double) {}
        func setPlaybackVolume(_ volume: Float) {}
        func level(for channel: MixerChannel) -> AudioLevel { .silent }
        func prepare() {}
        func start() {}
        func stop() {}
    }
}
