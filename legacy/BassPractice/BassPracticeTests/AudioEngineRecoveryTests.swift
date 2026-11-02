import Foundation
import Testing
@testable import BassPractice

@Suite("Audio engine recovery")
struct AudioEngineRecoveryTests {
    @Test("Interrupted Stop maps backend deactivation failure to a typed engine failure")
    func interruptedStopDeactivationFailureIsTyped() async throws {
        // Arrange
        let session = TestDoubles.Session()
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: session, engineBackend: engine)
        try await control.start()
        var events = await control.events().makeAsyncIterator()
        session.send(.interruptionBegan)
        _ = await events.next()
        session.failDeactivation = true
        var failure: AudioEngineFailure?

        // Act
        do { try await control.stop() } catch { failure = error }

        // Assert
        #expect(failure == .sessionDeactivation(.deactivationFailed))
        #expect(await control.state == .failed(.sessionDeactivation(.deactivationFailed)))
    }

    @Test("Stopped route changes reconcile inputs without starting audio")
    func stoppedRouteDoesNotStartAndDisconnectClearsStablePreference() async throws {
        // Arrange
        let session = TestDoubles.Session()
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: session, engineBackend: engine)
        session.inputs = [Fixtures.usbInput]
        try await control.selectPreferredInput(id: Fixtures.usbInput.id)
        var events = await control.events().makeAsyncIterator()

        // Act
        session.inputs = []
        session.send(.routeChanged(reason: .oldDeviceUnavailable))
        _ = await events.next()
        let disconnectedPreference = await control.preferredInput
        session.inputs = [AudioInput(id: "different-port", name: Fixtures.usbInput.name, portType: "USBAudio")]
        session.send(.routeChanged(reason: .newDeviceAvailable))
        _ = await events.next()

        // Assert
        #expect(disconnectedPreference == nil)
        #expect(await control.preferredInput == nil)
        #expect(await control.state == .stopped)
        #expect(engine.starts == 0)
    }

    @Test("Explicit Start in background returns a typed failure without starting audio")
    func startInBackgroundRejected() async {
        // Arrange
        let session = TestDoubles.Session()
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: session, engineBackend: engine)
        var events = await control.events().makeAsyncIterator()
        session.send(.enteredBackground)
        _ = await events.next()
        var failure: AudioEngineFailure?

        // Act
        do { try await control.start() } catch { failure = error }

        // Assert
        #expect(failure == .startUnavailableInBackground)
        #expect(engine.starts == 0)
    }

    @Test("Cancelling a UI subscriber while stopped preserves later engine recovery")
    func cancelledStoppedSubscriberDoesNotEndBackendObservation() async throws {
        // Arrange
        let session = TestDoubles.Session()
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: session, engineBackend: engine)
        let stream = await control.events()
        let subscriber = Task { for await _ in stream {} }

        // Act
        subscriber.cancel()
        await subscriber.value
        try await control.start()
        var deactivations = session.deactivationEvents.makeAsyncIterator()
        session.send(.enteredBackground)
        _ = await deactivations.next()

        // Assert
        #expect(await control.state == .stopped)
        #expect(session.deactivations == 1)
    }

    @Test("Cancelling the background UI subscriber preserves foreground reconciliation and explicit Start")
    func cancelledBackgroundSubscriberPreservesForeground() async throws {
        // Arrange
        let session = TestDoubles.Session()
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: session, engineBackend: engine)
        try await control.start()
        let stream = await control.events()
        let subscriber = Task { for await _ in stream {} }
        var deactivations = session.deactivationEvents.makeAsyncIterator()
        session.send(.enteredBackground)
        _ = await deactivations.next()

        // Act
        subscriber.cancel()
        await subscriber.value
        var foregroundEvents = await control.events().makeAsyncIterator()
        session.send(.enteredForeground)
        _ = await foregroundEvents.next()
        try await control.start()

        // Assert
        #expect(await control.state == .running)
        #expect(engine.starts == 2)
    }

    @Test("Running audio observes background events without a UI event subscriber")
    func observationIsIndependentOfUI() async throws {
        // Arrange
        let session = TestDoubles.Session()
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: session, engineBackend: engine)
        try await control.start()
        var deactivations = session.deactivationEvents.makeAsyncIterator()

        // Act
        session.send(.enteredBackground)
        _ = await deactivations.next()
        let state = await control.state

        // Assert
        #expect(state == .stopped)
        #expect(engine.stops == 1)
        #expect(session.deactivations == 1)
    }

    @Test("Background cancels interruption resume even after returning to foreground")
    func backgroundCancelsInterruptionResume() async throws {
        // Arrange
        let session = TestDoubles.Session()
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: session, engineBackend: engine)
        try await control.start()
        var events = await control.events().makeAsyncIterator()

        // Act
        for event in [AudioSessionBackendEvent.interruptionBegan, .enteredBackground, .enteredForeground, .interruptionEnded(shouldResume: true)] {
            session.send(event)
            _ = await events.next()
        }

        // Assert
        #expect(await control.state == .stopped)
        #expect(engine.starts == 1)
        #expect(session.deactivations == 1)
    }

    @Test("Interruption resumes only permitted prior running audio", arguments: [true, false])
    func interruptionResumePolicy(shouldResume: Bool) async throws {
        // Arrange
        let session = TestDoubles.Session()
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: session, engineBackend: engine)
        try await control.start()
        var events = await control.events().makeAsyncIterator()

        // Act
        session.send(.interruptionBegan)
        _ = await events.next()
        let interruptedState = await control.state
        session.send(.interruptionEnded(shouldResume: shouldResume))
        _ = await events.next()

        // Assert
        #expect(interruptedState == .interrupted)
        #expect(await control.state == (shouldResume ? .running : .interrupted))
        #expect(engine.starts == (shouldResume ? 2 : 1))
    }

    @Test("Duplicate interruption begin preserves the original running intent")
    func duplicateBeginPreservesIntent() async throws {
        // Arrange
        let session = TestDoubles.Session()
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: session, engineBackend: engine)
        try await control.start()
        var events = await control.events().makeAsyncIterator()

        // Act
        for event in [AudioSessionBackendEvent.interruptionBegan, .interruptionBegan, .interruptionEnded(shouldResume: true)] {
            session.send(event)
            _ = await events.next()
        }

        // Assert
        #expect(await control.state == .running)
        #expect(engine.starts == 2)
        #expect(engine.stops == 1)
    }

    @Test("An interruption end without a begin never starts stopped audio")
    func endWithoutBeginDoesNotStart() async {
        // Arrange
        let session = TestDoubles.Session()
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: session, engineBackend: engine)
        var events = await control.events().makeAsyncIterator()

        // Act
        session.send(.interruptionEnded(shouldResume: true))
        _ = await events.next()

        // Assert
        #expect(engine.starts == 0)
        #expect(await control.state == .stopped)
    }

    @Test("Explicit Stop during interruption cancels later resume")
    func explicitStopCancelsResume() async throws {
        // Arrange
        let session = TestDoubles.Session()
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: session, engineBackend: engine)
        try await control.start()
        var events = await control.events().makeAsyncIterator()
        session.send(.interruptionBegan)
        _ = await events.next()

        // Act
        try await control.stop()
        session.send(.interruptionEnded(shouldResume: true))
        _ = await events.next()

        // Assert
        #expect(await control.state == .stopped)
        #expect(engine.starts == 1)
    }

    @Test("Background stops and deactivates audio and foreground never restarts it")
    func backgroundForegroundPolicy() async throws {
        // Arrange
        let session = TestDoubles.Session()
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: session, engineBackend: engine)
        try await control.start()
        var events = await control.events().makeAsyncIterator()

        // Act
        session.send(.enteredBackground)
        _ = await events.next()
        let backgroundSnapshot = await control.snapshot
        session.send(.enteredForeground)
        _ = await events.next()

        // Assert
        #expect(!backgroundSnapshot.isActive)
        #expect(await control.state == .stopped)
        #expect(engine.stops == 1)
        #expect(engine.starts == 1)
        #expect(session.deactivations == 1)
    }

    @Test("A meaningful route or format change rebuilds running audio once", arguments: Fixtures.routeChanges)
    fileprivate func routeRecovery(testCase: Fixtures.RouteCase) async throws {
        // Arrange
        let session = TestDoubles.Session()
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: session, engineBackend: engine)
        try await control.setMonitoring(enabled: true, gain: 0.3)
        try await control.start()
        var events = await control.events().makeAsyncIterator()

        // Act
        session.route = testCase.route
        engine.format = testCase.format
        engine.outputFormat = testCase.outputFormat
        session.send(.routeChanged(reason: .routeConfigurationChange))
        _ = await events.next()

        // Assert
        #expect(engine.starts == testCase.expectedStarts)
        #expect(engine.volume == 0.3)
        #expect(await control.state == .running)
    }

    @Test("Failed route recovery makes one attempt then exposes a typed failure for explicit retry")
    func recoveryFailureAllowsExplicitRetry() async throws {
        // Arrange
        let session = TestDoubles.Session()
        let engine = TestDoubles.Engine()
        let control = AudioControlActor(backend: session, engineBackend: engine)
        try await control.start()
        var events = await control.events().makeAsyncIterator()
        engine.failStart = true
        session.route = Fixtures.usbRoute

        // Act
        session.send(.routeChanged(reason: .newDeviceAvailable))
        _ = await events.next()
        let failureState = await control.state
        let failedStarts = engine.starts
        engine.failStart = false
        try await control.start()

        // Assert
        #expect(failureState == .failed(.startFailed))
        #expect(failedStarts == 2)
        #expect(session.deactivations == 1)
        #expect(await control.state == .running)
        #expect(engine.starts == 3)
    }
}

