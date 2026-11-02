import Foundation
import Testing
@testable import BassPractice

@Suite("Audio engine lifecycle")
struct AudioEngineLifecycleTests {
    @MainActor
    @Test("Session input selection preserves stable identifiers and supports System Default")
    func sessionInputSelectionUsesStableIdentifiers() async {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let control = AudioControlActor(
            backend: TestDoubles.AudioSessionBackend(recorder: recorder, inputs: [Fixtures.reviewInput]),
            engineBackend: TestDoubles.AudioEngineBackend(recorder: recorder)
        )
        let model = SessionModel(engine: control, session: control, permission: TestDoubles.Permission(granted: true))

        // Act
        await model.selectInput(Fixtures.reviewInput.id)
        let selectedID = model.selectedInputID
        await model.selectInput(nil)

        // Assert
        #expect(selectedID == Fixtures.reviewInput.id)
        #expect(model.inputs == [Fixtures.reviewInput])
        #expect(model.selectedInputID == nil)
        #expect(model.errorMessage == nil)
    }

    @MainActor
    @Test("Unavailable input selection exposes the failure and retains the previously selected input")
    func sessionInputSelectionFailureRetainsSelection() async {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let control = AudioControlActor(
            backend: TestDoubles.AudioSessionBackend(recorder: recorder, inputs: [Fixtures.reviewInput]),
            engineBackend: TestDoubles.AudioEngineBackend(recorder: recorder)
        )
        let model = SessionModel(engine: control, session: control, permission: TestDoubles.Permission(granted: true))
        await model.selectInput(Fixtures.reviewInput.id)

        // Act
        await model.selectInput("disconnected-port")

        // Assert
        #expect(model.selectedInputID == Fixtures.reviewInput.id)
        #expect(model.errorMessage != nil)
        #expect(!model.isBusy)
    }

    @MainActor
    @Test("Monitoring write failure refreshes the committed controls and exposes the failure")
    func sessionMonitoringFailureRetainsCommittedControls() async {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let engine = TestDoubles.AudioEngineBackend(recorder: recorder)
        let control = AudioControlActor(backend: TestDoubles.AudioSessionBackend(recorder: recorder), engineBackend: engine)
        let model = SessionModel(engine: control, session: control, permission: TestDoubles.Permission(granted: true))
        await model.setMonitoring(enabled: true, gain: 0.4)
        engine.failsMixerVolumeWrite = true

        // Act
        await model.setMonitoring(enabled: true, gain: 0.8)

        // Assert
        #expect(model.monitoringEnabled)
        #expect(model.monitoringGain == 0.4)
        #expect(model.errorMessage != nil)
        #expect(!model.isBusy)
    }

