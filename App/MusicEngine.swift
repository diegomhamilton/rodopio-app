import AVFoundation
import Foundation

/// All scheduling is serialized on a dedicated queue, never on the render callback.
final class MusicEngine {
    private let queue = DispatchQueue(label: "org.ciranda.audio", qos: .userInteractive)
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    private var voices: [Int: AVAudioPlayerNode] = [:]
    private var previews: [AVAudioPlayerNode] = []
    private var buffers: [Int: AVAudioPCMBuffer] = [:]
    private var previewIndex = 0
    private var started = false
    private var timer: DispatchSourceTimer?
    private var config: SessionConfig?
    private var offset = 0.0
    private var nextClick: Int64 = 0
    private var scheduled = Set<Int64>()
    private var latency = 0.0
    private let monitorMixer = AVAudioMixerNode()
    private var recorder: DebugRecorder?
    private var outputTapInstalled = false
    var onRecordingState: ((DebugRecordingState) -> Void)?
    private var analyzer: LiveInputAnalyzer?
    private var streamCapture: AudioStreamCapture?
    private var streamingEnabled = false
    var onCapturedAudio: ((Data) -> Void)?
    private final class RemoteVoice {
        let node = AVAudioPlayerNode()
        let stream: UUID
        let rate: Double
        var queued = 0.0
        var playing = false
        init(stream: UUID, rate: Double) { self.stream = stream; self.rate = rate }
    }
    private var remoteVoices: [String: RemoteVoice] = [:]
    private var inputTapInstalled = false
    private var inputGraphConnected = false
    private var inputEnabled = false
    private var monitorGain: Float = 0.35
    private var inputState = LiveInputState()
    private struct PendingRoute {
        let id: UUID
        let uid: String
        let channel: Int
        var wait: CRRouteWait
        var sampleRate: Double = 0
        var channels: AVAudioChannelCount = 0
    }
    private var pendingRoute: PendingRoute?
    private var routePoll: DispatchWorkItem?
    private var routeObserver: NSObjectProtocol?
    var onInputRouteInvalidated: (() -> Void)?
    var onRouteDiagnostic: ((String) -> Void)?
    var onInputState: ((LiveInputState) -> Void)?
    var onInputReading: ((LiveInputReading) -> Void)?
    var onIssue: ((String) -> Void)?
    var onLate: ((Int64) -> Void)?
    var onAudioInfo: ((Double, Double, Double) -> Void)?

