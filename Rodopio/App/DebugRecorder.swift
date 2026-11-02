import AVFoundation
import Foundation

struct DebugMarker: Codable {
    let time: Double
    let kind: String
    let label: String
}
struct DebugRecordingState {
    var id = UUID()
    var recording = false
    var finalizing = false
    var duration = 0.0
    var inputPeaks: [Float] = []
    var outputPeaks: [Float] = []
    var markers: [DebugMarker] = []
    var files: [URL] = []
    var error: String? = nil
    var gaps = 0
}

/// One SPSC ring per tap. Only this object's writer queue touches files/waveforms.
final class DebugRecorder {
    private final class Track {
        let mailbox: OpaquePointer
        let rate: Double
        let scratch: AVAudioPCMBuffer
        var file: AVAudioFile?
        var url: URL?
        var frames: Int64 = 0
        var missingFrames: Int64 = 0
        var overlapFrames: Int64 = 0
        var estimatedTime = false
        var peaks: [Float] = []
        init(rate: Double) throws {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024),
                  let ring = cr_capture_create(rate) else {
                throw NSError(domain: "Ciranda", code: 20, userInfo: [NSLocalizedDescriptionKey: "Não foi possível preparar a gravação."])
            }
            mailbox = ring; self.rate = rate; scratch = buffer
        }
        deinit { cr_capture_destroy(mailbox) }
        func open(_ url: URL) throws {
            file = try AVAudioFile(forWriting: url, settings: scratch.format.settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
            self.url = url; frames = 0; missingFrames = 0; overlapFrames = 0
            estimatedTime = false; peaks.removeAll(keepingCapacity: true)
        }
        func append(_ source: UnsafePointer<Float>?, count: Int) throws {
            guard let file, count > 0 else { return }
            let destination = scratch.floatChannelData![0]
            for i in 0..<count {
                let value = source?[i] ?? 0
                destination[i] = value.isFinite ? value : 0
                let bin = Int((Double(frames) + Double(i)) / rate / 0.02)
                while peaks.count <= bin { peaks.append(0) }
                peaks[bin] = max(peaks[bin], abs(destination[i]))
            }
            scratch.frameLength = AVAudioFrameCount(count)
            try file.write(from: scratch); frames += Int64(count)
        }
    }
    private let queue = DispatchQueue(label: "org.ciranda.recording", qos: .utility)
    private let input: Track
    private let output: Track
    // Pop storage is distinct from AVAudioPCMBuffer: gap filling must not overwrite a pending block.
    private let popBuffer = UnsafeMutablePointer<Float>.allocate(capacity: 1024)
    private var timer: DispatchSourceTimer?
    private var active = false
    private var shuttingDown = false
    private var stopTime: Double?
    private var origin = 0.0
    private var folder: URL?
    private var markers: [DebugMarker] = []
    private var diagnostics: [String] = []
    private var sessionInfo: [[String: Any]] = []
    private var metadata: [String: Any] = [:]
    private var state = DebugRecordingState()
    private var lastPublish = 0.0
    var onState: ((DebugRecordingState) -> Void)?