    @MainActor
    @Test("Denied microphone access prevents session activation and exposes a Settings instruction")
    func microphoneDenialPreventsStart() async {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let control = AudioControlActor(
            backend: TestDoubles.AudioSessionBackend(recorder: recorder),
            engineBackend: TestDoubles.AudioEngineBackend(recorder: recorder)
        )
        let model = SessionModel(engine: control, session: control, permission: TestDoubles.Permission(granted: false))

        // Act
        await model.toggleRunning()

        // Assert
        #expect(recorder.commands.isEmpty)
        #expect(model.state == .stopped)
        #expect(model.errorMessage?.contains("Settings") == true)
        #expect(!model.isBusy)
    }
    @Test("Diagnostics expose actual session values and distinct hardware input and output formats")
    func diagnosticsReadActualValues() async throws {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let control = AudioControlActor(
            backend: TestDoubles.AudioSessionBackend(recorder: recorder),
            engineBackend: TestDoubles.AudioEngineBackend(recorder: recorder),
            configuration: AudioSessionConfiguration(preferredSampleRate: 96_000, preferredIOBufferDuration: 0.01)
        )

        // Act
        try await control.start()
        let diagnostics = await control.diagnostics

        // Assert
        #expect(diagnostics == AudioEngineDiagnostics(
            actualSessionSampleRate: 48_000,
            inputChannelCount: 1,
            inputFormat: Fixtures.diagnosticInput,
            outputFormat: Fixtures.diagnosticOutput,
            actualIOBufferDuration: 0.00533
        ))
    }

    @Test("Inactive sessions do not present stale diagnostics as current hardware values")
    func inactiveDiagnosticsUnavailable() async throws {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let control = AudioControlActor(
            backend: TestDoubles.AudioSessionBackend(recorder: recorder),
            engineBackend: TestDoubles.AudioEngineBackend(recorder: recorder)
        )
        try await control.start()

        // Act
        try await control.stop()
        let diagnostics = await control.diagnostics

        // Assert
        #expect(diagnostics == nil)
    }

    @MainActor
    @Test("Session controls start and stop audio and refresh observable diagnostics and monitoring")
    func sessionControlsReflectAudioState() async {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let control = AudioControlActor(
            backend: TestDoubles.AudioSessionBackend(recorder: recorder),
            engineBackend: TestDoubles.AudioEngineBackend(recorder: recorder)
        )
        let model = SessionModel(engine: control, session: control, permission: TestDoubles.Permission(granted: true))

        // Act
        await model.toggleRunning()
        await model.setMonitoring(enabled: true, gain: 0.4)
        let runningState = model.state
        let runningDiagnostics = model.diagnostics
        let monitoring = model.monitoringEnabled
        let gain = model.monitoringGain
        await model.toggleRunning()

        // Assert
        #expect(runningState == .running)
        #expect(runningDiagnostics?.inputFormat == Fixtures.diagnosticInput)
        #expect(monitoring)
        #expect(gain == 0.4)
        #expect(model.state == .stopped)
        #expect(model.diagnostics == nil)
        #expect(model.errorMessage == nil)
    }

    @MainActor
    @Test("Session start failures are visible and release the busy state for an explicit retry")
    func sessionControlsReportFailure() async {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let control = AudioControlActor(
            backend: TestDoubles.AudioSessionBackend(recorder: recorder, failsActivation: true),
            engineBackend: TestDoubles.AudioEngineBackend(recorder: recorder)
        )
        let model = SessionModel(engine: control, session: control, permission: TestDoubles.Permission(granted: true))

        // Act
        await model.toggleRunning()

        // Assert
        #expect(model.state == .failed(.sessionActivation(.activationFailed)))
        #expect(model.errorMessage != nil)
        #expect(!model.isBusy)
    }

    @Test("Start activates the session before preparing and starting the engine")
    func startOrdersLifecycleAndReachesRunning() async throws {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let session = TestDoubles.AudioSessionBackend(recorder: recorder)
        let engine = TestDoubles.AudioEngineBackend(recorder: recorder)
        let control = AudioControlActor(backend: session, engineBackend: engine)

        // Act
        try await control.start()

        // Assert
        #expect(await control.state == .running)
        #expect(recorder.commands == Fixtures.startCommands)
    }

    @Test(
        "Start rebuilds the exact input-to-instrument-to-main-to-output graph for supported hardware formats",
        arguments: Fixtures.validInputFormats
    )
    fileprivate func startBuildsGraphForHardwareFormat(
        testCase: Fixtures.InputFormatCase
    ) async throws {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let engine = TestDoubles.AudioEngineBackend(
            recorder: recorder,
            inputFormat: testCase.format
        )
        let control = AudioControlActor(
            backend: TestDoubles.AudioSessionBackend(recorder: recorder),
            engineBackend: engine
        )

        // Act
        try await control.start()

        // Assert
        #expect(recorder.commands == Fixtures.startCommands(for: testCase.format))
        #expect(await control.state == .running)
    }

    @Test(
        "Start rejects invalid hardware input formats before changing the graph",
        arguments: Fixtures.invalidInputFormats
    )
    fileprivate func startRejectsInvalidInputFormat(
        testCase: Fixtures.InputFormatCase
    ) async {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let control = AudioControlActor(
            backend: TestDoubles.AudioSessionBackend(recorder: recorder),
            engineBackend: TestDoubles.AudioEngineBackend(
                recorder: recorder,
                inputFormat: testCase.format
            )
        )
        let expectedFailure = AudioEngineFailure.invalidInputFormat(
            sampleRate: testCase.format.sampleRate,
            channelCount: testCase.format.channelCount
        )
        var receivedFailure: AudioEngineFailure?

        // Act
        do {
            try await control.start()
        } catch {
            receivedFailure = error
        }

        // Assert
        #expect(receivedFailure == expectedFailure)
        #expect(await control.state == .failed(expectedFailure))
        #expect(recorder.commands == Fixtures.sessionActivationCommands + [
            .engineReadInputFormat(
                sampleRate: testCase.format.sampleRate,
                channelCount: testCase.format.channelCount
            ),
            .engineStop,
            .sessionDeactivate
        ])
    }

    @Test(
        "Every graph operation failure stops the engine, deactivates the session, and publishes a typed failure",
        arguments: Fixtures.graphFailurePoints
    )
    fileprivate func graphFailuresCleanUp(
        failurePoint: TestDoubles.AudioEngineBackend.FailurePoint
    ) async {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let engine = TestDoubles.AudioEngineBackend(
            recorder: recorder,
            failure: failurePoint
        )
        let control = AudioControlActor(
            backend: TestDoubles.AudioSessionBackend(recorder: recorder),
            engineBackend: engine
        )
        var receivedFailure: AudioEngineFailure?

        // Act
        do {
            try await control.start()
        } catch {
            receivedFailure = error
        }

        // Assert
        #expect(receivedFailure == .graphConfigurationFailed)
        #expect(await control.state == .failed(.graphConfigurationFailed))
        #expect(recorder.commands == Fixtures.commandsForGraphFailure(at: failurePoint))
    }

    @Test("Restart rebuilds the graph once without duplicate attach or connection operations")
    func restartRebuildsGraphWithoutDuplicateOperations() async throws {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let engine = TestDoubles.AudioEngineBackend(recorder: recorder)
        let control = AudioControlActor(
            backend: TestDoubles.AudioSessionBackend(recorder: recorder),
            engineBackend: engine
        )

        // Act
        try await control.start()
        try await control.stop()
        try await control.start()

        // Assert
        #expect(engine.resetCount == 2)
        #expect(engine.attachCount == 2)
        #expect(engine.inputConnectionCount == 2)
        #expect(engine.instrumentConnectionCount == 2)
        #expect(engine.outputConnectionCount == 2)
        #expect(await control.state == .running)
    }

    @Test("Repeated start and stop calls are idempotent")
    func repeatedLifecycleCallsAreIdempotent() async throws {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let control = AudioControlActor(
            backend: TestDoubles.AudioSessionBackend(recorder: recorder),
            engineBackend: TestDoubles.AudioEngineBackend(recorder: recorder)
        )

        // Act
        try await control.start()
        try await control.start()
        try await control.stop()
        try await control.stop()

        // Assert
        #expect(await control.state == .stopped)
        #expect(recorder.commands == Fixtures.lifecycleCommands)
    }

    @Test("Monitoring starts disabled at unity stored gain and mutes the instrument mixer")
    func monitoringDefaultsToOff() async throws {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let engine = TestDoubles.AudioEngineBackend(recorder: recorder)
        let control = AudioControlActor(
            backend: TestDoubles.AudioSessionBackend(recorder: recorder),
            engineBackend: engine
        )

        // Act
        try await control.start()

        // Assert
        #expect(await control.monitoringEnabled == false)
        #expect(await control.monitoringGain == 1)
        #expect(engine.instrumentMixerVolume == 0)
    }

    @Test(
        "Monitoring clamps requested gain and applies the effective mixer volume",
        arguments: Fixtures.monitoringGainCases
    )
    fileprivate func monitoringClampsGain(testCase: Fixtures.MonitoringGainCase) async throws {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let engine = TestDoubles.AudioEngineBackend(recorder: recorder)
        let control = AudioControlActor(
            backend: TestDoubles.AudioSessionBackend(recorder: recorder),
            engineBackend: engine
        )
        try await control.start()
        recorder.reset()

        // Act
        try await control.setMonitoring(enabled: true, gain: testCase.requestedGain)

        // Assert
        #expect(await control.monitoringEnabled)
        #expect(await control.monitoringGain == testCase.expectedGain)
        #expect(engine.instrumentMixerVolume == testCase.expectedGain)
        #expect(recorder.commands == testCase.expectedCommands)
    }

    @Test("A disabled gain change is retained without writing an unchanged muted volume")
    func disabledMonitoringRetainsGainWithoutMixerWrite() async throws {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let engine = TestDoubles.AudioEngineBackend(recorder: recorder)
        let control = AudioControlActor(
            backend: TestDoubles.AudioSessionBackend(recorder: recorder),
            engineBackend: engine
        )
        try await control.start()
        recorder.reset()

        // Act
        try await control.setMonitoring(enabled: false, gain: 0.35)
        try await control.setMonitoring(enabled: true, gain: 0.35)

        // Assert
        #expect(await control.monitoringEnabled)
        #expect(await control.monitoringGain == 0.35)
        #expect(recorder.commands == [.engineSetInstrumentMixerVolume(0.35)])
    }

    @Test("Repeated monitoring settings avoid duplicate mixer writes and preserve the graph")
    func repeatedMonitoringSettingsAreIdempotent() async throws {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let engine = TestDoubles.AudioEngineBackend(recorder: recorder)
        let control = AudioControlActor(
            backend: TestDoubles.AudioSessionBackend(recorder: recorder),
            engineBackend: engine
        )
        try await control.start()
        recorder.reset()

        // Act
        try await control.setMonitoring(enabled: true, gain: 0.5)
        try await control.setMonitoring(enabled: true, gain: 0.5)
        try await control.setMonitoring(enabled: false, gain: 0.5)

        // Assert
        #expect(recorder.commands == [
            .engineSetInstrumentMixerVolume(0.5),
            .engineSetInstrumentMixerVolume(0)
        ])
        #expect(engine.resetCount == 1)
        #expect(engine.attachCount == 1)
        #expect(engine.inputConnectionCount == 1)
        #expect(engine.instrumentConnectionCount == 1)
        #expect(engine.outputConnectionCount == 1)
    }

    @Test("Graph rebuilds reapply the stored monitoring state")
    func graphRebuildReappliesMonitoringState() async throws {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let engine = TestDoubles.AudioEngineBackend(recorder: recorder)
        let control = AudioControlActor(
            backend: TestDoubles.AudioSessionBackend(recorder: recorder),
            engineBackend: engine
        )
        try await control.setMonitoring(enabled: true, gain: 0.4)
        recorder.reset()

        // Act
        try await control.start()
        try await control.stop()
        try await control.start()

        // Assert
        #expect(recorder.commands.filter(\.isMixerVolumeCommand) == [
            .engineSetInstrumentMixerVolume(0.4),
            .engineSetInstrumentMixerVolume(0.4)
        ])
        #expect(await control.monitoringEnabled)
        #expect(await control.monitoringGain == 0.4)
    }

    @Test("A mixer write failure preserves the previous monitoring state")
    func monitoringFailurePreservesState() async throws {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let engine = TestDoubles.AudioEngineBackend(recorder: recorder)
        let control = AudioControlActor(
            backend: TestDoubles.AudioSessionBackend(recorder: recorder),
            engineBackend: engine
        )
        try await control.start()
        engine.failsMixerVolumeWrite = true
        var receivedFailure: AudioEngineFailure?

        // Act
        do {
            try await control.setMonitoring(enabled: true, gain: 0.6)
        } catch {
            receivedFailure = error
        }

        // Assert
        #expect(receivedFailure == .monitoringConfigurationFailed)
        #expect(await control.monitoringEnabled == false)
        #expect(await control.monitoringGain == 1)
        #expect(engine.instrumentMixerVolume == 0)
    }

    @Test(
        "Start failures deactivate the session and publish a typed failed state",
        arguments: Fixtures.startFailureCases
    )
    fileprivate func startFailuresCleanUp(testCase: Fixtures.StartFailureCase) async {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let session = TestDoubles.AudioSessionBackend(
            recorder: recorder,
            failsActivation: testCase.failure == .sessionActivation
        )
        let engine = TestDoubles.AudioEngineBackend(
            recorder: recorder,
            failure: testCase.failure.engineFailure
        )
        let control = AudioControlActor(backend: session, engineBackend: engine)
        var receivedFailure: AudioEngineFailure?

        // Act
        do {
            try await control.start()
        } catch {
            receivedFailure = error
        }

        // Assert
        #expect(receivedFailure == testCase.expectedFailure)
        #expect(await control.state == .failed(testCase.expectedFailure))
        #expect(recorder.commands == testCase.expectedCommands)
    }

    @Test("Stop stops the engine before deactivating the session")
    func stopOrdersLifecycleAndReachesStopped() async throws {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let session = TestDoubles.AudioSessionBackend(recorder: recorder)
        let engine = TestDoubles.AudioEngineBackend(recorder: recorder)
        let control = AudioControlActor(backend: session, engineBackend: engine)
        try await control.start()
        recorder.reset()

        // Act
        try await control.stop()

        // Assert
        #expect(await control.state == .stopped)
        #expect(recorder.commands == [.engineStop, .sessionDeactivate])
    }

    @Test("A session deactivation failure leaves a typed failed state")
    func stopMapsDeactivationFailure() async throws {
        // Arrange
        let recorder = TestDoubles.CommandRecorder()
        let session = TestDoubles.AudioSessionBackend(recorder: recorder)
        let engine = TestDoubles.AudioEngineBackend(recorder: recorder)
        let control = AudioControlActor(backend: session, engineBackend: engine)
        try await control.start()
        recorder.reset()
        session.failsDeactivation = true
        var receivedFailure: AudioEngineFailure?

        // Act
        do {
            try await control.stop()
        } catch {
            receivedFailure = error
        }

        // Assert
        let expectedFailure = AudioEngineFailure.sessionDeactivation(.deactivationFailed)
        #expect(receivedFailure == expectedFailure)
        #expect(await control.state == .failed(expectedFailure))
        #expect(recorder.commands == [.engineStop, .sessionDeactivate])
    }
}

