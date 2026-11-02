import Foundation
import CryptoKit
import AVFoundation
import Darwin

func monotonicNow() -> Double { AVAudioTime.seconds(forHostTime: mach_absolute_time()) }

struct MusicalNote: Identifiable {
    let midi: Int
    let name: String
    let sharp: Bool
    var id: Int { midi }
    static let all: [MusicalNote] = zip(60...72, ["Dó", "Dó♯", "Ré", "Ré♯", "Mi", "Fá", "Fá♯", "Sol", "Sol♯", "Lá", "Lá♯", "Si", "Dó"]).map {
        MusicalNote(midi: $0.0, name: $0.1, sharp: [61,63,66,68,70].contains($0.0))
    }
}
struct SessionConfig: Codable, Equatable {
    let id: UUID
    let start: Double
    let bpm: Double
    var beat: Double { 60 / bpm }
    var barDuration: Double { beat * 4 }
    let lead: Double
    var subdivisionsPerBeat: Int = 4
    var slotDuration: Double { beat / Double(subdivisionsPerBeat) }
    var slotsPerBar: Int { 4 * subdivisionsPerBeat }
}
struct NoteAction: Codable {
    let id: UUID
    let session: UUID
    let midi: Int
    let gesture: Double
}
struct NoteEvent: Codable, Equatable {
    let actionID: UUID
    let midi: Int
    let slot: Int
}
struct CommittedBar: Codable {
    let session: UUID
    let index: Int64
    let events: [NoteEvent]
    var digest: String {
        let canonical = events.sorted { $0.actionID.uuidString < $1.actionID.uuidString }
            .map { "\($0.actionID.uuidString):\($0.midi):\($0.slot)" }.joined(separator: "|")
        let text = "\(session.uuidString):\(index):\(canonical)"
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
struct WireMessage: Codable {
    var kind: String
    var config: SessionConfig? = nil
    var action: NoteAction? = nil
    var bar: CommittedBar? = nil
    var bars: [CommittedBar]? = nil
    var t1: Double? = nil
    var t2: Double? = nil
    var t3: Double? = nil
    var actionID: UUID? = nil
    var acceptedBar: Int64? = nil
    var sessionID: UUID? = nil
}

/// Pure authority: arrival time selects an OPEN bar; gesture time selects a musical slot.
final class BarAuthority {
    let config: SessionConfig
    private(set) var committed: [Int64: CommittedBar] = [:]
    private var pending: [Int64: [NoteEvent]] = [:]
    private var accepted: [UUID: Int64] = [:]
    private var nextBar: Int64 = 0
    init(config: SessionConfig) { self.config = config }
    func accept(_ action: NoteAction, now: Double) -> Int64? {
        guard action.session == config.id, (60...72).contains(action.midi),
              action.gesture.isFinite, abs(action.gesture - now) < 30 else { return nil }
        if let prior = accepted[action.id] { return prior }
        let bar = max(nextBar, cr_open_bar(now, config.start, config.barDuration, config.lead))
        guard accepted.count < 100_000, (pending[bar]?.count ?? 0) < 64 else { return nil }
        let slot = Int(cr_quantize_slot(action.gesture, config.start, config.beat))
        pending[bar, default: []].append(NoteEvent(actionID: action.id, midi: action.midi, slot: slot))
        accepted[action.id] = bar
        return bar
    }
    func closeDue(now: Double) -> [CommittedBar] {
        var result: [CommittedBar] = []
        while cr_bar_time(nextBar, config.start, config.barDuration) - config.lead <= now {
            let bar = CommittedBar(session: config.id, index: nextBar, events: pending.removeValue(forKey: nextBar) ?? [])
            committed[nextBar] = bar; result.append(bar); nextBar += 1
        }
        committed = committed.filter { $0.key >= nextBar - 8 }
        return result
    }
}
