import AVFoundation

protocol AudioRecordingPermission: Sendable {
    func request() async -> Bool
}

struct SystemAudioRecordingPermission: AudioRecordingPermission {
    func request() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}
