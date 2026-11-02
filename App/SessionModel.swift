import SwiftUI
import MultipeerConnectivity
import AVFoundation

final class SessionModel: ObservableObject {
    enum Role: String { case solo = "Solo", host = "Anfitrião", guest = "Participante" }
    @Published var role: Role = .solo
    @Published var bpm = 120.0
    @Published var composing = false
    @Published var lagMS = 0.0
    @Published var status = "Explore as notas ou comece uma composição."
    @Published var peers: [String] = []
    @Published var running = false
    @Published var currentBar = 0
    @Published var currentSlot = -1
    @Published var currentBeat = 0
    @Published var beatPhase = 0.0
    @Published var lastNote = 60
    @Published private(set) var scoreHistory = ScoreHistory()
    private var scoreTake = UUID()
    private var scoreOrigin: Double?
    private var scoreBPM = 120.0
    @Published var collected = 0
    @Published var pendingCount = 0
    @Published var lateBars = 0
    @Published var offsetMS = 0.0
    @Published var rttMS = 0.0
    @Published var audioInfo = "Áudio ainda não iniciado"
    @Published var logs: [String] = []
    @Published var shownEvents: [NoteEvent] = []
    @Published var clockReady = false
    @Published var liveInput = LiveInputState()
    @Published var inputBusy = false
    @Published var inputRMS = -120.0
    @Published var inputPeak = -120.0
    @Published var inputClipped = false
    @Published var detectedMIDI: Int? = nil
    @Published var detectedNote = "—"
    @Published var detectedFrequency = 0.0
    @Published var inputDropped: UInt32 = 0
    @Published var bassContributes = false
    @Published var monitorVolume = 0.35
    var inputActive: Bool { liveInput.captureID != nil }
    private var inputRequest = UUID()
    @Published var bassSlotNotes = Array(repeating: "—", count: 16)
    @Published var bassAnalysisWindowMS = 0.0
    private var bassAnalysisBar: Int64 = -1
    private var bassSlotVotes = Array(repeating: [Int: Double](), count: 16)
    @Published var recording = DebugRecordingState()
    private var noteDisplay = cr_note_display_new()
    private var lastNotePublish = 0.0
    private var bassGate = BassNoteGate()
    @Published private(set) var transportBackend: TransportBackend = .multipeer
    @Published private(set) var transportMetrics: [TransportMetrics] = []
    @Published private(set) var transmittingAudio = false
    @Published private(set) var remoteAudioTracks: [RemoteAudioTrack] = []
    private struct AudioReception {
        var track: RemoteAudioTrack
        var stream: UUID
        var sequence: UInt64
        var arrival: Double
        var capture: Double
    }
    private var audioReceptions: [MCPeerID: AudioReception] = [:]
    private var lastAudioPublish = 0.0
    private let transport = NearbyTransport()
    private let audio = MusicEngine()
    private let audioDelivery = AudioPacketDelivery()
    private var config: SessionConfig?
    private var authority: BarAuthority?
    private var timer: Timer?
    private var offset = 0.0
    private var samples: [(rtt: Double, offset: Double)] = []
    private var pings: Set<Double> = []
    private var lastPing = 0.0
    private var lastSnapshot = 0.0
    private var seenBars = Set<Int64>()
    private var futureBars: [Int64: CommittedBar] = [:]
    private var pending: [UUID: (action: NoteAction, sent: Double)] = [:]
    private var acknowledged = Set<UUID>()
    private var observers: [NSObjectProtocol] = []
    private var lastTap = 0.0

