import AVFoundation
import Foundation
import UIKit

protocol AudioSessionManaging: AnyObject, Sendable {
    var snapshot: AudioSessionSnapshot { get async }
    var currentRoute: AudioRoute { get async }
    var availableInputs: [AudioInput] { get async }
    var preferredInput: AudioInput? { get async }

    func activate() async throws(AudioSessionError) -> AudioSessionSnapshot
    func deactivate() async throws(AudioSessionError)
    func selectPreferredInput(id: String?) async throws(AudioSessionError)
    func events() async -> AsyncStream<AudioSessionEvent>
}

struct AudioSessionConfiguration: Equatable, Sendable {
    let preferredSampleRate: Double
    let preferredIOBufferDuration: TimeInterval

    static let bassPractice = AudioSessionConfiguration(
        preferredSampleRate: 48_000,
        // Zero means system-negotiated duration. Forced durations produced
        // periodic silence on the built-in input of the physical test device.
        preferredIOBufferDuration: 0
    )
}

struct AudioSessionSnapshot: Equatable, Sendable {
    let requestedSampleRate: Double
    let requestedIOBufferDuration: TimeInterval
    let actualSampleRate: Double?
    let actualIOBufferDuration: TimeInterval?
    let isActive: Bool
}

enum AudioSessionError: Error, Equatable, Sendable {
    case categoryConfigurationFailed
    case preferredSampleRateFailed(requested: Double)
    case preferredIOBufferDurationFailed(requested: TimeInterval)
    case activationFailed
    case deactivationFailed
    case inputUnavailable(id: String)
    case inputSelectionFailed(id: String?)
}