private enum Fixtures {
    static let reviewInput = AudioInput(id: "stable-usb-port-id", name: "USB Instrument", portType: "USBAudio")
    static let diagnosticInput = AudioFormatDiagnostics(sampleRate: 48_000, channelCount: 1, sampleEncoding: "Float32", isInterleaved: false)
    static let diagnosticOutput = AudioFormatDiagnostics(sampleRate: 44_100, channelCount: 2, sampleEncoding: "Int16", isInterleaved: true)
    enum StartFailurePoint: Equatable, Sendable {
        case sessionActivation
        case enginePreparation
        case engineStart

        var engineFailure: TestDoubles.AudioEngineBackend.FailurePoint? {
            switch self {
            case .sessionActivation: nil
            case .enginePreparation: .prepare
            case .engineStart: .start
            }
        }
    }

    struct StartFailureCase: Sendable, CustomTestStringConvertible {
        let description: String
        let failure: StartFailurePoint
        let expectedFailure: AudioEngineFailure
        let expectedCommands: [TestDoubles.Command]

        var testDescription: String { description }
    }

    struct InputFormatCase: Sendable, CustomTestStringConvertible {
        let description: String
        let format: AudioEngineInputFormat

        var testDescription: String { description }
    }

    struct MonitoringGainCase: Sendable, CustomTestStringConvertible {
        let description: String
        let requestedGain: Float
        let expectedGain: Float
        let expectedCommands: [TestDoubles.Command]

