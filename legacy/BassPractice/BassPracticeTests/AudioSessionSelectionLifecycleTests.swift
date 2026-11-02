import Foundation
import Testing
@testable import BassPractice

@Suite("Audio input selection and session lifecycle")
struct AudioSessionSelectionLifecycleTests {
    @Test(
        "Selects an available input by its stable identifier",
        arguments: Fixtures.selectableInputs
    )
    fileprivate func selectsAvailableInput(testCase: Fixtures.SelectionCase) async throws {
        // Arrange
        let backend = TestDoubles.AudioSessionBackend(inputs: Fixtures.inputs)
        let control = AudioControlActor(backend: backend)

        // Act
        try await control.selectPreferredInput(id: testCase.input.id)

        // Assert
        #expect(backend.commands == [.setPreferredInput(testCase.input.id)])
        #expect(await control.preferredInput == testCase.input)
    }

    @Test("Refreshes available inputs before resolving a selection")
    func refreshesInputsBeforeSelection() async {
        // Arrange
        let backend = TestDoubles.AudioSessionBackend(inputs: [Fixtures.builtInInput])
        let control = AudioControlActor(backend: backend)
        backend.setInputs([Fixtures.usbInput])
        var receivedError: AudioSessionError?

        // Act
        do {
            try await control.selectPreferredInput(id: Fixtures.builtInInput.id)
        } catch {
            receivedError = error
        }

        // Assert
        #expect(receivedError == .inputUnavailable(id: Fixtures.builtInInput.id))
        #expect(backend.commands.isEmpty)
        #expect(await control.availableInputs == [Fixtures.usbInput])
    }

    @Test("Clears the current-run input preference when nil is selected")
    func clearsPreferredInput() async throws {
        // Arrange
        let backend = TestDoubles.AudioSessionBackend(inputs: Fixtures.inputs)
        let control = AudioControlActor(backend: backend)
        try await control.selectPreferredInput(id: Fixtures.usbInput.id)
        backend.resetCommands()

        // Act
        try await control.selectPreferredInput(id: nil)

        // Assert
        #expect(backend.commands == [.setPreferredInput(nil)])
        #expect(await control.preferredInput == nil)
    }

    @Test(
        "Maps unavailable and failed selections to typed errors",
        arguments: Fixtures.selectionFailureCases
    )
    fileprivate func mapsSelectionFailures(testCase: Fixtures.SelectionFailureCase) async {
        // Arrange
        let backend = TestDoubles.AudioSessionBackend(
            inputs: testCase.inputs,
            failingAt: testCase.failingOperation
        )
        let control = AudioControlActor(backend: backend)
        var receivedError: AudioSessionError?

        // Act
        do {
            try await control.selectPreferredInput(id: testCase.requestedID)
        } catch {
            receivedError = error
        }

        // Assert
        #expect(receivedError == testCase.expectedError)
        #expect(backend.commands == testCase.expectedCommands)
        #expect(await control.preferredInput == nil)
    }

    @Test(
        "Clears a disconnected preferred input after route changes",
        arguments: Fixtures.disconnectReasons
    )
    func clearsDisconnectedInput(reason: AudioRouteChangeReason) async throws {
        // Arrange
        let backend = TestDoubles.AudioSessionBackend(inputs: Fixtures.inputs)
        let control = AudioControlActor(backend: backend)
        try await control.selectPreferredInput(id: Fixtures.usbInput.id)
        let events = await control.events()
        var iterator = events.makeAsyncIterator()
        backend.resetCommands()

        // Act
        backend.changeRoute(inputs: [Fixtures.builtInInput], reason: reason)
        _ = await iterator.next()

        // Assert
        #expect(backend.commands == [.setPreferredInput(nil)])
        #expect(await control.preferredInput == nil)
        #expect(await control.availableInputs == [Fixtures.builtInInput])
    }

    @Test(
        "Resumes after an interruption only when the system permits it",
        arguments: Fixtures.interruptionResumeCases
    )
    fileprivate func resumesAfterInterruption(testCase: Fixtures.InterruptionResumeCase) async throws {
        // Arrange
        let backend = TestDoubles.AudioSessionBackend(inputs: [])
        let control = AudioControlActor(backend: backend)
        _ = try await control.activate()
        let events = await control.events()
        var iterator = events.makeAsyncIterator()
        backend.resetCommands()

        // Act
        backend.emit(.interruptionBegan)
        _ = await iterator.next()
        backend.emit(.interruptionEnded(shouldResume: testCase.shouldResume))
        _ = await iterator.next()

        // Assert
        #expect(backend.commands == testCase.expectedCommands)
        #expect(await control.snapshot.isActive == testCase.expectedActiveState)
    }

