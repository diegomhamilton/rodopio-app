import XCTest
@testable import Ciranda

final class ScoreHistoryTests: XCTestCase {
    func testProgressionKeepsEarlierBarsAndDeduplicates() {
        var history = ScoreHistory(); let take = UUID()
        history.append(midi: 64, time: 10, origin: 10, bpm: 120, take: take)
        history.append(midi: 64, time: 10.01, origin: 10, bpm: 120, take: take)
        history.append(midi: 69, time: 10.125, origin: 10, bpm: 120, take: take)
        history.append(midi: 67, time: 12, origin: 10, bpm: 120, take: take)
        XCTAssertEqual(history.bars.count, 2)
        XCTAssertEqual(history.bars[0].events.map(\.slot), [0, 1])
        XCTAssertEqual(history.bars[1].events.first?.slot, 0)
    }
    func testNewTakeDoesNotEraseOldAndHistoryIsBounded() {
        var history = ScoreHistory()
        for _ in 0..<40 { history.append(midi: 60, time: 10, origin: 10, bpm: 120, take: UUID()) }
        XCTAssertEqual(history.bars.count, 32)
        history.clear(); XCTAssertTrue(history.bars.isEmpty)
    }
    func testNoPhantomNoteForInvalidInputOrCountIn() {
        var history = ScoreHistory(); let take = UUID()
        for time in [Double.nan, 9] { history.append(midi: 60, time: time, origin: 10, bpm: 120, take: take) }
        history.append(midi: -1, time: 10, origin: 10, bpm: 120, take: take)
        XCTAssertTrue(history.bars.isEmpty)
    }
}
