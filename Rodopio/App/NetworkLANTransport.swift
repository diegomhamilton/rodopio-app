import Foundation
import Network
import MultipeerConnectivity
import UIKit

/// Local-network prototype. UDP audio is never retransmitted. Control messages have bounded ACK/retry.
/// MCPeerID is retained as an application identity for compatibility; no MCSession is used here.
/// UDP is unencrypted: use only a trusted LAN for this experimental backend.
final class NetworkLANTransport {
    private static let service = "_ciranda-sixteen._udp"
    private let queue = DispatchQueue(label: "org.ciranda.network", qos: .userInteractive)
    private let localID = UUID()
    private let localName = UIDevice.current.name
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var links: [UUID: Link] = [:]
    private var timer: DispatchSourceTimer?
    private var generation = UUID()
    private let generationLock = NSLock()
    private var hosting = false
    private var joining = false
    private(set) var peers: [MCPeerID] = [] // main queue only
    private(set) var hostPeer: MCPeerID?
    var onMessage: ((WireMessage, MCPeerID) -> Void)?
    var onAudio: ((Data, MCPeerID) -> Void)?
    var onPeers: (([MCPeerID]) -> Void)?
    var onError: ((String) -> Void)?
    var onMetrics: (([TransportMetrics]) -> Void)?