    init(inputRate: Double, outputRate: Double) throws {
        input = try Track(rate: inputRate); output = try Track(rate: outputRate)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(20))
        timer.setEventHandler { [weak self] in self?.drain() }
        self.timer = timer; timer.resume()
    }
    deinit { timer?.cancel(); popBuffer.deallocate() }
    func pushInput(_ buffer: AVAudioPCMBuffer, when: AVAudioTime, channel: Int) {
        push(buffer, when: when, channel: channel, track: input)
    }
    func pushOutput(_ buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        push(buffer, when: when, channel: 0, track: output)
    }
    private func push(_ buffer: AVAudioPCMBuffer, when: AVAudioTime, channel: Int, track: Track) {
        guard let data = buffer.floatChannelData, channel < Int(buffer.format.channelCount) else { return }
        let estimated = !when.isHostTimeValid
        let time = estimated ? monotonicNow() - Double(buffer.frameLength) / buffer.format.sampleRate
                             : AVAudioTime.seconds(forHostTime: when.hostTime)
        let pointer = buffer.format.isInterleaved ? data[0].advanced(by: channel) : data[channel]
        let stride: UInt32 = buffer.format.isInterleaved ? buffer.format.channelCount : 1
        cr_capture_push(track.mailbox, pointer, buffer.frameLength, stride, time, estimated ? 1 : 0)
    }
    func start(config: SessionConfig?, offset: Double, outputLatency: Double, route: LiveInputState) {
        let requestedAt = monotonicNow()
        queue.async {
            guard !self.active, !self.shuttingDown else { return }
            self.origin = requestedAt; self.stopTime = nil; self.markers = []; self.diagnostics = []; self.sessionInfo = []
            self.state = DebugRecordingState(recording: true)
            do {
                let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let folder = base.appendingPathComponent("Gravacoes", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                self.folder = folder
                try self.input.open(folder.appendingPathComponent("entrada-baixo.wav"))
                try self.output.open(folder.appendingPathComponent("saida-app-canal1.wav"))
                self.metadata = ["version": "0.4.2", "originHostSeconds": requestedAt,
                                 "inputPort": route.inputName, "inputChannel": route.analysisChannel + 1,
                                 "outputPort": route.outputName, "outputChannel": 1,
                                 "estimatedOutputLatencySeconds": outputLatency,
                                 "timeMeaning": "Common monotonic host time; output is rendered audio, not acoustic loudspeaker capture.",
                                 "waveformBinSeconds": 0.02,
                                 "inputDropsAtStart": cr_capture_dropped(self.input.mailbox),
                                 "outputDropsAtStart": cr_capture_dropped(self.output.mailbox)]
                self.active = true
                if let config { self.addSession(config, offset: offset, latency: outputLatency) }
                self.publish()
            } catch {
                self.input.file = nil; self.output.file = nil
                self.active = false; self.state.recording = false; self.state.error = error.localizedDescription; self.publish()
            }
        }
    }
    func sessionStarted(_ config: SessionConfig, offset: Double, latency: Double) {
        queue.async { if self.active { self.addSession(config, offset: offset, latency: latency) } }
    }
    private func addSession(_ config: SessionConfig, offset: Double, latency: Double) {
        let renderOrigin = config.start - offset - latency - origin
        sessionInfo.append(["id": config.id.uuidString, "bpm": config.bpm, "slotsPerBar": 16,
                            "renderOriginSeconds": renderOrigin, "clockOffsetSeconds": offset])
        let current = monotonicNow() - origin
        markers.removeAll { $0.kind == "beat" && $0.time > current }
        let first = max(0, Int(ceil(-renderOrigin / config.beat)))
        let last = Int(ceil((120 - renderOrigin) / config.beat))
        guard last >= first, last - first < 2000 else { return }
        for index in first...last {
            markers.append(DebugMarker(time: renderOrigin + Double(index) * config.beat,
                                       kind: "beat", label: index % 4 == 0 ? "Compasso \(index / 4 + 1)" : "Tempo \(index % 4 + 1)"))
        }
    }
    func noteScheduled(midi: Int, hostTime: Double) {
        queue.async {
            guard self.active else { return }
            self.markers.append(DebugMarker(time: hostTime - self.origin, kind: "note", label: "MIDI \(midi)"))
        }
    }
    func finish(logs: [String] = []) {
        let time = monotonicNow()
        queue.async { self.requestFinish(at: time, logs: logs) }
    }
    func shutdown() {
        let time = monotonicNow()
        queue.async {
            self.shuttingDown = true
            if self.active { self.requestFinish(at: time, logs: ["Captura encerrada: mudança de rota, desativação ou saída do app."]) }
            else { self.timer?.cancel(); self.timer = nil }
        }
    }
    private func requestFinish(at time: Double, logs: [String]) {
        guard active, stopTime == nil else { return }
        let renderedEnd = origin + max(Double(input.frames) / input.rate, Double(output.frames) / output.rate)
        stopTime = min(max(time, renderedEnd), origin + 120); diagnostics += logs
        state.recording = false; state.finalizing = true; publish()
        // Allow in-flight taps to deliver their final blocks. Missing data is explicit silence.
        queue.asyncAfter(deadline: .now() + .milliseconds(200)) { self.complete() }
    }
    private func drain() {
        do {
            try drain(input); try drain(output)
            if active && stopTime == nil && monotonicNow() >= origin + 120 { requestFinish(at: origin + 120, logs: ["Limite de 120 segundos atingido."]) }
            if active && monotonicNow() - lastPublish >= 0.2 { publish() }
        } catch {
            state.error = error.localizedDescription
            requestFinish(at: monotonicNow(), logs: ["Erro de escrita: " + error.localizedDescription])
        }
    }
    private func drain(_ track: Track) throws {
        while true {
            let block = cr_capture_pop(track.mailbox, popBuffer)
            guard block.frames > 0 else { return }
            guard active, track.file != nil else { continue }
            let end = stopTime ?? min(monotonicNow() + 0.1, origin + 120)
            let initialSkip = max(0, Int(ceil((origin - block.host_time) * track.rate)))
            let limit = min(Int(block.frames), Int(floor((end - block.host_time) * track.rate)))
            guard limit > initialSkip else { continue }
            var skip = initialSkip
            let target = Int64(((block.host_time - origin) * track.rate).rounded()) + Int64(skip)
            let gap = target - track.frames
            if gap > 2 { try pad(track, count: gap) }
            if gap < -2 { skip += Int(-gap); track.overlapFrames += -gap }
            guard limit > skip else { continue }
            track.estimatedTime = track.estimatedTime || block.estimated_time != 0
            try track.append(UnsafePointer(popBuffer.advanced(by: skip)), count: limit - skip)
        }
    }
    private func pad(_ track: Track, count: Int64) throws {
        // Files never grow beyond the explicit recording duration cap.
        var remaining = min(count, max(0, Int64(track.rate * 120) - track.frames))
        track.missingFrames += remaining
        while remaining > 0 {
            let n = Int(min(1024, remaining)); try track.append(nil, count: n); remaining -= Int64(n)
        }
    }
    private func complete() {
        guard active, let end = stopTime, let folder else { return }
        do {
            try drain(input); try drain(output)
            for track in [input, output] {
                try pad(track, count: max(0, Int64(((end - origin) * track.rate).rounded()) - track.frames))
                track.file = nil
            }
            metadata["durationSeconds"] = end - origin
            metadata["sessions"] = sessionInfo
            metadata["markers"] = markers.filter { $0.time >= 0 && $0.time <= end - origin }.map { ["time": $0.time, "kind": $0.kind, "label": $0.label] as [String: Any] }
            metadata["tracks"] = [input, output].map { t in
                ["file": t.url?.lastPathComponent ?? "", "sampleRate": t.rate, "frames": t.frames,
                 "silenceInsertedFrames": t.missingFrames, "overlapTrimmedFrames": t.overlapFrames,
                 "ringDroppedFramesTotal": cr_capture_dropped(t.mailbox), "usedEstimatedTimestamps": t.estimatedTime] as [String: Any]
            }
            metadata["diagnostics"] = diagnostics
            if let error = state.error { metadata["error"] = error }
            let metadataURL = folder.appendingPathComponent("sincronizacao.json")
            try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]).write(to: metadataURL)
            state.files = [input.url, output.url, metadataURL].compactMap { $0 }
        } catch { state.error = error.localizedDescription; input.file = nil; output.file = nil }
        active = false; state.recording = false; state.finalizing = false
        state.duration = end - origin; publish()
        if shuttingDown { timer?.cancel(); timer = nil }
    }
    private func publish() {
        lastPublish = monotonicNow()
        if active { state.duration = max(0, (stopTime ?? min(lastPublish, origin + 120)) - origin) }
        state.inputPeaks = input.peaks; state.outputPeaks = output.peaks
        state.markers = markers.filter { $0.time >= 0 && $0.time <= state.duration }
        state.gaps = Int(input.missingFrames + output.missingFrames)
        let copy = state
        DispatchQueue.main.async { self.onState?(copy) }
    }
}
