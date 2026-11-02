import AVFoundation
import Foundation
import Testing
@testable import BassPractice

@Suite("Session library persistence")
struct SessionRepositoryTests {
    @Test("Reopening storage restores tone and recording metadata with relocated URLs")
    func relocatedRoundTrip() async throws {
        // Arrange
        let root = Fixtures.root()
        let relocated = Fixtures.root()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: relocated) }
        let repository = FileSessionRepository(rootDirectory: root)
        let id = UUID(), recordingID = UUID()
        let url = Fixtures.audioURL(root: root, session: id, recording: recordingID)
        let recording = Recording(id: recordingID, fileURL: url, createdAt: Fixtures.date, frameCount: 512, sampleRate: 48_000, channelCount: 1)
        let equalizer = EQConfiguration(bands: [try EQBand(frequencyHertz: 120, gainDecibels: 3, q: 0.8, enabled: false)], bypassed: true)
        let audio = WorkspaceAudioConfiguration(inputGain: GainConfiguration(decibels: 6, bypassed: true), outputGain: GainConfiguration(decibels: -3, bypassed: false), equalizer: equalizer, instrumentMix: MixerChannelConfiguration(volume: 0.4, muted: false), playbackMix: MixerChannelConfiguration(volume: 0.8, muted: true), inputProfileID: BuiltInInputProfiles.bassID)
        let presetID = UUID()
        let original = try PracticeSession(id: id, name: "Bass practice", audio: audio, recordings: [recording], effectPresetID: presetID, createdAt: Fixtures.date)

        // Act
        try await repository.save(original)
        try FileManager.default.copyItem(at: root, to: relocated)
        let restored = try await FileSessionRepository(rootDirectory: relocated).load(id: id)

        // Assert
        #expect(restored.audio == audio)
        #expect(restored.name == original.name)
        #expect(restored.effectPresetID == presetID)
        #expect(restored.recordings.first?.fileURL == Fixtures.audioURL(root: relocated, session: id, recording: recordingID))
        #expect(restored.recordings.first?.frameCount == 512)
    }

    @Test("Rename preserves audio bytes and deletion leaves sibling sessions intact")
    func renameAndDelete() async throws {
        // Arrange
        let root = Fixtures.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootDirectory: root)
        let first = try await repository.create(name: "First")
        let sibling = try await repository.create(name: "Sibling")
        let url = Fixtures.audioURL(root: root, session: first.id, recording: UUID())
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = Data([1, 2, 3])
        try bytes.write(to: url)
        let renamed = try PracticeSession(id: first.id, name: "Renamed", createdAt: first.createdAt)

        // Act
        try await repository.save(renamed)
        let preserved = try Data(contentsOf: url)
        try await repository.delete(id: first.id)
        let remaining = try await repository.sessions()

        // Assert
        #expect(preserved == bytes)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(remaining.map(\.id) == [sibling.id])
    }

    @Test("Corrupt and future metadata cannot be overwritten", arguments: Fixtures.invalidMetadata)
    func preservesInvalidMetadata(bytes: Data) async throws {
        // Arrange
        let root = Fixtures.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootDirectory: root)
        let session = try await repository.create(name: "Original")
        let url = root.appendingPathComponent("Sessions/\(session.id.uuidString)/session.json")
        try bytes.write(to: url)

        // Act
        var rejected = false
        do { try await repository.save(session) } catch { rejected = true }
        let preserved = try Data(contentsOf: url)

        // Assert
        #expect(rejected)
        #expect(preserved == bytes)
    }

    @Test("Earlier CAF folders recover valid audio and preserve incomplete files")
    func recoversLegacyCapture() async throws {
        // Arrange
        let root = Fixtures.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), recordingID = UUID()
        let url = Fixtures.audioURL(root: root, session: id, recording: recordingID)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        buffer.frameLength = 512
        let sink = try AudioRecordingSink(fileURL: url, format: format)
        sink.consume(buffer)
        _ = try sink.finish()
        let incomplete = url.deletingLastPathComponent().appendingPathComponent("incomplete.caf")
        try Data([0]).write(to: incomplete)

        // Act
        let sessions = try await FileSessionRepository(rootDirectory: root).sessions()

        // Assert
        let recovered = try #require(sessions.first)
        #expect(recovered.id == id)
        #expect(recovered.recordings.map(\.id) == [recordingID])
        #expect(recovered.recordings.first?.frameCount == 512)
        #expect(recovered.recoveryNotice != nil)
        #expect(FileManager.default.fileExists(atPath: incomplete.path))
    }

    @Test("Blank names and duplicate recording IDs are rejected")
    func validatesSession() throws {
        // Arrange
        let recording = Recording(id: UUID(), fileURL: URL(fileURLWithPath: "/tmp/example.caf"), createdAt: Fixtures.date, frameCount: 1, sampleRate: 48_000, channelCount: 1)

        // Act
        let blank = Result { try PracticeSession(name: "  ") }
        let duplicate = Result { try PracticeSession(name: "Practice", recordings: [recording, recording]) }

        // Assert
        #expect(throws: SessionValidationError.emptyName) { try blank.get() }
        #expect(throws: SessionValidationError.duplicateRecordingID) { try duplicate.get() }
    }

    @Test("A late save cannot recreate a deleted session")
    func deletedSessionRejectsLateSave() async throws {
        // Arrange
        let root = Fixtures.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootDirectory: root)
        let session = try await repository.create(name: "Deleted")
        try await repository.delete(id: session.id)

        // Act
        var failure: SessionRepositoryError?
        do { try await repository.save(session) } catch { failure = error }
        let remaining = try await repository.sessions()

        // Assert
        #expect(failure == .notFound)
        #expect(remaining.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Sessions/\(session.id.uuidString)").path))
    }

    @Test("Cancelled saves leave existing metadata untouched")
    func cancelledSavePreservesMetadata() async throws {
        // Arrange
        let root = Fixtures.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootDirectory: root)
        let original = try await repository.create(name: "Original")
        let changed = try PracticeSession(id: original.id, name: "Changed", createdAt: original.createdAt)

        // Act
        let rejected = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do { try await repository.save(changed); return false } catch { return true }
        }.value
        let restored = try await repository.load(id: original.id)

        // Assert
        #expect(rejected)
        #expect(restored == original)
    }
}

private enum Fixtures {
    static let date = Date(timeIntervalSince1970: 1_700_000_000)
    static let invalidMetadata = [Data("invalid".utf8), Data("{\"schemaVersion\":99}".utf8)]
    static func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    static func audioURL(root: URL, session: UUID, recording: UUID) -> URL {
        root.appendingPathComponent("Sessions/\(session.uuidString)/recordings/\(recording.uuidString).caf")
    }
}
