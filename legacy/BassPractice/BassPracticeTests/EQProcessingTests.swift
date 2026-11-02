import Foundation
import Testing
@testable import BassPractice

@Suite("EQ and live profiles")
struct EQProcessingTests {
    @Test("Profile application changes input gain and EQ together without restarting or changing output", arguments: BuiltInInputProfiles.profiles)
    func liveProfile(profile: InputProfile) async throws {
        // Arrange
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: engine)
        try await control.start()
        try await control.setMonitoring(enabled: true, gain: 0.3)
        let output = GainConfiguration(decibels: -6, bypassed: true)
        try await control.setGain(output, for: .output)

        // Act
        try await control.applyProfile(profile)

        // Assert
        #expect(await control.equalizer == profile.eq)
        #expect(await control.selectedProfileID == profile.id)
        #expect(await control.gain(for: .input).decibels == profile.inputGainDecibels)
        #expect(await control.gain(for: .output) == output)
        #expect(engine.eq == profile.eq)
        #expect(engine.starts == 1)
        #expect(engine.volume == 0.3)
    }

    @Test("Native EQ rejects unsupported frequency, gain, Q and count before tone writes", arguments: Fixtures.invalidEQ)
    fileprivate func rejectionPreservesEntireTone(testCase: Fixtures.InvalidEQ) async throws {
        // Arrange
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: engine)
        let original = BuiltInInputProfiles.profiles[0]
        try await control.applyProfile(original)
        let candidate = try InputProfile(name: "Invalid native tone", instrument: .custom, inputGainDecibels: -12, eq: testCase.configuration)
        var failure: ToneProcessingError?

        // Act
        do { try await control.applyProfile(candidate) } catch { failure = error }

        // Assert
        #expect(failure == testCase.failure)
        #expect(await control.selectedProfileID == original.id)
        #expect(await control.equalizer == original.eq)
        #expect(await control.gain(for: .input).decibels == original.inputGainDecibels)
        #expect(engine.writes == 1)
        #expect(engine.eq == original.eq)
    }

    @MainActor @Test("Backend failure retains profile selection and reports a UI error")
    func backendFailureRetainsSelection() async throws {
        // Arrange
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: engine)
        let model = ProfileSelectionModel(controller: control, repository: TestDoubles.Repository())
        await model.refresh()
        await model.select(BuiltInInputProfiles.bassID)
        engine.failWrites = true

        // Act
        await model.select(BuiltInInputProfiles.guitarID)

        // Assert
        #expect(model.selectedID == BuiltInInputProfiles.bassID)
        #expect(model.errorMessage != nil)
        #expect(!model.isBusy)
        #expect(await control.equalizer == BuiltInInputProfiles.profiles[0].eq)
        #expect(engine.eq == BuiltInInputProfiles.profiles[0].eq)
    }

    @Test("EQ edits and input edits mark an applied profile as modified and rebuilds restore tone")
    func editedToneSurvivesRebuild() async throws {
        // Arrange
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: engine)
        try await control.applyProfile(BuiltInInputProfiles.profiles[0])
        let configuration = EQConfiguration(bands: [EQDefaults.newBand], bypassed: true)

        // Act
        try await control.setEqualizer(configuration)
        try await control.setGain(GainConfiguration(decibels: -3, bypassed: false), for: .input)
        try await control.start()
        try await control.stop()
        try await control.start()

        // Assert
        #expect(await control.selectedProfileID == nil)
        #expect(await control.equalizer == configuration)
        #expect(engine.eq == configuration)
        #expect(engine.input.decibels == -3)
        #expect(engine.starts == 2)
    }

    @MainActor @Test("Saving snapshots the audible input gain and EQ and reopened custom profiles can be selected and deleted")
    func customProfileRoundTrip() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("profiles.json")
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: TestDoubles.Engine())
        try await control.applyProfile(BuiltInInputProfiles.profiles[1])
        try await control.setGain(GainConfiguration(decibels: -12, bypassed: true), for: .input)
        let model = ProfileSelectionModel(controller: control, repository: FileInputProfileRepository(fileURL: file))

        // Act
        await model.saveCurrent(name: "My guitar")
        let reopened = FileInputProfileRepository(fileURL: file)
        let saved = try #require(try await reopened.profiles().first)
        await model.select(saved.id)
        let selected = model.selectedID
        await model.delete(saved.id)

        // Assert
        #expect(saved.inputGainDecibels == 0)
        #expect(saved.eq == BuiltInInputProfiles.profiles[1].eq)
        #expect(selected == saved.id)
        #expect(model.selectedID == nil)
        #expect(try await reopened.profiles().isEmpty)
        #expect(model.errorMessage == nil)
        #expect(await control.equalizer == saved.eq)
    }

    @MainActor @Test("Storage failure leaves built-ins available and is visible to the user")
    func storageFailureIsVisible() async {
        // Arrange
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: TestDoubles.Engine())
        let model = ProfileSelectionModel(controller: control, repository: UnavailableInputProfileRepository(failure: .invalidStore))

        // Act
        await model.refresh()

        // Assert
        #expect(model.profiles == BuiltInInputProfiles.profiles)
        #expect(model.errorMessage != nil)
    }

    @Test("Legacy profiles without EQ bypass decode to active EQ")
    func legacyEQDecodes() throws {
        // Arrange
        let legacy = Data("{\"bands\":[]}".utf8)

        // Act
        let decoded = try JSONDecoder().decode(EQConfiguration.self, from: legacy)

        // Assert
        #expect(decoded == .flat)
        #expect(!decoded.bypassed)
    }
}

