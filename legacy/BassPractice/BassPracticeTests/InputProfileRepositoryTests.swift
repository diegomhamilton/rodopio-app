import Foundation
import Testing
@testable import BassPractice

@Suite("Custom input profile persistence")
struct InputProfileRepositoryTests {
    @Test("A missing store returns no custom profiles without creating a file")
    func missingStoreIsEmpty() async throws {
        // Arrange
        let location = Fixtures.temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let repository = FileInputProfileRepository(fileURL: location.file)

        // Act
        let profiles = try await repository.profiles()

        // Assert
        #expect(profiles.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: location.file.path))
    }

    @Test("Saving, updating, and deleting custom profiles round-trips a versioned store in UUID order")
    func customCRUDRoundTrip() async throws {
        // Arrange
        let location = Fixtures.temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let repository = FileInputProfileRepository(fileURL: location.file)
        let first = try InputProfile(id: Fixtures.firstID, name: "Custom Bass", instrument: .bass)
        let second = try InputProfile(id: Fixtures.secondID, name: "Custom Guitar", instrument: .guitar)
        let updated = try InputProfile(id: first.id, name: "Edited Bass", instrument: .bass, inputGainDecibels: -6)

        // Act
        try await repository.save(second)
        try await repository.save(first)
        try await repository.save(updated)
        let reopened = FileInputProfileRepository(fileURL: location.file)
        let restored = try await reopened.profiles()
        let envelope = try JSONDecoder().decode(Fixtures.StoredEnvelope.self, from: Data(contentsOf: location.file))
        try await reopened.delete(id: second.id)
        let remaining = try await repository.profiles()

        // Assert
        #expect(restored == [updated, second])
        #expect(envelope.schemaVersion == 1)
        #expect(envelope.profiles == restored)
        #expect(remaining == [updated])
    }

    @Test("Invalid existing stores surface typed errors and remain untouched by attempted save or delete", arguments: Fixtures.invalidStores)
    fileprivate func invalidStoreDoesNotGetOverwritten(testCase: Fixtures.InvalidStore) async throws {
        // Arrange
        let location = Fixtures.temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        let original = Data(testCase.json.utf8)
        try original.write(to: location.file)
        let repository = FileInputProfileRepository(fileURL: location.file)
        let custom = try InputProfile(id: Fixtures.secondID, name: "New Custom", instrument: .custom)
        var readFailure: InputProfileRepositoryError?
        var saveFailure: InputProfileRepositoryError?
        var deleteFailure: InputProfileRepositoryError?

        // Act
        do { _ = try await repository.profiles() } catch { readFailure = error }
        do { try await repository.save(custom) } catch { saveFailure = error }
        do { try await repository.delete(id: Fixtures.firstID) } catch { deleteFailure = error }
        let retained = try Data(contentsOf: location.file)

        // Assert
        #expect(readFailure == testCase.expected)
        #expect(saveFailure == testCase.expected)
        #expect(deleteFailure == testCase.expected)
        #expect(retained == original)
    }

    @Test("Built-in identities cannot be saved or deleted from the custom store", arguments: BuiltInInputProfiles.profiles)
    func builtInMutationsRejected(profile: InputProfile) async throws {
        // Arrange
        let location = Fixtures.temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let repository = FileInputProfileRepository(fileURL: location.file)
        var saveFailure: InputProfileRepositoryError?
        var deleteFailure: InputProfileRepositoryError?

        // Act
        do { try await repository.save(profile) } catch { saveFailure = error }
        do { try await repository.delete(id: profile.id) } catch { deleteFailure = error }

        // Assert
        #expect(saveFailure == .reservedProfileID(profile.id))
        #expect(deleteFailure == .reservedProfileID(profile.id))
        #expect(!FileManager.default.fileExists(atPath: location.file.path))
    }

    @Test("Deleting an absent custom identifier reports a typed failure without creating a store")
    func absentDeleteDoesNotCreateStore() async throws {
        // Arrange
        let location = Fixtures.temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let repository = FileInputProfileRepository(fileURL: location.file)
        var failure: InputProfileRepositoryError?

        // Act
        do { try await repository.delete(id: Fixtures.firstID) } catch { failure = error }

        // Assert
        #expect(failure == .profileNotFound(Fixtures.firstID))
        #expect(!FileManager.default.fileExists(atPath: location.file.path))
    }