private enum Fixtures {
    struct RouteCase: Sendable {
        let route: AudioRoute
        let format: AudioEngineInputFormat
        var outputFormat: AudioFormatDiagnostics = Fixtures.initialOutputFormat
        let expectedStarts: Int
    }
    static let usbInput = AudioInput(id: "usb-stable-id", name: "Instrument", portType: "USBAudio")
    static let initialFormat = AudioEngineInputFormat(sampleRate: 48_000, channelCount: 1)
    static let initialOutputFormat = AudioFormatDiagnostics(sampleRate: 48_000, channelCount: 2, sampleEncoding: "Float32", isInterleaved: false)
    static let usbRoute = AudioRoute(inputs: [AudioDevice(id: "usb-stable-id", name: "Instrument", portType: "USBAudio")], outputs: [])
    static let routeChanges = [
        RouteCase(route: .empty, format: initialFormat, expectedStarts: 1),
        RouteCase(route: usbRoute, format: initialFormat, expectedStarts: 2),
        RouteCase(route: .empty, format: AudioEngineInputFormat(sampleRate: 44_100, channelCount: 2), expectedStarts: 2),
        RouteCase(route: .empty, format: initialFormat, outputFormat: AudioFormatDiagnostics(sampleRate: 44_100, channelCount: 2, sampleEncoding: "Float32", isInterleaved: false), expectedStarts: 2)
    ]
}