private enum Fixtures {
    struct InvalidEQ: Sendable {
        let configuration: EQConfiguration
        let failure: ToneProcessingError
    }
    static let invalidEQ: [InvalidEQ] = {
        do {
            return [
                InvalidEQ(configuration: EQConfiguration(bands: [try EQBand(frequencyHertz: 19, gainDecibels: 0, q: 1)]), failure: .unsupportedBand(index: 0)),
                InvalidEQ(configuration: EQConfiguration(bands: [try EQBand(frequencyHertz: 25_000, gainDecibels: 0, q: 1)]), failure: .unsupportedBand(index: 0)),
                InvalidEQ(configuration: EQConfiguration(bands: [try EQBand(frequencyHertz: 1000, gainDecibels: 25, q: 1)]), failure: .unsupportedBand(index: 0)),
                InvalidEQ(configuration: EQConfiguration(bands: [try EQBand(frequencyHertz: 1000, gainDecibels: 0, q: 0.01)]), failure: .unsupportedBand(index: 0)),
                InvalidEQ(configuration: EQConfiguration(bands: [try EQBand(frequencyHertz: 1000, gainDecibels: 0, q: 100)]), failure: .unsupportedBand(index: 0)),
                InvalidEQ(configuration: EQConfiguration(bands: Array(repeating: EQDefaults.newBand, count: 9)), failure: .unsupportedBandCount(9))
            ]
        } catch { preconditionFailure("Invalid test fixtures") }
    }()
}

private enum TestDoubles {
    actor Repository: InputProfileRepository {
        private var stored: [InputProfile] = []
        func profiles() -> [InputProfile] { stored }
        func save(_ profile: InputProfile) { stored.removeAll { $0.id == profile.id }; stored.append(profile) }
        func delete(id: UUID) { stored.removeAll { $0.id == id } }
    }
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
    final class Engine: AudioEngineBackend, @unchecked Sendable {
        enum Failure: Error { case requested }
        private let lock = NSLock()
        private var storedEQ: EQConfiguration = .flat
        private var storedInput: GainConfiguration = .unity
        private var storedStarts = 0
        private var storedWrites = 0
        private var storedVolume: Float = 0
        private var storedFailWrites = false
        let inputFormat = AudioEngineInputFormat(sampleRate: 48_000, channelCount: 1)
        var eq: EQConfiguration { lock.withLock { storedEQ } }
        var input: GainConfiguration { lock.withLock { storedInput } }
        var starts: Int { lock.withLock { storedStarts } }
        var writes: Int { lock.withLock { storedWrites } }
        var volume: Float { lock.withLock { storedVolume } }
        var failWrites: Bool {
            get { lock.withLock { storedFailWrites } }
            set { lock.withLock { storedFailWrites = newValue } }
        }
        func resetGraph() { lock.withLock { storedEQ = .flat; storedInput = .unity } }
        func attachInstrumentMixer() {}
        func connectInputToInstrument(format: AudioEngineInputFormat) {}
        func connectInstrumentToMain() {}
        func connectMainToOutput() {}
        func setInstrumentMixerVolume(_ volume: Float) { lock.withLock { storedVolume = volume } }
        func setGain(_ configuration: GainConfiguration, for stage: GainStage) throws {
            try lock.withLock {
                if storedFailWrites { throw Failure.requested }
                if stage == .input { storedInput = configuration }
            }
        }
        func setTone(inputGain: GainConfiguration, equalizer: EQConfiguration, sampleRate: Double) throws {
            try lock.withLock {
                if storedFailWrites { throw Failure.requested }
                storedInput = inputGain; storedEQ = equalizer; storedWrites += 1
            }
        }
        func prepare() {}
        func start() { lock.withLock { storedStarts += 1 } }
        func stop() {}
    }
}
