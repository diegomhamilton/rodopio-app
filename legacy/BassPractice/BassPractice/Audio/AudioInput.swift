import AVFoundation

enum AudioInputKind: Equatable, Sendable {
    case builtInMicrophone
    case usb
    case bluetooth
    case unknown(rawPortType: String)

    init(portType: String) {
        switch portType {
        case AVAudioSession.Port.builtInMic.rawValue:
            self = .builtInMicrophone
        case AVAudioSession.Port.usbAudio.rawValue:
            self = .usb
        case AVAudioSession.Port.bluetoothHFP.rawValue,
             AVAudioSession.Port.bluetoothA2DP.rawValue,
             AVAudioSession.Port.bluetoothLE.rawValue:
            self = .bluetooth
        default:
            self = .unknown(rawPortType: portType)
        }
    }
}

struct AudioInput: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let portType: String
    let kind: AudioInputKind

    init(id: String, name: String, portType: String) {
        self.id = id
        self.name = name
        self.portType = portType
        kind = AudioInputKind(portType: portType)
    }
}
