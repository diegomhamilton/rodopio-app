import AVFoundation
import Testing
@testable import BassPractice

@Suite("Native session output policy", .serialized)
struct AudioSessionOutputPolicyTests {
    @Test("System buffer policy leaves the native preference unchanged")
    func systemNegotiatedBuffer() throws {
        let session = AVAudioSession.sharedInstance()
        let previous = session.preferredIOBufferDuration
        let backend = SystemAudioSessionBackend(session: session)

        try backend.setPreferredIOBufferDuration(0)

        #expect(session.preferredIOBufferDuration == previous)
    }

    @Test("Practice uses normal duplex mode and defaults to speaker")
    func builtInPlaybackDefaultsToSpeaker() throws {
        let session = AVAudioSession.sharedInstance()
        let category = session.category
        let mode = session.mode
        let options = session.categoryOptions
        defer { try? session.setCategory(category, mode: mode, options: options) }
        let backend = SystemAudioSessionBackend(session: session)

        try backend.configureForMeasurement()

        #expect(session.category == .playAndRecord)
        #expect(session.mode == .default)
        #expect(session.categoryOptions.contains(.defaultToSpeaker))
    }
}
