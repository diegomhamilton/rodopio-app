import XCTest
@testable import Ciranda

final class AudioStreamingTests: XCTestCase {
    func testPCMTransportPreservesTimbreSamplesAndMetadata() throws {
        let original = AudioPacket(stream: UUID(), sequence: 0x0102030405060708, captureTime: 123.456,
                                   sampleRate: 96_000, samples: [-32768, -12000, 0, 12000, 32767])
        let result = try XCTUnwrap(AudioPacket(data: original.data))
        XCTAssertEqual(result.samples, original.samples)
        XCTAssertEqual(result.stream, original.stream)
        XCTAssertEqual(result.sequence, original.sequence)
        XCTAssertEqual(result.captureTime, original.captureTime)
        XCTAssertEqual(result.sampleRate, original.sampleRate)
    }
    func testMalformedPacketsAndDatagramCeiling() {
        XCTAssertNil(AudioPacket(data: Data()))
        let packet = AudioPacket(stream: UUID(), sequence: 1, captureTime: 1, sampleRate: 48_000,
                                 samples: Array(repeating: 12, count: 480))
        XCTAssertEqual(packet.data.count, 1001)
        XCTAssertNotNil(AudioPacket(data: packet.data))
        var bad = packet.data; bad[4] = 2
        XCTAssertNil(AudioPacket(data: bad))
        XCTAssertNil(AudioPacket(data: packet.data + Data([0,0])))
        XCTAssertNil(AudioPacket(data: packet.data.dropLast()))
    }
    func testStalledUIWillNotTransmitOldCapturedAudio() {
        let delivery = AudioPacketDelivery()
        var delivered = 0
        delivery.onPacket = { _ in delivered += 1 }
        let stale = AudioPacket(stream: UUID(), sequence: 1, captureTime: monotonicNow() - 1,
                                sampleRate: 48_000, samples: [100, -100]).data
        delivery.enqueue(stale)
        let drained = expectation(description: "main delivery drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertEqual(delivered, 0)
    }
    func testAudioRingIsBoundedAndKeepsSelectedChannelTimestamp() throws {
        let ring = try XCTUnwrap(cr_stream_create())
        defer { cr_stream_destroy(ring) }
        cr_stream_enable(ring, 1)
        var source: [Float] = [0.5, -0.25, -0.5, 0.75]
        cr_stream_push(ring, &source, 2, 2, 10, 48_000)
        var samples = [Int16](repeating: 0, count: 480), time = 0.0
        XCTAssertEqual(cr_stream_read(ring, &samples, 480, &time), 2)
        XCTAssertEqual(samples[0], 16384); XCTAssertEqual(samples[1], -16384)
        XCTAssertEqual(time, 10)
        var huge = [Float](repeating: 0.2, count: 20_000)
        cr_stream_push(ring, &huge, 20_000, 1, 20, 48_000)
        XCTAssertEqual(cr_stream_dropped(ring), 3616)
        var total: UInt32 = 0
        for _ in 0..<40 { total += cr_stream_read(ring, &samples, 480, &time) }
        XCTAssertEqual(total, 16384)
        cr_stream_enable(ring, 0)
        cr_stream_push(ring, &source, 2, 2, 30, 48_000)
        XCTAssertEqual(cr_stream_read(ring, &samples, 480, &time), 0)
    }
}
