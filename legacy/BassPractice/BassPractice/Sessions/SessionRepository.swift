import AVFoundation
import Foundation

enum SessionValidationError: Error, Equatable, Sendable { case emptyName, invalidDate, invalidAudio, duplicateRecordingID }

struct PracticeSession: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let audio: WorkspaceAudioConfiguration
    let recordings: [Recording]
    let effectPresetID: UUID?
    let createdAt: Date
    let updatedAt: Date
    let recoveryNotice: String?

    init(id: UUID = UUID(), name: String, audio: WorkspaceAudioConfiguration = .initial, recordings: [Recording] = [], effectPresetID: UUID? = nil, createdAt: Date = Date(), updatedAt: Date? = nil, recoveryNotice: String? = nil) throws(SessionValidationError) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .emptyName }
        let updated = updatedAt ?? createdAt
        guard createdAt.timeIntervalSince1970.isFinite, updated.timeIntervalSince1970.isFinite, updated >= createdAt else { throw .invalidDate }
        guard audio.inputGain.decibels.isFinite, audio.outputGain.decibels.isFinite,
              [audio.instrumentMix, audio.playbackMix].allSatisfy({ $0.volume.isFinite && (Float(0)...1).contains($0.volume) }) else { throw .invalidAudio }
        var ids = Set<UUID>()
        for recording in recordings {
            guard ids.insert(recording.id).inserted else { throw .duplicateRecordingID }
            guard recording.fileURL.isFileURL, recording.frameCount > 0, recording.sampleRate.isFinite, recording.sampleRate > 0,
                  recording.channelCount > 0, recording.createdAt.timeIntervalSince1970.isFinite else { throw .invalidAudio }
        }
        self.id = id; self.name = name; self.audio = audio; self.recordings = recordings
        self.effectPresetID = effectPresetID; self.createdAt = createdAt; self.updatedAt = updated; self.recoveryNotice = recoveryNotice
    }

    private enum CodingKeys: String, CodingKey { case id, name, audio, recordings, effectPresetID, createdAt, updatedAt, recoveryNotice }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: values.decode(UUID.self, forKey: .id), name: values.decode(String.self, forKey: .name), audio: values.decode(WorkspaceAudioConfiguration.self, forKey: .audio), recordings: values.decode([Recording].self, forKey: .recordings), effectPresetID: values.decodeIfPresent(UUID.self, forKey: .effectPresetID), createdAt: values.decode(Date.self, forKey: .createdAt), updatedAt: values.decode(Date.self, forKey: .updatedAt), recoveryNotice: values.decodeIfPresent(String.self, forKey: .recoveryNotice))
    }
}

enum SessionRepositoryError: Error, Equatable, Sendable {
    case unavailable, readFailed, invalidStore, writeFailed, notFound, deleteFailed
    case unsupportedVersion(Int)
}

protocol SessionRepository: Sendable {
    func sessions() async throws(SessionRepositoryError) -> [PracticeSession]
    func create(name: String) async throws(SessionRepositoryError) -> PracticeSession
    func load(id: UUID) async throws(SessionRepositoryError) -> PracticeSession
    func save(_ session: PracticeSession) async throws(SessionRepositoryError)
    func delete(id: UUID) async throws(SessionRepositoryError)
}

struct UnavailableSessionRepository: SessionRepository {
    func sessions() async throws(SessionRepositoryError) -> [PracticeSession] { throw .unavailable }
    func create(name: String) async throws(SessionRepositoryError) -> PracticeSession { throw .unavailable }
    func load(id: UUID) async throws(SessionRepositoryError) -> PracticeSession { throw .unavailable }
    func save(_ session: PracticeSession) async throws(SessionRepositoryError) { throw .unavailable }
    func delete(id: UUID) async throws(SessionRepositoryError) { throw .unavailable }
}