actor AudioControlActor: AudioSessionManaging, AudioEngineProtocol, AudioToneControlling, AudioRecordingControlling, AudioPlaybackControlling, AudioMixerControlling, AudioWorkspaceControlling {
    private let backend: any AudioSessionBackend
    private let engineBackend: any AudioEngineBackend
    private let configuration: AudioSessionConfiguration
    private var eventContinuations: [UUID: AsyncStream<AudioSessionEvent>.Continuation] = [:]
    private var observationTask: Task<Void, Never>?
    private var wasActiveBeforeInterruption = false
    private var interruptionInProgress = false
    private var resumeEngineAfterInterruption = false
    private var configuredInputFormat: AudioEngineInputFormat?
    private var configuredOutputFormat: AudioFormatDiagnostics?
    private var isInBackground = false
    private var inputGain: GainConfiguration = .unity
    private var outputGain: GainConfiguration = .unity
    private(set) var equalizer: EQConfiguration = .flat
    private(set) var selectedProfileID: UUID? = BuiltInInputProfiles.customID
    private(set) var recordingState: AudioRecordingState = .idle
    private(set) var recordings: [Recording] = []
    private(set) var playbackState: AudioPlaybackState = .stopped
    private var playbackGeneration: UUID?
    private var playbackMix = MixerChannelConfiguration(volume: 1, muted: false)

    private(set) var snapshot: AudioSessionSnapshot
    private(set) var currentRoute: AudioRoute
    private(set) var availableInputs: [AudioInput]
    private(set) var preferredInput: AudioInput?
    private(set) var state: AudioEngineState = .stopped
    private(set) var monitoringEnabled = false
    private(set) var monitoringGain: Float = 1

    var diagnostics: AudioEngineDiagnostics? {
        guard snapshot.isActive, let formats = engineBackend.diagnosticFormats else { return nil }
        return AudioEngineDiagnostics(
            actualSessionSampleRate: backend.sampleRate,
            inputChannelCount: formats.input.channelCount,
            inputFormat: formats.input,
            outputFormat: formats.output,
            actualIOBufferDuration: backend.ioBufferDuration
        )
    }

    init(
        backend: any AudioSessionBackend,
        engineBackend: any AudioEngineBackend = SystemAudioEngineBackend(),
        configuration: AudioSessionConfiguration = .bassPractice
    ) {
        self.backend = backend
        self.engineBackend = engineBackend
        self.configuration = configuration
        currentRoute = backend.currentRoute
        availableInputs = backend.availableInputs
        preferredInput = nil
        snapshot = AudioSessionSnapshot(
            requestedSampleRate: configuration.preferredSampleRate,
            requestedIOBufferDuration: configuration.preferredIOBufferDuration,
            actualSampleRate: nil,
            actualIOBufferDuration: nil,
            isActive: false
        )

    }

    func start() throws(AudioEngineFailure) {
        guard !isInBackground else {
            throw .startUnavailableInBackground
        }
        guard state != .running, state != .starting else {
            return
        }

        state = .starting

        do {
            _ = try activate()
        } catch {
            let failure = AudioEngineFailure.sessionActivation(error)
            deactivateAfterFailedStart()
            state = .failed(failure)
            throw failure
        }

        do {
            try configureGraph()
        } catch let failure {
            stopMediaAndBackend()
            deactivateAfterFailedStart()
            state = .failed(failure)
            throw failure
        }

        do {
            try engineBackend.prepare()
        } catch {
            let failure = AudioEngineFailure.preparationFailed
            stopMediaAndBackend()
            deactivateAfterFailedStart()
            state = .failed(failure)
            throw failure
        }

        do {
            try engineBackend.start()
        } catch {
            let failure = AudioEngineFailure.startFailed
            stopMediaAndBackend()
            deactivateAfterFailedStart()
            state = .failed(failure)
            throw failure
        }

        state = .running
        startObservationIfNeeded()
    }

    private func configureGraph() throws(AudioEngineFailure) {
        let inputFormat = engineBackend.inputFormat
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw .invalidInputFormat(
                sampleRate: inputFormat.sampleRate,
                channelCount: inputFormat.channelCount
            )
        }

        do {
            try engineBackend.resetGraph()
            try engineBackend.attachInstrumentMixer()
            try engineBackend.connectInputToInstrument(format: inputFormat)
            try engineBackend.connectInstrumentToMain()
            try engineBackend.connectMainToOutput()
            try engineBackend.setInstrumentMixerVolume(effectiveMonitoringVolume)
            try engineBackend.setTone(inputGain: inputGain, equalizer: equalizer, sampleRate: inputFormat.sampleRate)
            try engineBackend.setGain(outputGain, for: .output)
            if let mixer = engineBackend as? any AudioMixerBackend { try mixer.setPlaybackVolume(playbackMix.muted ? 0 : playbackMix.volume) }
            configuredInputFormat = inputFormat
            configuredOutputFormat = engineBackend.diagnosticFormats?.output
        } catch {
            throw .graphConfigurationFailed
        }
    }

    func setMonitoring(enabled: Bool, gain: Float) throws(AudioEngineFailure) {
        guard gain.isFinite else { throw .monitoringConfigurationFailed }
        let clampedGain = min(max(gain, 0), 1)
        let previousVolume = effectiveMonitoringVolume
        let requestedVolume = enabled ? clampedGain : 0

        guard monitoringEnabled != enabled || monitoringGain != clampedGain else {
            return
        }

        if previousVolume != requestedVolume {
            do {
                try engineBackend.setInstrumentMixerVolume(requestedVolume)
            } catch {
                throw .monitoringConfigurationFailed
            }
        }

        monitoringEnabled = enabled
        monitoringGain = clampedGain
        publish(.mixerChanged)
    }

    func mixerConfiguration(for channel: MixerChannel) -> MixerChannelConfiguration {
        channel == .instrument ? MixerChannelConfiguration(volume: monitoringGain, muted: !monitoringEnabled) : playbackMix
    }

    func setMixerConfiguration(_ configuration: MixerChannelConfiguration, for channel: MixerChannel) throws(AudioMixerFailure) {
        guard configuration.volume.isFinite, (Float(0)...1).contains(configuration.volume) else { throw .invalidVolume }
        if channel == .instrument {
            do { try setMonitoring(enabled: !configuration.muted, gain: configuration.volume) }
            catch { throw .writeFailed }
        } else {
            guard let mixer = engineBackend as? any AudioMixerBackend else { throw .unsupportedBackend }
            do { try mixer.setPlaybackVolume(configuration.muted ? 0 : configuration.volume) }
            catch { throw .writeFailed }
            playbackMix = configuration
            publish(.mixerChanged)
        }
    }

    func level(for channel: MixerChannel) -> AudioLevel? {
        guard state == .running else { return .silent }
        return (engineBackend as? any AudioMixerBackend)?.level(for: channel)
    }

    func gain(for stage: GainStage) -> GainConfiguration {
        stage == .input ? inputGain : outputGain
    }

    func setGain(_ configuration: GainConfiguration, for stage: GainStage) throws(GainProcessingError) {
        try NativeGainLimits.validate(configuration, stage: stage)
        guard gain(for: stage) != configuration else { return }
        do { try engineBackend.setGain(configuration, for: stage) }
        catch { throw .backendFailure }
        if stage == .input { inputGain = configuration; selectedProfileID = nil }
        else { outputGain = configuration }
        publish(.toneChanged)
    }

    func setEqualizer(_ configuration: EQConfiguration) throws(ToneProcessingError) {
        try commitTone(inputGain: inputGain, equalizer: configuration)
        equalizer = configuration
        selectedProfileID = nil
        publish(.toneChanged)
    }

    func applyProfile(_ profile: InputProfile) throws(ToneProcessingError) {
        let gain = GainConfiguration(decibels: profile.inputGainDecibels, bypassed: false)
        try commitTone(inputGain: gain, equalizer: profile.eq)
        inputGain = gain
        equalizer = profile.eq
        selectedProfileID = profile.id
        publish(.toneChanged)
    }

    func workspaceSnapshot() -> AudioWorkspaceSnapshot {
        AudioWorkspaceSnapshot(audio: WorkspaceAudioConfiguration(inputGain: inputGain, outputGain: outputGain, equalizer: equalizer, instrumentMix: mixerConfiguration(for: .instrument), playbackMix: playbackMix, inputProfileID: selectedProfileID), recordings: recordings)
    }

    func restoreWorkspace(_ snapshot: AudioWorkspaceSnapshot) throws(AudioWorkspaceFailure) {
        guard state == .stopped else { throw .engineRunning }
        guard let workspace = engineBackend as? any AudioWorkspaceBackend else { throw .unsupportedBackend }
        let configuration = snapshot.audio
        let sampleRate = configuredInputFormat?.sampleRate ?? self.configuration.preferredSampleRate
        do {
            try NativeGainLimits.validate(configuration.inputGain, stage: .input)
            try NativeGainLimits.validate(configuration.outputGain, stage: .output)
            try NativeEQLimits.validate(configuration.equalizer, sampleRate: sampleRate)
            for mix in [configuration.instrumentMix, configuration.playbackMix] {
                guard mix.volume.isFinite, (Float(0)...1).contains(mix.volume) else { throw AudioWorkspaceFailure.invalidConfiguration }
            }
        } catch { throw .invalidConfiguration }
        do { try workspace.applyWorkspace(configuration, sampleRate: sampleRate) }
        catch { throw .backendFailure }
        inputGain = configuration.inputGain
        outputGain = configuration.outputGain
        equalizer = configuration.equalizer
        monitoringGain = configuration.instrumentMix.volume
        monitoringEnabled = !configuration.instrumentMix.muted
        playbackMix = configuration.playbackMix
        selectedProfileID = configuration.inputProfileID
        recordings = snapshot.recordings
        recordingState = .idle
        playbackState = .stopped
        publish(.workspaceChanged)
    }

    func profileSnapshot(name: String) throws(InputProfileValidationError) -> InputProfile {
        try InputProfile(name: name, instrument: .custom, inputGainDecibels: inputGain.bypassed ? 0 : inputGain.decibels, eq: equalizer)
    }

    private func commitTone(inputGain: GainConfiguration, equalizer: EQConfiguration) throws(ToneProcessingError) {
        let sampleRate = configuredInputFormat?.sampleRate ?? snapshot.actualSampleRate ?? configuration.preferredSampleRate
        guard inputGain.decibels.isFinite, NativeGainLimits.range.contains(inputGain.decibels) else {
            throw .unsupportedInputGain(inputGain.decibels)
        }
        try NativeEQLimits.validate(equalizer, sampleRate: sampleRate)
        do { try engineBackend.setTone(inputGain: inputGain, equalizer: equalizer, sampleRate: sampleRate) }
        catch { throw .backendFailure }
    }

    private var effectiveMonitoringVolume: Float {
        monitoringEnabled ? monitoringGain : 0
    }

    func startRecording(id: UUID, to fileURL: URL) throws(AudioRecordingFailure) {
        guard state == .running else { throw .engineNotRunning }
        if case .recording = recordingState { throw .alreadyRecording }
        guard let capture = engineBackend as? any AudioCaptureBackend else { throw .unsupportedBackend }
        do { try capture.beginRecording(to: fileURL) }
        catch { recordingState = .failed(error); throw error }
        recordingState = .recording(id: id, fileURL: fileURL, startedAt: Date())
        publish(.mediaChanged)
    }

    @discardableResult func stopRecording() throws(AudioRecordingFailure) -> Recording {
        guard case let .recording(id, fileURL, startedAt) = recordingState else { throw .notRecording }
        guard let capture = engineBackend as? any AudioCaptureBackend else { throw .unsupportedBackend }
        do {
            let audio = try capture.finishRecording()
            let recording = Recording(id: id, fileURL: fileURL, createdAt: startedAt, frameCount: audio.frameCount, sampleRate: audio.sampleRate, channelCount: audio.channelCount)
            recordings.append(recording)
            recordingState = .idle
            publish(.mediaChanged)
            return recording
        } catch {
            recordingState = .failed(error)
            publish(.mediaChanged)
            throw error
        }
    }

    func play(_ recording: Recording) throws(AudioPlaybackFailure) {
        guard state == .running else { throw .engineUnavailable }
        guard let player = engineBackend as? any AudioPlaybackBackend else { throw .unsupportedBackend }
        let id = recording.id
        let generation = UUID()
        playbackGeneration = generation
        do {
            try player.play(fileURL: recording.fileURL) { [weak self] in await self?.playbackCompleted(id: id, generation: generation) }
            playbackState = .playing(id)
            publish(.mediaChanged)
        } catch {
            playbackGeneration = nil
            player.stopPlayback()
            playbackState = .failed(error)
            publish(.mediaChanged)
            throw error
        }
    }

    func stopPlayback() {
        playbackGeneration = nil
        playbackState = .stopped
        (engineBackend as? any AudioPlaybackBackend)?.stopPlayback()
        publish(.mediaChanged)
    }

    private func playbackCompleted(id: UUID, generation: UUID) {
        guard playbackGeneration == generation, playbackState == .playing(id) else { return }
        playbackGeneration = nil
        playbackState = .stopped
        publish(.mediaChanged)
    }

    private func stopMediaAndBackend() {
        if case .recording = recordingState { _ = try? stopRecording() }
        playbackState = .stopped
        playbackGeneration = nil
        (engineBackend as? any AudioPlaybackBackend)?.stopPlayback()
        engineBackend.stop()
    }

    func stop() throws(AudioEngineFailure) {
        resumeEngineAfterInterruption = false
        wasActiveBeforeInterruption = false
        guard state != .stopped else {
            return
        }

        stopMediaAndBackend()

        do throws(AudioSessionError) {
            if state == .interrupted && !snapshot.isActive {
                do {
                    try backend.setActive(false, notifyOthersOnDeactivation: true)
                } catch {
                    throw AudioSessionError.deactivationFailed
                }
            } else {
                try deactivate()
            }
        } catch {
            let failure = AudioEngineFailure.sessionDeactivation(error)
            state = .failed(failure)
            throw failure
        }

        state = .stopped
    }

    private func deactivateAfterFailedStart() {
        if snapshot.isActive {
            try? deactivate()
        } else {
            try? backend.setActive(false, notifyOthersOnDeactivation: true)
        }
    }

    func events() -> AsyncStream<AudioSessionEvent> {
        startObservationIfNeeded()
        let identifier = UUID()
        let (stream, continuation) = AsyncStream<AudioSessionEvent>.makeStream()
        eventContinuations[identifier] = continuation
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeEventContinuation(identifier: identifier)
            }
        }
        return stream
    }

    func activate() throws(AudioSessionError) -> AudioSessionSnapshot {
        guard !snapshot.isActive else {
            return snapshot
        }

        do {
            try backend.configureForMeasurement()
        } catch {
            throw .categoryConfigurationFailed
        }

        do {
            try backend.setPreferredSampleRate(configuration.preferredSampleRate)
        } catch {
            throw .preferredSampleRateFailed(requested: configuration.preferredSampleRate)
        }

        do {
            try backend.setPreferredIOBufferDuration(configuration.preferredIOBufferDuration)
        } catch {
            throw .preferredIOBufferDurationFailed(
                requested: configuration.preferredIOBufferDuration
            )
        }

        do {
            try backend.setActive(true, notifyOthersOnDeactivation: false)
        } catch {
            throw .activationFailed
        }

        snapshot = AudioSessionSnapshot(
            requestedSampleRate: configuration.preferredSampleRate,
            requestedIOBufferDuration: configuration.preferredIOBufferDuration,
            actualSampleRate: backend.sampleRate,
            actualIOBufferDuration: backend.ioBufferDuration,
            isActive: true
        )
        availableInputs = backend.availableInputs
        currentRoute = backend.currentRoute
        return snapshot
    }

    func deactivate() throws(AudioSessionError) {
        guard snapshot.isActive else {
            return
        }

        do {
            try backend.setActive(false, notifyOthersOnDeactivation: true)
        } catch {
            throw .deactivationFailed
        }

        snapshot = AudioSessionSnapshot(
            requestedSampleRate: snapshot.requestedSampleRate,
            requestedIOBufferDuration: snapshot.requestedIOBufferDuration,
            actualSampleRate: snapshot.actualSampleRate,
            actualIOBufferDuration: snapshot.actualIOBufferDuration,
            isActive: false
        )
    }

    func selectPreferredInput(id: String?) throws(AudioSessionError) {
        let refreshedInputs = backend.availableInputs
        availableInputs = refreshedInputs

        guard let id else {
            do {
                try backend.setPreferredInput(id: nil)
            } catch {
                throw .inputSelectionFailed(id: nil)
            }
            preferredInput = nil
            return
        }

        guard let input = refreshedInputs.first(where: { $0.id == id }) else {
            throw .inputUnavailable(id: id)
        }

        do {
            try backend.setPreferredInput(id: id)
        } catch {
            throw .inputSelectionFailed(id: id)
        }
        preferredInput = input
    }

    private func receive(
        _ event: AudioSessionBackendEvent,
        from backend: any AudioSessionBackend
    ) {
        switch event {
        case let .routeChanged(reason):
            let previousRoute = currentRoute
            currentRoute = backend.currentRoute
            availableInputs = backend.availableInputs
            reconcilePreferredInput(using: backend)
            refreshActualSessionValues()
            if state == .running,
               previousRoute != currentRoute
                || configuredInputFormat != engineBackend.inputFormat
                || configuredOutputFormat != engineBackend.diagnosticFormats?.output {
                rebuildRunningEngine()
            }
            let routedEvent = AudioSessionEvent.routeChanged(
                route: currentRoute,
                reason: reason
            )
            publish(routedEvent)
        case .interruptionBegan:
            if !interruptionInProgress {
                interruptionInProgress = true
                wasActiveBeforeInterruption = snapshot.isActive
                resumeEngineAfterInterruption = state == .running
                if resumeEngineAfterInterruption {
                    stopMediaAndBackend()
                    state = .interrupted
                }
            }
            snapshot = snapshot.withActiveState(false)
            publish(.interruptionBegan)
        case let .interruptionEnded(shouldResume):
            let shouldReactivate = interruptionInProgress && shouldResume && wasActiveBeforeInterruption && !isInBackground
            let shouldRestartEngine = shouldReactivate && resumeEngineAfterInterruption
            interruptionInProgress = false
            wasActiveBeforeInterruption = false
            resumeEngineAfterInterruption = false
            if shouldRestartEngine {
                try? start()
            } else if shouldReactivate {
                _ = try? activate()
            }
            publish(.interruptionEnded(shouldResume: shouldResume))
        case .enteredBackground:
            isInBackground = true
            resumeEngineAfterInterruption = false
            wasActiveBeforeInterruption = false
            if state != .stopped {
                try? stop()
            } else {
                try? deactivate()
            }
            publish(.enteredBackground)
        case .enteredForeground:
            isInBackground = false
            currentRoute = backend.currentRoute
            availableInputs = backend.availableInputs
            reconcilePreferredInput(using: backend)
            refreshActualSessionValues()
            publish(.enteredForeground)
        }
    }

    private func refreshActualSessionValues() {
        guard snapshot.isActive else { return }
        snapshot = AudioSessionSnapshot(
            requestedSampleRate: snapshot.requestedSampleRate,
            requestedIOBufferDuration: snapshot.requestedIOBufferDuration,
            actualSampleRate: backend.sampleRate,
            actualIOBufferDuration: backend.ioBufferDuration,
            isActive: true
        )
    }

    private func rebuildRunningEngine() {
        stopMediaAndBackend()
        state = .stopped
        try? start()
    }

    private func reconcilePreferredInput(using backend: any AudioSessionBackend) {
        guard let preferredInput else {
            return
        }

        if let refreshedInput = availableInputs.first(where: { $0.id == preferredInput.id }) {
            self.preferredInput = refreshedInput
        } else {
            try? backend.setPreferredInput(id: nil)
            self.preferredInput = nil
        }
    }

    private func publish(_ event: AudioSessionEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    private func removeEventContinuation(identifier: UUID) {
        eventContinuations[identifier] = nil
    }

    deinit {
        observationTask?.cancel()
    }

    private func startObservationIfNeeded() {
        guard observationTask == nil else {
            return
        }
        let backend = backend
        observationTask = Task { [weak self] in
            for await event in backend.events {
                guard !Task.isCancelled else {
                    return
                }
                await self?.receive(event, from: backend)
            }
        }
    }
}

