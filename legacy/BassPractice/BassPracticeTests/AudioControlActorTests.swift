import Foundation
import Testing
@testable import BassPractice

@Suite("Audio session control")
struct AudioControlActorTests {
    @Test("Activation configures measurement audio before activating and records negotiated values")
    func activationConfiguresAndRecordsValues() async throws {
        // Arrange
        let backend = TestDoubles.AudioSessionBackend(
            sampleRate: Fixtures.negotiatedSampleRate,
            ioBufferDuration: Fixtures.negotiatedIOBufferDuration
        )
        let control = AudioControlActor(backend: backend)

        // Act
        let snapshot = try await control.activate()

        // Assert
        #expect(backend.commands == Fixtures.activationCommands)
        #expect(snapshot == Fixtures.activeSnapshot)
        #expect(await control.snapshot == Fixtures.activeSnapshot)
    }

    @Test(
        "Activation maps backend failures to typed audio session errors",
        arguments: Fixtures.activationFailureCases
    )
    fileprivate func activationMapsBackendFailures(
        testCase: Fixtures.ActivationFailureCase
    ) async {
        // Arrange
        let backend = TestDoubles.AudioSessionBackend(failingAt: testCase.operation)
        let control = AudioControlActor(backend: backend)
        var receivedError: AudioSessionError?

        // Act
        do {
            _ = try await control.activate()
        } catch {
            receivedError = error
        }

        // Assert
        #expect(receivedError == testCase.expectedError)
        #expect(backend.commands == testCase.expectedCommands)
        #expect(await control.snapshot == Fixtures.inactiveSnapshot)
    }

    @Test("Deactivation updates active state while retaining negotiated values")
    func deactivationUpdatesActiveState() async throws {
        // Arrange
        let backend = TestDoubles.AudioSessionBackend(
            sampleRate: Fixtures.negotiatedSampleRate,
            ioBufferDuration: Fixtures.negotiatedIOBufferDuration
        )
        let control = AudioControlActor(backend: backend)
        _ = try await control.activate()
        backend.resetCommands()

        // Act
        try await control.deactivate()

        // Assert
        #expect(backend.commands == [.setActive(false, notifyOthers: true)])
        #expect(await control.snapshot == Fixtures.deactivatedSnapshot)
    }

    @Test("Repeated activation and deactivation are idempotent")
    func repeatedLifecycleCallsAreIdempotent() async throws {
        // Arrange
        let backend = TestDoubles.AudioSessionBackend()
        let control = AudioControlActor(backend: backend)

        // Act
        _ = try await control.activate()
        _ = try await control.activate()
        try await control.deactivate()
        try await control.deactivate()

        // Assert
        #expect(backend.commands == Fixtures.lifecycleCommands)
        #expect(await control.snapshot.isActive == false)
    }

    @Test("Deactivation maps backend failure and preserves active state")
    func deactivationMapsBackendFailure() async throws {
        // Arrange
        let backend = TestDoubles.AudioSessionBackend()
        let control = AudioControlActor(backend: backend)
        _ = try await control.activate()
        backend.resetCommands()
        backend.failingOperation = .setActive(false, notifyOthers: true)
        var receivedError: AudioSessionError?

        // Act
        do {
            try await control.deactivate()
        } catch {
            receivedError = error
        }

        // Assert
        #expect(receivedError == .deactivationFailed)
        #expect(backend.commands == [.setActive(false, notifyOthers: true)])
        #expect(await control.snapshot.isActive)
    }
}

private enum Fixtures {
    struct ActivationFailureCase: Sendable {
        let operation: TestDoubles.AudioSessionBackend.Operation
        let expectedError: AudioSessionError
        let expectedCommands: [TestDoubles.AudioSessionBackend.Command]
    }

    static let negotiatedSampleRate = 47_999.5
    static let negotiatedIOBufferDuration = 0.0055

    static let activationCommands: [TestDoubles.AudioSessionBackend.Command] = [
        .configureForMeasurement,
        .setPreferredSampleRate(48_000),
        .setPreferredIOBufferDuration(0),
        .setActive(true, notifyOthers: false)
    ]

    static let lifecycleCommands = activationCommands + [
        .setActive(false, notifyOthers: true)
    ]

    static let inactiveSnapshot = AudioSessionSnapshot(
        requestedSampleRate: 48_000,
        requestedIOBufferDuration: 0,
        actualSampleRate: nil,
        actualIOBufferDuration: nil,
        isActive: false
    )

    static let activeSnapshot = AudioSessionSnapshot(
        requestedSampleRate: 48_000,
        requestedIOBufferDuration: 0,
        actualSampleRate: negotiatedSampleRate,
        actualIOBufferDuration: negotiatedIOBufferDuration,
        isActive: true
    )

    static let deactivatedSnapshot = AudioSessionSnapshot(
        requestedSampleRate: 48_000,
        requestedIOBufferDuration: 0,
        actualSampleRate: negotiatedSampleRate,
        actualIOBufferDuration: negotiatedIOBufferDuration,
        isActive: false
    )

    static let activationFailureCases = [
        ActivationFailureCase(
            operation: .configureForMeasurement,
            expectedError: .categoryConfigurationFailed,
            expectedCommands: [.configureForMeasurement]
        ),
        ActivationFailureCase(
            operation: .setPreferredSampleRate,
            expectedError: .preferredSampleRateFailed(requested: 48_000),
            expectedCommands: [
                .configureForMeasurement,
                .setPreferredSampleRate(48_000)
            ]
        ),
        ActivationFailureCase(
            operation: .setPreferredIOBufferDuration,
            expectedError: .preferredIOBufferDurationFailed(requested: 0),
            expectedCommands: [
                .configureForMeasurement,
                .setPreferredSampleRate(48_000),
                .setPreferredIOBufferDuration(0)
            ]
        ),
        ActivationFailureCase(
            operation: .setActive(true, notifyOthers: false),
            expectedError: .activationFailed,
            expectedCommands: activationCommands
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
        }

        enum Command: Equatable, Sendable {
            case configureForMeasurement
            case setPreferredSampleRate(Double)
            case setPreferredIOBufferDuration(TimeInterval)
            case setActive(Bool, notifyOthers: Bool)
        }

        enum Failure: Error {
            case requested
        }

        private let lock = NSLock()
        private var recordedCommands: [Command] = []
        private var operationToFail: Operation?

        let sampleRate: Double
        let ioBufferDuration: TimeInterval
        let currentRoute = AudioRoute.empty
        let availableInputs: [AudioInput] = []
        let events: AsyncStream<AudioSessionBackendEvent>

        var commands: [Command] {
            lock.withLock { recordedCommands }
        }

        var failingOperation: Operation? {
            get { lock.withLock { operationToFail } }
            set { lock.withLock { operationToFail = newValue } }
        }

        init(
            sampleRate: Double = 48_000,
            ioBufferDuration: TimeInterval = 0.00533,
            failingAt operation: Operation? = nil
        ) {
            self.sampleRate = sampleRate
            self.ioBufferDuration = ioBufferDuration
            operationToFail = operation
            events = AsyncStream { _ in }
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

        func setPreferredInput(id: String?) throws {}

        func resetCommands() {
            lock.withLock { recordedCommands = [] }
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
