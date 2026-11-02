import AVFoundation

protocol AudioEngineProtocol: AnyObject, Sendable {
    var state: AudioEngineState { get async }
    var monitoringEnabled: Bool { get async }
    var monitoringGain: Float { get async }
    var diagnostics: AudioEngineDiagnostics? { get async }

    func start() async throws(AudioEngineFailure)
    func stop() async throws(AudioEngineFailure)
    func setMonitoring(enabled: Bool, gain: Float) async throws(AudioEngineFailure)
}

extension AudioEngineProtocol {
    var diagnostics: AudioEngineDiagnostics? { get async { nil } }
}

struct AudioFormatDiagnostics: Equatable, Sendable {
    let sampleRate: Double
    let channelCount: UInt32
    let sampleEncoding: String
    let isInterleaved: Bool

    init(sampleRate: Double, channelCount: UInt32, sampleEncoding: String, isInterleaved: Bool) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.sampleEncoding = sampleEncoding
        self.isInterleaved = isInterleaved
    }

    init(audioFormat: AVAudioFormat) {
        sampleRate = audioFormat.sampleRate
        channelCount = audioFormat.channelCount
        isInterleaved = audioFormat.isInterleaved
        switch audioFormat.commonFormat {
        case .pcmFormatFloat32: sampleEncoding = "Float32"
        case .pcmFormatFloat64: sampleEncoding = "Float64"
        case .pcmFormatInt16: sampleEncoding = "Int16"
        case .pcmFormatInt32: sampleEncoding = "Int32"
        case .otherFormat: sampleEncoding = "Other"
        @unknown default: sampleEncoding = "Unknown"
        }
    }
}

struct AudioEngineDiagnostics: Equatable, Sendable {
    let actualSessionSampleRate: Double
    let inputChannelCount: UInt32
    let inputFormat: AudioFormatDiagnostics
    let outputFormat: AudioFormatDiagnostics
    let actualIOBufferDuration: Double
}

enum AudioEngineState: Equatable, Sendable {
    case stopped
    case starting
    case running
    case interrupted
    case failed(AudioEngineFailure)
}

enum AudioEngineFailure: Error, Equatable, Sendable {
    case startUnavailableInBackground
    case sessionActivation(AudioSessionError)
    case invalidInputFormat(sampleRate: Double, channelCount: UInt32)
    case graphConfigurationFailed
    case preparationFailed
    case startFailed
    case monitoringConfigurationFailed
    case sessionDeactivation(AudioSessionError)
}

protocol AudioEngineBackend: Sendable {
    var inputFormat: AudioEngineInputFormat { get }
    var diagnosticFormats: (input: AudioFormatDiagnostics, output: AudioFormatDiagnostics)? { get }

    func resetGraph() throws
    func attachInstrumentMixer() throws
    func connectInputToInstrument(format: AudioEngineInputFormat) throws
    func connectInstrumentToMain() throws
    func connectMainToOutput() throws
    func setInstrumentMixerVolume(_ volume: Float) throws
    func setGain(_ configuration: GainConfiguration, for stage: GainStage) throws
    /// Must either apply the entire tone or throw without changing the committed processing.
    func setTone(inputGain: GainConfiguration, equalizer: EQConfiguration, sampleRate: Double) throws
    func prepare() throws
    func start() throws
    func stop()
}

extension AudioEngineBackend {
    var diagnosticFormats: (input: AudioFormatDiagnostics, output: AudioFormatDiagnostics)? { nil }
}

struct AudioEngineInputFormat: Equatable, Sendable {
    let sampleRate: Double
    let channelCount: UInt32

    init(audioFormat: AVAudioFormat) {
        sampleRate = audioFormat.sampleRate
        channelCount = audioFormat.channelCount
    }

    init(sampleRate: Double, channelCount: UInt32) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }
}

final class SystemAudioEngineBackend: AudioCaptureBackend, AudioPlaybackBackend, AudioWorkspaceBackend, @unchecked Sendable {
    private enum BackendError: Error {
        case missingAudioFormat
        case nativeRecordingActive
    }

    private let engine: AVAudioEngine
    private let instrumentMixer: AVAudioMixerNode
    private let inputGain = NativeGainProcessor(stage: .input)
    private let outputGain = NativeGainProcessor(stage: .output)
    private let equalizer = NativeEQProcessor()
    private lazy var instrumentChain = InstrumentProcessingChain(processors: [inputGain, equalizer])
    // A stable boundary for the future recorder, independent of chain contents or monitor mute.
    private let processedInstrument = AVAudioMixerNode()
    private let playbackPlayer = AVAudioPlayerNode()
    private let playbackMixer = AVAudioMixerNode()
    private var recordingSink: AudioRecordingSink?
    private var nativeRecorder: AVAudioRecorder?
    private let instrumentTap = AudioTapState()
    private let playbackTap = AudioTapState()
    private var meterTapsInstalled = false