enum AudioSessionBackendEvent: Equatable, Sendable {
    case routeChanged(reason: AudioRouteChangeReason)
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case enteredBackground
    case enteredForeground
}

protocol AudioSessionBackend: Sendable {
    var sampleRate: Double { get }
    var ioBufferDuration: TimeInterval { get }
    var currentRoute: AudioRoute { get }
    var availableInputs: [AudioInput] { get }
    var events: AsyncStream<AudioSessionBackendEvent> { get }

    func configureForMeasurement() throws
    func setPreferredSampleRate(_ sampleRate: Double) throws
    func setPreferredIOBufferDuration(_ duration: TimeInterval) throws
    func setActive(_ active: Bool, notifyOthersOnDeactivation: Bool) throws
    func setPreferredInput(id: String?) throws
}

final class SystemAudioSessionBackend: AudioSessionBackend, @unchecked Sendable {
    private let session: AVAudioSession
    private let notificationCenter: NotificationCenter
    private let eventContinuation: AsyncStream<AudioSessionBackendEvent>.Continuation
    private var notificationObservers: [NSObjectProtocol] = []

    let events: AsyncStream<AudioSessionBackendEvent>

    var sampleRate: Double {
        session.sampleRate
    }

    var ioBufferDuration: TimeInterval {
        session.ioBufferDuration
    }

