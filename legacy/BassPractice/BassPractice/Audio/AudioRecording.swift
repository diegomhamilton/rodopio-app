import AVFoundation
import Foundation

struct Recording: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let fileURL: URL
    let createdAt: Date
    let frameCount: Int64
    let sampleRate: Double
    let channelCount: UInt32
    var duration: TimeInterval { Double(frameCount) / sampleRate }
}

enum AudioRecordingFailure: Error, Equatable, Sendable {
    case engineNotRunning, alreadyRecording, notRecording, unsupportedBackend
    case fileCreationFailed, writeFailed, emptyRecording, finalizationFailed
    var message: String {
        switch self {
        case .engineNotRunning: "Start audio before recording."
        case .alreadyRecording: "A recording is already in progress."
        case .notRecording: "No recording is in progress."
        case .unsupportedBackend: "Recording is unavailable."
        case .fileCreationFailed: "The recording file could not be created. Check available storage."
        case .writeFailed, .finalizationFailed: "The recording could not be saved. Try recording again."
        case .emptyRecording: "No audio was captured. Start audio and try recording again."
        }
    }
}

enum AudioRecordingState: Equatable, Sendable {
    case idle
    case recording(id: UUID, fileURL: URL, startedAt: Date)
    case failed(AudioRecordingFailure)
}

struct CapturedAudio: Equatable, Sendable {
    let frameCount: Int64
    let sampleRate: Double
    let channelCount: UInt32
}

protocol AudioRecordingControlling: AnyObject, Sendable {
    var recordingState: AudioRecordingState { get async }
    var recordings: [Recording] { get async }
    func startRecording(id: UUID, to fileURL: URL) async throws(AudioRecordingFailure)
    @discardableResult func stopRecording() async throws(AudioRecordingFailure) -> Recording
}

/// Optional capability: backends without recording fail explicitly at the actor boundary.
protocol AudioCaptureBackend: AudioEngineBackend {
    func beginRecording(to fileURL: URL) throws(AudioRecordingFailure)
    func finishRecording() throws(AudioRecordingFailure) -> CapturedAudio
}

/// Synchronizes tap callbacks with finalization. Closing rejects late callbacks and flushes the CAF.
final class AudioRecordingSink: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var frames: Int64 = 0
    private var failure: AudioRecordingFailure?
    private let sampleRate: Double
    private let channels: UInt32

    init(fileURL: URL, format: AVAudioFormat) throws(AudioRecordingFailure) {
        guard format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0,
              !FileManager.default.fileExists(atPath: fileURL.path) else { throw .fileCreationFailed }
        sampleRate = format.sampleRate
        channels = format.channelCount
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            file = try AVAudioFile(forWriting: fileURL, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch { throw .fileCreationFailed }
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard let file, failure == nil else { return }
            guard buffer.format.sampleRate == sampleRate, buffer.format.channelCount == channels,
                  buffer.format.commonFormat == .pcmFormatFloat32, !buffer.format.isInterleaved else {
                failure = .writeFailed
                return
            }
            do { try file.write(from: buffer); frames += Int64(buffer.frameLength) }
            catch { failure = .writeFailed }
        }
    }

    func finish() throws(AudioRecordingFailure) -> CapturedAudio {
        let result: Result<CapturedAudio, AudioRecordingFailure> = lock.withLock {
            guard file != nil else { return .failure(.notRecording) }
            file = nil
            if let failure { return .failure(failure) }
            guard frames > 0 else { return .failure(.emptyRecording) }
            return .success(CapturedAudio(frameCount: frames, sampleRate: sampleRate, channelCount: channels))
        }
        return try result.get()
    }
}
