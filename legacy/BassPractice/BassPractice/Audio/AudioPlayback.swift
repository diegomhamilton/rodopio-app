import AVFoundation
import Foundation

enum AudioPlaybackFailure: Error, Equatable, Sendable {
    case engineUnavailable, unsupportedBackend, unreadableFile, invalidFormat, loopTooLarge, startFailed
    var message: String {
        switch self {
        case .engineUnavailable: "Start audio to play this recording."
        case .unsupportedBackend: "Playback is unavailable."
        case .unreadableFile: "The recording file could not be opened."
        case .invalidFormat: "This recording has no readable audio."
        case .loopTooLarge: "This recording is too long to loop. Record a shorter phrase."
        case .startFailed: "Audio playback could not start. Try again."
        }
    }
}

enum AudioPlaybackState: Equatable, Sendable {
    case stopped
    case playing(UUID)
    case failed(AudioPlaybackFailure)
}

protocol AudioPlaybackControlling: AnyObject, Sendable {
    var playbackState: AudioPlaybackState { get async }
    // Playback repeats until stopped or replaced.
    func play(_ recording: Recording) async throws(AudioPlaybackFailure)
    func stopPlayback() async
}

protocol AudioPlaybackBackend: AudioEngineBackend {
    func play(fileURL: URL, completion: @escaping @Sendable () async -> Void) throws(AudioPlaybackFailure)
    func stopPlayback()
}

/// Loads the full decoded phrase, including short reads and the final partial block.
/// Regression: a device CAF advertised 163286 frames but one read returned 162816,
/// even with an explicit frame count. Aligned synthetic fixtures hid this failure.
/// Keep incremental reads and the nonaligned mono/stereo tests; see the audio plan.
/// docs/plan/reference/audio-regression-prevention.md
enum AudioLoopBuffer {
    static func load(_ file: AVAudioFile) throws(AudioPlaybackFailure) -> AVAudioPCMBuffer {
        let format = file.processingFormat
        guard file.length > 0, format.sampleRate > 0, format.channelCount > 0,
              format.commonFormat == .pcmFormatFloat32, !format.isInterleaved else { throw .invalidFormat }
        let bytesPerFrame = Int64(format.channelCount) * 4
        guard file.length <= Int64(UInt32.max), file.length <= (64 * 1024 * 1024) / bytesPerFrame else { throw .loopTooLarge }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
              let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024),
              let destination = buffer.floatChannelData, let source = chunk.floatChannelData else { throw .startFailed }
        var offset = 0
        do {
            file.framePosition = 0
            while offset < Int(buffer.frameCapacity) {
                try file.read(into: chunk, frameCount: min(1024, buffer.frameCapacity - AVAudioFrameCount(offset)))
                guard chunk.frameLength > 0 else { throw AudioPlaybackFailure.invalidFormat }
                let count = Int(chunk.frameLength)
                for channel in 0..<Int(format.channelCount) {
                    destination[channel].advanced(by: offset).update(from: source[channel], count: count)
                }
                offset += count
            }
        } catch let failure as AudioPlaybackFailure { throw failure }
        catch { throw .unreadableFile }
        buffer.frameLength = AVAudioFrameCount(offset)
        return buffer
    }
}