    var currentRoute: AudioRoute {
        AudioRoute(
            inputs: session.currentRoute.inputs.map(AudioDevice.init(portDescription:)),
            outputs: session.currentRoute.outputs.map(AudioDevice.init(portDescription:))
        )
    }

    var availableInputs: [AudioInput] {
        (session.availableInputs ?? []).map(AudioInput.init(portDescription:))
    }

    init(
        session: AVAudioSession = .sharedInstance(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.session = session
        self.notificationCenter = notificationCenter
        let (events, continuation) = AsyncStream<AudioSessionBackendEvent>.makeStream()
        self.events = events
        eventContinuation = continuation
        notificationObservers.append(notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: nil
        ) { notification in
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            continuation.yield(
                .routeChanged(reason: AudioRouteChangeReason(rawValue: rawReason))
            )
        })
        notificationObservers.append(notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: nil
        ) { notification in
            guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
                return
            }
            switch type {
            case .began:
                continuation.yield(.interruptionBegan)
            case .ended:
                let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                continuation.yield(
                    .interruptionEnded(shouldResume: options.contains(.shouldResume))
                )
            @unknown default:
                return
            }
        })
        notificationObservers.append(notificationCenter.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { _ in
            continuation.yield(.enteredBackground)
        })
        notificationObservers.append(notificationCenter.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { _ in
            continuation.yield(.enteredForeground)
        })
    }

    deinit {
        for observer in notificationObservers {
            notificationCenter.removeObserver(observer)
        }
        eventContinuation.finish()
    }

    func configureForMeasurement() throws {
        // Use the normal duplex playback mode for audible practice. Measurement
        // mode minimizes system processing but has not provided the expected
        // loudspeaker playback on the physical device under test.
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
    }

    func setPreferredSampleRate(_ sampleRate: Double) throws {
        try session.setPreferredSampleRate(sampleRate)
    }

    func setPreferredIOBufferDuration(_ duration: TimeInterval) throws {
        guard duration > 0 else { return }
        try session.setPreferredIOBufferDuration(duration)
    }

    func setActive(_ active: Bool, notifyOthersOnDeactivation: Bool) throws {
        let options: AVAudioSession.SetActiveOptions = notifyOthersOnDeactivation
            ? [.notifyOthersOnDeactivation]
            : []
        try session.setActive(active, options: options)
        if active, session.currentRoute.outputs.contains(where: { $0.portType == .builtInReceiver }) {
            // Some device/mode combinations retain the receiver despite the
            // category default. Apply the explicit override after activation,
            // when the effective route is known; never override headphones.
            try session.overrideOutputAudioPort(.speaker)
        }
        AppLogger().audioSessionChanged("active=\(active) category=\(session.category.rawValue) mode=\(session.mode.rawValue) sampleRate=\(session.sampleRate) ioBuffer=\(session.ioBufferDuration) inputChannels=\(session.inputNumberOfChannels) outputs=\(session.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ","))")
    }

    func setPreferredInput(id: String?) throws {
        let port: AVAudioSessionPortDescription?
        if let id {
            guard let availablePort = session.availableInputs?.first(where: { $0.uid == id }) else {
                throw SystemAudioSessionBackendError.inputUnavailable
            }
            port = availablePort
        } else {
            port = nil
        }
        try session.setPreferredInput(port)
    }
}