private enum TestDoubles {
    final class Session: AudioSessionBackend, @unchecked Sendable {
        enum Failure: Error { case requested }
        private let lock = NSLock()
        private var storedRoute = AudioRoute.empty
        private var storedDeactivations = 0
        private var storedInputs: [AudioInput] = []
        private var storedFailDeactivation = false
        var failDeactivation: Bool {
            get { lock.withLock { storedFailDeactivation } }
            set { lock.withLock { storedFailDeactivation = newValue } }
        }
        private let continuation: AsyncStream<AudioSessionBackendEvent>.Continuation
        private let deactivationContinuation: AsyncStream<Void>.Continuation
        let events: AsyncStream<AudioSessionBackendEvent>
        let deactivationEvents: AsyncStream<Void>
        let sampleRate = 48_000.0
        let ioBufferDuration = 0.00533
        var inputs: [AudioInput] {
            get { lock.withLock { storedInputs } }
            set { lock.withLock { storedInputs = newValue } }
        }
        var availableInputs: [AudioInput] { inputs }
        var route: AudioRoute {
            get { lock.withLock { storedRoute } }
            set { lock.withLock { storedRoute = newValue } }
        }
        var currentRoute: AudioRoute { route }
        var deactivations: Int { lock.withLock { storedDeactivations } }
        init() {
            (events, continuation) = AsyncStream.makeStream()
            (deactivationEvents, deactivationContinuation) = AsyncStream.makeStream()
        }
        func send(_ event: AudioSessionBackendEvent) { continuation.yield(event) }
        func configureForMeasurement() {}
        func setPreferredSampleRate(_ sampleRate: Double) {}
        func setPreferredIOBufferDuration(_ duration: TimeInterval) {}
        func setActive(_ active: Bool, notifyOthersOnDeactivation: Bool) throws {
            if !active {
                lock.withLock { storedDeactivations += 1 }
                if failDeactivation { throw Failure.requested }
                deactivationContinuation.yield(())
            }
        }
        func setPreferredInput(id: String?) {}
    }

