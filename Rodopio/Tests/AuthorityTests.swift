import XCTest
@testable import Ciranda

final class AuthorityTests: XCTestCase {
    private func config() -> SessionConfig { SessionConfig(id: UUID(), start: 10, bpm: 120, lead: 0.5) }
    func testDuplicateDoesNotSpendTwice() {
        let c = config(), id = UUID()
        let a = BarAuthority(config: c)
        let action = NoteAction(id: id, session: c.id, midi: 60, gesture: 9)
        XCTAssertEqual(a.accept(action, now: 9), 0)
        XCTAssertEqual(a.accept(action, now: 11), 0)
        let bars = a.closeDue(now: 9.5)
        XCTAssertEqual(bars.first?.events.count, 1)
    }
    func testDeadlineAndLateAction() {
        let c = config(), a = BarAuthority(config: config())
        // Each authority is tied to one specific session.
        XCTAssertNil(a.accept(NoteAction(id: UUID(), session: c.id, midi: 60, gesture: 9), now: 9))
        let correct = BarAuthority(config: c)
        XCTAssertEqual(correct.accept(NoteAction(id: UUID(), session: c.id, midi: 61, gesture: 9), now: 9.499), 0)
        XCTAssertEqual(correct.accept(NoteAction(id: UUID(), session: c.id, midi: 63, gesture: 9), now: 9.5), 1)
        XCTAssertEqual(correct.closeDue(now: 9.5).map(\.index), [0])
        XCTAssertTrue(correct.closeDue(now: 9.6).isEmpty)
    }
    func testClosedBarNeverChanges() {
        let c = config()
        let authority = BarAuthority(config: c)
        let first = authority.closeDue(now: 9.5)[0]
        _ = authority.accept(NoteAction(id: UUID(), session: c.id, midi: 72, gesture: 9.4), now: 10)
        XCTAssertEqual(authority.committed[0]?.digest, first.digest)
        XCTAssertTrue(first.events.isEmpty)
        XCTAssertEqual(authority.closeDue(now: 11.5).first?.events.count, 1)
    }
    func testMalformedAndOldActionsRejected() {
        let c = config()
        let authority = BarAuthority(config: c)
        XCTAssertNil(authority.accept(NoteAction(id: UUID(), session: c.id, midi: 59, gesture: 9), now: 9))
        XCTAssertNil(authority.accept(NoteAction(id: UUID(), session: c.id, midi: 60, gesture: .nan), now: 9))
        XCTAssertNil(authority.accept(NoteAction(id: UUID(), session: c.id, midi: 60, gesture: -100), now: 9))
    }
    func testCodableRoundTripAndContentHash() throws {
        let c = config()
        let bar = CommittedBar(session: c.id, index: 2, events: [NoteEvent(actionID: UUID(), midi: 66, slot: 3)])
        let decoded = try JSONDecoder().decode(CommittedBar.self, from: JSONEncoder().encode(bar))
        XCTAssertEqual(decoded.digest, bar.digest)
        XCTAssertNotEqual(CommittedBar(session: c.id, index: 3, events: bar.events).digest, bar.digest)
    }
    func testRepeatedClosuresWithReorderedRetries() {
        let c = config()
        let a = BarAuthority(config: c)
        let actions = (0..<32).map { NoteAction(id: UUID(), session: c.id, midi: 60 + $0 % 13, gesture: 8.0 + Double($0) * 0.01) }
        for action in actions { _ = a.accept(action, now: 9) }
        for action in actions.reversed() { _ = a.accept(action, now: 9.2) }
        let closed = a.closeDue(now: 9.5)
        XCTAssertEqual(closed[0].events.count, 32)
        XCTAssertEqual(Set(closed[0].events.map(\.actionID)).count, 32)
    }
}