        var testDescription: String { description }
    }

    static let defaultInputFormat = AudioEngineInputFormat(
        sampleRate: 48_000,
        channelCount: 1
    )

    static let validInputFormats = [
        InputFormatCase(
            description: "44.1 kHz mono",
            format: AudioEngineInputFormat(sampleRate: 44_100, channelCount: 1)
        ),
        InputFormatCase(
            description: "48 kHz stereo",
            format: AudioEngineInputFormat(sampleRate: 48_000, channelCount: 2)
        ),
        InputFormatCase(
            description: "96 kHz mono",
            format: AudioEngineInputFormat(sampleRate: 96_000, channelCount: 1)
        )
    ]

    static let invalidInputFormats = [
        InputFormatCase(
            description: "zero sample rate",
            format: AudioEngineInputFormat(sampleRate: 0, channelCount: 1)
        ),
        InputFormatCase(
            description: "zero channels",
            format: AudioEngineInputFormat(sampleRate: 48_000, channelCount: 0)
        )
    ]

    static let monitoringGainCases = [
        MonitoringGainCase(
            description: "below minimum",
            requestedGain: -0.5,
            expectedGain: 0,
            expectedCommands: []
        ),
        MonitoringGainCase(
            description: "minimum",
            requestedGain: 0,
            expectedGain: 0,
            expectedCommands: []
        ),
        MonitoringGainCase(
            description: "nominal",
            requestedGain: 0.35,
            expectedGain: 0.35,
            expectedCommands: [.engineSetInstrumentMixerVolume(0.35)]
        ),
        MonitoringGainCase(
            description: "maximum",
            requestedGain: 1,
            expectedGain: 1,
            expectedCommands: [.engineSetInstrumentMixerVolume(1)]
        ),
        MonitoringGainCase(
            description: "above maximum",
            requestedGain: 1.5,
            expectedGain: 1,
            expectedCommands: [.engineSetInstrumentMixerVolume(1)]
        )
    ]