    @Test("Does not activate after an interruption when the session was previously inactive")
    func leavesPreviouslyInactiveSessionInactive() async {
        // Arrange
        let backend = TestDoubles.AudioSessionBackend(inputs: [])
        let control = AudioControlActor(backend: backend)
        let events = await control.events()
        var iterator = events.makeAsyncIterator()

        // Act
        backend.emit(.interruptionBegan)
        _ = await iterator.next()
        backend.emit(.interruptionEnded(shouldResume: true))
        _ = await iterator.next()

        // Assert
        #expect(backend.commands.isEmpty)
        #expect(await control.snapshot.isActive == false)
    }

    @Test("Backgrounding deactivates an active session")
    func backgroundDeactivatesSession() async throws {
        // Arrange
        let backend = TestDoubles.AudioSessionBackend(inputs: [])
        let control = AudioControlActor(backend: backend)
        _ = try await control.activate()
        let events = await control.events()
        var iterator = events.makeAsyncIterator()
        backend.resetCommands()

        // Act
        backend.emit(.enteredBackground)
        let event = await iterator.next()

        // Assert
        #expect(event == .enteredBackground)
        #expect(backend.commands == [.setActive(false, notifyOthers: true)])
        #expect(await control.snapshot.isActive == false)
    }

    @Test("Foregrounding refreshes routes and clears a stale input preference")
    func foregroundReconcilesSessionState() async throws {
        // Arrange
        let backend = TestDoubles.AudioSessionBackend(
            inputs: Fixtures.inputs,
            route: Fixtures.usbRoute
        )
        let control = AudioControlActor(backend: backend)
        try await control.selectPreferredInput(id: Fixtures.usbInput.id)
        let events = await control.events()
        var iterator = events.makeAsyncIterator()
        backend.resetCommands()
        backend.setInputs([])
        backend.setRoute(.empty)

        // Act
        backend.emit(.enteredForeground)
        let event = await iterator.next()

        // Assert
        #expect(event == .enteredForeground)
        #expect(backend.commands == [.setPreferredInput(nil)])
        #expect(await control.availableInputs.isEmpty)
        #expect(await control.currentRoute == .empty)
        #expect(await control.preferredInput == nil)
    }

    @Test("A failed interruption recovery makes one activation attempt without retrying")
    func interruptionRecoveryDoesNotRetry() async throws {
        // Arrange
        let backend = TestDoubles.AudioSessionBackend(inputs: [])
        let control = AudioControlActor(backend: backend)
        _ = try await control.activate()
        let events = await control.events()
        var iterator = events.makeAsyncIterator()
        backend.resetCommands()
        backend.failingOperation = .setActive(true, notifyOthers: false)

        // Act
        backend.emit(.interruptionBegan)
        _ = await iterator.next()
        backend.emit(.interruptionEnded(shouldResume: true))
        _ = await iterator.next()

        // Assert
        #expect(backend.commands == Fixtures.activationCommands)
        #expect(await control.snapshot.isActive == false)
    }
}

private enum Fixtures {
    struct SelectionCase: Sendable, CustomTestStringConvertible {
        let input: AudioInput

        var testDescription: String { input.name }
    }

    struct SelectionFailureCase: Sendable, CustomTestStringConvertible {
        let description: String
        let inputs: [AudioInput]
        let requestedID: String?
        let failingOperation: TestDoubles.AudioSessionBackend.Operation?
        let expectedError: AudioSessionError
        let expectedCommands: [TestDoubles.AudioSessionBackend.Command]

        var testDescription: String { description }
    }

    struct InterruptionResumeCase: Sendable, CustomTestStringConvertible {
        let shouldResume: Bool
        let expectedCommands: [TestDoubles.AudioSessionBackend.Command]
        let expectedActiveState: Bool

        var testDescription: String { shouldResume ? "resume permitted" : "resume denied" }
    }