    var inputFormat: AudioEngineInputFormat {
        AudioEngineInputFormat(audioFormat: engine.inputNode.outputFormat(forBus: 0))
    }

    var diagnosticFormats: (input: AudioFormatDiagnostics, output: AudioFormatDiagnostics)? {
        (
            AudioFormatDiagnostics(audioFormat: engine.inputNode.outputFormat(forBus: 0)),
            AudioFormatDiagnostics(audioFormat: engine.outputNode.inputFormat(forBus: 0))
        )
    }

    init(
        engine: AVAudioEngine = AVAudioEngine(),
        instrumentMixer: AVAudioMixerNode = AVAudioMixerNode()
    ) {
        self.engine = engine
        self.instrumentMixer = instrumentMixer
    }

    func resetGraph() throws {
        engine.stop()
        playbackPlayer.stop()
        if meterTapsInstalled {
            processedInstrument.removeTap(onBus: 0)
            playbackMixer.removeTap(onBus: 0)
            meterTapsInstalled = false
        }
        instrumentTap.reset()
        playbackTap.reset()
        engine.disconnectNodeOutput(engine.inputNode)
        instrumentChain.detach(from: engine)
        for node in [processedInstrument, playbackMixer, outputGain.node] as [AVAudioNode] where node.engine != nil {
            engine.disconnectNodeInput(node)
            engine.disconnectNodeOutput(node)
            engine.detach(node)
        }
        if playbackPlayer.engine != nil {
            engine.disconnectNodeOutput(playbackPlayer)
            engine.detach(playbackPlayer)
        }
        if instrumentMixer.engine != nil {
            engine.disconnectNodeInput(instrumentMixer)
            engine.disconnectNodeOutput(instrumentMixer)
            engine.detach(instrumentMixer)
        }
        engine.disconnectNodeInput(engine.mainMixerNode)
        engine.disconnectNodeOutput(engine.mainMixerNode)
        engine.disconnectNodeInput(engine.outputNode)
        engine.reset()
    }

    func attachInstrumentMixer() throws {
        engine.attach(instrumentMixer)
        instrumentChain.attach(to: engine)
        engine.attach(outputGain.node)
        engine.attach(processedInstrument)
        engine.attach(playbackMixer)
        engine.attach(playbackPlayer)
    }

    func connectInputToInstrument(format: AudioEngineInputFormat) throws {
        let audioFormat = engine.inputNode.outputFormat(forBus: 0)
        guard audioFormat.sampleRate == format.sampleRate,
              audioFormat.channelCount == format.channelCount else {
            throw BackendError.missingAudioFormat
        }
        instrumentChain.connect(in: engine, input: engine.inputNode, output: processedInstrument, format: audioFormat)
        engine.connect(processedInstrument, to: instrumentMixer, format: audioFormat)
    }

    func connectInstrumentToMain() throws {
        engine.connect(instrumentMixer, to: engine.mainMixerNode, format: nil)
        engine.connect(playbackPlayer, to: playbackMixer, format: nil)
        engine.connect(playbackMixer, to: engine.mainMixerNode, format: nil)
    }