    static let sessionActivationCommands: [TestDoubles.Command] = [
        .sessionConfigure,
        .sessionPreferredSampleRate(48_000),
        .sessionPreferredBufferDuration(0),
        .sessionActivate
    ]

    static let startCommands = sessionActivationCommands + [
        .engineReadInputFormat(sampleRate: 48_000, channelCount: 1),
        .engineResetGraph,
        .engineAttachInstrumentMixer,
        .engineConnectInputToInstrument(sampleRate: 48_000, channelCount: 1),
        .engineConnectInstrumentToMain,
        .engineConnectMainToOutput,
        .engineSetInstrumentMixerVolume(0),
        .enginePrepare,
        .engineStart
    ]

    static func startCommands(for format: AudioEngineInputFormat) -> [TestDoubles.Command] {
        sessionActivationCommands + graphCommands(for: format) + [
            .enginePrepare,
            .engineStart
        ]
    }

    static func graphCommands(for format: AudioEngineInputFormat) -> [TestDoubles.Command] {
        [
            .engineReadInputFormat(
                sampleRate: format.sampleRate,
                channelCount: format.channelCount
            ),
            .engineResetGraph,
            .engineAttachInstrumentMixer,
            .engineConnectInputToInstrument(
                sampleRate: format.sampleRate,
                channelCount: format.channelCount
            ),
            .engineConnectInstrumentToMain,
            .engineConnectMainToOutput,
            .engineSetInstrumentMixerVolume(0)
        ]
    }

