import Foundation

/// One local monotonic clock only. RTT includes transport and callback scheduling.
struct TransportMetrics: Codable {
    var transport: String
    var peer: String
    var roundTrips: Int = 0
    var rttMedianMS: Double = 0
    var rttP95MS: Double = 0
    var rttVariationMS: Double = 0
    var audioReceived: UInt64 = 0
    var audioMissing: UInt64 = 0
    var audioReordered: UInt64 = 0
    var audioDuplicates: UInt64 = 0
    var audioBytes: UInt64 = 0
    var controlRetries: UInt64 = 0
}

/// Bounded history. Gaps are provisional until late/reordered packets arrive.
struct TransportMetricAccumulator {
    private var roundTrips: [Double] = []
    private var firstSequence: UInt64?
    private var highestSequence: UInt64 = 0
    private var receivedSequences = Set<UInt64>()
    private var unique: UInt64 = 0
    private var missingBaseline: UInt64 = 0
    private(set) var snapshot: TransportMetrics

    init(transport: String, peer: String) { snapshot = TransportMetrics(transport: transport, peer: peer) }
    mutating func recordRTT(_ seconds: Double) {
        guard seconds.isFinite, seconds >= 0, seconds < 10 else { return }
        roundTrips.append(seconds * 1_000)
        if roundTrips.count > 120 { roundTrips.removeFirst() }
        let sorted = roundTrips.sorted()
        snapshot.roundTrips += 1
        snapshot.rttMedianMS = sorted[(sorted.count - 1) / 2]
        snapshot.rttP95MS = sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
        snapshot.rttVariationMS = roundTrips.count > 1
            ? zip(roundTrips.dropFirst(), roundTrips).map { abs($0 - $1) }.reduce(0, +) / Double(roundTrips.count - 1) : 0
    }
    mutating func recordRetry() { snapshot.controlRetries += 1 }
    mutating func beginAudioStream() {
        missingBaseline = snapshot.audioMissing
        firstSequence = nil; highestSequence = 0; unique = 0; receivedSequences.removeAll()
    }
    mutating func recordAudio(sequence: UInt64, bytes: Int) {
        snapshot.audioBytes += UInt64(max(0, bytes))
        snapshot.audioReceived += 1
        if receivedSequences.contains(sequence) { snapshot.audioDuplicates += 1; return }
        // Packets older than the deduplication window cannot safely revise the loss estimate.
        if firstSequence != nil, sequence < highestSequence, highestSequence - sequence > 4_096 {
            snapshot.audioReordered += 1; return
        }
        receivedSequences.insert(sequence)
        if let first = firstSequence {
            if sequence < highestSequence { snapshot.audioReordered += 1 }
            if sequence < first { firstSequence = sequence }
        } else { firstSequence = sequence }
        highestSequence = max(highestSequence, sequence)
        unique += 1
        if let first = firstSequence {
            let expected = highestSequence - first + 1
            snapshot.audioMissing = missingBaseline + (expected > unique ? expected - unique : 0)
        }
        if highestSequence > 4_096 { receivedSequences = receivedSequences.filter { $0 >= highestSequence - 4_096 } }
    }
}
