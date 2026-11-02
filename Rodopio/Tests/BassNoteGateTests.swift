import XCTest
@testable import Ciranda

final class BassNoteGateTests: XCTestCase {
    func testStableBassNoteMapsToKeyboardOnce() {
        var gate = BassNoteGate()
        XCTAssertNil(gate.accept(midi: 28, confidence: 0.98, rmsDB: -20))
        XCTAssertEqual(gate.accept(midi: 28, confidence: 0.98, rmsDB: -20), 64)
        for _ in 0..<20 { XCTAssertNil(gate.accept(midi: 28, confidence: 0.98, rmsDB: -20)) }
    }
    func testSilenceRearmsRepeatedNote() {
        var gate = BassNoteGate()
        _ = gate.accept(midi: 33, confidence: 0.98, rmsDB: -20)
        XCTAssertEqual(gate.accept(midi: 33, confidence: 0.98, rmsDB: -20), 69)
        for _ in 0..<3 { XCTAssertNil(gate.accept(midi: nil, confidence: 0, rmsDB: -90)) }
        XCTAssertNil(gate.accept(midi: 33, confidence: 0.98, rmsDB: -20))
        XCTAssertEqual(gate.accept(midi: 33, confidence: 0.98, rmsDB: -20), 69)
    }
    func testWeakOrUnstablePitchDoesNotCollect() {
        var gate = BassNoteGate()
        for _ in 0..<5 { XCTAssertNil(gate.accept(midi: 40, confidence: 0.7, rmsDB: -20)) }
        for _ in 0..<5 { XCTAssertNil(gate.accept(midi: 40, confidence: 0.98, rmsDB: -60)) }
        for note in [28,29,28,30,28] { XCTAssertNil(gate.accept(midi: note, confidence: 0.98, rmsDB: -20)) }
    }
    func testChangingNoteCreatesNewContribution() {
        var gate = BassNoteGate()
        _ = gate.accept(midi: 28, confidence: 0.98, rmsDB: -20)
        _ = gate.accept(midi: 28, confidence: 0.98, rmsDB: -20)
        XCTAssertNil(gate.accept(midi: 30, confidence: 0.98, rmsDB: -20))
        XCTAssertEqual(gate.accept(midi: 30, confidence: 0.98, rmsDB: -20), 66)
    }
}