private enum SystemAudioSessionBackendError: Error {
    case inputUnavailable
}

private extension AudioSessionSnapshot {
    func withActiveState(_ isActive: Bool) -> Self {
        AudioSessionSnapshot(
            requestedSampleRate: requestedSampleRate,
            requestedIOBufferDuration: requestedIOBufferDuration,
            actualSampleRate: actualSampleRate,
            actualIOBufferDuration: actualIOBufferDuration,
            isActive: isActive
        )
    }
}

private extension AudioDevice {
    init(portDescription: AVAudioSessionPortDescription) {
        self.init(
            id: portDescription.uid,
            name: portDescription.portName,
            portType: portDescription.portType.rawValue
        )
    }
}

private extension AudioInput {
    init(portDescription: AVAudioSessionPortDescription) {
        self.init(
            id: portDescription.uid,
            name: portDescription.portName,
            portType: portDescription.portType.rawValue
        )
    }
}

private extension AudioRouteChangeReason {
    init(rawValue: UInt?) {
        guard let rawValue else {
            self = .unknown
            return
        }

        switch AVAudioSession.RouteChangeReason(rawValue: rawValue) {
        case .unknown:
            self = .unknown
        case .newDeviceAvailable:
            self = .newDeviceAvailable
        case .oldDeviceUnavailable:
            self = .oldDeviceUnavailable
        case .categoryChange:
            self = .categoryChange
        case .override:
            self = .override
        case .wakeFromSleep:
            self = .wakeFromSleep
        case .noSuitableRouteForCategory:
            self = .noSuitableRouteForCategory
        case .routeConfigurationChange:
            self = .routeConfigurationChange
        case .none:
            self = .unrecognized(rawValue)
        @unknown default:
            self = .unrecognized(rawValue)
        }
    }
}
