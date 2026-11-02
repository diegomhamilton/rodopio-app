import Foundation
import Testing
@testable import BassPractice

@Suite("Audio route observation")
struct AudioRouteObservationTests {
    @Test("Current route is available before a route change")
    func exposesInitialRoute() async {
        // Arrange
        let backend = TestDoubles.AudioSessionBackend(route: Fixtures.builtInRoute)
        let control = AudioControlActor(backend: backend)

        // Act
        let route = await control.currentRoute

        // Assert
        #expect(route == Fixtures.builtInRoute)
    }

    @Test(
        "Route events refresh the current route and preserve their typed reason",
        arguments: Fixtures.routeChanges
    )
    fileprivate func refreshesRouteForEvent(testCase: Fixtures.RouteChangeCase) async {
        // Arrange
        let backend = TestDoubles.AudioSessionBackend(route: Fixtures.builtInRoute)
        let control = AudioControlActor(backend: backend)
        let events = await control.events()
        var iterator = events.makeAsyncIterator()

        // Act
        backend.changeRoute(to: testCase.route, reason: testCase.reason)
        let event = await iterator.next()

        // Assert
        #expect(event == .routeChanged(route: testCase.route, reason: testCase.reason))
        #expect(await control.currentRoute == testCase.route)
    }

    @Test("Every route observer receives the same event")
    func broadcastsToMultipleObservers() async {
        // Arrange
        let backend = TestDoubles.AudioSessionBackend(route: Fixtures.builtInRoute)
        let control = AudioControlActor(backend: backend)
        let firstEvents = await control.events()
        let secondEvents = await control.events()
        var firstIterator = firstEvents.makeAsyncIterator()
        var secondIterator = secondEvents.makeAsyncIterator()

        // Act
        backend.changeRoute(to: Fixtures.usbRoute, reason: .newDeviceAvailable)
        let firstEvent = await firstIterator.next()
        let secondEvent = await secondIterator.next()

        // Assert
        #expect(
            firstEvent == .routeChanged(
                route: Fixtures.usbRoute,
                reason: .newDeviceAvailable
            )
        )
        #expect(secondEvent == firstEvent)
        #expect(await control.currentRoute == Fixtures.usbRoute)
    }
}

private enum Fixtures {
    struct RouteChangeCase: Sendable, CustomTestStringConvertible {
        let route: AudioRoute
        let reason: AudioRouteChangeReason

        var testDescription: String {
            String(describing: reason)
        }
    }

    static let builtInRoute = AudioRoute(
        inputs: [
            AudioDevice(id: "built-in-mic", name: "iPhone Microphone", portType: "MicrophoneBuiltIn")
        ],
        outputs: [
            AudioDevice(id: "receiver", name: "Receiver", portType: "Receiver")
        ]
    )

    static let usbRoute = AudioRoute(
        inputs: [
            AudioDevice(id: "cube-baby", name: "Cube Baby", portType: "USBAudio")
        ],
        outputs: [
            AudioDevice(id: "cube-baby", name: "Cube Baby", portType: "USBAudio")
        ]
    )

    static let outputOnlyRoute = AudioRoute(
        inputs: [],
        outputs: [
            AudioDevice(id: "headphones", name: "Headphones", portType: "Headphones")
        ]
    )

    static let routeChanges = [
        RouteChangeCase(route: usbRoute, reason: .newDeviceAvailable),
        RouteChangeCase(route: outputOnlyRoute, reason: .oldDeviceUnavailable),
        RouteChangeCase(route: builtInRoute, reason: .routeConfigurationChange)
    ]
}

private enum TestDoubles {
    final class AudioSessionBackend: BassPractice.AudioSessionBackend, @unchecked Sendable {
        private let lock = NSLock()
        private var storedRoute: AudioRoute
        private let continuation: AsyncStream<AudioSessionBackendEvent>.Continuation

        let sampleRate = 48_000.0
        let ioBufferDuration = 0.00533
        let availableInputs: [AudioInput] = []
        let events: AsyncStream<AudioSessionBackendEvent>

        var currentRoute: AudioRoute {
            lock.withLock { storedRoute }
        }

        init(route: AudioRoute) {
            storedRoute = route
            let (events, continuation) = AsyncStream<AudioSessionBackendEvent>.makeStream()
            self.events = events
            self.continuation = continuation
        }

        func changeRoute(to route: AudioRoute, reason: AudioRouteChangeReason) {
            lock.withLock { storedRoute = route }
            continuation.yield(.routeChanged(reason: reason))
        }

        func configureForMeasurement() throws {}
        func setPreferredSampleRate(_ sampleRate: Double) throws {}
        func setPreferredIOBufferDuration(_ duration: TimeInterval) throws {}
        func setActive(_ active: Bool, notifyOthersOnDeactivation: Bool) throws {}
        func setPreferredInput(id: String?) throws {}
    }
}
