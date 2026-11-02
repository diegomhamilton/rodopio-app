import AVFoundation
import Foundation
import Testing
@testable import BassPractice

@Suite("Recording and playback")
struct RecordingPlaybackTests {
    @Test("CAF writer preserves irregular callback lengths without inserting silence")
    func irregularCallbackLengths() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("irregular.caf")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let sink = try AudioRecordingSink(fileURL: url, format: format)
        let lengths: [AVAudioFrameCount] = [256, 1024, 1104, 1280, 4096, 4800, 5120, 257]
        var expected: [Float] = []
        for (block, length) in lengths.enumerated() {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: length + 1024))
            let data = try #require(buffer.floatChannelData?[0])
            for frame in 0..<Int(buffer.frameCapacity) { data[frame] = -0.75 }
            buffer.frameLength = length
            for frame in 0..<Int(length) {
                let value = Float((frame + block) % 97 + 1) / 128
                data[frame] = value
                expected.append(value)
            }
            sink.consume(buffer)
        }
        let captured = try sink.finish()
        let file = try AVAudioFile(forReading: url)
        #expect(captured.frameCount == Int64(expected.count))
        #expect(file.length == Int64(expected.count))
        let loaded = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1024))
        var actual: [Float] = []
        while file.framePosition < file.length {
            try file.read(into: loaded, frameCount: 1024)
            try #require(loaded.frameLength > 0)
            let samples = try #require(loaded.floatChannelData?[0])
            actual.append(contentsOf: UnsafeBufferPointer(start: samples, count: Int(loaded.frameLength)))
        }
        #expect(actual == expected)
    }

    @Test("Native loop repeats across three boundaries and stops through the production mixer")
    func nativePlaybackRendersCAF() throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("source.caf")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let source = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_397))
        source.frameLength = source.frameCapacity
        let values = try #require(source.floatChannelData?[0])
        for index in 0..<Int(source.frameLength) { values[index] = 0.125 }
        let sink = try AudioRecordingSink(fileURL: fileURL, format: format)
        sink.consume(source)
        _ = try sink.finish()
        let engine = AVAudioEngine()
        let backend = SystemAudioEngineBackend(engine: engine)
        try backend.attachInstrumentMixer()
        try backend.connectInstrumentToMain()
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        try backend.connectMainToOutput()
        try backend.setGain(GainConfiguration(decibels: -6, bypassed: false), for: .output)
        try backend.prepare()
        try backend.start()
        defer { backend.stop() }
        let output = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))

        // Act
        try backend.play(fileURL: fileURL) { }
        var sum = 0.0
        var samples = 0
        for _ in 0..<64 {
            if try engine.renderOffline(1024, to: output) == .success {
                if engine.manualRenderingSampleTime > 4096 && engine.manualRenderingSampleTime <= 57_344 {
                    let rendered = try #require(output.floatChannelData?[0])
                    for index in 0..<Int(output.frameLength) { sum += Double(rendered[index]); samples += 1 }
                }
                if engine.manualRenderingSampleTime >= 57_344 { break }
            }
        }

        // Assert
        try #require(samples >= 48_000)
        #expect(abs(sum / Double(samples) / 0.125 - pow(10, -6.0 / 20)) < 0.002)
        backend.stopPlayback()
        for _ in 0..<8 { _ = try engine.renderOffline(1024, to: output) }
        let stopped = try #require(output.floatChannelData?[0])
        #expect((0..<Int(output.frameLength)).allSatisfy { abs(stopped[$0]) < 0.00001 })
    }

    @Test("Loop loading preserves all samples of nonaligned mono and stereo takes", arguments: [1, 2])
    func completeLoopBuffer(channels: AVAudioChannelCount) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("nonaligned.caf")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: channels == 1 ? 48_000 : 44_100, channels: channels))
        let source = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 163_286))
        source.frameLength = source.frameCapacity
        let values = try #require(source.floatChannelData)
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(source.frameLength) { values[channel][frame] = Float((frame + channel) % 97 + 1) / 128 }
        }
        do {
            let writer = try AVAudioFile(forWriting: url, settings: format.settings)
            try writer.write(from: source)
        }
        let file = try AVAudioFile(forReading: url)
        let loaded = try AudioLoopBuffer.load(file)
        #expect(loaded.frameLength == source.frameLength)
        #expect(file.framePosition == file.length)
        let samples = try #require(loaded.floatChannelData)
        for channel in 0..<Int(channels) {
            #expect(Array(UnsafeBufferPointer(start: samples[channel], count: Int(loaded.frameLength))) ==
                    Array(UnsafeBufferPointer(start: values[channel], count: Int(source.frameLength))))
        }
    }

    @Test("Interruption finalizes capture and stops playback before publishing interrupted state")
    func interruptionFinalizesMedia() async throws {
        // Arrange
        let session = TestDoubles.EventSession()
        defer { session.finish() }
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: session, engineBackend: engine)
        try await control.start()
        try await control.startRecording(id: UUID(), to: Fixtures.url(id: UUID()))
        try await control.play(Fixtures.recording)
        let events = await control.events()
        var iterator = events.makeAsyncIterator()

        // Act
        session.send(.interruptionBegan)
        for _ in 0..<2 {
            if try #require(await iterator.next()) == .interruptionBegan { break }
        }

        // Assert
        #expect(await control.state == .interrupted)
        #expect(await control.recordingState == .idle)
        #expect(await control.recordings.count == 1)
        #expect(await control.playbackState == .stopped)
    }
    @Test("CAF sink flushes samples and rejects late callbacks after finalization", arguments: [UInt32(1), UInt32(2)])
    func losslessCAFRoundTrip(channels: UInt32) throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("recording.caf")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: channels))
        let buffer = try Fixtures.buffer(format: format)
        let sink = try AudioRecordingSink(fileURL: fileURL, format: format)

        // Act
        sink.consume(buffer)
        let captured = try sink.finish()
        sink.consume(buffer)
        let file = try AVAudioFile(forReading: fileURL)
        let loaded = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 512))
        try file.read(into: loaded)

        // Assert
        #expect(captured == CapturedAudio(frameCount: 512, sampleRate: 48_000, channelCount: channels))
        #expect(file.length == 512)
        #expect(loaded.frameLength == 512)
        let values = try #require(loaded.floatChannelData)
        for channel in 0..<Int(channels) { #expect(abs(values[channel][100] - Float(channel + 1) * 0.125) < 0.00001) }
    }

    @Test("Format failure is reported at finalization and an existing file is never overwritten")
    func invalidCaptureAndExistingFile() throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("recording.caf")
        let mono = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let stereo = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let sink = try AudioRecordingSink(fileURL: fileURL, format: mono)
        let wrong = try Fixtures.buffer(format: stereo)
        var failure: AudioRecordingFailure?

        // Act
        sink.consume(wrong)
        do { _ = try sink.finish() } catch { failure = error }
        let original = try Data(contentsOf: fileURL)
        var existingFileFailure: AudioRecordingFailure?
        do { _ = try AudioRecordingSink(fileURL: fileURL, format: mono) } catch { existingFileFailure = error }

        // Assert
        #expect(failure == .writeFailed)
        #expect(existingFileFailure == .fileCreationFailed)
        #expect(try Data(contentsOf: fileURL) == original)
    }

    @Test("Stopping the engine finalizes recording before backend stop with monitoring muted")
    func stopFinalizesRecording() async throws {
        // Arrange
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: engine)
        let id = UUID()
        let url = Fixtures.url(id: id)
        try await control.start()
        try await control.startRecording(id: id, to: url)

        // Act
        try await control.stop()

        // Assert
        let recording = try #require(await control.recordings.first)
        #expect(recording.id == id)
        #expect(recording.fileURL == url)
        #expect(recording.duration == 1)
        #expect(await control.recordingState == .idle)
        #expect(await control.state == .stopped)
        #expect(await control.monitoringEnabled == false)
        #expect(engine.events.suffix(2) == ["finishRecording", "stop"])
    }

    @Test("Capture cannot begin before audio starts and cannot replace an active recording")
    func recordingLifecycleGuards() async throws {
        // Arrange
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: engine)
        let id = UUID()
        var stoppedFailure: AudioRecordingFailure?
        var duplicateFailure: AudioRecordingFailure?

        // Act
        do { try await control.startRecording(id: id, to: Fixtures.url(id: id)) } catch { stoppedFailure = error }
        try await control.start()
        try await control.startRecording(id: id, to: Fixtures.url(id: id))
        do { try await control.startRecording(id: UUID(), to: Fixtures.url(id: UUID())) } catch { duplicateFailure = error }

        // Assert
        #expect(stoppedFailure == .engineNotRunning)
        #expect(duplicateFailure == .alreadyRecording)
        #expect(engine.events.filter { $0 == "beginRecording" }.count == 1)
    }

    @Test("Finalization failure remains visible and does not publish a valid recording")
    func finalizationFailure() async throws {
        // Arrange
        let engine = TestDoubles.Engine()
        engine.failFinish = true
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: engine)
        try await control.start()
        try await control.startRecording(id: UUID(), to: Fixtures.url(id: UUID()))

        // Act
        try await control.stop()

        // Assert
        #expect(await control.recordingState == .failed(.writeFailed))
        #expect(await control.recordings.isEmpty)
        #expect(await control.state == .stopped)
    }

    @Test("Old completion cannot stop a restarted playback of the same recording")
    func playbackGenerationGuards() async throws {
        // Arrange
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: engine)
        let recording = Fixtures.recording
        try await control.start()
        try await control.play(recording)
        try await control.play(recording)

        // Act
        await engine.complete(index: 0)
        let afterOldCompletion = await control.playbackState
        await engine.complete(index: 1)

        // Assert
        #expect(afterOldCompletion == .playing(recording.id))
        #expect(await control.playbackState == .stopped)
    }

    @Test("Missing playback file becomes an explicit failure and stop remains available")
    func playbackFailure() async throws {
        // Arrange
        let engine = TestDoubles.Engine()
        engine.failPlay = true
        let control = AudioControlActor(backend: TestDoubles.Session(), engineBackend: engine)
        try await control.start()
        var failure: AudioPlaybackFailure?

        // Act
        do { try await control.play(Fixtures.recording) } catch { failure = error }
        let failedState = await control.playbackState
        await control.stopPlayback()

        // Assert
        #expect(failure == .unreadableFile)
        #expect(failedState == .failed(.unreadableFile))
        #expect(await control.playbackState == .stopped)
    }
}

