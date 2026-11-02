import AVFoundation
import Foundation

struct AudioInputOption: Identifiable, Equatable {
    let id: String
    let name: String
    let usb: Bool
    var bluetooth = false
}
struct LiveInputState {
    var captureID: UUID? = nil
    var available: [AudioInputOption] = []
    var selectedUID = ""
    var requestedUID = ""
    var isConfiguring = false
    var inputName = "Nenhuma entrada ativa"
    var outputName = ""
    var channels = 0
    var analysisChannel = 0
    var monitoring = false
    var canMonitor = false
    var sampleRate = 0.0
    var inputLatency = 0.0
    var error: String? = nil
}
struct LiveInputReading {
    let captureID: UUID
    let rmsDB: Double
    let peakDB: Double
    let frequency: Double
    let midi: Int?
    let captureTime: Double
    let windowSeconds: Double
    let confidence: Double
    let clipped: Bool
    let dropped: UInt32
}

/// Owns a bounded SPSC mailbox. Audio tap writes only; analysis queue consumes.
/// No audio buffers escape the tap. A captured analyzer stays alive through teardown.
final class LiveInputAnalyzer {
    let id = UUID()
    private let mailbox: OpaquePointer
    private let analysisQueue = DispatchQueue(label: "org.ciranda.input-analysis", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    var onReading: ((LiveInputReading) -> Void)?
    init?(sampleRate: Double) {
        guard let pointer = cr_input_create(sampleRate) else { return nil }
        mailbox = pointer
    }
    deinit { timer?.cancel(); cr_input_destroy(mailbox) }
    func push(_ buffer: AVAudioPCMBuffer, channel: Int, when: AVAudioTime) {
        guard let data = buffer.floatChannelData, channel >= 0,
              channel < Int(buffer.format.channelCount) else { return }
        let time = when.isHostTimeValid ? AVAudioTime.seconds(forHostTime: when.hostTime) : monotonicNow() - Double(buffer.frameLength) / buffer.format.sampleRate
        if buffer.format.isInterleaved {
            cr_input_push_timed(mailbox, data[0].advanced(by: channel), buffer.frameLength, buffer.format.channelCount, time)
        } else { cr_input_push_timed(mailbox, data[channel], buffer.frameLength, 1, time) }
    }
    func start() {
        let timer = DispatchSource.makeTimerSource(queue: analysisQueue)
        timer.schedule(deadline: .now() + .milliseconds(10), repeating: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let reading = cr_input_read(self.mailbox)
            guard reading.frames > 0 else { return }
            let midi = Int(cr_frequency_midi(reading.frequency))
            let value = LiveInputReading(captureID: self.id, rmsDB: reading.rms_db,
                                        peakDB: reading.peak_db, frequency: reading.frequency,
                                        midi: midi >= 0 ? midi : nil, captureTime: reading.capture_time,
                                        windowSeconds: reading.window_seconds, confidence: reading.confidence,
                                        clipped: reading.clipped != 0, dropped: reading.dropped)
            DispatchQueue.main.async { self.onReading?(value) }
        }
        self.timer = timer; timer.resume()
    }
    func stop() { timer?.cancel(); timer = nil }
}

/// One stable monophonic note per change; silence rearms repeated notes.
/// This is a game input filter, not an attack-time estimator or polyphonic tracker.
struct BassNoteGate {
    private var candidate: Int?
    private var consecutive = 0
    private var lastEmitted: Int?
    private var silenceFrames = 0
    mutating func accept(midi: Int?, confidence: Double, rmsDB: Double) -> Int? {
        guard let midi, confidence >= 0.85, rmsDB > -50 else {
            candidate = nil; consecutive = 0
            if rmsDB <= -50 {
                silenceFrames += 1
                if silenceFrames >= 3 { lastEmitted = nil }
            }
            return nil
        }
        silenceFrames = 0
        if candidate == midi { consecutive += 1 } else { candidate = midi; consecutive = 1 }
        guard consecutive >= 2, lastEmitted != midi else { return nil }
        lastEmitted = midi
        return Int(cr_keyboard_midi(Int32(midi)))
    }
}
