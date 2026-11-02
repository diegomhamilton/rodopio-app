import AVFoundation
import Foundation

enum MixerChannel: String, Codable, CaseIterable, Sendable { case instrument, playback }

struct MixerChannelConfiguration: Codable, Equatable, Sendable {
    let volume: Float
    let muted: Bool
}

struct AudioLevel: Equatable, Sendable {
    let rms: Float
    let peak: Float
    var clipping: Bool { peak >= 1 }
    static let silent = AudioLevel(rms: 0, peak: 0)
}

enum AudioMixerFailure: Error, Equatable, Sendable { case invalidVolume, unsupportedBackend, writeFailed }

protocol AudioMixerControlling: AnyObject, Sendable {
    func mixerConfiguration(for channel: MixerChannel) async -> MixerChannelConfiguration
    func setMixerConfiguration(_ configuration: MixerChannelConfiguration, for channel: MixerChannel) async throws(AudioMixerFailure)
    func level(for channel: MixerChannel) async -> AudioLevel?
}

protocol AudioMixerBackend: AudioEngineBackend {
    func setPlaybackVolume(_ volume: Float) throws
    func level(for channel: MixerChannel) -> AudioLevel
}

/// One tap serves metering and optional recording, avoiding multiple taps on a bus.
final class AudioTapState: @unchecked Sendable {
    private let lock = NSLock()
    private var sink: AudioRecordingSink?
    private var storedLevel: AudioLevel = .silent
    private var generation = UUID()
    var level: AudioLevel { lock.withLock { storedLevel } }
    func setSink(_ sink: AudioRecordingSink?) { lock.withLock { self.sink = sink } }
    func beginObservation() -> UUID {
        lock.withLock { generation = UUID(); storedLevel = .silent; return generation }
    }
    func reset() { lock.withLock { generation = UUID(); storedLevel = .silent; sink = nil } }

    func consume(_ buffer: AVAudioPCMBuffer, generation expectedGeneration: UUID) {
        guard lock.withLock({ generation == expectedGeneration }) else { return }
        var peak: Float = 0
        var squares: Double = 0
        let count = Int(buffer.frameLength) * Int(buffer.format.channelCount)
        if let data = buffer.floatChannelData, count > 0, !buffer.format.isInterleaved {
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) {
                    let value = data[channel][frame]
                    if value.isFinite { peak = max(peak, abs(value)); squares += Double(value) * Double(value) }
                }
            }
        }
        let level = AudioLevel(rms: count > 0 ? Float(sqrt(squares / Double(count))) : 0, peak: peak)
        let activeSink = lock.withLock {
            guard generation == expectedGeneration else { return nil as AudioRecordingSink? }
            storedLevel = level
            return sink
        }
        activeSink?.consume(buffer)
    }
}
