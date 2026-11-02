import Foundation
import AVFoundation

enum GainStage: String, CaseIterable, Hashable, Sendable { case input, output }

struct GainConfiguration: Codable, Equatable, Sendable {
    let decibels: Float
    let bypassed: Bool
    static let unity = GainConfiguration(decibels: 0, bypassed: false)
}

enum GainProcessingError: Error, Equatable, Sendable {
    case unsupportedValue(stage: GainStage, decibels: Float)
    case backendFailure
}

protocol AudioGainControlling: AnyObject, Sendable {
    func gain(for stage: GainStage) async -> GainConfiguration
    func setGain(_ configuration: GainConfiguration, for stage: GainStage) async throws(GainProcessingError)
}

/// Native AVAudioUnitEQ globalGain contract, in decibels.
enum NativeGainLimits {
    static let range: ClosedRange<Float> = -96...24
    static func validate(_ configuration: GainConfiguration, stage: GainStage) throws(GainProcessingError) {
        guard configuration.decibels.isFinite, range.contains(configuration.decibels) else {
            throw .unsupportedValue(stage: stage, decibels: configuration.decibels)
        }
    }
}

/// Owned and accessed exclusively by the audio control actor in production.
final class NativeGainProcessor: NativeInstrumentProcessor {
    let node = AVAudioUnitEQ(numberOfBands: 0)
    var audioNode: AVAudioNode { node }
    let stage: GainStage
    init(stage: GainStage) { self.stage = stage }
    func apply(_ configuration: GainConfiguration) throws(GainProcessingError) {
        try NativeGainLimits.validate(configuration, stage: stage)
        node.globalGain = configuration.decibels
        // Do not render an EQ audio unit for an identity gain operation.
        node.bypass = configuration.bypassed || configuration.decibels == 0
    }
}
