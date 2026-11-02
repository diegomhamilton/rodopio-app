import AVFoundation
import Foundation
import Testing
@testable import BassPractice

@Suite("Source mixer and metering")
struct AudioMixerTests {
    @Test("Playback volume and mute preserve input monitoring and survive graph rebuild")
    func independentPlaybackMix() async throws {
        // Arrange
        let backend = TestDoubles.Engine()
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: backend)
        try await control.start()
        try await control.setMonitoring(enabled: true, gain: 0.7)
        let muted = MixerChannelConfiguration(volume: 0.4, muted: true)

        // Act
        try await control.setMixerConfiguration(muted, for: .playback)
        try await control.stop()
        try await control.start()
        let afterRebuild = backend.playbackVolume
        try await control.setMixerConfiguration(MixerChannelConfiguration(volume: 0.4, muted: false), for: .playback)

        // Assert
        #expect(afterRebuild == 0)
        #expect(backend.playbackVolume == 0.4)
        #expect(backend.instrumentVolume == 0.7)
        #expect(await control.monitoringEnabled)
        #expect(await control.monitoringGain == 0.7)
    }

    @Test("Invalid mixer values never reach the backend", arguments: [Float(-1), Float(2), .nan, .infinity])
    func invalidVolume(value: Float) async {
        // Arrange
        let backend = TestDoubles.Engine()
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: backend)
        var failure: AudioMixerFailure?

        // Act
        do { try await control.setMixerConfiguration(MixerChannelConfiguration(volume: value, muted: false), for: .playback) }
        catch { failure = error }

        // Assert
        #expect(failure == .invalidVolume)
        #expect(backend.playbackWrites == 0)
        #expect(await control.mixerConfiguration(for: .playback) == MixerChannelConfiguration(volume: 1, muted: false))
    }

    @Test("Playback write failure preserves the committed configuration")
    func writeFailureRetainsConfiguration() async throws {
        // Arrange
        let backend = TestDoubles.Engine()
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: backend)
        let original = MixerChannelConfiguration(volume: 0.4, muted: false)
        try await control.setMixerConfiguration(original, for: .playback)
        backend.failPlaybackWrite = true
        var failure: AudioMixerFailure?

        // Act
        do { try await control.setMixerConfiguration(MixerChannelConfiguration(volume: 0.9, muted: true), for: .playback) }
        catch { failure = error }

        // Assert
        #expect(failure == .writeFailed)
        #expect(await control.mixerConfiguration(for: .playback) == original)
        #expect(backend.playbackVolume == original.volume)
    }

    @Test("One tap measures RMS/peak/clipping while preserving captured samples", arguments: [Float(0), Float(0.25), Float(1.2)])
    func meteringAndRecording(value: Float) throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        buffer.frameLength = 512
        let values = try #require(buffer.floatChannelData?[0])
        for index in 0..<512 { values[index] = index.isMultiple(of: 2) ? value : -value }
        let fileURL = directory.appendingPathComponent("metered.caf")
        let sink = try AudioRecordingSink(fileURL: fileURL, format: format)
        let tap = AudioTapState()
        let generation = tap.beginObservation()
        tap.setSink(sink)

        // Act
        tap.consume(buffer, generation: generation)
        tap.setSink(nil)
        _ = try sink.finish()
        let file = try AVAudioFile(forReading: fileURL)
        let read = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 512))
        try file.read(into: read)

        // Assert
        #expect(abs(tap.level.rms - value) < 0.0001)
        #expect(tap.level.peak == value)
        #expect(tap.level.clipping == (value >= 1))
        #expect(try #require(read.floatChannelData?[0])[100] == value)
    }

    @Test("A late buffer from a removed graph cannot enter a new recording")
    func oldTapGenerationIsRejected() throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        buffer.frameLength = 512
        let values = try #require(buffer.floatChannelData?[0])
        for index in 0..<512 { values[index] = 0.25 }
        let tap = AudioTapState()
        let old = tap.beginObservation()
        tap.reset()
        let current = tap.beginObservation()
        let sink = try AudioRecordingSink(fileURL: directory.appendingPathComponent("new.caf"), format: format)
        tap.setSink(sink)

        // Act
        tap.consume(buffer, generation: old)
        let afterOld = tap.level
        tap.consume(buffer, generation: current)
        tap.setSink(nil)
        let captured = try sink.finish()

        // Assert
        #expect(afterOld == .silent)
        #expect(captured.frameCount == 512)
        #expect(tap.level.peak == 0.25)
    }
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
    final class Engine: AudioMixerBackend, @unchecked Sendable {
        enum Failure: Error { case requested }
        private let lock = NSLock()
        private var storedInstrumentVolume: Float = 0
        private var storedPlaybackVolume: Float = 1
        private var storedPlaybackWrites = 0
        private var storedFailure = false
        let inputFormat = AudioEngineInputFormat(sampleRate: 48_000, channelCount: 1)
        var instrumentVolume: Float { lock.withLock { storedInstrumentVolume } }
        var playbackVolume: Float { lock.withLock { storedPlaybackVolume } }
        var playbackWrites: Int { lock.withLock { storedPlaybackWrites } }
        var failPlaybackWrite: Bool {
            get { lock.withLock { storedFailure } }
            set { lock.withLock { storedFailure = newValue } }
        }
        func resetGraph() { lock.withLock { storedPlaybackVolume = 1; storedInstrumentVolume = 1 } }
        func attachInstrumentMixer() {}
        func connectInputToInstrument(format: AudioEngineInputFormat) {}
        func connectInstrumentToMain() {}
        func connectMainToOutput() {}
        func setInstrumentMixerVolume(_ volume: Float) { lock.withLock { storedInstrumentVolume = volume } }
        func setGain(_ configuration: GainConfiguration, for stage: GainStage) throws { try NativeGainLimits.validate(configuration, stage: stage) }
        func setTone(inputGain: GainConfiguration, equalizer: EQConfiguration, sampleRate: Double) throws {
            try NativeGainLimits.validate(inputGain, stage: .input)
            try NativeEQLimits.validate(equalizer, sampleRate: sampleRate)
        }
        func setPlaybackVolume(_ volume: Float) throws {
            try lock.withLock {
                if storedFailure { throw Failure.requested }
                storedPlaybackWrites += 1; storedPlaybackVolume = volume
            }
        }
        func level(for channel: MixerChannel) -> AudioLevel { .silent }
        func prepare() {}
        func start() {}
        func stop() {}
    }
}
