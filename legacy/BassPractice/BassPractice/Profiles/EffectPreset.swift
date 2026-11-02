import Foundation

enum EffectConfiguration: Codable, Equatable, Sendable {
    case gain(GainConfiguration)
    case equalizer(EQConfiguration)
}

struct OrderedEffect: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let configuration: EffectConfiguration
}

enum EffectPresetValidationError: Error, Equatable, Sendable {
    case duplicateEffectID(UUID)
    case nonFiniteGain
    case emptyName
}

struct EffectChain: Codable, Equatable, Sendable {
    let effects: [OrderedEffect]
    init(effects: [OrderedEffect]) throws(EffectPresetValidationError) {
        var ids = Set<UUID>()
        for effect in effects {
            guard ids.insert(effect.id).inserted else { throw .duplicateEffectID(effect.id) }
            if case let .gain(gain) = effect.configuration, !gain.decibels.isFinite { throw .nonFiniteGain }
        }
        self.effects = effects
    }
    private enum CodingKeys: String, CodingKey { case effects }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(effects: values.decode([OrderedEffect].self, forKey: .effects))
    }
}

struct EffectPreset: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let inputProfileID: UUID?
    let chain: EffectChain
    init(id: UUID = UUID(), name: String, inputProfileID: UUID? = nil, chain: EffectChain) throws(EffectPresetValidationError) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .emptyName }
        self.id = id; self.name = name; self.inputProfileID = inputProfileID; self.chain = chain
    }
    private enum CodingKeys: String, CodingKey { case id, name, inputProfileID, chain }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: values.decode(UUID.self, forKey: .id), name: values.decode(String.self, forKey: .name), inputProfileID: values.decodeIfPresent(UUID.self, forKey: .inputProfileID), chain: values.decode(EffectChain.self, forKey: .chain))
    }
}