    func connectMainToOutput() throws {
        let format = engine.isInManualRenderingMode
            ? engine.manualRenderingFormat
            : engine.outputNode.inputFormat(forBus: 0)
        engine.connect(engine.mainMixerNode, to: outputGain.node, format: format)
        engine.connect(outputGain.node, to: engine.outputNode, format: format)
        if !meterTapsInstalled {
            let instrumentObserver = instrumentTap
            let playbackObserver = playbackTap
            let instrumentGeneration = instrumentObserver.beginObservation()
            let playbackGeneration = playbackObserver.beginObservation()
            processedInstrument.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in instrumentObserver.consume(buffer, generation: instrumentGeneration) }
            playbackMixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in playbackObserver.consume(buffer, generation: playbackGeneration) }
            meterTapsInstalled = true
        }
    }

    func setGain(_ configuration: GainConfiguration, for stage: GainStage) throws {
        if stage == .input && nativeRecorder != nil { throw BackendError.nativeRecordingActive }
        try (stage == .input ? inputGain : outputGain).apply(configuration)
    }

    func setTone(inputGain: GainConfiguration, equalizer: EQConfiguration, sampleRate: Double) throws {
        guard nativeRecorder == nil else { throw BackendError.nativeRecordingActive }
        try NativeGainLimits.validate(inputGain, stage: .input)
        try NativeEQLimits.validate(equalizer, sampleRate: sampleRate)
        // AVAudioUnit parameter assignments are nonthrowing after all validation succeeds.
        try self.inputGain.apply(inputGain)
        self.equalizer.applyValidated(equalizer)
    }

    func setInstrumentMixerVolume(_ volume: Float) throws {
        if volume > 0 && nativeRecorder != nil { throw BackendError.nativeRecordingActive }
        instrumentMixer.outputVolume = volume
    }

    func prepare() throws {
        engine.prepare()
    }

    func start() throws {
        try engine.start()
    }

    func stop() {
        playbackPlayer.stop()
        engine.stop()
        instrumentTap.reset()
        playbackTap.reset()
    }

    func beginRecording(to fileURL: URL) throws(AudioRecordingFailure) {
        guard recordingSink == nil, nativeRecorder == nil else { throw .alreadyRecording }
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { throw .fileCreationFailed }
        let nativeVoiceCapture = AVAudioSession.sharedInstance().currentRoute.inputs.contains { $0.portType == .builtInMic }
            && inputGain.node.bypass && equalizer.node.bypass && instrumentMixer.outputVolume == 0
        if nativeVoiceCapture {
            // Neutral built-in-mic capture avoids the discontinuous engine input
            // observed before file writes on the physical device. A same-session
            // AVAudioRecorder control had continuous PCM; forced I/O timing and
            // neutral DSP alone did not fix the engine path. Preserve eligibility:
            // effects/monitoring must retain the graph instead of losing processing.
            // See docs/plan/reference/audio-regression-prevention.md.
            engine.stop()
            do {
                let recorder = try AVAudioRecorder(url: fileURL, settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false
                ])
                guard recorder.record() else { throw AudioRecordingFailure.fileCreationFailed }
                nativeRecorder = recorder
                return
            } catch {
                try? engine.start()
                throw .fileCreationFailed
            }
        }
        let format = processedInstrument.outputFormat(forBus: 0)
        let sink = try AudioRecordingSink(fileURL: fileURL, format: format)
        recordingSink = sink
        instrumentTap.setSink(sink)
    }

    func finishRecording() throws(AudioRecordingFailure) -> CapturedAudio {
        if let recorder = nativeRecorder {
            recorder.stop()
            nativeRecorder = nil
            do {
                let file = try AVAudioFile(forReading: recorder.url)
                guard file.length > 0 else { throw AudioRecordingFailure.emptyRecording }
                engine.prepare()
                try engine.start()
                return CapturedAudio(frameCount: file.length, sampleRate: file.processingFormat.sampleRate, channelCount: file.processingFormat.channelCount)
            } catch { throw .finalizationFailed }
        }
        guard let sink = recordingSink else { throw .notRecording }
        instrumentTap.setSink(nil)
        recordingSink = nil
        return try sink.finish()
    }

    func play(fileURL: URL, completion: @escaping @Sendable () async -> Void) throws(AudioPlaybackFailure) {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: fileURL) } catch { throw .unreadableFile }
        guard file.length > 0, file.processingFormat.sampleRate > 0, file.processingFormat.channelCount > 0 else { throw .invalidFormat }
        // Load a bounded phrase once. The audio player repeats it on the render thread,
        // without completion callbacks or gaps caused by scheduling from the UI.
        let buffer = try AudioLoopBuffer.load(file)
        playbackPlayer.stop()
        engine.connect(playbackPlayer, to: playbackMixer, format: file.processingFormat)
        // Preserve the file's channel layout until the main mixer performs hardware conversion.
        engine.connect(playbackMixer, to: engine.mainMixerNode, format: file.processingFormat)
        playbackPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
        playbackPlayer.play()
    }

    func stopPlayback() { playbackPlayer.stop() }
    func setPlaybackVolume(_ volume: Float) { playbackMixer.outputVolume = volume }
    func level(for channel: MixerChannel) -> AudioLevel { channel == .instrument ? instrumentTap.level : playbackTap.level }

    func applyWorkspace(_ configuration: WorkspaceAudioConfiguration, sampleRate: Double) throws {
        try NativeGainLimits.validate(configuration.inputGain, stage: .input)
        try NativeGainLimits.validate(configuration.outputGain, stage: .output)
        try NativeEQLimits.validate(configuration.equalizer, sampleRate: sampleRate)
        for mix in [configuration.instrumentMix, configuration.playbackMix] {
            guard mix.volume.isFinite, (Float(0)...1).contains(mix.volume) else { throw AudioWorkspaceFailure.invalidConfiguration }
        }
        try inputGain.apply(configuration.inputGain)
        try outputGain.apply(configuration.outputGain)
        equalizer.applyValidated(configuration.equalizer)
        instrumentMixer.outputVolume = configuration.instrumentMix.muted ? 0 : configuration.instrumentMix.volume
        playbackMixer.outputVolume = configuration.playbackMix.muted ? 0 : configuration.playbackMix.volume
    }
}