    static let builtInInput = AudioInput(
        id: "built-in-mic",
        name: "iPhone Microphone",
        portType: "MicrophoneBuiltIn"
    )
    static let usbInput = AudioInput(
        id: "cube-baby",
        name: "Cube Baby",
        portType: "USBAudio"
    )
    static let inputs = [builtInInput, usbInput]
    static let selectableInputs = inputs.map { SelectionCase(input: $0) }
    static let usbRoute = AudioRoute(
        inputs: [
            AudioDevice(id: usbInput.id, name: usbInput.name, portType: usbInput.portType)
        ],
        outputs: []
    )
    static let activationCommands: [TestDoubles.AudioSessionBackend.Command] = [
        .configureForMeasurement,
        .setPreferredSampleRate(48_000),
        .setPreferredIOBufferDuration(0),
        .setActive(true, notifyOthers: false)
    ]
    static let selectionFailureCases = [
        SelectionFailureCase(
            description: "requested input is unavailable",
            inputs: [builtInInput],
            requestedID: usbInput.id,
            failingOperation: nil,
            expectedError: .inputUnavailable(id: usbInput.id),
            expectedCommands: []
        ),
        SelectionFailureCase(
            description: "backend rejects an available input",
            inputs: inputs,
            requestedID: usbInput.id,
            failingOperation: .setPreferredInput(usbInput.id),
            expectedError: .inputSelectionFailed(id: usbInput.id),
            expectedCommands: [.setPreferredInput(usbInput.id)]
        ),
        SelectionFailureCase(
            description: "backend rejects clearing the preference",
            inputs: inputs,
            requestedID: nil,
            failingOperation: .setPreferredInput(nil),
            expectedError: .inputSelectionFailed(id: nil),
            expectedCommands: [.setPreferredInput(nil)]
        )
    ]
    static let disconnectReasons: [AudioRouteChangeReason] = [
        .oldDeviceUnavailable,
        .routeConfigurationChange
    ]
    static let interruptionResumeCases = [
        InterruptionResumeCase(
            shouldResume: true,
            expectedCommands: activationCommands,
            expectedActiveState: true
        ),
        InterruptionResumeCase(
            shouldResume: false,
            expectedCommands: [],
            expectedActiveState: false
        )
    ]
}

private enum TestDoubles {
    final class AudioSessionBackend: BassPractice.AudioSessionBackend, @unchecked Sendable {
        enum Operation: Equatable, Sendable {
            case configureForMeasurement
            case setPreferredSampleRate
            case setPreferredIOBufferDuration
            case setActive(Bool, notifyOthers: Bool)
            case setPreferredInput(String?)
        }

        enum Command: Equatable, Sendable {
            case configureForMeasurement
            case setPreferredSampleRate(Double)
            case setPreferredIOBufferDuration(TimeInterval)
            case setActive(Bool, notifyOthers: Bool)
            case setPreferredInput(String?)
        }

        enum Failure: Error {
            case requested
        }

        private let lock = NSLock()
        private var storedInputs: [AudioInput]
        private var storedRoute: AudioRoute
        private var recordedCommands: [Command] = []
        private var operationToFail: Operation?
        private let continuation: AsyncStream<AudioSessionBackendEvent>.Continuation

        let sampleRate = 48_000.0
        let ioBufferDuration = 0.00533
        let events: AsyncStream<AudioSessionBackendEvent>

        var availableInputs: [AudioInput] {
            lock.withLock { storedInputs }
        }

        var currentRoute: AudioRoute {
            lock.withLock { storedRoute }
        }

        var commands: [Command] {
            lock.withLock { recordedCommands }
        }

        var failingOperation: Operation? {
            get { lock.withLock { operationToFail } }
            set { lock.withLock { operationToFail = newValue } }
        }

        init(
            inputs: [AudioInput],
            route: AudioRoute = .empty,
            failingAt operation: Operation? = nil
        ) {
            storedInputs = inputs
            storedRoute = route
            operationToFail = operation
            let (events, continuation) = AsyncStream<AudioSessionBackendEvent>.makeStream()
            self.events = events
            self.continuation = continuation
        }

        func setInputs(_ inputs: [AudioInput]) {
            lock.withLock { storedInputs = inputs }
        }

        func setRoute(_ route: AudioRoute) {
            lock.withLock { storedRoute = route }
        }

        func changeRoute(inputs: [AudioInput], reason: AudioRouteChangeReason) {
            setInputs(inputs)
            emit(.routeChanged(reason: reason))
        }

        func emit(_ event: AudioSessionBackendEvent) {
            continuation.yield(event)
        }

        func resetCommands() {
            lock.withLock { recordedCommands = [] }
        }

        func configureForMeasurement() throws {
            try record(.configureForMeasurement, operation: .configureForMeasurement)
        }

        func setPreferredSampleRate(_ sampleRate: Double) throws {
            try record(
                .setPreferredSampleRate(sampleRate),
                operation: .setPreferredSampleRate
            )
        }

        func setPreferredIOBufferDuration(_ duration: TimeInterval) throws {
            try record(
                .setPreferredIOBufferDuration(duration),
                operation: .setPreferredIOBufferDuration
            )
        }

        func setActive(_ active: Bool, notifyOthersOnDeactivation: Bool) throws {
            try record(
                .setActive(active, notifyOthers: notifyOthersOnDeactivation),
                operation: .setActive(active, notifyOthers: notifyOthersOnDeactivation)
            )
        }

        func setPreferredInput(id: String?) throws {
            try record(.setPreferredInput(id), operation: .setPreferredInput(id))
        }

        private func record(_ command: Command, operation: Operation) throws {
            let shouldFail = lock.withLock {
                recordedCommands.append(command)
                return operationToFail == operation
            }
            if shouldFail {
                throw Failure.requested
            }
        }
    }
}
