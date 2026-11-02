import Foundation
import Testing
@testable import BassPractice

@Suite("App dependencies")
struct AppDependenciesTests {
    @Test("Dependencies can be replaced with test doubles")
    func dependenciesCanBeReplacedWithTestDoubles() async throws {
        // Arrange
        let audioSession = TestDoubles.AudioSession()
        let audioEngine = TestDoubles.AudioEngine()
        let sessions = TestDoubles.SessionRepository()
        let files = TestDoubles.AudioFileStore()

        // Act
        let dependencies = AppDependencies(
            audioSession: audioSession,
            audioEngine: audioEngine,
            gainController: audioEngine,
            profileRepository: UnavailableInputProfileRepository(failure: .applicationSupportUnavailable),
            sessionRepository: sessions,
            audioFileStore: files,
            logger: AppLogger()
        )

        // Assert
        #expect(dependencies.audioSession === audioSession)
        #expect(dependencies.audioEngine === audioEngine)
        #expect(try await dependencies.sessionRepository.sessions() == sessions.result)
        #expect(dependencies.audioFileStore.rootDirectory == files.rootDirectory)
    }

    @Test("Live dependencies share one serialized audio control actor")
    func liveDependenciesShareAudioControlActor() {
        // Arrange
        let dependencies = AppDependencies.live()

        // Act
        let audioSessionIdentifier = ObjectIdentifier(dependencies.audioSession)
        let audioEngineIdentifier = ObjectIdentifier(dependencies.audioEngine)

        // Assert
        #expect(audioSessionIdentifier == audioEngineIdentifier)
    }

    @Test(
        "Initial destination follows supported launch arguments",
        arguments: Fixtures.destinationCases
    )
    fileprivate func initialDestination(testCase: Fixtures.DestinationCase) {
        // Arrange
        let arguments = testCase.arguments

        // Act
        let destination = AppDestination.initial(arguments: arguments)

        // Assert
        #expect(destination == testCase.expectedDestination)
    }
}

private enum Fixtures {
    struct DestinationCase: Sendable {
        let arguments: [String]
        let expectedDestination: AppDestination
    }

    static let destinationCases = [
        DestinationCase(arguments: [], expectedDestination: .session),
        DestinationCase(
            arguments: ["BassPractice", "-initial-tab", "library"],
            expectedDestination: .library
        )
    ]
}

private enum TestDoubles {
    actor AudioSession: AudioSessionManaging {
        let currentRoute = AudioRoute.empty
        let availableInputs: [AudioInput] = []
        let preferredInput: AudioInput? = nil

        private(set) var snapshot = AudioSessionSnapshot(
            requestedSampleRate: 48_000,
            requestedIOBufferDuration: 0.00533,
            actualSampleRate: nil,
            actualIOBufferDuration: nil,
            isActive: false
        )

        func activate() -> AudioSessionSnapshot {
            snapshot
        }

        func deactivate() {}

        func selectPreferredInput(id: String?) {}

        func events() -> AsyncStream<AudioSessionEvent> {
            AsyncStream { _ in }
        }
    }

    actor AudioEngine: AudioEngineProtocol, AudioToneControlling {
        let state: AudioEngineState = .stopped
        let monitoringEnabled = false
        let monitoringGain: Float = 1

        func start() {}
        func stop() {}
        func setMonitoring(enabled: Bool, gain: Float) {}
        private var gains: [GainStage: GainConfiguration] = [:]
        private(set) var equalizer: EQConfiguration = .flat
        private(set) var selectedProfileID: UUID?
        func setEqualizer(_ configuration: EQConfiguration) throws(ToneProcessingError) {
            try NativeEQLimits.validate(configuration, sampleRate: 48_000)
            equalizer = configuration
            selectedProfileID = nil
        }
        func applyProfile(_ profile: InputProfile) throws(ToneProcessingError) {
            try NativeEQLimits.validate(profile.eq, sampleRate: 48_000)
            guard NativeGainLimits.range.contains(profile.inputGainDecibels) else { throw .unsupportedInputGain(profile.inputGainDecibels) }
            gains[.input] = GainConfiguration(decibels: profile.inputGainDecibels, bypassed: false)
            equalizer = profile.eq
            selectedProfileID = profile.id
        }
        func profileSnapshot(name: String) throws(InputProfileValidationError) -> InputProfile {
            let input = gains[.input] ?? .unity
            return try InputProfile(name: name, instrument: .custom, inputGainDecibels: input.bypassed ? 0 : input.decibels, eq: equalizer)
        }
        func gain(for stage: GainStage) -> GainConfiguration { gains[stage] ?? .unity }
        func setGain(_ configuration: GainConfiguration, for stage: GainStage) throws(GainProcessingError) {
            try NativeGainLimits.validate(configuration, stage: stage)
            gains[stage] = configuration
        }
    }

    actor SessionRepository: BassPractice.SessionRepository {
        let result = [try! PracticeSession(name: "Test Session")]

        func sessions() -> [PracticeSession] {
            result
        }
        func create(name: String) throws(SessionRepositoryError) -> PracticeSession { throw .unavailable }
        func load(id: UUID) throws(SessionRepositoryError) -> PracticeSession { throw .notFound }
        func save(_ session: PracticeSession) throws(SessionRepositoryError) { throw .unavailable }
        func delete(id: UUID) throws(SessionRepositoryError) { throw .unavailable }
    }

    struct AudioFileStore: BassPractice.AudioFileStore {
        let rootDirectory: URL? = URL(fileURLWithPath: "/tmp/bass-practice-tests")
        func recordingURL(sessionID: UUID, recordingID: UUID) throws(AudioFileStoreError) -> URL {
            guard let rootDirectory else { throw .unavailable }
            return rootDirectory.appendingPathComponent(recordingID.uuidString + ".caf")
        }
    }
}