    @Test("A failed atomic write preserves the last committed store and allows a later retry")
    func writeFailurePreservesCommittedStore() async throws {
        // Arrange
        let location = Fixtures.temporaryLocation()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: location.directory.path)
            try? FileManager.default.removeItem(at: location.directory)
        }
        let repository = FileInputProfileRepository(fileURL: location.file)
        let original = try InputProfile(id: Fixtures.firstID, name: "Original", instrument: .custom)
        let replacement = try InputProfile(id: original.id, name: "Edited", instrument: .custom)
        try await repository.save(original)
        let committedBytes = try Data(contentsOf: location.file)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: location.directory.path)
        var failure: InputProfileRepositoryError?

        // Act
        do { try await repository.save(replacement) } catch { failure = error }
        let retainedBytes = try Data(contentsOf: location.file)
        let retainedProfiles = try await repository.profiles()
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: location.directory.path)
        try await repository.save(replacement)
        let retriedProfiles = try await repository.profiles()

        // Assert
        #expect(failure == .writeFailed)
        #expect(retainedBytes == committedBytes)
        #expect(retainedProfiles == [original])
        #expect(retriedProfiles == [replacement])
    }

    @Test("Concurrent saves on one repository serialize without losing independent custom records")
    func concurrentSavesPreserveRecords() async throws {
        // Arrange
        let location = Fixtures.temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let repository = FileInputProfileRepository(fileURL: location.file)
        let first = try InputProfile(id: Fixtures.firstID, name: "First", instrument: .bass)
        let second = try InputProfile(id: Fixtures.secondID, name: "Second", instrument: .guitar)

        // Act
        async let firstSave: Void = repository.save(first)
        async let secondSave: Void = repository.save(second)
        _ = try await (firstSave, secondSave)
        let profiles = try await repository.profiles()

        // Assert
        #expect(profiles == [first, second])
    }

    @Test("A directory at the store path surfaces a read failure without replacing it")
    func unreadableStoreIsNotTreatedAsMissing() async throws {
        // Arrange
        let location = Fixtures.temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        try FileManager.default.createDirectory(at: location.file, withIntermediateDirectories: true)
        let repository = FileInputProfileRepository(fileURL: location.file)
        var failure: InputProfileRepositoryError?

        // Act
        do { _ = try await repository.profiles() } catch { failure = error }

        // Assert
        #expect(failure == .readFailed)
        #expect(FileManager.default.fileExists(atPath: location.file.path))
    }
}

private enum Fixtures {
    static let firstID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 16))
    static let secondID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 32))
    struct Location {
        let directory: URL
        let file: URL
    }
    static func temporaryLocation() -> Location {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("InputProfileTests-\(UUID().uuidString)", isDirectory: true)
        return Location(directory: directory, file: directory.appendingPathComponent("profiles.json"))
    }
    struct StoredEnvelope: Decodable {
        let schemaVersion: Int
        let profiles: [InputProfile]
    }
    struct InvalidStore: Sendable {
        let json: String
        let expected: InputProfileRepositoryError
    }
    static let profileJSON = #"{"id":"00000000-0000-0000-0000-000000000010","name":"Custom","instrument":"custom","inputGainDecibels":0,"eq":{"bands":[]}}"#
    static let invalidStores = [
        InvalidStore(json: "not JSON", expected: .invalidStore),
        InvalidStore(json: #"{"schemaVersion":2,"profiles":"future-format"}"#, expected: .unsupportedSchemaVersion(2)),
        InvalidStore(json: "{\"schemaVersion\":1,\"profiles\":[\(profileJSON),\(profileJSON)]}", expected: .duplicateProfileID(firstID)),
        InvalidStore(json: "{\"schemaVersion\":1,\"profiles\":[\(profileJSON.replacingOccurrences(of: "000000000010", with: "000000000001"))]}", expected: .reservedProfileID(BuiltInInputProfiles.bassID)),
        InvalidStore(json: "{\"schemaVersion\":1,\"profiles\":[\(profileJSON.replacingOccurrences(of: "\"name\":\"Custom\"", with: "\"name\":\" \""))]}", expected: .invalidStore),
        InvalidStore(json: "{\"schemaVersion\":1,\"profiles\":[\(profileJSON.replacingOccurrences(of: "\"bands\":[]", with: "\"bands\":[{\"frequencyHertz\":0,\"gainDecibels\":0,\"q\":1,\"enabled\":true}]"))]}", expected: .invalidStore),
        InvalidStore(json: #"{"profiles":[]}"#, expected: .invalidStore)
    ]
}
