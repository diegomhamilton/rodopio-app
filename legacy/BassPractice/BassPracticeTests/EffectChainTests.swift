import AVFoundation
import Foundation
import Testing
@testable import BassPractice

@Suite("Ordered effect chain")
struct EffectChainTests {
    @Test("Native connections preserve declared order between stable boundaries", arguments: [false, true])
    func nativeOrder(reversed: Bool) throws {
        // Arrange
        let engine = AVAudioEngine()
        let input = AVAudioPlayerNode()
        let output = AVAudioMixerNode()
        let gain = NativeGainProcessor(stage: .input)
        let eq = NativeEQProcessor()
        let nodes: [any NativeInstrumentProcessor] = reversed ? [eq, gain] : [gain, eq]
        let chain = InstrumentProcessingChain(processors: nodes)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        engine.attach(input); engine.attach(output)
        chain.attach(to: engine)

        // Act
        chain.connect(in: engine, input: input, output: output, format: format)

        // Assert
        #expect(engine.outputConnectionPoints(for: input, outputBus: 0).first?.node === nodes[0].audioNode)
        #expect(engine.outputConnectionPoints(for: nodes[0].audioNode, outputBus: 0).first?.node === nodes[1].audioNode)
        #expect(engine.outputConnectionPoints(for: nodes[1].audioNode, outputBus: 0).first?.node === output)
    }

    @Test("Preset storage preserves ordering, processor bypass and profile identity across reopening")
    func presetRoundTrip() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("presets.json")
        let chain = try EffectChain(effects: [
            OrderedEffect(id: UUID(), configuration: .equalizer(EQConfiguration(bands: [EQDefaults.newBand], bypassed: true))),
            OrderedEffect(id: UUID(), configuration: .gain(GainConfiguration(decibels: -6, bypassed: true)))
        ])
        let preset = try EffectPreset(name: "My ordered tone", inputProfileID: BuiltInInputProfiles.guitarID, chain: chain)
        let repository = FileEffectPresetRepository(fileURL: file)

        // Act
        try await repository.save(preset)
        let reopened = FileEffectPresetRepository(fileURL: file)
        let records = try await reopened.presets()
        let renamed = try EffectPreset(id: preset.id, name: "Renamed", inputProfileID: preset.inputProfileID, chain: chain)
        try await reopened.save(renamed)
        let updated = try await repository.presets()
        try await repository.delete(id: preset.id)

        // Assert
        #expect(records == [preset])
        #expect(updated == [renamed])
        #expect(try await reopened.presets().isEmpty)
    }

    @Test("Malformed and unsupported preset stores cannot be overwritten", arguments: Fixtures.invalidStores)
    func invalidStorePreserved(data: Data) async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("presets.json")
        try data.write(to: file)
        let repository = FileEffectPresetRepository(fileURL: file)
        let preset = try EffectPreset(name: "New", chain: EffectChain(effects: []))
        var failure: EffectPresetRepositoryError?

        // Act
        do { try await repository.save(preset) } catch { failure = error }

        // Assert
        #expect(failure != nil)
        #expect(try Data(contentsOf: file) == data)
    }

    @Test("Chain rejects duplicate processor identities before serialization")
    func duplicateEffectRejected() {
        // Arrange
        let id = UUID()
        let effects = [OrderedEffect(id: id, configuration: .gain(.unity)), OrderedEffect(id: id, configuration: .equalizer(.flat))]
        var failure: EffectPresetValidationError?

        // Act
        do { _ = try EffectChain(effects: effects) } catch { failure = error }

        // Assert
        #expect(failure == .duplicateEffectID(id))
    }
}

private enum Fixtures {
    static let invalidStores = [Data("broken JSON".utf8), Data("{\"schemaVersion\":2,\"presets\":[]}".utf8), Data("{\"schemaVersion\":1,\"presets\":42}".utf8)]
}
