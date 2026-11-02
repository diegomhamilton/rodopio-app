import AVFoundation
import Foundation

/// Versioned mono PCM16 packet. Integer metadata is big endian; PCM is little endian.
struct AudioPacket {
    static let magic = Data([0x43, 0x52, 0x50, 0x41])
    let stream: UUID
    let sequence: UInt64
    let captureTime: Double
    let sampleRate: Double
    let samples: [Int16]
    var data: Data {
        var data = Self.magic; data.append(1)
        func append<T: FixedWidthInteger>(_ value: T) { var v = value.bigEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        append(UInt32(sampleRate)); append(sequence); append(captureTime.bitPattern)
        var id = stream.uuid; withUnsafeBytes(of: &id) { data.append(contentsOf: $0) }
        for sample in samples { var value = sample.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        return data
    }
    init(stream: UUID, sequence: UInt64, captureTime: Double, sampleRate: Double, samples: [Int16]) {
        self.stream = stream; self.sequence = sequence; self.captureTime = captureTime
        self.sampleRate = sampleRate; self.samples = samples
    }
    init?(data: Data) {
        guard data.count >= 43, data.count <= 1001, (data.count - 41) % 2 == 0,
              data.prefix(4) == Self.magic, data[4] == 1 else { return nil }
        let bytes = [UInt8](data)
        func read(_ start: Int, _ count: Int) -> UInt64 { bytes[start..<start+count].reduce(0) { ($0 << 8) | UInt64($1) } }
        sampleRate = Double(read(5, 4)); sequence = read(9, 8); captureTime = Double(bitPattern: read(17, 8))
        guard (8_000...192_000).contains(sampleRate), captureTime.isFinite, captureTime >= 0 else { return nil }
        let b = Array(bytes[25..<41])
        stream = UUID(uuid: (b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9],b[10],b[11],b[12],b[13],b[14],b[15]))
        samples = stride(from: 41, to: bytes.count, by: 2).map { Int16(bitPattern: UInt16(bytes[$0]) | UInt16(bytes[$0+1]) << 8) }
    }
    var peak: Double { samples.map { abs(Double($0) / 32768) }.max() ?? 0 }
}

/// Tap only copies into a bounded SPSC ring; serialization and networking run off the audio callback.
final class AudioStreamCapture {
    private let ring: OpaquePointer
    private let queue = DispatchQueue(label: "org.ciranda.pcm-send", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private let stream = UUID()
    private var sequence: UInt64 = 0
    private let rate: Double
    private let send: (Data) -> Void
    init?(rate: Double, send: @escaping (Data) -> Void) {
        guard let ring = cr_stream_create() else { return nil }
        self.ring = ring; self.rate = rate; self.send = send
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.drain() }
        self.timer = timer; timer.resume()
    }
    deinit { timer?.cancel(); cr_stream_destroy(ring) }
    func enable(_ enabled: Bool) { cr_stream_enable(ring, enabled ? 1 : 0) }
    func push(_ buffer: AVAudioPCMBuffer, channel: Int, when: AVAudioTime) {
        guard let data = buffer.floatChannelData else { return }
        let time = when.isHostTimeValid ? AVAudioTime.seconds(forHostTime: when.hostTime) : monotonicNow()
        let stride: UInt32 = buffer.format.isInterleaved ? buffer.format.channelCount : 1
        let pointer = buffer.format.isInterleaved ? data[0].advanced(by: channel) : data[channel]
        cr_stream_push(ring, pointer, buffer.frameLength, stride, time, rate)
    }
    private func drain() {
        var samples = [Int16](repeating: 0, count: 480), time = 0.0
        // Limit work per wake; stale capture is discarded instead of building latency.
        for _ in 0..<36 {
            let count = cr_stream_read(ring, &samples, 480, &time)
            guard count > 0 else { return }
            guard monotonicNow() - time < 0.06 else { continue }
            send(AudioPacket(stream: stream, sequence: sequence, captureTime: time, sampleRate: rate,
                             samples: Array(samples.prefix(Int(count)))).data)
            sequence &+= 1
        }
    }
}

struct RemoteAudioTrack: Identifiable {
    let id: String
    var name: String
    var peak = 0.0
    var received: UInt64 = 0
    var missing: UInt64 = 0
    var late: UInt64 = 0
    var jitterMS = 0.0
    var bufferedMS = 0.0
    var muted = false
    var volume: Float = 0.7
}

/// Bound pending main-thread deliveries too: a busy UI must never turn into a network audio backlog.
final class AudioPacketDelivery {
    private let lock = NSLock()
    private var pending: [Data] = []
    private var scheduled = false
    var onPacket: ((Data) -> Void)?
    func enqueue(_ data: Data) {
        lock.lock()
        pending.append(data)
        if pending.count > 12 { pending.removeFirst(pending.count - 12) }
        let schedule = !scheduled; scheduled = true
        lock.unlock()
        if schedule { DispatchQueue.main.async { [weak self] in self?.drain() } }
    }
    private func drain() {
        lock.lock(); let batch = pending; pending.removeAll(keepingCapacity: true); scheduled = false; lock.unlock()
        for data in batch {
            guard data.count >= 41 else { continue }
            let bits = data[17..<25].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            let age = monotonicNow() - Double(bitPattern: bits)
            guard age.isFinite, age >= -0.1, age < 0.06 else { continue }
            onPacket?(data)
        }
    }
}
