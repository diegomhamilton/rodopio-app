import Foundation
import Testing
@testable import BassPractice

@Suite("Gain processing")
struct GainProcessingTests {
    @Test("Input and output adjustments do not restart audio or alter monitoring", arguments: GainStage.allCases)
    func independentStages(stage: GainStage) async throws {
        // Arrange
        let backend = TestDoubles.Engine()
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: backend)
        try await control.start()
        try await control.setMonitoring(enabled: true, gain: 0.4)
        let requested = GainConfiguration(decibels: -6, bypassed: true)
        let other: GainStage = stage == .input ? .output : .input

        // Act
        try await control.setGain(requested, for: stage)

        // Assert
        #expect(await control.gain(for: stage) == requested)
        #expect(await control.gain(for: other) == .unity)
        #expect(backend.gain(stage) == requested)
        #expect(backend.starts == 1)
        #expect(backend.volume == 0.4)
        #expect(await control.state == .running)
    }

    @Test("Rejected native values never reach the backend", arguments: Fixtures.invalidValues)
    func invalidValues(value: Float) async {
        // Arrange
        let backend = TestDoubles.Engine()
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: backend)
        var rejected = false

        // Act
        do { try await control.setGain(GainConfiguration(decibels: value, bypassed: false), for: .input) }
        catch { if case .unsupportedValue(stage: .input, decibels: _) = error { rejected = true } }

        // Assert
        #expect(rejected)
        #expect(backend.writes == 0)
        #expect(await control.gain(for: .input) == .unity)
    }

    @Test("Native range endpoints are accepted", arguments: [Float(-96), Float(24)])
    func rangeEndpoints(value: Float) async throws {
        // Arrange
        let backend = TestDoubles.Engine()
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: backend)
        let requested = GainConfiguration(decibels: value, bypassed: false)

        // Act
        try await control.setGain(requested, for: .output)

        // Assert
        #expect(backend.gain(.output) == requested)
        #expect(await control.gain(for: .output) == requested)
    }

    @MainActor @Test("Backend failure retains committed values and exposes a UI error")
    func failureRetainsValues() async {
        // Arrange
        let backend = TestDoubles.Engine()
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: backend)
        let model = ToneModel(controller: control)
        await model.update(GainConfiguration(decibels: -6, bypassed: false), stage: .input)
        backend.failWrites = true

        // Act
        await model.update(GainConfiguration(decibels: 12, bypassed: true), stage: .input)

        // Assert
        #expect(model.input == GainConfiguration(decibels: -6, bypassed: false))
        #expect(model.output == .unity)
        #expect(model.errorMessage != nil)
        #expect(!model.isBusy)
        #expect(backend.gain(.input) == model.input)
    }

    @Test("Graph rebuild restores both gains and bypass after backend reset")
    func rebuildRestoresGains() async throws {
        // Arrange
        let backend = TestDoubles.Engine()
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: backend)
        let input = GainConfiguration(decibels: -6, bypassed: false)
        let output = GainConfiguration(decibels: -12, bypassed: true)
        try await control.setGain(input, for: .input)
        try await control.setGain(output, for: .output)
        try await control.start()
        try await control.stop()

        // Act
        try await control.start()

        // Assert
        #expect(backend.gain(.input) == input)
        #expect(backend.gain(.output) == output)
        #expect(await control.gain(for: .input) == input)
        #expect(await control.gain(for: .output) == output)
        #expect(backend.starts == 2)
    }
}

private enum Fixtures {
    static let invalidValues: [Float] = [-97, 25, .nan, .infinity, -.infinity]
}

private enum TestDoubles {
    final class Engine: AudioEngineBackend, @unchecked Sendable {
        enum Failure: Error { case requested }
        private let lock = NSLock()
        private var gains: [GainStage: GainConfiguration] = [:]
        private var storedStarts = 0
        private var storedWrites = 0
        private var storedVolume: Float = 0
        private var storedFailure = false
        let inputFormat = AudioEngineInputFormat(sampleRate: 48_000, channelCount: 1)
        var starts: Int { lock.withLock { storedStarts } }
        var writes: Int { lock.withLock { storedWrites } }
        var volume: Float { lock.withLock { storedVolume } }
        var failWrites: Bool {
            get { lock.withLock { storedFailure } }
            set { lock.withLock { storedFailure = newValue } }
        }
        func gain(_ stage: GainStage) -> GainConfiguration { lock.withLock { gains[stage] ?? .unity } }
        func resetGraph() { lock.withLock { gains = [:] } }
        func attachInstrumentMixer() {}
        func connectInputToInstrument(format: AudioEngineInputFormat) {}
        func connectInstrumentToMain() {}
        func connectMainToOutput() {}
        func setInstrumentMixerVolume(_ volume: Float) { lock.withLock { storedVolume = volume } }
        func setGain(_ configuration: GainConfiguration, for stage: GainStage) throws {
            try lock.withLock {
                if storedFailure { throw Failure.requested }
                gains[stage] = configuration
                storedWrites += 1
            }
        }
        func prepare() {}
        private var storedEqualizer: EQConfiguration = .flat
        func setTone(inputGain: GainConfiguration, equalizer: EQConfiguration, sampleRate: Double) throws {
            try NativeGainLimits.validate(inputGain, stage: .input)
            try NativeEQLimits.validate(equalizer, sampleRate: sampleRate)
            try lock.withLock {
                if storedFailure { throw Failure.requested }
                gains[.input] = inputGain
                storedEqualizer = equalizer
                storedWrites += 1
            }
        }
        func start() { lock.withLock { storedStarts += 1 } }
        func stop() {}
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
}
