import SwiftUI

struct RecordingPanel: View {
    @ObservedObject var model: SessionModel
    @State private var follow = true
    @State private var position = 0.0
    @State private var window = 4.0
    @State private var preparingExport = false
    @State private var exportMessage: String?
    @State private var exportError: String?
    @State private var share: RecordingShare?
    @State private var exportTask: Task<Void, Never>?

    private var state: DebugRecordingState { model.recording }
    private var start: Double { follow ? max(0, state.duration - window) : min(position, max(0, state.duration - window)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Gravação · sincronização", systemImage: "record.circle").font(.headline)
            HStack {
                if state.recording {
                    Button("Parar gravação", action: model.stopRecording).tint(.red)
                } else {
                    Button("Gravar áudio", action: model.startRecording)
                        .disabled(!model.inputActive || model.inputBusy || state.finalizing || preparingExport || share != nil)
                }
                Spacer()
                Text(String(format: "%.1f / 120 s", state.duration)).monospacedDigit()
            }.buttonStyle(.bordered)
            if state.finalizing { ProgressView("Salvando áudio…") }
            if !model.inputActive { Text("Ative a entrada de áudio para gravar.").font(.caption) }
            if state.duration > 0 {
                waveform(state.inputPeaks, title: "Entrada · canal selecionado", color: .mint)
                waveform(state.outputPeaks, title: "Saída do app · canal 1", color: .orange)
                HStack {
                    Text(String(format: "%.2f s", start))
                    Spacer()
                    Text(String(format: "%.2f s", start + window))
                }.font(.caption.monospacedDigit())
                Picker("Janela", selection: $window) {
                    Text("1 s").tag(1.0); Text("4 s").tag(4.0); Text("8 s").tag(8.0)
                }.pickerStyle(.segmented)
                Toggle("Acompanhar ao vivo", isOn: $follow)
                if !follow && state.duration > window {
                    Slider(value: $position, in: 0...max(0.01, state.duration - window))
                }
                Text("Linhas claras: tempos. Laranja: notas agendadas. As duas pistas usam o mesmo relógio; a saída representa o áudio renderizado.").font(.caption).foregroundStyle(.secondary)
                if state.gaps > 0 { Text("Lacunas preenchidas com silêncio: \(state.gaps) amostras. Consulte o JSON.").font(.caption) }
            }
            if !state.files.isEmpty {
                Button(action: exportRecording) {
                    HStack {
                        if preparingExport { ProgressView() }
                        Label(preparingExport ? "Preparando exportação…" : "Exportar WAVs + timestamps", systemImage: "square.and.arrow.up")
                    }
                }.disabled(preparingExport || state.finalizing || state.recording || share != nil)
                if preparingExport {
                    Text("Preparando os arquivos para compartilhar. O áudio continua funcionando.").font(.caption).foregroundStyle(.secondary)
                }
                if let exportMessage { Text(exportMessage).font(.caption).foregroundStyle(.secondary) }
                if let exportError { Text(exportError).font(.caption).foregroundStyle(.red) }
            }
            if let error = state.error { Text(error).foregroundStyle(.red).font(.caption) }
        }.padding(18).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
        .sheet(item: $share) { item in
            RecordingShareSheet(files: item.files) { completed, error in
                exportError = error
                exportMessage = error == nil ? (completed ? "Compartilhamento concluído." : "Compartilhamento cancelado.") : nil
                share = nil
            }
        }
        .onDisappear { exportTask?.cancel(); exportTask = nil }
    }
    @MainActor private func exportRecording() {
        guard !preparingExport, share == nil, !state.files.isEmpty else { return }
        let files = state.files, recordingID = state.id
        preparingExport = true; exportError = nil; exportMessage = nil
        exportTask = Task { @MainActor in
            defer { preparingExport = false; exportTask = nil }
            do {
                let prepared = try await RecordingExport.prepare(files: files, recordingID: recordingID)
                try Task.checkCancellation()
                share = RecordingShare(files: prepared)
            } catch is CancellationError {
                exportMessage = "Preparação cancelada."
            } catch {
                exportError = "Não foi possível preparar a exportação: " + error.localizedDescription
            }
        }
    }
    private func waveform(_ peaks: [Float], title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption)
            Canvas { context, size in
                let middle = size.height / 2
                var path = Path()
                let first = max(0, Int(start / 0.02))
                let last = min(peaks.count, Int((start + window) / 0.02) + 1)
                if last > first {
                    for index in first..<last {
                        let x = (Double(index) * 0.02 - start) / window * size.width
                        let amplitude = CGFloat(min(1, peaks[index])) * middle
                        path.move(to: CGPoint(x: x, y: middle - amplitude))
                        path.addLine(to: CGPoint(x: x, y: middle + amplitude))
                    }
                }
                context.stroke(path, with: .color(color), lineWidth: max(1, size.width * 0.02 / window))
                for marker in state.markers where marker.time >= start && marker.time <= start + window {
                    let x = (marker.time - start) / window * size.width
                    var line = Path(); line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(line, with: .color(marker.kind == "beat" ? .white.opacity(0.4) : .orange.opacity(0.7)), lineWidth: 1)
                }
            }.frame(height: 70).clipped().background(.black.opacity(0.2))
        }
    }
}
