import Foundation

enum AudioFileStoreError: Error, Equatable, Sendable { case unavailable, creationFailed }

protocol AudioFileStore: Sendable {
    var rootDirectory: URL? { get }
    func recordingURL(sessionID: UUID, recordingID: UUID) throws(AudioFileStoreError) -> URL
}

struct LocalAudioFileStore: AudioFileStore {
    let rootDirectory: URL?

    init(fileManager: FileManager = .default) {
        rootDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("Bassy", isDirectory: true)
    }

    init(rootDirectory: URL) { self.rootDirectory = rootDirectory }

    func recordingURL(sessionID: UUID, recordingID: UUID) throws(AudioFileStoreError) -> URL {
        guard let rootDirectory else { throw .unavailable }
        let directory = rootDirectory.appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { throw .creationFailed }
        return directory.appendingPathComponent(recordingID.uuidString + ".caf")
    }
}
