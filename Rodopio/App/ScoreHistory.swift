import Foundation

struct ScoreBar: Identifiable, Equatable {
    let id: UUID
    let take: UUID
    let index: Int
    var events: [NoteEvent]
}

/// Local detected/played gestures. Independent of committed playback and network ACKs.
struct ScoreHistory {
    private(set) var bars: [ScoreBar] = []
    private let limit = 32
    mutating func append(midi: Int, time: Double, origin: Double, bpm: Double, take: UUID) {
        guard (60...72).contains(midi), time.isFinite, origin.isFinite,
              bpm.isFinite, (40...200).contains(bpm), time >= origin else { return }
        let position = (time - origin) / (60 / bpm / 4)
        guard position < Double(Int.max / 2) else { return }
        let absoluteSlot = Int(floor(position))
        let index = absoluteSlot / 16, slot = absoluteSlot % 16
        if let row = bars.firstIndex(where: { $0.take == take && $0.index == index }) {
            guard !bars[row].events.contains(where: { $0.midi == midi && $0.slot == slot }) else { return }
            bars[row].events.append(NoteEvent(actionID: UUID(), midi: midi, slot: slot))
            bars[row].events.sort { $0.slot < $1.slot }
        } else {
            bars.append(ScoreBar(id: UUID(), take: take, index: index,
                                 events: [NoteEvent(actionID: UUID(), midi: midi, slot: slot)]))
            if bars.count > limit { bars.removeFirst(bars.count - limit) }
        }
    }
    mutating func clear() { bars.removeAll() }
}
