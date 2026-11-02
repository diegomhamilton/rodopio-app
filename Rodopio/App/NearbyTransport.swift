import Foundation
import MultipeerConnectivity
import UIKit

/// iOS proximity transport. All callbacks delivered on main queue.
private final class MultipeerTransport: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    private let service = "ciranda-sixteen"
    private let peer = MCPeerID(displayName: UIDevice.current.name)
    private lazy var session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var invited = Set<MCPeerID>()
    private(set) var hostPeer: MCPeerID?
    private var hosting = false
    var onAudio: ((Data, MCPeerID) -> Void)?
    var onMessage: ((WireMessage, MCPeerID) -> Void)?
    var onPeers: (([MCPeerID]) -> Void)?
    var onError: ((String) -> Void)?
    var onMetrics: (([TransportMetrics]) -> Void)?
    private var metricTimer: Timer?
    private var metrics: [MCPeerID: TransportMetricAccumulator] = [:]
    private var metricStreams: [MCPeerID: Data] = [:]
    private var pendingPings: [MCPeerID: (UInt64, Double)] = [:]
    private var pingSequence: UInt64 = 0
    private let probeMagic = Data("CRPB".utf8)
    var peers: [MCPeerID] { session.connectedPeers }

    func host() {
        stop(); startMetrics(); hosting = true; session.delegate = self
        advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: nil, serviceType: service)
        advertiser?.delegate = self; advertiser?.startAdvertisingPeer()
    }
    func join() {
        stop(); startMetrics(); hosting = false; session.delegate = self
        browser = MCNearbyServiceBrowser(peer: peer, serviceType: service)
        browser?.delegate = self; browser?.startBrowsingForPeers()
    }
    func stop() {
        metricTimer?.invalidate(); metricTimer = nil; metrics.removeAll(); metricStreams.removeAll(); pendingPings.removeAll()
        advertiser?.stopAdvertisingPeer(); browser?.stopBrowsingForPeers()
        advertiser = nil; browser = nil; session.disconnect()
        invited.removeAll(); hostPeer = nil
    }
    func send(_ message: WireMessage, to peer: MCPeerID? = nil) {
        let targets = peer.map { [$0] } ?? session.connectedPeers
        guard !targets.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: targets, with: .reliable)
        } catch { onError?(error.localizedDescription) }
    }
    /// PCM is expendable: never retransmit an old sound behind newer input.
    func sendAudio(_ data: Data) {
        guard !session.connectedPeers.isEmpty, data.count <= 1001 else { return }
        do { try session.send(data, toPeers: session.connectedPeers, with: .unreliable) }
        catch { DispatchQueue.main.async { self.onError?(error.localizedDescription) } }
    }
    private func startMetrics() {
        metricTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            for peer in self.session.connectedPeers {
                if let pending = self.pendingPings[peer], now - pending.1 < 2 { continue }
                let sequence = self.pingSequence; self.pingSequence &+= 1
                self.pendingPings[peer] = (sequence, now)
                self.probe(kind: 0, sequence: sequence, to: peer)
            }
            self.onMetrics?(self.metrics.values.map(\.snapshot))
        }
    }
    private func probe(kind: UInt8, sequence: UInt64, to peer: MCPeerID) {
        var sequence = sequence.bigEndian
        let packet = probeMagic + Data([kind]) + withUnsafeBytes(of: &sequence) { Data($0) }
        try? session.send(packet, toPeers: [peer], with: .unreliable)
    }
    private func receiveProbe(_ data: Data, _ peer: MCPeerID) {
        guard data.count == 13 else { return }
        let sequence = data[5..<13].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        if data[4] == 0 { probe(kind: 1, sequence: sequence, to: peer) }
        else if data[4] == 1, let pending = pendingPings[peer], pending.0 == sequence {
            var metric = metrics[peer] ?? TransportMetricAccumulator(transport: "Multipeer", peer: peer.displayName)
            metric.recordRTT(ProcessInfo.processInfo.systemUptime - pending.1)
            metrics[peer] = metric; pendingPings.removeValue(forKey: peer)
        }
    }
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        // Join exactly one room; first advertised host. UI makes this prototype behavior explicit.
        guard hostPeer == nil, invited.isEmpty else { return }
        invited.insert(peerID); hostPeer = peerID
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) { }
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async { self.onError?(error.localizedDescription) }
    }
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(hosting && session.connectedPeers.count < 3, session)
    }
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { self.onError?(error.localizedDescription) }
    }
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            if state == .notConnected && peerID == self.hostPeer {
                self.hostPeer = nil; self.invited.remove(peerID)
            }
            if state == .notConnected {
                self.metrics.removeValue(forKey: peerID); self.metricStreams.removeValue(forKey: peerID)
                self.pendingPings.removeValue(forKey: peerID)
            }
            self.onPeers?(session.connectedPeers)
        }
    }
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if data.prefix(4) == probeMagic {
            DispatchQueue.main.async { self.receiveProbe(data, peerID) }; return
        }
        if data.prefix(4) == AudioPacket.magic {
            guard data.count <= 1001 else { return }
            DispatchQueue.main.async {
                if data.count >= 41 {
                    let stream = Data(data[25..<41])
                    var metric = self.metrics[peerID] ?? TransportMetricAccumulator(transport: "Multipeer", peer: peerID.displayName)
                    if self.metricStreams[peerID] != stream { metric.beginAudioStream(); self.metricStreams[peerID] = stream }
                    let sequence = data[9..<17].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                    metric.recordAudio(sequence: sequence, bytes: data.count); self.metrics[peerID] = metric
                }
                self.onAudio?(data, peerID)
            }
            return
        }
        guard data.count < 262_144, let message = try? JSONDecoder().decode(WireMessage.self, from: data) else { return }
        DispatchQueue.main.async { self.onMessage?(message, peerID) }
    }
    func session(_ session: MCSession, didReceive stream: InputStream, withName name: String, fromPeer peerID: MCPeerID) { }
    func session(_ session: MCSession, didStartReceivingResourceWithName name: String, fromPeer peerID: MCPeerID, with progress: Progress) { }
    func session(_ session: MCSession, didFinishReceivingResourceWithName name: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) { }
}


