import OSLog

struct AppLogger {
    private let app = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BassPractice", category: "app")
    private let audio = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BassPractice", category: "audio")
    private let storage = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BassPractice", category: "storage")

    func appLaunched() {
        app.info("App launched")
    }

    func audioRouteChanged(_ description: String) {
        audio.info("Audio route changed: \(description, privacy: .public)")
    }

    func audioSessionChanged(_ description: String) {
        audio.info("Audio session changed: \(description, privacy: .public)")
    }

    func audioEngineChanged(_ description: String) {
        audio.info("Audio engine changed: \(description, privacy: .public)")
    }

    func recordingChanged(_ description: String) {
        audio.info("Recording changed: \(description, privacy: .public)")
    }

    func fileOperationFailed(_ description: String) {
        storage.error("File operation failed: \(description, privacy: .public)")
    }

    func sessionLoaded(_ identifier: String) {
        storage.info("Session loaded: \(identifier, privacy: .private(mask: .hash))")
    }
}