    static let graphFailurePoints: [TestDoubles.AudioEngineBackend.FailurePoint] = [
        .resetGraph,
        .attachInstrumentMixer,
        .connectInputToInstrument,
        .connectInstrumentToMain,
        .connectMainToOutput,
        .setInstrumentMixerVolume
    ]

    static func commandsForGraphFailure(
        at failurePoint: TestDoubles.AudioEngineBackend.FailurePoint
    ) -> [TestDoubles.Command] {
        let graphCommands = graphCommands(for: defaultInputFormat)
        let failingCommandIndex = failurePoint.graphCommandIndex
        return sessionActivationCommands
            + Array(graphCommands.prefix(failingCommandIndex + 1))
            + [.engineStop, .sessionDeactivate]
    }

    static let lifecycleCommands = startCommands + [
        .engineStop,
        .sessionDeactivate
    ]

    static let startFailureCases = [
        StartFailureCase(
            description: "session activation",
            failure: .sessionActivation,
            expectedFailure: .sessionActivation(.activationFailed),
            expectedCommands: sessionActivationCommands + [.sessionDeactivate]
        ),
        StartFailureCase(
            description: "engine preparation",
            failure: .enginePreparation,
            expectedFailure: .preparationFailed,
            expectedCommands: sessionActivationCommands
                + graphCommands(for: defaultInputFormat) + [
                .enginePrepare,
                .engineStop,
                .sessionDeactivate
            ]
        ),
        StartFailureCase(
            description: "engine start",
            failure: .engineStart,
            expectedFailure: .startFailed,
            expectedCommands: startCommands + [
                .engineStop,
                .sessionDeactivate
            ]
        )
    ]
}

