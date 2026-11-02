import AVFoundation
import Foundation
import Testing
@testable import BassPractice

@Suite("Audio input discovery")
struct AudioInputDiscoveryTests {
    @Test(
        "Classifies audio input port types",
        arguments: Fixtures.inputKindCases
    )
    fileprivate func classifiesPortTypes(testCase: Fixtures.InputKindCase) {
        // Arrange
        let portType = testCase.portType

        // Act
        let kind = AudioInputKind(portType: portType)

        // Assert
        #expect(kind == testCase.expectedKind)
    }

    @Test(
        "Exposes the backend's initial available input snapshot",
        arguments: Fixtures.initialInputSnapshots
    )
    func exposesInitialAvailableInputs(inputs: [AudioInput]) async {
        // Arrange
        let backend = TestDoubles.AudioSessionBackend(inputs: inputs)
        let control = AudioControlActor(backend: backend)

        // Act
        let availableInputs = await control.availableInputs

        // Assert
        #expect(availableInputs == inputs)
    }

    @Test("Activation refreshes inputs made available by session configuration")
    func activationRefreshesAvailableInputs() async throws {
        // Arrange
        let backend = TestDoubles.AudioSessionBackend(inputs: [])
        let control = AudioControlActor(backend: backend)
        backend.setInputs(Fixtures.availableInputs)

        // Act
        _ = try await control.activate()

        // Assert
        #expect(await control.availableInputs == Fixtures.availableInputs)
    }

    @Test(
        "Route events refresh available inputs before notifying observers",
        arguments: Fixtures.inputRefreshCases
    )
    fileprivate func routeEventsRefreshAvailableInputs(
        testCase: Fixtures.InputRefreshCase
    ) async {
        // Arrange
        let backend = TestDoubles.AudioSessionBackend(inputs: testCase.initialInputs)
        let control = AudioControlActor(backend: backend)
        let events = await control.events()
        var iterator = events.makeAsyncIterator()

        // Act
        backend.changeInputs(testCase.updatedInputs)
        let event = await iterator.next()
        let availableInputs = await control.availableInputs

        // Assert
        #expect(
            event == .routeChanged(
                route: .empty,
                reason: .newDeviceAvailable
            )
        )
        #expect(availableInputs == testCase.updatedInputs)
    }
}

private enum Fixtures {
    struct InputKindCase: Sendable, CustomTestStringConvertible {
        let portType: String
        let expectedKind: AudioInputKind

        var testDescription: String {
            portType
        }
    }

    struct InputRefreshCase: Sendable, CustomTestStringConvertible {
        let description: String
        let initialInputs: [AudioInput]
        let updatedInputs: [AudioInput]

        var testDescription: String {
            description
        }
    }

    static let availableInputs = [
        AudioInput(
            id: "built-in-mic",
            name: "iPhone Microphone",
            portType: "MicrophoneBuiltIn"
        ),
        AudioInput(
            id: "usb-input",
            name: "USB Audio Device",
            portType: "USBAudio"
        )
    ]

    static let inputKindCases = [
        InputKindCase(
            portType: AVAudioSession.Port.builtInMic.rawValue,
            expectedKind: .builtInMicrophone
        ),
        InputKindCase(portType: AVAudioSession.Port.usbAudio.rawValue, expectedKind: .usb),
        InputKindCase(portType: AVAudioSession.Port.bluetoothHFP.rawValue, expectedKind: .bluetooth),
        InputKindCase(portType: AVAudioSession.Port.bluetoothA2DP.rawValue, expectedKind: .bluetooth),
        InputKindCase(portType: AVAudioSession.Port.bluetoothLE.rawValue, expectedKind: .bluetooth),
        InputKindCase(
            portType: "FutureInputPort",
            expectedKind: .unknown(rawPortType: "FutureInputPort")
        )
    ]

    static let initialInputSnapshots: [[AudioInput]] = [
        [],
        availableInputs
    ]

    static let inputRefreshCases = [
        InputRefreshCase(
            description: "inputs become available",
            initialInputs: [],
            updatedInputs: availableInputs
        ),
        InputRefreshCase(
            description: "inputs become unavailable",
            initialInputs: availableInputs,
            updatedInputs: []
        )
    ]
}

private enum TestDoubles {
    final class AudioSessionBackend: BassPractice.AudioSessionBackend, @unchecked Sendable {
        private let lock = NSLock()
        private var storedInputs: [AudioInput]
        private let continuation: AsyncStream<AudioSessionBackendEvent>.Continuation

        let sampleRate = 48_000.0
        let ioBufferDuration = 0.00533
        let currentRoute = AudioRoute.empty
        let events: AsyncStream<AudioSessionBackendEvent>

        var availableInputs: [AudioInput] {
            lock.withLock { storedInputs }
        }

        init(inputs: [AudioInput]) {
            storedInputs = inputs
            let (events, continuation) = AsyncStream<AudioSessionBackendEvent>.makeStream()
            self.events = events
            self.continuation = continuation
        }

        func setInputs(_ inputs: [AudioInput]) {
            lock.withLock { storedInputs = inputs }
        }

        func changeInputs(_ inputs: [AudioInput]) {
            setInputs(inputs)
            continuation.yield(.routeChanged(reason: .newDeviceAvailable))
        }

        func configureForMeasurement() throws {}
        func setPreferredSampleRate(_ sampleRate: Double) throws {}
        func setPreferredIOBufferDuration(_ duration: TimeInterval) throws {}
        func setActive(_ active: Bool, notifyOthersOnDeactivation: Bool) throws {}
        func setPreferredInput(id: String?) throws {}
    }
}