    init() {
        engine.attach(monitorMixer)
        monitorMixer.outputVolume = 0
        for midi in Array(60...72) + [90, 91] {
            // Four voices per pitch retain release tails on repeated sixteenth notes.
            for lane in 0..<(midi >= 90 ? 1 : 4) {
                let node = AVAudioPlayerNode()
                engine.attach(node); engine.connect(node, to: engine.mainMixerNode, format: format)
                voices[midi >= 90 ? midi : midi * 4 + lane] = node
            }
            buffers[midi] = makeBuffer(midi: midi)
        }
        for _ in 0..<8 {
            let node = AVAudioPlayerNode()
            engine.attach(node); engine.connect(node, to: engine.mainMixerNode, format: format)
            previews.append(node)
        }
        // Headroom for polyphonic contributions; bar admission is bounded as well.
        engine.mainMixerNode.outputVolume = 0.4
        routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            self?.queue.async { [weak self] in
                guard let self else { return }
                self.logRoute("notification reason=\(reason)")
                if let pending = self.pendingRoute { self.checkInputRoute(id: pending.id) }
                else { self.refreshPorts() }
            }
        }
    }
    deinit {
        routePoll?.cancel()
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
    }
    func setStreaming(_ enabled: Bool) {
        queue.async { self.streamingEnabled = enabled; self.streamCapture?.enable(enabled) }
    }
    func setRemoteVolume(_ id: String, volume: Float) {
        queue.async { self.remoteVoices[id]?.node.volume = max(0, min(1, volume)) }
    }
    func removeRemote(_ id: String) {
        queue.async { self.removeRemoteVoice(id) }
    }
    private func removeRemoteVoice(_ id: String) {
        guard let voice = remoteVoices.removeValue(forKey: id) else { return }
        voice.node.stop(); engine.disconnectNodeOutput(voice.node); engine.detach(voice.node)
    }
    func removeAllRemote() {
        queue.async { for id in Array(self.remoteVoices.keys) { self.removeRemoteVoice(id) } }
    }
    /// 20 ms initial prebuffer, 60 ms hard queue ceiling. Old queued audio is flushed on overflow.
    func receiveAudio(_ packet: AudioPacket, from id: String, volume: Float, report: @escaping (Double) -> Void) {
        queue.async {
            do {
                try self.ensureStarted()
                if let old = self.remoteVoices[id], old.stream != packet.stream || old.rate != packet.sampleRate {
                    self.removeRemoteVoice(id)
                }
                let format = AVAudioFormat(standardFormatWithSampleRate: packet.sampleRate, channels: 1)!
                let voice: RemoteVoice
                if let existing = self.remoteVoices[id] { voice = existing }
                else {
                    guard self.remoteVoices.count < 3 else { return }
                    voice = RemoteVoice(stream: packet.stream, rate: packet.sampleRate)
                    self.engine.attach(voice.node)
                    self.engine.connect(voice.node, to: self.engine.mainMixerNode, format: format)
                    self.remoteVoices[id] = voice
                }
                let duration = Double(packet.samples.count) / packet.sampleRate
                if voice.queued + duration > 0.06 {
                    self.removeRemoteVoice(id)
                    DispatchQueue.main.async { report(-1) }
                    return
                }
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(packet.samples.count)) else { return }
                buffer.frameLength = buffer.frameCapacity
                let channel = buffer.floatChannelData![0]
                for i in packet.samples.indices { channel[i] = Float(packet.samples[i]) / 32768 }
                voice.node.volume = max(0, min(1, volume)); voice.queued += duration
                voice.node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self, weak voice] _ in
                    self?.queue.async {
                        guard let voice else { return }
                        voice.queued = max(0, voice.queued - duration)
                        if voice.queued < 0.0001 { voice.node.stop(); voice.playing = false }
                    }
                }
                if !voice.playing && voice.queued >= 0.02 { voice.node.play(); voice.playing = true }
                let queued = voice.queued * 1000
                DispatchQueue.main.async { report(queued) }
            } catch { DispatchQueue.main.async { self.onIssue?(error.localizedDescription) } }
        }
    }
    private func makeBuffer(midi: Int) -> AVAudioPCMBuffer {
        let click = midi >= 90
        let seconds = click ? 0.035 : 0.16
        let count = AVAudioFrameCount(seconds * 48_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        let data = buffer.floatChannelData![0]
        let frequency = click ? (midi == 90 ? 1600.0 : 1100.0) : 440 * pow(2, Double(midi - 69) / 12)
        for i in 0..<Int(count) {
            let t = Double(i) / 48_000
            let attack = min(1, t / 0.005)
            let release = min(1, (seconds - t) / 0.025)
            let envelope = attack * release * exp(-t * (click ? 65 : 8))
            data[i] = Float(sin(2 * .pi * frequency * t) * envelope * (click ? 0.25 : 0.12))
        }
        return buffer
    }
    private func ensureStarted() throws {
        guard pendingRoute == nil else {
            throw NSError(domain: "Ciranda", code: 7, userInfo: [NSLocalizedDescriptionKey: "Aguarde a troca da entrada de áudio."])
        }
        guard !started else { return }
        let session = AVAudioSession.sharedInstance()
        if !inputEnabled {
            try session.setCategory(.playback, mode: .default)
            try session.setPreferredSampleRate(48_000)
            try session.setPreferredIOBufferDuration(256.0 / 48_000)
            try session.setActive(true)
        }
        try engine.start()
        for node in Array(voices.values) + previews { node.play() }
        started = true
        // Estimate only: physical output must be measured on actual devices/routes.
        latency = session.outputLatency + session.ioBufferDuration
        let rate = session.sampleRate, duration = session.ioBufferDuration, output = latency
        DispatchQueue.main.async { self.onAudioInfo?(rate, duration, output) }
    }
    func preview(midi: Int) {
        queue.async {
            do {
                try self.ensureStarted()
                guard let buffer = self.buffers[midi] else { return }
                let voice = self.previews[self.previewIndex % self.previews.count]
                self.previewIndex += 1
                voice.stop(); voice.scheduleBuffer(buffer, at: nil); voice.play()
            } catch { self.report(error) }
        }
    }
    func begin(_ config: SessionConfig, offset: Double) {
        queue.async {
            self.resetTimeline()
            do {
                try self.ensureStarted()
                self.config = config; self.offset = offset
                self.recorder?.sessionStarted(config, offset: offset, latency: self.latency)
                let hostNow = monotonicNow() + offset
                self.nextClick = max(0, Int64(ceil((hostNow + self.latency + 0.08 - config.start) / config.beat)))
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now(), repeating: .milliseconds(20))
                timer.setEventHandler { [weak self] in self?.fillClicks() }
                self.timer = timer; timer.resume()
            } catch { self.report(error) }
        }
    }
    func updateOffset(_ value: Double) { queue.async { self.offset = value } }
    private func fillClicks() {
        guard let c = config else { return }
        let now = monotonicNow()
        while c.start + Double(nextClick) * c.beat - offset < now + 0.2 {
            let target = c.start + Double(nextClick) * c.beat - offset - latency
            if target > now + 0.005 { schedule(midi: nextClick % 4 == 0 ? 90 : 91, at: target) }
            nextClick += 1
        }
    }
    func commit(_ bar: CommittedBar) {
        queue.async {
            guard let c = self.config, bar.session == c.id, !self.scheduled.contains(bar.index) else { return }
            self.scheduled.insert(bar.index)
            self.scheduled = self.scheduled.filter { $0 >= bar.index - 16 }
            let beginning = c.start + Double(bar.index) * c.barDuration - self.offset - self.latency
            guard beginning > monotonicNow() + 0.02 else {
                DispatchQueue.main.async { self.onLate?(bar.index) }; return
            }
            // Aggregate unison notes to avoid amplification and competing queues per pitch.
            var unique = Set<String>()
            for event in bar.events.sorted(by: { $0.slot < $1.slot }) {
                guard (60...72).contains(event.midi), (0..<c.slotsPerBar).contains(event.slot),
                      unique.insert("\(event.midi):\(event.slot)").inserted else { continue }
                self.schedule(midi: event.midi, at: beginning + Double(event.slot) * c.slotDuration, lane: event.slot % 4)
            }
        }
    }
    private func schedule(midi: Int, at seconds: Double, lane: Int = 0) {
        let key = midi >= 90 ? midi : midi * 4 + lane
        guard seconds > 0, let voice = voices[key], let buffer = buffers[midi] else { return }
        voice.scheduleBuffer(buffer, at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: seconds)))
        if midi < 90 { recorder?.noteScheduled(midi: midi, hostTime: seconds) }
    }
    private func resetTimeline() {
        timer?.cancel(); timer = nil; config = nil; scheduled.removeAll()
        for node in voices.values { node.stop(); if started { node.play() } }
    }
    func stop() { queue.async { self.resetTimeline() } }
    func suspend() {
        queue.async {
            self.resetTimeline()
            self.cancelInputTransition()
            self.stopInputGraph()
            for node in self.previews { node.stop() }
            self.engine.stop(); self.started = false
            try? AVAudioSession.sharedInstance().setActive(false)
            self.inputState = LiveInputState(); self.publishInputState()
        }
    }
    /// Route selection is asynchronous; build the input graph only after route + format settle.
    func enableInput(uid: String? = nil, channel: Int = 0) {
        queue.async {
            guard self.config == nil else {
                self.reportInputError("Encerre a composição antes de mudar a entrada."); return
            }
            self.cancelInputTransition()
            self.engine.stop(); self.started = false
            for node in Array(self.voices.values) + self.previews { node.stop() }
            self.stopInputGraph()
            self.engine.reset()
            self.inputState.captureID = nil
            self.inputState.monitoring = false
            self.inputState.isConfiguring = true
            self.inputState.requestedUID = uid ?? ""
            self.inputState.error = nil
            self.publishInputState()
            do {
                let session = AVAudioSession.sharedInstance()
                // HFP is opt-in; without it paired Bluetooth microphones are omitted from availableInputs.
                // Keep measurement and USB preference; do not enable the higher-latency HQ recording mode.
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetoothHFP])
                try session.setPreferredSampleRate(48_000)
                try session.setPreferredIOBufferDuration(256.0 / 48_000)
                try session.setActive(true)
                let ports = session.availableInputs ?? []
                let selected: AVAudioSessionPortDescription?
                if let uid { selected = ports.first(where: { $0.uid == uid }) }
                else { selected = ports.first(where: { $0.portType == .usbAudio }) ?? ports.first }
                guard let selected else {
                    throw NSError(domain: "Ciranda", code: 3, userInfo: [NSLocalizedDescriptionKey: "A entrada escolhida não está disponível. Atualize as entradas."])
                }
                self.inputState.requestedUID = selected.uid
                self.refreshPorts()
                let pending = PendingRoute(id: UUID(), uid: selected.uid, channel: channel,
                                           wait: cr_route_wait(monotonicNow(), 3))
                self.pendingRoute = pending
                self.logRoute("request uid=\(selected.uid) name=\(selected.portName)")
                try session.setPreferredInput(selected)
                self.checkInputRoute(id: pending.id)
            } catch { self.failInputTransition(error.localizedDescription) }
        }
    }
    private func checkInputRoute(id: UUID) {
        guard var pending = pendingRoute, pending.id == id else { return }
        routePoll?.cancel(); routePoll = nil
        let session = AVAudioSession.sharedInstance()
        let ports = session.availableInputs ?? []
        let matches = session.currentRoute.inputs.contains { $0.uid == pending.uid }
        let format = engine.inputNode.outputFormat(forBus: 0)
        let validFormat = format.sampleRate > 0 && format.channelCount > 0 && format.commonFormat == .pcmFormatFloat32
        if pending.sampleRate != format.sampleRate || pending.channels != format.channelCount {
            pending.wait.stable_since = -1
            pending.sampleRate = format.sampleRate; pending.channels = format.channelCount
        }
        let decision = cr_route_step(&pending.wait, monotonicNow(),
                                     ports.contains(where: { $0.uid == pending.uid }) ? 1 : 0,
                                     matches ? 1 : 0, validFormat ? 1 : 0)
        pendingRoute = pending
        if decision == 1 {
            pendingRoute = nil
            do { try installInputGraph(channel: pending.channel, requestedUID: pending.uid) }
            catch { failInputTransition(error.localizedDescription) }
        } else if decision < 0 {
            failInputTransition(decision == -1 ? "A interface foi desconectada durante a seleção." : "O iOS não confirmou essa entrada em 3 segundos. A entrada ativa está indicada abaixo; tente novamente.")
        } else {
            let work = DispatchWorkItem { [weak self] in self?.checkInputRoute(id: id) }
            routePoll = work
            queue.asyncAfter(deadline: .now() + .milliseconds(100), execute: work)
        }
    }
    private func installInputGraph(channel: Int, requestedUID: String) throws {
        let session = AVAudioSession.sharedInstance()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let chosen = max(0, min(channel, Int(format.channelCount) - 1))
        guard session.currentRoute.inputs.contains(where: { $0.uid == requestedUID }),
              format.sampleRate > 0, format.channelCount > 0,
              let analyzer = LiveInputAnalyzer(sampleRate: format.sampleRate) else {
            throw NSError(domain: "Ciranda", code: 5, userInfo: [NSLocalizedDescriptionKey: "A entrada mudou durante a preparação. Selecione-a novamente."])
        }
        self.analyzer = analyzer
        let capture = AudioStreamCapture(rate: format.sampleRate) { [weak self] data in self?.onCapturedAudio?(data) }
        capture?.enable(streamingEnabled)
        self.streamCapture = capture
        analyzer.onReading = { [weak self] value in self?.onInputReading?(value) }
        engine.connect(input, to: monitorMixer, format: format)
        let mixFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: min(2, format.channelCount))!
        engine.connect(monitorMixer, to: engine.mainMixerNode, format: mixFormat)
        inputGraphConnected = true; monitorMixer.outputVolume = 0
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, when in
            analyzer.push(buffer, channel: chosen, when: when)
            capture?.push(buffer, channel: chosen, when: when)
        }
        inputTapInstalled = true; inputEnabled = true
        try ensureStarted()
        // Never label the requested port as active if iOS chose a different one.
        guard session.currentRoute.inputs.contains(where: { $0.uid == requestedUID }) else {
            throw NSError(domain: "Ciranda", code: 6, userInfo: [NSLocalizedDescriptionKey: "O iOS alterou a entrada ao iniciar o áudio. Selecione a interface novamente."])
        }
        inputState = LiveInputState(captureID: analyzer.id, requestedUID: requestedUID,
                                    channels: Int(format.channelCount), analysisChannel: chosen,
                                    canMonitor: safeMonitorRoute(), sampleRate: format.sampleRate,
                                    inputLatency: session.inputLatency)
        refreshPorts()
        logRoute("confirmed rate=\(format.sampleRate) channels=\(format.channelCount)")
        do {
            let outputFormat = engine.mainMixerNode.outputFormat(forBus: 0)
            let recorder = try DebugRecorder(inputRate: format.sampleRate, outputRate: outputFormat.sampleRate)
            recorder.onState = { [weak self] state in self?.onRecordingState?(state) }
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, when in
                analyzer.push(buffer, channel: chosen, when: when)
                capture?.push(buffer, channel: chosen, when: when)
                recorder.pushInput(buffer, when: when, channel: chosen)
            }
            engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: outputFormat) { buffer, when in
                recorder.pushOutput(buffer, when: when)
            }
            outputTapInstalled = true; self.recorder = recorder
        } catch {
            let state = DebugRecordingState(error: error.localizedDescription)
            DispatchQueue.main.async { self.onRecordingState?(state) }
        }
        analyzer.start()
    }
    private func cancelInputTransition() {
        pendingRoute = nil; routePoll?.cancel(); routePoll = nil
    }
    private func failInputTransition(_ message: String) {
        cancelInputTransition()
        engine.stop(); started = false; stopInputGraph()
        inputState.captureID = nil; inputState.monitoring = false
        inputState.isConfiguring = false; inputState.error = message
        // Keep playAndRecord so the user can see/retry the available ports after a failure.
        refreshPorts(); logRoute("failed: " + message)
    }
    func refreshInputOptions() {
        queue.async { self.refreshPorts() }
    }
    private func refreshPorts() {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute
        var invalidated = false
        if inputEnabled && pendingRoute == nil && !inputState.selectedUID.isEmpty {
            let format = engine.inputNode.outputFormat(forBus: 0)
            let sameInput = route.inputs.first?.uid == inputState.selectedUID
            let sameOutput = route.outputs.map(\.portName).joined(separator: ", ") == inputState.outputName
            let sameFormat = format.sampleRate == inputState.sampleRate && Int(format.channelCount) == inputState.channels
            if !sameInput || !sameOutput || !sameFormat {
                engine.stop(); started = false; stopInputGraph()
                inputState.captureID = nil; inputState.monitoring = false
                invalidated = true
            }
        }
        inputState.available = (session.availableInputs ?? []).map {
            AudioInputOption(id: $0.uid, name: $0.portName, usb: $0.portType == .usbAudio,
                             bluetooth: [.bluetoothHFP, .bluetoothLE].contains($0.portType))
        }
        inputState.selectedUID = session.currentRoute.inputs.first?.uid ?? ""
        inputState.inputName = session.currentRoute.inputs.map(\.portName).joined(separator: ", ")
        inputState.outputName = session.currentRoute.outputs.map(\.portName).joined(separator: ", ")
        inputState.canMonitor = safeMonitorRoute()
        publishInputState()
        if invalidated { DispatchQueue.main.async { self.onInputRouteInvalidated?() } }
    }
    private func logRoute(_ message: String) {
        let route = AVAudioSession.sharedInstance().currentRoute
        let session = AVAudioSession.sharedInstance()
        let text = "ROUTE " + message + " category=" + session.category.rawValue + " mode=" + session.mode.rawValue + " options=" + String(session.categoryOptions.rawValue) + " available=" + (session.availableInputs ?? []).map { $0.portName + ":" + $0.portType.rawValue }.joined(separator: ",") + " input=" + route.inputs.map { $0.portName + ":" + $0.portType.rawValue + ":" + $0.uid }.joined(separator: ",") + " output=" + route.outputs.map { $0.portName + ":" + $0.portType.rawValue }.joined(separator: ",")
        DispatchQueue.main.async { self.onRouteDiagnostic?(text) }
    }
    func disableInput() {
        queue.async {
            guard self.config == nil else { self.reportInputError("Encerre a composição antes de desligar a entrada."); return }
            self.cancelInputTransition()
            self.engine.stop(); self.started = false
            for node in Array(self.voices.values) + self.previews { node.stop() }
            self.stopInputGraph(); self.inputState = LiveInputState(); self.publishInputState()
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(false)
        }
    }
    func setMonitoring(_ enabled: Bool, gain: Float) {
        queue.async {
            guard self.pendingRoute == nil else { return }
            self.monitorGain = max(0, min(1, gain))
            let permitted = self.safeMonitorRoute()
            self.inputState.canMonitor = permitted
            self.inputState.monitoring = enabled && self.inputEnabled && permitted
            self.monitorMixer.outputVolume = self.inputState.monitoring ? self.monitorGain : 0
            self.publishInputState()
        }
    }
    private func safeMonitorRoute() -> Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return !outputs.isEmpty && outputs.allSatisfy { [.headphones, .usbAudio, .lineOut].contains($0.portType) }
    }
    private func stopInputGraph() {
        streamCapture?.enable(false); streamCapture = nil
        monitorMixer.outputVolume = 0
        if inputTapInstalled { engine.inputNode.removeTap(onBus: 0); inputTapInstalled = false }
        if outputTapInstalled { engine.mainMixerNode.removeTap(onBus: 0); outputTapInstalled = false }
        recorder?.shutdown(); recorder = nil
        analyzer?.stop(); analyzer = nil
        if inputGraphConnected {
            engine.disconnectNodeOutput(engine.inputNode)
            engine.disconnectNodeOutput(monitorMixer)
            inputGraphConnected = false
        }
        inputEnabled = false
    }
    func startDebugRecording() {
        queue.async {
            guard self.inputEnabled, self.pendingRoute == nil else { return }
            self.recorder?.start(config: self.config, offset: self.offset, outputLatency: self.latency, route: self.inputState)
        }
    }
    func stopDebugRecording(logs: [String]) { queue.async { self.recorder?.finish(logs: logs) } }
    private func publishInputState() {
        let value = inputState
        DispatchQueue.main.async { self.onInputState?(value) }
    }
    private func reportInputError(_ message: String) {
        var value = inputState; value.error = message
        DispatchQueue.main.async { self.onInputState?(value) }
    }
    private func report(_ error: Error) { DispatchQueue.main.async { self.onIssue?(error.localizedDescription) } }
}