actor FileSessionRepository: SessionRepository {
    private let rootDirectory: URL
    // Actor jobs may arrive after deletion; late saves must not recreate removed folders.
    private var deletedIDs = Set<UUID>()
    init(rootDirectory: URL) { self.rootDirectory = rootDirectory.appendingPathComponent("Sessions", isDirectory: true) }
    func sessions() throws(SessionRepositoryError) -> [PracticeSession] {
        let folders: [URL]
        do { folders = try FileManager.default.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
        catch { throw .readFailed }
        var result: [PracticeSession] = []
        for folder in folders {
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            let isDirectory: Bool
            do { isDirectory = try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true } catch { throw .readFailed }
            guard isDirectory else { continue }
            if FileManager.default.fileExists(atPath: metadataURL(id).path) { result.append(try load(id: id)) }
            else { result.append(try recover(id: id)) }
        }
        return result.sorted { $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt }
    }
    func create(name: String) throws(SessionRepositoryError) -> PracticeSession {
        let session: PracticeSession
        do { session = try PracticeSession(name: name) } catch { throw .invalidStore }
        try save(session)
        return session
    }
    func load(id: UUID) throws(SessionRepositoryError) -> PracticeSession {
        let data: Data
        do { data = try Data(contentsOf: metadataURL(id)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { throw .notFound }
        catch { throw .readFailed }
        return try decode(data, id: id)
    }
    func save(_ session: PracticeSession) throws(SessionRepositoryError) {
        guard !Task.isCancelled else { throw .writeFailed }
        guard !deletedIDs.contains(session.id) else { throw .notFound }
        if FileManager.default.fileExists(atPath: metadataURL(session.id).path) { _ = try load(id: session.id) }
        guard session.recordings.allSatisfy({ $0.fileURL.standardizedFileURL == recordingURL(sessionID: session.id, recordingID: $0.id).standardizedFileURL }) else { throw .invalidStore }
        do {
            let data = try JSONEncoder().encode(Store(schemaVersion: 1, session: StoredSession(session)))
            try FileManager.default.createDirectory(at: folderURL(session.id), withIntermediateDirectories: true)
            try data.write(to: metadataURL(session.id), options: .atomic)
        } catch { throw .writeFailed }
    }
    func delete(id: UUID) throws(SessionRepositoryError) {
        _ = try load(id: id)
        do {
            try FileManager.default.removeItem(at: folderURL(id))
            deletedIDs.insert(id)
        } catch { throw .deleteFailed }
    }
    private func folderURL(_ id: UUID) -> URL { rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func metadataURL(_ id: UUID) -> URL { folderURL(id).appendingPathComponent("session.json") }
    private func recordingURL(sessionID: UUID, recordingID: UUID) -> URL { folderURL(sessionID).appendingPathComponent("recordings", isDirectory: true).appendingPathComponent(recordingID.uuidString + ".caf") }
    private func decode(_ data: Data, id: UUID) throws(SessionRepositoryError) -> PracticeSession {
        let header: Header
        do { header = try JSONDecoder().decode(Header.self, from: data) } catch { throw .invalidStore }
        guard header.schemaVersion == 1 else { throw .unsupportedVersion(header.schemaVersion) }
        do {
            let stored = try JSONDecoder().decode(Store.self, from: data).session
            guard stored.id == id else { throw SessionRepositoryError.invalidStore }
            return try stored.domain(recordingURL: { self.recordingURL(sessionID: id, recordingID: $0) })
        } catch { throw .invalidStore }
    }
    /// Upgrades F4 folders that predate metadata without deleting incomplete files.
    private func recover(id: UUID) throws(SessionRepositoryError) -> PracticeSession {
        let directory = folderURL(id).appendingPathComponent("recordings", isDirectory: true)
        let files: [URL]
        do { files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { files = [] }
        catch { throw .readFailed }
        var recordings: [Recording] = []
        var incomplete = false
        for file in files where file.pathExtension == "caf" {
            guard let recordingID = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { incomplete = true; continue }
            do {
                let audio = try AVAudioFile(forReading: file)
                guard audio.length > 0 else { incomplete = true; continue }
                let date = try file.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date()
                recordings.append(Recording(id: recordingID, fileURL: file, createdAt: date, frameCount: audio.length, sampleRate: audio.processingFormat.sampleRate, channelCount: audio.processingFormat.channelCount))
            } catch { incomplete = true }
        }
        let created = recordings.map(\.createdAt).min() ?? Date()
        let updated = recordings.map(\.createdAt).max() ?? created
        let session: PracticeSession
        do { session = try PracticeSession(id: id, name: "Recovered Practice", recordings: recordings.sorted { $0.createdAt < $1.createdAt }, createdAt: created, updatedAt: updated, recoveryNotice: incomplete ? "Some incomplete audio files remain in this session folder and are not listed." : "Recovered recordings from an earlier app version. The original tone settings were not stored.") }
        catch { throw .invalidStore }
        try save(session)
        return session
    }
    private struct Header: Codable { let schemaVersion: Int }
    private struct Store: Codable { let schemaVersion: Int; let session: StoredSession }
    private struct StoredRecording: Codable {
        let id: UUID; let createdAt: Date; let frameCount: Int64; let sampleRate: Double; let channelCount: UInt32
        init(_ recording: Recording) { id = recording.id; createdAt = recording.createdAt; frameCount = recording.frameCount; sampleRate = recording.sampleRate; channelCount = recording.channelCount }
        func domain(url: URL) -> Recording { Recording(id: id, fileURL: url, createdAt: createdAt, frameCount: frameCount, sampleRate: sampleRate, channelCount: channelCount) }
    }
    private struct StoredSession: Codable {
        let id: UUID; let name: String; let audio: WorkspaceAudioConfiguration; let recordings: [StoredRecording]
        let effectPresetID: UUID?; let createdAt: Date; let updatedAt: Date; let recoveryNotice: String?
        init(_ session: PracticeSession) { id = session.id; name = session.name; audio = session.audio; recordings = session.recordings.map(StoredRecording.init); effectPresetID = session.effectPresetID; createdAt = session.createdAt; updatedAt = session.updatedAt; recoveryNotice = session.recoveryNotice }
        func domain(recordingURL: (UUID) -> URL) throws -> PracticeSession { try PracticeSession(id: id, name: name, audio: audio, recordings: recordings.map { $0.domain(url: recordingURL($0.id)) }, effectPresetID: effectPresetID, createdAt: createdAt, updatedAt: updatedAt, recoveryNotice: recoveryNotice) }
    }
}