    init() {
        audioDelivery.onPacket = { [weak self] data in
            guard let self, self.transmittingAudio, self.role != .solo else { return }
            self.transport.sendAudio(data)
        }
        audio.onCapturedAudio = { [weak audioDelivery] data in audioDelivery?.enqueue(data) }
        transport.onMetrics = { [weak self] values in self?.transportMetrics = values }
        transport.onAudio = { [weak self] data, peer in self?.receiveAudio(data, from: peer) }
        transport.onMessage = { [weak self] message, peer in self?.receive(message, from: peer) }
        transport.onPeers = { [weak self] peers in
            guard let self else { return }
            self.peers = peers.map(\.displayName)
            for peer in Array(self.audioReceptions.keys) where !peers.contains(peer) {
                if let state = self.audioReceptions.removeValue(forKey: peer) { self.audio.removeRemote(state.track.id) }
            }
            self.publishAudioTracks()
            if self.role == .guest && peers.isEmpty {
                self.stopPlayback(); self.clockReady = false; self.samples.removeAll()
                self.status = "Conexão encerrada. Entre novamente para sincronizar."
            }
            if self.role == .host { self.sendSnapshot() }
        }
        transport.onError = { [weak self] in self?.status = $0 }
        audio.onIssue = { [weak self] in self?.status = "Áudio: \($0)" }
        audio.onLate = { [weak self] index in
            self?.lateBars += 1; self?.record("Compasso \(index + 1) atrasado: somente base local.")
        }
        audio.onInputState = { [weak self] state in
            guard let self else { return }
            let changedCapture = self.liveInput.captureID != state.captureID
            self.liveInput = state; self.inputBusy = state.isConfiguring
            if changedCapture { self.bassGate = BassNoteGate(); self.noteDisplay = cr_note_display_new() }
            if !self.inputActive {
                self.inputRMS = -120; self.inputPeak = -120; self.inputClipped = false
                self.detectedMIDI = nil; self.setAudioTransmission(false)
                self.detectedNote = "—"; self.detectedFrequency = 0
                self.bassContributes = false
            }
            if let error = state.error { self.status = "Entrada: " + error }
            else if state.isConfiguring { self.status = "Aguardando o iOS confirmar a entrada selecionada…" }
            else if changedCapture && self.inputActive { self.status = "Entrada ativa: " + state.inputName }
        }
        audio.onInputRouteInvalidated = { [weak self] in
            self?.leave()
            self?.status = "A rota de áudio mudou. Selecione e ative a entrada novamente."
        }
        audio.onRouteDiagnostic = { [weak self] text in self?.record(text) }
        audio.onInputReading = { [weak self] value in
            guard let self, self.liveInput.captureID == value.captureID else { return }
            self.updateBassSlots(value)
            let now = monotonicNow()
            cr_note_display_update(&self.noteDisplay, now, Int32(value.midi ?? -1), value.frequency, value.confidence, value.rmsDB)
            if now - self.lastNotePublish >= 0.1 {
                self.lastNotePublish = now
                self.inputRMS = value.rmsDB; self.inputPeak = value.peakDB
                self.inputClipped = value.clipped; self.inputDropped = value.dropped
                let midi = Int(self.noteDisplay.midi)
                self.detectedMIDI = midi >= 0 ? midi : nil
                let names = ["Dó", "Dó♯", "Ré", "Ré♯", "Mi", "Fá", "Fá♯", "Sol", "Sol♯", "Lá", "Lá♯", "Si"]
                let label = midi >= 0 ? names[midi % 12] + String(midi / 12 - 1) : "—"
                if self.detectedNote != label { self.detectedNote = label }
                let frequency = (self.noteDisplay.frequency * 10).rounded() / 10
                if self.detectedFrequency != frequency { self.detectedFrequency = frequency }
            }
            // Visual feedback is independent of contribution mode and network acceptance.
            if let note = self.bassGate.accept(midi: value.midi, confidence: value.confidence, rmsDB: value.rmsDB) {
                self.lastNote = note
                self.appendScore(note, at: value.captureTime)
                if self.bassContributes && self.running && self.composing {
                    self.submit(note, capturedAt: value.captureTime, recordVisual: false)
                }
            }

        }
        audio.onRecordingState = { [weak self] state in self?.recording = state }
        audio.onAudioInfo = { [weak self] rate, buffer, latency in
            self?.audioInfo = String(format: "%.0f Hz · buffer %.1f ms · saída estimada %.1f ms", rate, buffer * 1000, latency * 1000)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self, self.running || self.inputActive || self.inputBusy else { return }
                if notification.name == AVAudioSession.routeChangeNotification {
                    let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
                    guard let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                          reason == .oldDeviceUnavailable || reason == .newDeviceAvailable || reason == .routeConfigurationChange else { return }
                    // Requested changes are handled by MusicEngine's bounded route transition.
                    // Do not interpret our own selection notification as a disconnection.
                    if self.inputBusy { return }
                    if self.inputActive {
                        let session = AVAudioSession.sharedInstance()
                        let sameInput = session.currentRoute.inputs.first?.uid == self.liveInput.selectedUID
                        let sameOutput = session.currentRoute.outputs.map(\.portName).joined(separator: ", ") == self.liveInput.outputName
                        // Format validation belongs to MusicEngine on its serialized queue.
                        if sameInput && sameOutput { return }
                    }
                } else {
                    let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
                    guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
                }
                self.leave()
                self.status = "Áudio interrompido ou saída alterada. Inicie uma nova sessão."
            })
        }
    }
    deinit { timer?.invalidate(); observers.forEach(NotificationCenter.default.removeObserver) }
    func record(_ text: String) {
        logs.append(String(format: "%.3f ", monotonicNow()) + text)
        if logs.count > 300 { logs.removeFirst(logs.count - 300) }
    }
    func host() {
        resetRoom(releaseAudio: false); role = .host; clockReady = true; transport.host()
        status = "Sala aberta para até 4 pessoas. Inicie quando quiser."
    }
    func join() {
        resetRoom(releaseAudio: false); role = .guest; clockReady = false; transport.join()
        status = "Buscando a primeira sala próxima…"
    }
    func leave() { resetRoom(releaseAudio: true) }
    private func resetRoom(releaseAudio: Bool) {
        if role == .host, let c = config {
            transport.send(WireMessage(kind: "stop", sessionID: c.id))
        }
        setAudioTransmission(false); audio.removeAllRemote()
        audioReceptions.removeAll(); remoteAudioTracks = []
        stopPlayback(); transport.stop()
        if releaseAudio {
            inputRequest = UUID(); inputBusy = false; bassContributes = false
            audio.suspend()
        }
        transportMetrics = []
        role = .solo; peers = []; offset = 0; offsetMS = 0
        samples.removeAll(); pings.removeAll(); clockReady = false
        status = "Explore as notas ou comece uma composição."
    }
    func stopPlayback() {
        audio.stop(); running = false; config = nil; authority = nil
        pending.removeAll(); pendingCount = 0; futureBars.removeAll(); seenBars.removeAll()
        scoreOrigin = nil; scoreTake = UUID()
        shownEvents = []; currentBar = 0; currentBeat = 0; currentSlot = -1
    }
    func start() {
        guard role != .guest, !inputBusy else { return }
        let c = SessionConfig(id: UUID(), start: monotonicNow() + 3, bpm: bpm, lead: 0.5)
        offset = 0; authority = BarAuthority(config: c)
        apply(c); composing = true; sendSnapshot()
    }
    func stop() {
        if role == .guest { leave(); return }
        if let c = config { transport.send(WireMessage(kind: "stop", sessionID: c.id)) }
        stopPlayback(); status = "Composição encerrada."
    }
    private func apply(_ c: SessionConfig) {
        guard c.bpm >= 40, c.bpm <= 200, c.start.isFinite, c.lead >= 0.2, c.lead <= 4, c.subdivisionsPerBeat == 4 else { return }
        if config?.id == c.id { return }
        bassAnalysisBar = -1; bassSlotNotes = Array(repeating: "—", count: 16)
        scoreTake = c.id; scoreOrigin = c.start - offset; scoreBPM = c.bpm
        config = c; bpm = c.bpm; running = true
        seenBars.removeAll(); futureBars.removeAll(); pending.removeAll(); acknowledged.removeAll()
        pendingCount = 0; collected = 0; lateBars = 0; composing = true
        audio.begin(c, offset: offset)
        status = "Sessão ativa · contribuições entram em compassos futuros."
        record("START \(c.id) bpm=\(c.bpm) epoch=\(c.start)")
    }
    func play(_ midi: Int) { submit(midi, capturedAt: nil) }
    private func submit(_ midi: Int, capturedAt: Double?, recordVisual: Bool = true) {
        guard (60...72).contains(midi) else { return }
        lastNote = midi
        if recordVisual { appendScore(midi, at: capturedAt ?? monotonicNow()) }
        if !composing { audio.preview(midi: midi); return }
        guard running, let c = config else { status = "Inicie a composição para contribuir."; return }
        let now = monotonicNow()
        guard now - lastTap >= 0.06 else { return }
        lastTap = now
        let gesture: Double
        if let capturedAt, capturedAt > 0 {
            // Assign the window center to its containing sixteenth, independent of UI delivery.
            gesture = c.start + floor((capturedAt + offset - c.start) / c.slotDuration) * c.slotDuration
        } else { gesture = now + offset }
        let action = NoteAction(id: UUID(), session: c.id, midi: midi, gesture: gesture)
        pending[action.id] = (action, now); pendingCount = pending.count
        deliver(action)
        status = "\(MusicalNote.all[midi - 60].name) enviada · aguardando compasso."
    }
    private func deliver(_ action: NoteAction) {
        let capturedID = config?.id
        DispatchQueue.main.asyncAfter(deadline: .now() + lagMS / 1000) { [weak self] in
            guard let self, self.running, self.config?.id == capturedID else { return }
            if self.role == .guest {
                guard let host = self.transport.hostPeer else { return }
                self.transport.send(WireMessage(kind: "action", action: action), to: host)
            } else { self.accept(action, from: nil) }
        }
    }
    private func accept(_ action: NoteAction, from peer: MCPeerID?) {
        guard let bar = authority?.accept(action, now: monotonicNow()) else { return }
        let ack = WireMessage(kind: "ack", actionID: action.id, acceptedBar: bar, sessionID: action.session)
        if let peer { transport.send(ack, to: peer) } else { acknowledge(ack) }
        record("ACCEPT \(action.id) bar=\(bar) midi=\(action.midi)")
    }
    private func acknowledge(_ message: WireMessage) {
        guard message.sessionID == config?.id, let id = message.actionID, let bar = message.acceptedBar,
              pending.removeValue(forKey: id) != nil else { return }
        if acknowledged.insert(id).inserted { collected += 1 }
        pendingCount = pending.count
        status = "Contribuição confirmada para o compasso \(bar + 1)."
    }
    private func consume(_ bar: CommittedBar) {
        guard bar.session == config?.id, bar.index >= 0, bar.events.count <= 64,
              seenBars.insert(bar.index).inserted else { return }
        futureBars[bar.index] = bar
        audio.commit(bar)
        record("BAR \(bar.index) hash=\(bar.digest) notes=\(bar.events.count)")
    }
    private func sendSnapshot() {
        guard role == .host, let c = config else { return }
        let bars = authority?.committed.values.sorted { $0.index < $1.index } ?? []
        transport.send(WireMessage(kind: "snapshot", config: c, bars: bars))
    }
    private func receive(_ m: WireMessage, from peer: MCPeerID) {
        let now = monotonicNow()
        if role == .host {
            if m.kind == "ping", let t1 = m.t1 {
                transport.send(WireMessage(kind: "pong", t1: t1, t2: now, t3: monotonicNow()), to: peer)
            } else if m.kind == "action", let action = m.action { accept(action, from: peer) }
            return
        }
        guard role == .guest, peer == transport.hostPeer else { return }
        switch m.kind {
        case "pong":
            guard let a = m.t1, let b = m.t2, let c = m.t3,
                  pings.remove(a) != nil, b.isFinite, c.isFinite else { return }
            let rtt = cr_round_trip(a, b, c, now)
            guard rtt >= 0, rtt < 2 else { return }
            samples.append((rtt, cr_clock_offset(a, b, c, now)))
            if samples.count > 20 { samples.removeFirst() }
            guard let best = samples.min(by: { $0.rtt < $1.rtt }) else { return }
            if !running { offset = best.offset }
            else { offset += min(0.0005, max(-0.0005, best.offset - offset)) }
            offsetMS = offset * 1000; rttMS = best.rtt * 1000
            clockReady = samples.count >= 8
            audio.updateOffset(offset)
            if !running && clockReady { status = "Relógio sincronizado. Aguardando o anfitrião." }
        case "snapshot":
            guard clockReady, !inputBusy, let c = m.config else { return }
            apply(c)
            for bar in (m.bars ?? []).sorted(by: { $0.index < $1.index }) {
                if c.start + Double(bar.index) * c.barDuration > now + offset + 0.05 { consume(bar) }
            }
        case "bar":
            if let bar = m.bar { consume(bar) }
        case "ack": acknowledge(m)
        case "stop":
            if m.sessionID == config?.id { stopPlayback(); status = "Anfitrião encerrou a composição." }
        default: break
        }
    }
    private func tick() {
        let now = monotonicNow()
        if now - lastAudioPublish >= 0.1 {
            lastAudioPublish = now
            for peer in Array(audioReceptions.keys) {
                guard var state = audioReceptions[peer] else { continue }
                if now - state.arrival > 0.25 { state.track.peak = 0; state.track.bufferedMS = 0; audio.removeRemote(state.track.id) }
                audioReceptions[peer] = state
            }
            publishAudioTracks()
        }
        if role == .guest, let host = transport.hostPeer,
           now - lastPing >= (clockReady ? 2 : 0.15) {
            lastPing = now; pings = pings.filter { now - $0 < 4 }; pings.insert(now)
            transport.send(WireMessage(kind: "ping", t1: now), to: host)
        }
        guard running, let c = config else { return }
        if let authority {
            for bar in authority.closeDue(now: now) {
                consume(bar)
                if role == .host { transport.send(WireMessage(kind: "bar", bar: bar)) }
            }
        }
        if now - lastSnapshot > 1 { lastSnapshot = now; sendSnapshot() }
        for (id, item) in Array(pending) where now - item.sent > 1.5 {
            if now + offset - item.action.gesture >= 25 {
                pending.removeValue(forKey: id); pendingCount = pending.count
                record("EXPIRED \(id): contribution could not be confirmed")
                status = "Uma contribuição expirou. Toque novamente."
                continue
            }
            pending[id] = (item.action, now); deliver(item.action)
        }
        let position = (now + offset - c.start) / c.beat
        currentBar = position < 0 ? 0 : Int(position / 4) + 1
        currentBeat = position < 0 ? 0 : Int(position) % 4 + 1
        currentSlot = position < 0 ? -1 : Int(position * 4) % 16
        beatPhase = position < 0 ? 0 : position - floor(position)
        if currentBar > 0 {
            shownEvents = futureBars[Int64(currentBar - 1)]?.events ?? []
            futureBars = futureBars.filter { $0.key >= Int64(currentBar - 3) }
            seenBars = seenBars.filter { $0 >= Int64(currentBar - 8) }
        }
    }
    func selectTransportBackend(_ value: TransportBackend) {
        guard role == .solo, !running, !inputBusy else { return }
        transport.selectBackend(value); transportBackend = value; transportMetrics = []
        record("TRANSPORT " + value.rawValue)
    }
    func setAudioTransmission(_ enabled: Bool) {
        transmittingAudio = enabled && inputActive && role != .solo && !inputBusy
        audio.setStreaming(transmittingAudio)
    }
    func setRemoteAudioVolume(_ id: String, volume: Float) {
        guard let peer = audioReceptions.first(where: { $0.value.track.id == id })?.key,
              var state = audioReceptions[peer] else { return }
        state.track.volume = volume; audioReceptions[peer] = state
        audio.setRemoteVolume(id, volume: state.track.muted ? 0 : volume); publishAudioTracks()
    }
    func setRemoteAudioMuted(_ id: String, muted: Bool) {
        guard let peer = audioReceptions.first(where: { $0.value.track.id == id })?.key,
              var state = audioReceptions[peer] else { return }
        state.track.muted = muted; audioReceptions[peer] = state
        audio.setRemoteVolume(id, volume: muted ? 0 : state.track.volume); publishAudioTracks()
    }
    private func publishAudioTracks() {
        remoteAudioTracks = audioReceptions.values.map(\.track).sorted { $0.id < $1.id }
    }
    private func receiveAudio(_ data: Data, from peer: MCPeerID) {
        guard role != .solo, transport.peers.contains(peer), let packet = AudioPacket(data: data) else { return }
        let now = monotonicNow()
        var state: AudioReception
        if let current = audioReceptions[peer], current.stream == packet.stream {
            state = current
            guard packet.sequence > state.sequence else {
                state.track.late += 1; audioReceptions[peer] = state; return
            }
            state.track.missing += min(1_000_000, packet.sequence - state.sequence - 1)
            let variation = abs((now - state.arrival) - (packet.captureTime - state.capture)) * 1000
            state.track.jitterMS += (variation - state.track.jitterMS) / 16
        } else {
            let previous = audioReceptions[peer]?.track
            var track = RemoteAudioTrack(id: previous?.id ?? UUID().uuidString, name: peer.displayName)
            track.muted = previous?.muted ?? false; track.volume = previous?.volume ?? 0.7
            state = AudioReception(track: track, stream: packet.stream, sequence: packet.sequence, arrival: now, capture: packet.captureTime)
        }
        state.sequence = packet.sequence; state.arrival = now; state.capture = packet.captureTime
        state.track.received += 1; state.track.peak = packet.peak
        audioReceptions[peer] = state
        let id = state.track.id
        audio.receiveAudio(packet, from: id, volume: state.track.muted ? 0 : state.track.volume) { [weak self] queued in
            guard let self, var current = self.audioReceptions[peer], current.stream == packet.stream else { return }
            if queued < 0 { current.track.late += 1; current.track.bufferedMS = 0 }
            else { current.track.bufferedMS = queued }
            self.audioReceptions[peer] = current
        }
    }
    func enableBassInput() {
        guard !running, !inputBusy else { return }
        inputBusy = true
        let request = UUID(); inputRequest = request
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, self.inputRequest == request else { return }
                if granted {
                    self.status = "Preparando entrada de áudio…"
                    self.audio.enableInput()
                } else {
                    self.inputBusy = false
                    self.status = "Permita o microfone nos Ajustes do iOS para usar entrada de áudio, inclusive USB."
                }
            }
        }
    }
    func disableBassInput() {
        guard !running else { return }
        inputRequest = UUID(); bassContributes = false; inputBusy = true
        audio.disableInput()
    }
    func selectBassInput(_ uid: String) {
        guard !running, !inputBusy, liveInput.available.contains(where: { $0.id == uid }) else { return }
        inputBusy = true; bassContributes = false
        liveInput.requestedUID = uid; liveInput.error = nil
        record("INPUT_SELECT uid=\(uid)")
        audio.enableInput(uid: uid, channel: 0)
    }
    func refreshInputOptions() { audio.refreshInputOptions() }
    func selectAnalysisChannel(_ channel: Int) {
        guard !running, !inputBusy, inputActive else { return }
        inputBusy = true; bassContributes = false
        audio.enableInput(uid: liveInput.selectedUID, channel: channel)
    }
    func setInputMonitoring(_ enabled: Bool) {
        audio.setMonitoring(enabled, gain: Float(monitorVolume))
    }
    func updateMonitorVolume(_ volume: Double) {
        monitorVolume = volume
        audio.setMonitoring(liveInput.monitoring, gain: Float(volume))
    }
    private func updateBassSlots(_ value: LiveInputReading) {
        let windowMS = (value.windowSeconds * 1000).rounded()
        if bassAnalysisWindowMS != windowMS { bassAnalysisWindowMS = windowMS }
        guard let c = config, running, value.captureTime > 0 else { return }
        let relative = value.captureTime + offset - c.start
        guard relative >= 0 else { return }
        let bar = Int64(floor(relative / c.barDuration))
        if bar != bassAnalysisBar {
            guard bar > bassAnalysisBar else { return }
            bassAnalysisBar = bar
            bassSlotVotes = Array(repeating: [:], count: 16)
            bassSlotNotes = Array(repeating: "—", count: 16)
        }
        let slot = Int(floor(relative / c.slotDuration)) % 16
        guard let midi = value.midi, value.confidence >= 0.85, value.rmsDB > -55 else { return }
        bassSlotVotes[slot][midi, default: 0] += value.confidence
        guard let winner = bassSlotVotes[slot].max(by: { $0.value < $1.value })?.key else { return }
        let names = ["Dó", "Dó♯", "Ré", "Ré♯", "Mi", "Fá", "Fá♯", "Sol", "Sol♯", "Lá", "Lá♯", "Si"]
        let name = names[winner % 12] + String(winner / 12 - 1)
        if bassSlotNotes[slot] != name { bassSlotNotes[slot] = name }
    }
    private func appendScore(_ midi: Int, at time: Double) {
        guard time.isFinite, time > 0 else { return }
        if scoreOrigin == nil { scoreOrigin = time; scoreBPM = bpm }
        guard let origin = scoreOrigin else { return }
        scoreHistory.append(midi: midi, time: time, origin: origin, bpm: scoreBPM, take: scoreTake)
    }
    func clearScore() {
        scoreHistory.clear()
        if !running { scoreOrigin = nil; scoreTake = UUID() }
    }
    func startRecording() {
        guard inputActive, !inputBusy, !recording.recording, !recording.finalizing else { return }
        audio.startDebugRecording()
    }
    func stopRecording() { audio.stopDebugRecording(logs: logs) }
    func exportLog() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Rodopio-diagnostico.txt")
        let header = "Rodopio v0.5.0 build9 backend=\(transportBackend.rawValue)\n\(audioInfo)\noffset_ms=\(offsetMS) rtt_ms=\(rttMS) late=\(lateBars)\n"
        let metricJSON = (try? JSONEncoder().encode(transportMetrics)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let remote = remoteAudioTracks.map { "audio_peer=\($0.name) packets=\($0.received) sequence_gaps=\($0.missing) discarded=\($0.late) jitter_ms=\($0.jitterMS) queued_ms=\($0.bufferedMS)" }.joined(separator: "\n")
        do { try (header + "metrics=" + metricJSON + "\n" + remote + "\n" + "input=\(liveInput.inputName) output=\(liveInput.outputName) channel=\(liveInput.analysisChannel+1) input_rate=\(liveInput.sampleRate) dropped=\(inputDropped)\n" + logs.joined(separator: "\n")).write(to: url, atomically: true, encoding: .utf8); return url }
        catch { status = error.localizedDescription; return nil }
    }
}
