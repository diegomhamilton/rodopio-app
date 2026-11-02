import Foundation

struct WorkspaceAudioConfiguration: Codable, Equatable, Sendable {
    let inputGain: GainConfiguration
    let outputGain: GainConfiguration
    let equalizer: EQConfiguration
    let instrumentMix: MixerChannelConfiguration
    let playbackMix: MixerChannelConfiguration
    let inputProfileID: UUID?
    static let initial = WorkspaceAudioConfiguration(inputGain: .unity, outputGain: .unity, equalizer: .flat, instrumentMix: MixerChannelConfiguration(volume: 1, muted: true), playbackMix: MixerChannelConfiguration(volume: 1, muted: false), inputProfileID: BuiltInInputProfiles.customID)
}

struct AudioWorkspaceSnapshot: Equatable, Sendable {
    let audio: WorkspaceAudioConfiguration
    let recordings: [Recording]
}

enum AudioWorkspaceFailure: Error, Equatable, Sendable { case engineRunning, unsupportedBackend, invalidConfiguration, backendFailure }

protocol AudioWorkspaceControlling: AnyObject, Sendable {
    func workspaceSnapshot() async -> AudioWorkspaceSnapshot
    func restoreWorkspace(_ snapshot: AudioWorkspaceSnapshot) async throws(AudioWorkspaceFailure)
}

protocol AudioWorkspaceBackend: AudioMixerBackend {
    /// Apply all settings or throw before changing native parameters.
    func applyWorkspace(_ configuration: WorkspaceAudioConfiguration, sampleRate: Double) throws
}
