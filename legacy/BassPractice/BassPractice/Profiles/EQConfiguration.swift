import Foundation

enum EQBandValidationError: Error, Equatable, Sendable {
    case invalidFrequency
    case nonFiniteGain
    case invalidQ
}

/// A validated value schema independent of the eventual DSP backend's supported ranges.
struct EQBand: Codable, Equatable, Sendable {
    /// Center frequency in hertz; must be finite and positive.
    let frequencyHertz: Float
    /// Gain in decibels; zero means no boost or cut.
    let gainDecibels: Float
    /// Dimensionless quality factor; must be finite and positive.
    let q: Float
    let enabled: Bool

    init(frequencyHertz: Float, gainDecibels: Float, q: Float, enabled: Bool = true) throws(EQBandValidationError) {
        guard frequencyHertz.isFinite, frequencyHertz > 0 else { throw .invalidFrequency }
        guard gainDecibels.isFinite else { throw .nonFiniteGain }
        guard q.isFinite, q > 0 else { throw .invalidQ }
        self.frequencyHertz = frequencyHertz
        self.gainDecibels = gainDecibels
        self.q = q
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey {
        case frequencyHertz, gainDecibels, q, enabled
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            frequencyHertz: values.decode(Float.self, forKey: .frequencyHertz),
            gainDecibels: values.decode(Float.self, forKey: .gainDecibels),
            q: values.decode(Float.self, forKey: .q),
            enabled: values.decode(Bool.self, forKey: .enabled)
        )
    }
}

struct EQConfiguration: Codable, Equatable, Sendable {
    let bands: [EQBand]
    let bypassed: Bool

    init(bands: [EQBand], bypassed: Bool = false) {
        self.bands = bands
        self.bypassed = bypassed
    }

    private enum CodingKeys: String, CodingKey { case bands, bypassed }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bands = try values.decode([EQBand].self, forKey: .bands)
        bypassed = try values.decodeIfPresent(Bool.self, forKey: .bypassed) ?? false
    }

    static let flat = EQConfiguration(bands: [])
}