    final class Engine: AudioEngineBackend, @unchecked Sendable {
        enum Failure: Error { case requested }
        private let lock = NSLock()
        private var storedFormat = Fixtures.initialFormat
        private var storedOutputFormat = Fixtures.initialOutputFormat
        private var storedStarts = 0
        private var storedStops = 0
        private var storedVolume: Float = 0
        private var storedFailStart = false
        var format: AudioEngineInputFormat {
            get { lock.withLock { storedFormat } }
            set { lock.withLock { storedFormat = newValue } }
        }
        var inputFormat: AudioEngineInputFormat { format }
        var outputFormat: AudioFormatDiagnostics {
            get { lock.withLock { storedOutputFormat } }
            set { lock.withLock { storedOutputFormat = newValue } }
        }
        var diagnosticFormats: (input: AudioFormatDiagnostics, output: AudioFormatDiagnostics)? {
            let input = format
            return (AudioFormatDiagnostics(sampleRate: input.sampleRate, channelCount: input.channelCount, sampleEncoding: "Float32", isInterleaved: false), outputFormat)
        }
        var starts: Int { lock.withLock { storedStarts } }
        var stops: Int { lock.withLock { storedStops } }
        var volume: Float { lock.withLock { storedVolume } }
        var failStart: Bool {
            get { lock.withLock { storedFailStart } }
            set { lock.withLock { storedFailStart = newValue } }
        }
        func resetGraph() {}
        func attachInstrumentMixer() {}
        func setGain(_ configuration: GainConfiguration, for stage: GainStage) throws {
            try NativeGainLimits.validate(configuration, stage: stage)
            lock.withLock { storedGains[stage] = configuration }
        }
        private var storedGains: [GainStage: GainConfiguration] = [:]
        private var storedEqualizer: EQConfiguration = .flat
        func setTone(inputGain: GainConfiguration, equalizer: EQConfiguration, sampleRate: Double) throws {
            try NativeGainLimits.validate(inputGain, stage: .input)
            try NativeEQLimits.validate(equalizer, sampleRate: sampleRate)
            lock.withLock { storedGains[.input] = inputGain; storedEqualizer = equalizer }
        }
        func connectInputToInstrument(format: AudioEngineInputFormat) {}
        func connectInstrumentToMain() {}
        func connectMainToOutput() {}
        func setInstrumentMixerVolume(_ volume: Float) { lock.withLock { storedVolume = volume } }
        func prepare() {}
        func start() throws {
            let failure = lock.withLock { storedStarts += 1; return storedFailStart }
            if failure { throw Failure.requested }
        }
        func stop() { lock.withLock { storedStops += 1 } }
    }
}
