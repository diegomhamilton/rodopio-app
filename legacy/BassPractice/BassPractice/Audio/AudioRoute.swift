import Foundation
import AVFoundation

struct AudioDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let portType: String
}

struct AudioRoute: Equatable, Sendable {
    let inputs: [AudioDevice]
    let outputs: [AudioDevice]

    static let empty = AudioRoute(inputs: [], outputs: [])

    var needsMonitoringConfirmation: Bool {
        let builtInInput = inputs.isEmpty || inputs.contains { $0.portType == AVAudioSession.Port.builtInMic.rawValue }
        let builtInOutput = outputs.isEmpty || outputs.contains {
            $0.portType == AVAudioSession.Port.builtInSpeaker.rawValue || $0.portType == AVAudioSession.Port.builtInReceiver.rawValue
        }
        return builtInInput && builtInOutput
    }

    var outputDescription: String {
        guard !outputs.isEmpty else { return "Output not yet confirmed" }
        return outputs.map { device in
            switch device.portType {
            case AVAudioSession.Port.builtInSpeaker.rawValue: "iPhone Speaker"
            case AVAudioSession.Port.builtInReceiver.rawValue: "iPhone Receiver"
            default: device.name
            }
        }.joined(separator: ", ")
    }
}

enum AudioRouteChangeReason: Equatable, Sendable {
    case unknown
    case newDeviceAvailable
    case oldDeviceUnavailable
    case categoryChange
    case override
    case wakeFromSleep
    case noSuitableRouteForCategory
    case routeConfigurationChange
    case unrecognized(UInt)
}

enum AudioSessionEvent: Equatable, Sendable {
    case mediaChanged
    case mixerChanged
    case toneChanged
    case workspaceChanged
    case routeChanged(route: AudioRoute, reason: AudioRouteChangeReason)
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case enteredBackground
    case enteredForeground
}
