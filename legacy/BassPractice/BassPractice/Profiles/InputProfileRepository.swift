import Foundation

enum InputProfileRepositoryError: Error, Equatable, Sendable {
    case readFailed
    case invalidStore
    case unsupportedSchemaVersion(Int)
    case duplicateProfileID(UUID)
    case reservedProfileID(UUID)
    case profileNotFound(UUID)
    case writeFailed
    case applicationSupportUnavailable
}

protocol InputProfileRepository: Sendable {
    /// Custom profiles, ordered by UUID for stable ordering independent of name edits.
    func profiles() async throws(InputProfileRepositoryError) -> [InputProfile]
    func save(_ profile: InputProfile) async throws(InputProfileRepositoryError)
    func delete(id: UUID) async throws(InputProfileRepositoryError)
}

/// Keeps built-in tones usable while surfacing a production storage-location failure.
struct UnavailableInputProfileRepository: InputProfileRepository {
    let failure: InputProfileRepositoryError
    func profiles() async throws(InputProfileRepositoryError) -> [InputProfile] { throw failure }
    func save(_ profile: InputProfile) async throws(InputProfileRepositoryError) { throw failure }
    func delete(id: UUID) async throws(InputProfileRepositoryError) { throw failure }
}

/// Serializes custom-profile mutations. A failed read or write never replaces the existing store.
actor FileInputProfileRepository: InputProfileRepository {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Production data lives in Application Support/Bassy/input-profiles.json.
    /// Failure is surfaced rather than redirecting user data to temporary storage.
    static func live() throws(InputProfileRepositoryError) -> FileInputProfileRepository {
        let support: URL
        do {
            support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
        } catch { throw .applicationSupportUnavailable }
        return FileInputProfileRepository(fileURL: support
            .appendingPathComponent("Bassy", isDirectory: true)
            .appendingPathComponent("input-profiles.json"))
    }

    func profiles() throws(InputProfileRepositoryError) -> [InputProfile] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        } catch { throw .readFailed }

        let header: SchemaHeader
        do { header = try JSONDecoder().decode(SchemaHeader.self, from: data) }
        catch { throw .invalidStore }
        guard header.schemaVersion == 1 else { throw .unsupportedSchemaVersion(header.schemaVersion) }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw .invalidStore }
        try validate(envelope.profiles)
        return ordered(envelope.profiles)
    }

    func save(_ profile: InputProfile) throws(InputProfileRepositoryError) {
        try rejectReservedID(profile.id)
        var updated = try profiles()
        if let index = updated.firstIndex(where: { $0.id == profile.id }) {
            updated[index] = profile
        } else {
            updated.append(profile)
        }
        try write(updated)
    }

    func delete(id: UUID) throws(InputProfileRepositoryError) {
        try rejectReservedID(id)
        var updated = try profiles()
        guard let index = updated.firstIndex(where: { $0.id == id }) else {
            throw .profileNotFound(id)
        }
        updated.remove(at: index)
        try write(updated)
    }

    private func write(_ profiles: [InputProfile]) throws(InputProfileRepositoryError) {
        try validate(profiles)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(Envelope(schemaVersion: 1, profiles: ordered(profiles)))
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch { throw .writeFailed }
    }

    private func validate(_ profiles: [InputProfile]) throws(InputProfileRepositoryError) {
        var seen = Set<UUID>()
        for profile in profiles {
            try rejectReservedID(profile.id)
            guard seen.insert(profile.id).inserted else { throw .duplicateProfileID(profile.id) }
        }
    }

    private func rejectReservedID(_ id: UUID) throws(InputProfileRepositoryError) {
        guard !BuiltInInputProfiles.profiles.contains(where: { $0.id == id }) else {
            throw .reservedProfileID(id)
        }
    }

    private func ordered(_ profiles: [InputProfile]) -> [InputProfile] {
        profiles.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private struct Envelope: Codable {
        let schemaVersion: Int
        let profiles: [InputProfile]
    }

    private struct SchemaHeader: Decodable {
        let schemaVersion: Int
    }
}
