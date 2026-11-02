import Foundation

enum InstrumentType: String, CaseIterable, Codable, Equatable, Sendable {
    case bass
    case guitar
    case custom
}

enum InputProfileValidationError: Error, Equatable, Sendable {
    case emptyName
    case nonFiniteInputGain
}

/// Validated immutable data. Editing creates a replacement value through this initializer.
/// These values describe a profile; they do not apply audio processing.
struct InputProfile: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let instrument: InstrumentType
    /// Input gain in decibels. Zero means unity gain.
    let inputGainDecibels: Float
    let eq: EQConfiguration

    init(
        id: UUID = UUID(),
        name: String,
        instrument: InstrumentType,
        inputGainDecibels: Float = 0,
        eq: EQConfiguration = .flat
    ) throws(InputProfileValidationError) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw .emptyName
        }
        guard inputGainDecibels.isFinite else { throw .nonFiniteInputGain }
        self.id = id
        self.name = name
        self.instrument = instrument
        self.inputGainDecibels = inputGainDecibels
        self.eq = eq
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, instrument, inputGainDecibels, eq
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            name: values.decode(String.self, forKey: .name),
            instrument: values.decode(InstrumentType.self, forKey: .instrument),
            inputGainDecibels: values.decode(Float.self, forKey: .inputGainDecibels),
            eq: values.decode(EQConfiguration.self, forKey: .eq)
        )
    }
}
