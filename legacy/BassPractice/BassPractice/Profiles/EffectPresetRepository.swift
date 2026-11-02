import Foundation

enum EffectPresetRepositoryError: Error, Equatable, Sendable {
    case readFailed, invalidStore, writeFailed, applicationSupportUnavailable
    case unsupportedVersion(Int)
    case duplicateID(UUID)
    case notFound(UUID)
}

protocol EffectPresetRepository: Sendable {
    func presets() async throws(EffectPresetRepositoryError) -> [EffectPreset]
    func save(_ preset: EffectPreset) async throws(EffectPresetRepositoryError)
    func delete(id: UUID) async throws(EffectPresetRepositoryError)
}

actor FileEffectPresetRepository: EffectPresetRepository {
    private let fileURL: URL
    init(fileURL: URL) { self.fileURL = fileURL }
    static func live() throws(EffectPresetRepositoryError) -> FileEffectPresetRepository {
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            return FileEffectPresetRepository(fileURL: support.appendingPathComponent("Bassy/effect-presets.json"))
        } catch { throw .applicationSupportUnavailable }
    }
    func presets() throws(EffectPresetRepositoryError) -> [EffectPreset] {
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
        catch { throw .readFailed }
        let header: Header
        do { header = try JSONDecoder().decode(Header.self, from: data) } catch { throw .invalidStore }
        guard header.schemaVersion == 1 else { throw .unsupportedVersion(header.schemaVersion) }
        let store: Store
        do { store = try JSONDecoder().decode(Store.self, from: data) } catch { throw .invalidStore }
        var ids = Set<UUID>()
        for preset in store.presets {
            guard ids.insert(preset.id).inserted else { throw .duplicateID(preset.id) }
        }
        return store.presets.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    func save(_ preset: EffectPreset) throws(EffectPresetRepositoryError) {
        var updated = try presets()
        updated.removeAll { $0.id == preset.id }
        updated.append(preset)
        try write(updated)
    }
    func delete(id: UUID) throws(EffectPresetRepositoryError) {
        var updated = try presets()
        guard updated.contains(where: { $0.id == id }) else { throw .notFound(id) }
        updated.removeAll { $0.id == id }
        try write(updated)
    }
    private func write(_ presets: [EffectPreset]) throws(EffectPresetRepositoryError) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(Store(schemaVersion: 1, presets: presets.sorted { $0.id.uuidString < $1.id.uuidString }))
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch { throw .writeFailed }
    }
    private struct Header: Decodable { let schemaVersion: Int }
    private struct Store: Codable { let schemaVersion: Int; let presets: [EffectPreset] }
}