private enum TestDoubles {
    struct Permission: AudioRecordingPermission {
        let granted: Bool
        func request() async -> Bool { granted }
    }
    enum Command: Equatable, Sendable {
        case sessionConfigure
        case sessionPreferredSampleRate(Double)
        case sessionPreferredBufferDuration(TimeInterval)
        case sessionActivate
        case sessionDeactivate
        case engineReadInputFormat(sampleRate: Double, channelCount: UInt32)
        case engineResetGraph
        case engineAttachInstrumentMixer
        case engineConnectInputToInstrument(sampleRate: Double, channelCount: UInt32)
        case engineConnectInstrumentToMain
        case engineConnectMainToOutput
        case engineSetInstrumentMixerVolume(Float)
        case enginePrepare
        case engineStart
        case engineStop

        var isMixerVolumeCommand: Bool {
            if case .engineSetInstrumentMixerVolume = self {
                return true
            }
            return false
        }
    }

    final class CommandRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var recordedCommands: [Command] = []

        var commands: [Command] {
            lock.withLock { recordedCommands }
        }

        func append(_ command: Command) {
            lock.withLock { recordedCommands.append(command) }
        }

        func reset() {
            lock.withLock { recordedCommands = [] }
        }
    }

    final class AudioSessionBackend: BassPractice.AudioSessionBackend, @unchecked Sendable {
        enum Failure: Error {
            case requested
        }

        private let recorder: CommandRecorder
        private let failsActivation: Bool
        private let lock = NSLock()
        private var shouldFailDeactivation = false

        let sampleRate = 48_000.0
        let ioBufferDuration: TimeInterval = 0.00533
        let currentRoute = AudioRoute.empty
        let availableInputs: [AudioInput]
        let events = AsyncStream<AudioSessionBackendEvent> { _ in }

        var failsDeactivation: Bool {
            get { lock.withLock { shouldFailDeactivation } }
            set { lock.withLock { shouldFailDeactivation = newValue } }
        }

        init(recorder: CommandRecorder, failsActivation: Bool = false, inputs: [AudioInput] = []) {
            self.recorder = recorder
            self.failsActivation = failsActivation
            availableInputs = inputs
        }

        func configureForMeasurement() {
            recorder.append(.sessionConfigure)
        }

        func setPreferredSampleRate(_ sampleRate: Double) {
            recorder.append(.sessionPreferredSampleRate(sampleRate))
        }

        func setPreferredIOBufferDuration(_ duration: TimeInterval) {
            recorder.append(.sessionPreferredBufferDuration(duration))
        }

        func setActive(_ active: Bool, notifyOthersOnDeactivation: Bool) throws {
            recorder.append(active ? .sessionActivate : .sessionDeactivate)
            if active && failsActivation {
                throw Failure.requested
            }
            if !active && failsDeactivation {
                throw Failure.requested
            }
        }

        func setPreferredInput(id: String?) {}
    }

    final class AudioEngineBackend: BassPractice.AudioEngineBackend, @unchecked Sendable {
        enum FailurePoint: Equatable, Sendable {
            case resetGraph
            case attachInstrumentMixer
            case connectInputToInstrument
            case connectInstrumentToMain
            case connectMainToOutput
            case setInstrumentMixerVolume
            case prepare
            case start

            var graphCommandIndex: Int {
                switch self {
                case .resetGraph: 1
                case .attachInstrumentMixer: 2
                case .connectInputToInstrument: 3
                case .connectInstrumentToMain: 4
                case .connectMainToOutput: 5
                case .setInstrumentMixerVolume: 6
                case .prepare, .start: preconditionFailure("Not a graph failure point")
                }
            }
        }

        enum Failure: Error {
            case requested
        }

        private let recorder: CommandRecorder
        private let failure: FailurePoint?
        private let format: AudioEngineInputFormat
        private let lock = NSLock()
        private var graphResetCount = 0
        private var mixerAttachCount = 0
        private var inputConnectCount = 0
        private var instrumentConnectCount = 0
        private var outputConnectCount = 0
        private var storedInstrumentMixerVolume: Float = 1
        private var shouldFailMixerVolumeWrite = false

        var inputFormat: AudioEngineInputFormat {
            recorder.append(.engineReadInputFormat(
                sampleRate: format.sampleRate,
                channelCount: format.channelCount
            ))
            return format
        }

        var diagnosticFormats: (input: AudioFormatDiagnostics, output: AudioFormatDiagnostics)? {
            (Fixtures.diagnosticInput, Fixtures.diagnosticOutput)
        }

        var resetCount: Int { lock.withLock { graphResetCount } }
        var attachCount: Int { lock.withLock { mixerAttachCount } }
        var inputConnectionCount: Int { lock.withLock { inputConnectCount } }
        var instrumentConnectionCount: Int { lock.withLock { instrumentConnectCount } }
        var outputConnectionCount: Int { lock.withLock { outputConnectCount } }
        var instrumentMixerVolume: Float { lock.withLock { storedInstrumentMixerVolume } }
        var failsMixerVolumeWrite: Bool {
            get { lock.withLock { shouldFailMixerVolumeWrite } }
            set { lock.withLock { shouldFailMixerVolumeWrite = newValue } }
        }

        init(
            recorder: CommandRecorder,
            inputFormat: AudioEngineInputFormat = Fixtures.defaultInputFormat,
            failure: FailurePoint? = nil
        ) {
            self.recorder = recorder
            format = inputFormat
            self.failure = failure
        }

        func resetGraph() throws {
            try record(.engineResetGraph, failurePoint: .resetGraph)
            lock.withLock { graphResetCount += 1 }
        }

        func attachInstrumentMixer() throws {
            try record(.engineAttachInstrumentMixer, failurePoint: .attachInstrumentMixer)
            lock.withLock { mixerAttachCount += 1 }
        }

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

        func connectInputToInstrument(format: AudioEngineInputFormat) throws {
            try record(
                .engineConnectInputToInstrument(
                    sampleRate: format.sampleRate,
                    channelCount: format.channelCount
                ),
                failurePoint: .connectInputToInstrument
            )
            lock.withLock { inputConnectCount += 1 }
        }

        func connectInstrumentToMain() throws {
            try record(.engineConnectInstrumentToMain, failurePoint: .connectInstrumentToMain)
            lock.withLock { instrumentConnectCount += 1 }
        }

        func connectMainToOutput() throws {
            try record(.engineConnectMainToOutput, failurePoint: .connectMainToOutput)
            lock.withLock { outputConnectCount += 1 }
        }

        func setInstrumentMixerVolume(_ volume: Float) throws {
            recorder.append(.engineSetInstrumentMixerVolume(volume))
            if failure == .setInstrumentMixerVolume || failsMixerVolumeWrite {
                throw Failure.requested
            }
            lock.withLock { storedInstrumentMixerVolume = volume }
        }

        func prepare() throws {
            recorder.append(.enginePrepare)
            if failure == .prepare {
                throw Failure.requested
            }
        }

        func start() throws {
            recorder.append(.engineStart)
            if failure == .start {
                throw Failure.requested
            }
        }

        func stop() {
            recorder.append(.engineStop)
        }

        private func record(_ command: Command, failurePoint: FailurePoint) throws {
            recorder.append(command)
            if failure == failurePoint {
                throw Failure.requested
            }
        }
    }
}
