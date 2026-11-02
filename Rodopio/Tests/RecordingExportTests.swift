import XCTest
@testable import Ciranda

final class RecordingExportTests: XCTestCase {
    func testPreparationCopiesBytesAndReusesSnapshot() async throws {
        let fm = FileManager.default
        let source = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: source) }
        let files = ["entrada.wav", "saida.wav", "sincronizacao.json"].map { source.appendingPathComponent($0) }
        for file in files { try Data("test-\(file.lastPathComponent)".utf8).write(to: file) }
        let id = UUID()
        let result = try await RecordingExport.prepare(files: files, recordingID: id)
        defer { if let parent = result.first?.deletingLastPathComponent() { try? fm.removeItem(at: parent) } }
        XCTAssertEqual(result.count, 3)
        for (original, copy) in zip(files, result) { XCTAssertEqual(try Data(contentsOf: original), try Data(contentsOf: copy)) }
        let cached = try await RecordingExport.prepare(files: files, recordingID: id)
        XCTAssertEqual(result, cached)
    }
    func testMissingFileFailsWithoutDeletingOriginals() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        do {
            _ = try await RecordingExport.prepare(files: [url], recordingID: UUID())
            XCTFail("Expected a file error")
        } catch { XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)) }
    }
}
