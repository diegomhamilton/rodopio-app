import AVFoundation
import Foundation

enum ToneProcessingError: Error, Equatable, Sendable {
    case unsupportedBandCount(Int)
    case unsupportedBand(index: Int)
    case unsupportedInputGain(Float)
    case backendFailure
}

protocol AudioToneControlling: AudioGainControlling {
    var equalizer: EQConfiguration { get async }
    var selectedProfileID: UUID? { get async }
    func setEqualizer(_ configuration: EQConfiguration) async throws(ToneProcessingError)
    func applyProfile(_ profile: InputProfile) async throws(ToneProcessingError)
    func profileSnapshot(name: String) async throws(InputProfileValidationError) -> InputProfile
}

enum NativeEQLimits {
    static let maximumBands = 8
    /// Converts dimensionless Q to AVAudioUnitEQ bandwidth in octaves.
    static func bandwidth(q: Float) -> Float { 2 * asinh(1 / (2 * q)) / log(2) }

    static func validate(_ configuration: EQConfiguration, sampleRate: Double) throws(ToneProcessingError) {
        guard configuration.bands.count <= maximumBands else { throw .unsupportedBandCount(configuration.bands.count) }
        for (index, band) in configuration.bands.enumerated() {
            let bandwidth = bandwidth(q: band.q)
            guard band.frequencyHertz >= 20, Double(band.frequencyHertz) <= sampleRate / 2,
                  NativeGainLimits.range.contains(band.gainDecibels),
                  bandwidth.isFinite, (Float(0.05)...5).contains(bandwidth) else {
                throw .unsupportedBand(index: index)
            }
        }
    }
}

enum EQDefaults {
    static let newBand: EQBand = {
        do { return try EQBand(frequencyHertz: 1000, gainDecibels: 0, q: 1) }
        catch { preconditionFailure("Invalid literal EQ band defaults") }
    }()
}

/// Fixed capacity permits live changes without rebuilding the audio graph.
final class NativeEQProcessor: NativeInstrumentProcessor {
    let node = AVAudioUnitEQ(numberOfBands: NativeEQLimits.maximumBands)
    var audioNode: AVAudioNode { node }

    func apply(_ configuration: EQConfiguration, sampleRate: Double) throws(ToneProcessingError) {
        try NativeEQLimits.validate(configuration, sampleRate: sampleRate)
        applyValidated(configuration)
    }

    /// Caller validates the entire tone before performing any native writes.
    func applyValidated(_ configuration: EQConfiguration) {
        for (index, nativeBand) in node.bands.enumerated() {
            guard index < configuration.bands.count else { nativeBand.bypass = true; continue }
            let band = configuration.bands[index]
            nativeBand.filterType = .parametric
            nativeBand.frequency = band.frequencyHertz
            nativeBand.gain = band.gainDecibels
            nativeBand.bandwidth = NativeEQLimits.bandwidth(q: band.q)
            nativeBand.bypass = !band.enabled
        }
        // A flat chain needs no audio-unit processing, including empty profiles.
        node.bypass = configuration.bypassed || !configuration.bands.contains { $0.enabled && $0.gainDecibels != 0 }
    }
}
