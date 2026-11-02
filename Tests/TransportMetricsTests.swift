import XCTest
@testable import Ciranda

final class TransportMetricsTests: XCTestCase {
    func testReorderedAudioClosesProvisionalGapAndDuplicateDoesNot() {
        var metrics = TransportMetricAccumulator(transport: "test", peer: "peer")
        metrics.recordAudio(sequence: 10, bytes: 1_000)
        metrics.recordAudio(sequence: 12, bytes: 1_000)
        XCTAssertEqual(metrics.snapshot.audioMissing, 1)
        metrics.recordAudio(sequence: 12, bytes: 1_000)
        XCTAssertEqual(metrics.snapshot.audioMissing, 1)
        XCTAssertEqual(metrics.snapshot.audioDuplicates, 1)
        metrics.recordAudio(sequence: 11, bytes: 1_000)
        XCTAssertEqual(metrics.snapshot.audioMissing, 0)
        XCTAssertEqual(metrics.snapshot.audioReordered, 1)
    }
    func testNewCaptureStreamKeepsPriorLossWithoutCreatingFalseGap() {
        var metrics = TransportMetricAccumulator(transport: "test", peer: "peer")
        metrics.recordAudio(sequence: 20, bytes: 1_000)
        metrics.recordAudio(sequence: 22, bytes: 1_000)
        metrics.beginAudioStream()
        metrics.recordAudio(sequence: 0, bytes: 1_000)
        metrics.recordAudio(sequence: 1, bytes: 1_000)
        XCTAssertEqual(metrics.snapshot.audioMissing, 1)
        XCTAssertEqual(metrics.snapshot.audioReceived, 4)
    }
    func testRoundTripDistributionAndVariationUseLocalDurations() {
        var metrics = TransportMetricAccumulator(transport: "test", peer: "peer")
        [0.010, 0.020, 0.030, Double.nan, -1].forEach { metrics.recordRTT($0) }
        XCTAssertEqual(metrics.snapshot.roundTrips, 3)
        XCTAssertEqual(metrics.snapshot.rttMedianMS, 20, accuracy: 0.001)
        XCTAssertEqual(metrics.snapshot.rttP95MS, 30, accuracy: 0.001)
        XCTAssertEqual(metrics.snapshot.rttVariationMS, 10, accuracy: 0.001)
    }
}