enum TransportBackend: String, CaseIterable, Identifiable {
    case multipeer = "Multipeer"
    case network = "Network UDP"
    var id: String { rawValue }
}

/// One facade keeps capture, packetization and playback identical for A/B tests.
final class NearbyTransport {
    private let multipeer = MultipeerTransport()
    private let network = NetworkLANTransport()
    private(set) var backend: TransportBackend = .multipeer
    var onAudio: ((Data, MCPeerID) -> Void)?
    var onMessage: ((WireMessage, MCPeerID) -> Void)?
    var onPeers: (([MCPeerID]) -> Void)?
    var onError: ((String) -> Void)?
    var onMetrics: (([TransportMetrics]) -> Void)?
    var peers: [MCPeerID] { backend == .network ? network.peers : multipeer.peers }
    var hostPeer: MCPeerID? { backend == .network ? network.hostPeer : multipeer.hostPeer }
    init() {
        multipeer.onAudio = { [weak self] value, peer in
            guard let self, self.backend == .multipeer else { return }
            self.onAudio?(value, peer)
        }
        multipeer.onMessage = { [weak self] value, peer in
            guard let self, self.backend == .multipeer else { return }
            self.onMessage?(value, peer)
        }
        multipeer.onPeers = { [weak self] value in
            guard let self, self.backend == .multipeer else { return }
            self.onPeers?(value)
        }
        multipeer.onError = { [weak self] value in
            guard let self, self.backend == .multipeer else { return }
            self.onError?(value)
        }
        multipeer.onMetrics = { [weak self] value in
            guard let self, self.backend == .multipeer else { return }
            self.onMetrics?(value)
        }
        network.onAudio = { [weak self] value, peer in
            guard let self, self.backend == .network else { return }
            self.onAudio?(value, peer)
        }
        network.onMessage = { [weak self] value, peer in
            guard let self, self.backend == .network else { return }
            self.onMessage?(value, peer)
        }
        network.onPeers = { [weak self] value in
            guard let self, self.backend == .network else { return }
            self.onPeers?(value)
        }
        network.onError = { [weak self] value in
            guard let self, self.backend == .network else { return }
            self.onError?(value)
        }
        network.onMetrics = { [weak self] value in
            guard let self, self.backend == .network else { return }
            self.onMetrics?(value)
        }
    }
    /// Caller must end the musical session first; changing backends always disconnects peers.
    func selectBackend(_ value: TransportBackend) {
        guard value != backend else { return }
        stop(); backend = value; onPeers?([]); onMetrics?([])
    }
    func host() { if backend == .network { network.host() } else { multipeer.host() } }
    func join() { if backend == .network { network.join() } else { multipeer.join() } }
    func stop() { multipeer.stop(); network.stop() }
    func send(_ message: WireMessage, to peer: MCPeerID? = nil) {
        if backend == .network { network.send(message, to: peer) } else { multipeer.send(message, to: peer) }
    }
    func sendAudio(_ data: Data) {
        if backend == .network { network.sendAudio(data) } else { multipeer.sendAudio(data) }
    }
}