private enum Fixtures {
    static let recording = Recording(id: UUID(), fileURL: URL(fileURLWithPath: "/tmp/test-playback.caf"), createdAt: Date(timeIntervalSince1970: 0), frameCount: 48_000, sampleRate: 48_000, channelCount: 1)
    static func url(id: UUID) -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(id.uuidString + ".caf") }
    static func buffer(format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        buffer.frameLength = 512
        let data = try #require(buffer.floatChannelData)
        for channel in 0..<Int(format.channelCount) { for index in 0..<512 { data[channel][index] = Float(channel + 1) * 0.125 } }
        return buffer
    }
}

private enum TestDoubles {
    struct EventSession: AudioSessionBackend {
        let sampleRate = 48_000.0
        let ioBufferDuration = 0.00533
        let currentRoute = AudioRoute.empty
        let availableInputs: [AudioInput] = []
        let events: AsyncStream<AudioSessionBackendEvent>
        private let continuation: AsyncStream<AudioSessionBackendEvent>.Continuation
        init() { (events, continuation) = AsyncStream.makeStream() }
        func send(_ event: AudioSessionBackendEvent) { continuation.yield(event) }
        func finish() { continuation.finish() }
        func configureForMeasurement() {}
        func setPreferredSampleRate(_ sampleRate: Double) {}
        func setPreferredIOBufferDuration(_ duration: TimeInterval) {}
        func setActive(_ active: Bool, notifyOthersOnDeactivation: Bool) {}
        func setPreferredInput(id: String?) {}
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
    final class Engine: AudioCaptureBackend, AudioPlaybackBackend, @unchecked Sendable {
        private let lock = NSLock()
        private var storedEvents: [String] = []
        private var completions: [@Sendable () async -> Void] = []
        private var storedFailFinish = false
        private var storedFailPlay = false
        let inputFormat = AudioEngineInputFormat(sampleRate: 48_000, channelCount: 1)
        var events: [String] { lock.withLock { storedEvents } }
        var failFinish: Bool {
            get { lock.withLock { storedFailFinish } }
            set { lock.withLock { storedFailFinish = newValue } }
        }
        var failPlay: Bool {
            get { lock.withLock { storedFailPlay } }
            set { lock.withLock { storedFailPlay = newValue } }
        }
        func resetGraph() {}
        func attachInstrumentMixer() {}
        func connectInputToInstrument(format: AudioEngineInputFormat) {}
        func connectInstrumentToMain() {}
        func connectMainToOutput() {}
        func setInstrumentMixerVolume(_ volume: Float) {}
        func setGain(_ configuration: GainConfiguration, for stage: GainStage) throws { try NativeGainLimits.validate(configuration, stage: stage) }
        func setTone(inputGain: GainConfiguration, equalizer: EQConfiguration, sampleRate: Double) throws {
            try NativeGainLimits.validate(inputGain, stage: .input)
            try NativeEQLimits.validate(equalizer, sampleRate: sampleRate)
        }
        func prepare() {}
        func start() {}
        func stop() { lock.withLock { storedEvents.append("stop") } }
        func beginRecording(to fileURL: URL) { lock.withLock { storedEvents.append("beginRecording") } }
        func finishRecording() throws(AudioRecordingFailure) -> CapturedAudio {
            let failed = lock.withLock { storedEvents.append("finishRecording"); return storedFailFinish }
            if failed { throw .writeFailed }
            return CapturedAudio(frameCount: 48_000, sampleRate: 48_000, channelCount: 1)
        }
        func play(fileURL: URL, completion: @escaping @Sendable () async -> Void) throws(AudioPlaybackFailure) {
            let failed = lock.withLock { storedFailPlay }
            if failed { throw .unreadableFile }
            lock.withLock { completions.append(completion) }
        }
        func stopPlayback() {}
        func complete(index: Int) async {
            let callback = lock.withLock { completions[index] }
            await callback()
        }
    }
}