    private struct Hello: Codable { let id: UUID; let name: String }
    private struct Pending { let data: Data; var sent: Double; var attempts: Int }
    private final class Link {
        let id = UUID()
        let connection: NWConnection
        var peer: MCPeerID?
        var remoteID: UUID?
        var lastReceive = ProcessInfo.processInfo.systemUptime
        var nextControl: UInt64 = 0
        var nextAudio: UInt64 = 0
        var audioInFlight = 0
        var pending: [UInt64: Pending] = [:]
        var nextReceivedControl: UInt64 = 0
        var receivedControls: [UInt64: WireMessage] = [:]
        var ping: (UInt64, Double)?
        var pingSequence: UInt64 = 0
        var metrics = TransportMetricAccumulator(transport: "Network UDP", peer: "conectando")
        init(_ connection: NWConnection) { self.connection = connection }
    }
    private func parameters() -> NWParameters {
        let p = NWParameters.udp
        p.includePeerToPeer = false // compare the same infrastructure Wi-Fi, without AWDL path changes
        return p
    }
    func host() { start(host: true) }
    func join() { start(host: false) }
    private func start(host: Bool) {
        stop()
        queue.async {
            self.hosting = host; self.joining = !host
            do {
                if host {
                    let listener = try NWListener(using: self.parameters())
                    listener.service = NWListener.Service(name: "Ciranda-" + self.localID.uuidString.prefix(8), type: Self.service)
                    listener.newConnectionHandler = { [weak self, weak listener] connection in
                        guard let self, let listener, self.listener === listener, self.hosting else { connection.cancel(); return }
                        guard self.links.count < 3 else { connection.cancel(); return }
                        self.attach(connection)
                    }
                    listener.stateUpdateHandler = { [weak self] state in if case .failed(let error) = state { self?.issue(error.localizedDescription) } }
                    self.listener = listener; listener.start(queue: self.queue)
                } else {
                    let browser = NWBrowser(for: .bonjour(type: Self.service, domain: nil), using: self.parameters())
                    browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
                        guard let self, let browser, self.browser === browser, self.joining, self.links.isEmpty, let result = results.sorted(by: { String(describing: $0.endpoint) < String(describing: $1.endpoint) }).first else { return }
                        self.attach(NWConnection(to: result.endpoint, using: self.parameters()))
                    }
                    browser.stateUpdateHandler = { [weak self] state in if case .failed(let error) = state { self?.issue(error.localizedDescription) } }
                    self.browser = browser; browser.start(queue: self.queue)
                }
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now(), repeating: .milliseconds(100))
                timer.setEventHandler { [weak self] in self?.tick() }
                self.timer = timer; timer.resume()
            } catch { self.issue(error.localizedDescription) }
        }
    }
    func stop() {
        queue.async {
            self.generationLock.lock(); self.generation = UUID(); self.generationLock.unlock()
            self.hosting = false; self.joining = false
            self.timer?.cancel(); self.timer = nil
            self.browser?.cancel(); self.browser = nil; self.listener?.cancel(); self.listener = nil
            self.links.values.forEach { $0.connection.cancel() }; self.links.removeAll()
            self.publishPeers()
        }
    }
    private func attach(_ connection: NWConnection) {
        let link = Link(connection); links[link.id] = link
        connection.stateUpdateHandler = { [weak self, weak link] state in
            guard let self, let link, self.links[link.id] != nil else { return }
            switch state {
            case .ready: self.hello(link); self.receive(link)
            case .failed(let error): self.issue(error.localizedDescription); self.remove(link)
            case .cancelled: self.remove(link)
            default: break
            }
        }
        connection.start(queue: queue)
    }
    private func remove(_ link: Link) {
        guard links.removeValue(forKey: link.id) != nil else { return }
        link.connection.cancel(); publishPeers()
    }
    private func hello(_ link: Link) {
        if let data = try? JSONEncoder().encode(Hello(id: localID, name: localName)) { transmit(Data([0]) + data, link) }
    }
    private func receive(_ link: Link) {
        link.connection.receiveMessage { [weak self, weak link] data, _, _, error in
            guard let self, let link, self.links[link.id] != nil else { return }
            if let data, !data.isEmpty, data.count <= 65_000 { self.handle(data, link) }
            if let error { self.issue(error.localizedDescription); self.remove(link) }
            else { self.receive(link) }
        }
    }
    private func handle(_ data: Data, _ link: Link) {
        let now = ProcessInfo.processInfo.systemUptime
        link.lastReceive = now
        let kind = data[data.startIndex]
        if kind == 0 {
            guard data.count < 1_024, let hello = try? JSONDecoder().decode(Hello.self, from: data.dropFirst()), hello.id != localID else { return }
            if link.peer == nil {
                // Include an id suffix because iOS device names are often identical.
                let name = String(hello.name.prefix(40)) + " · " + hello.id.uuidString.prefix(4)
                link.peer = MCPeerID(displayName: name); link.remoteID = hello.id
                link.metrics = TransportMetricAccumulator(transport: "Network UDP", peer: name)
                self.hello(link); publishPeers()
            }
            return
        }
        guard let peer = link.peer, data.count >= 9, let sequence = Self.number(data, at: 1) else { return }
        let payload = Data(data.dropFirst(9))
        switch kind {
        case 1:
            if sequence < link.nextReceivedControl {
                transmit(Self.packet(kind: 2, sequence: sequence), link); return
            }
            guard sequence - link.nextReceivedControl < 128,
                  let message = try? JSONDecoder().decode(WireMessage.self, from: payload) else { return }
            transmit(Self.packet(kind: 2, sequence: sequence), link)
            link.receivedControls[sequence] = message
            while let next = link.receivedControls.removeValue(forKey: link.nextReceivedControl) {
                link.nextReceivedControl &+= 1
                emit { self.onMessage?(next, peer) }
            }
        case 2: link.pending.removeValue(forKey: sequence)
        case 3:
            guard payload.count <= 1_200, payload.starts(with: Data("CRPA".utf8)) else { return }
            link.metrics.recordAudio(sequence: sequence, bytes: payload.count)
            emit { self.onAudio?(payload, peer) }
        case 4: transmit(Self.packet(kind: 5, sequence: sequence), link)
        case 5:
            if let ping = link.ping, ping.0 == sequence { link.metrics.recordRTT(now - ping.1); link.ping = nil }
        default: break
        }
    }
    func send(_ message: WireMessage, to peer: MCPeerID? = nil) {
        guard let data = try? JSONEncoder().encode(message), data.count <= 60_000 else { return }
        queue.async {
            for link in self.links.values where link.peer != nil && (peer == nil || link.peer == peer) {
                guard link.pending.count < 128 else { self.issue("Fila de controles Network cheia."); continue }
                let sequence = link.nextControl; link.nextControl &+= 1
                let packet = Self.packet(kind: 1, sequence: sequence, payload: data)
                link.pending[sequence] = Pending(data: packet, sent: ProcessInfo.processInfo.systemUptime, attempts: 1)
                self.transmit(packet, link)
            }
        }
    }
    func sendAudio(_ data: Data) {
        guard data.count <= 1_200 else { return }
        queue.async {
            for link in self.links.values where link.peer != nil {
                let sequence = link.nextAudio; link.nextAudio &+= 1
                guard link.audioInFlight < 4 else { continue }
                link.audioInFlight += 1
                link.connection.send(content: Self.packet(kind: 3, sequence: sequence, payload: data), completion: .contentProcessed { [weak self, weak link] error in
                    guard let self, let link else { return }
                    link.audioInFlight = max(0, link.audioInFlight - 1)
                    if let error { self.issue(error.localizedDescription) }
                })
            }
        }
    }
    private var ticks = 0
    private func tick() {
        ticks += 1
        let now = ProcessInfo.processInfo.systemUptime
        for link in Array(links.values) {
            if now - link.lastReceive > 8 { remove(link); continue }
            if link.peer == nil { if ticks % 10 == 0 { hello(link) }; continue }
            for (sequence, var pending) in link.pending where now - pending.sent > 0.15 {
                if pending.attempts >= 20 {
                    issue("Controle Network sem confirmação; reconecte os aparelhos."); remove(link); break
                }
                pending.sent = now; pending.attempts += 1; link.pending[sequence] = pending
                link.metrics.recordRetry(); transmit(pending.data, link)
            }
            if ticks % 5 == 0, link.ping == nil || now - (link.ping?.1 ?? now) >= 2 {
                let sequence = link.pingSequence; link.pingSequence &+= 1
                link.ping = (sequence, now); transmit(Self.packet(kind: 4, sequence: sequence), link)
            }
        }
        if ticks % 10 == 0 {
            let metrics = links.values.map { $0.metrics.snapshot }
            emit { self.onMetrics?(metrics) }
        }
    }
    private func transmit(_ data: Data, _ link: Link) {
        link.connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error { self?.issue(error.localizedDescription) }
        })
    }
    private func publishPeers() {
        let peers = links.values.compactMap(\.peer)
        let host = hosting ? nil : peers.first
        emit { self.peers = peers; self.hostPeer = host; self.onPeers?(peers) }
    }
    private func issue(_ text: String) { emit { self.onError?(text) } }
    /// Generation token suppresses callbacks queued by a stopped session.
    private func emit(_ callback: @escaping () -> Void) {
        generationLock.lock(); let token = generation; generationLock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.generationLock.lock(); let valid = token == self.generation; self.generationLock.unlock()
            if valid { callback() }
        }
    }
    private static func packet(kind: UInt8, sequence: UInt64, payload: Data = Data()) -> Data {
        var value = sequence.bigEndian
        return Data([kind]) + withUnsafeBytes(of: &value) { Data($0) } + payload
    }
    private static func number(_ data: Data, at index: Int) -> UInt64? {
        guard index >= 0, data.count >= index + 8 else { return nil }
        return data[index..<(index + 8)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}
