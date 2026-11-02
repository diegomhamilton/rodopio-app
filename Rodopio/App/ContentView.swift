import SwiftUI

private let sea = Color(red: 0.06, green: 0.13, blue: 0.19)
private let mint = Color(red: 0.47, green: 0.91, blue: 0.74)

struct ContentView: View {
    @ObservedObject var model: SessionModel
    @State private var showDiagnostics = false
    @State private var logURL: URL?
    @State private var showInputSelection = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("RODOPIO").font(.caption.weight(.bold)).tracking(4).foregroundStyle(mint)
                        Text("Toda nota conta.").font(.largeTitle.bold())
                        Text("Uma música construída em conjunto.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "waveform.path").font(.largeTitle).foregroundStyle(mint)
                }
                roomCard
                bassInputCard
                AudioStreamingPanel(model: model)
                InstrumentPanel(model: model)
                if model.inputActive {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notas capturadas · 16 posições").font(.headline)
                        Text("Janela \(Int(model.bassAnalysisWindowMS)) ms · FFT + periodicidade").font(.caption)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 8), spacing: 5) {
                            ForEach(0..<16, id: \.self) { slot in
                                VStack {
                                    Text("\(slot + 1)").font(.caption2).foregroundStyle(.secondary)
                                    Text(model.bassSlotNotes[slot]).font(.caption2).lineLimit(1).minimumScaleFactor(0.6)
                                }.frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                            }
                        }
                        Text("Inicie a composição. Estimativas por posição, com atraso da análise; uma nota por vez.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                RecordingPanel(model: model)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(model.currentBar == 0 ? "Preparar" : "Compasso \(model.currentBar)", systemImage: "metronome")
                        Spacer()
                        Text("4/4 · \(Int(model.bpm)) BPM").monospacedDigit().foregroundStyle(.secondary)
                    }.font(.headline)
                    HStack(spacing: 12) {
                        ForEach(1...4, id: \.self) { beat in
                            VStack(spacing: 6) {
                                Circle().fill(model.currentBeat == beat ? mint : Color.white.opacity(0.1))
                                    .frame(width: model.currentBeat == beat ? 28 : 20, height: 28)
                                Text("\(beat)").font(.caption.monospacedDigit())
                            }.frame(maxWidth: .infinity)
                        }
                    }.accessibilityElement(children: .ignore)
                        .accessibilityLabel("Tempo \(model.currentBeat) de quatro")
                    HStack(spacing: 3) {
                        ForEach(0..<16, id: \.self) { slot in
                            Text(slot % 4 == 0 ? "\(slot / 4 + 1)" : ["", "e", "&", "a"][slot % 4])
                                .font(.caption2).frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(model.currentSlot == slot ? mint : Color.white.opacity(0.08))
                                .foregroundStyle(model.currentSlot == slot ? sea : .white)
                        }
                    }.accessibilityLabel("16 semicolcheias por compasso")
                    ScoreHistoryView(model: model)
                    DisclosureGroup("Reprodução coletiva · compasso atual") {
                        ScrollView(.horizontal) {
                            StaffView(midi: model.lastNote, events: model.shownEvents)
                                .frame(width: 760, height: 125)
                        }
                    }.font(.caption)
                    HStack {
                        Text("\(model.collected) contribuições").foregroundStyle(mint)
                        Spacer()
                        Text("\(model.pendingCount) aguardando").foregroundStyle(.secondary)
                    }.font(.caption)
                }.padding(18).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))

                Text(model.status).font(.callout).foregroundStyle(mint)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                DisclosureGroup("Laboratório de sincronização", isExpanded: $showDiagnostics) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Atraso artificial das contribuições: \(Int(model.lagMS)) ms")
                        Slider(value: $model.lagMS, in: 0...3000, step: 100).tint(mint)
                        Text("Só as mensagens de ação são atrasadas. O áudio continua no relógio local.")
                        Text(String(format: "RTT %.1f ms · diferença de relógio %.1f ms", model.rttMS, model.offsetMS))
                        Text("Compassos recebidos tarde: \(model.lateBars)")
                        Text(model.audioInfo)
                        Button("Preparar diagnóstico") { logURL = model.exportLog() }
                        if let logURL { ShareLink("Compartilhar diagnóstico", item: logURL) }
                        Text("Validação física pendente. A diferença entre relógios não é a diferença audível entre aparelhos.")
                            .foregroundStyle(.secondary)
                    }.font(.caption).padding(.top, 10)
                }.tint(mint)
                Text("PROTÓTIPO 0.5.0 · Música, encontro e cooperação")
                    .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.padding(22).frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
        }.background(sea.ignoresSafeArea())
            .sheet(isPresented: $showInputSelection) {
                InputSelectionView(options: model.liveInput.available,
                                   activeUID: model.liveInput.selectedUID,
                                   select: { uid in
                                       showInputSelection = false
                                       model.selectBassInput(uid)
                                   }, refresh: model.refreshInputOptions)
            }
    }
    private var bassInputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Baixo ao vivo", systemImage: "waveform").font(.headline)
            if !model.liveInput.available.isEmpty {
                Button {
                    model.refreshInputOptions()
                    showInputSelection = true
                } label: {
                    HStack {
                        Text("Escolher entrada")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }.frame(minHeight: 44)
                }.disabled(model.running || model.inputBusy)
                Text("Entrada ativa no iOS: " + (model.liveInput.inputName.isEmpty ? "Nenhuma" : model.liveInput.inputName))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.inputBusy {
                HStack {
                    ProgressView()
                    Text("Selecionando " + (model.liveInput.available.first(where: { $0.id == model.liveInput.requestedUID })?.name ?? "entrada") + "…")
                        .font(.subheadline)
                }
            }
            if let error = model.liveInput.error {
                Text(error).font(.callout).foregroundStyle(.orange)
            }
            if !model.inputActive {
                Text("Conecte sua interface USB e ative a entrada. O microfone também pode ser usado.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Ativar entrada de áudio", action: model.enableBassInput)
                    .buttonStyle(.bordered).disabled(model.running || model.inputBusy)
            } else {
                if model.liveInput.channels > 1 {
                    Picker("Canal analisado", selection: Binding(get: { model.liveInput.analysisChannel }, set: model.selectAnalysisChannel)) {
                        ForEach(0..<model.liveInput.channels, id: \.self) { channel in Text("Canal \(channel + 1)").tag(channel) }
                    }.disabled(model.running || model.inputBusy)
                }
                HStack {
                    Text("Nível de entrada")
                    Spacer()
                    Text(model.inputRMS <= -100 ? "Sem sinal" : String(format: "%.1f dBFS", model.inputRMS)).monospacedDigit()
                }.font(.caption)
                ProgressView(value: max(0, min(1, (model.inputRMS + 60) / 60)))
                    .tint(model.inputClipped ? .red : mint)
                    .accessibilityLabel("Nível de áudio")
                HStack {
                    Text(model.detectedNote).font(.title2.bold())
                    Text(model.detectedFrequency > 0 ? String(format: "%.1f Hz", model.detectedFrequency) : "Toque uma nota isolada")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if model.inputClipped { Text("CLIP").foregroundStyle(.red).font(.caption.bold()) }
                }
                Toggle("Ouvir o baixo", isOn: Binding(get: { model.liveInput.monitoring }, set: model.setInputMonitoring))
                    .tint(mint).disabled(!model.liveInput.canMonitor)
                if model.liveInput.monitoring {
                    HStack {
                        Text("Volume").font(.caption)
                        Slider(value: Binding(get: { model.monitorVolume }, set: model.updateMonitorVolume), in: 0...1).tint(mint)
                    }
                }
                Text("Saída: " + model.liveInput.outputName).font(.caption).foregroundStyle(.secondary)
                if !model.liveInput.canMonitor {
                    Text("Use fones com fio ou a saída da interface USB para ouvir o baixo pelo app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Usar notas do baixo na composição", isOn: $model.bassContributes).tint(mint)
                Text("Experimental: uma nota por vez, transposta para Dó4–Si4. As contribuições são notas sintetizadas. Ative “Transmitir áudio real” para enviar o timbre da entrada.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("O canal selecionado serve para análise. A monitoração reproduz os canais da interface.")
                    .font(.caption2).foregroundStyle(.secondary)
                Button("Desativar entrada", action: model.disableBassInput)
                    .font(.caption).disabled(model.running || model.inputBusy)
            }
            if model.running {
                Text("Encerre a composição para trocar a entrada de áudio.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(18).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
    }
    private var roomCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(model.role.rawValue, systemImage: "person.2.wave.2")
                Spacer()
                Text("\(model.peers.count + 1)/4 pessoas").font(.caption).foregroundStyle(.secondary)
            }
            if model.role == .solo {
                HStack {
                    Button("Criar sala", action: model.host)
                    Button("Entrar perto", action: model.join)
                }.buttonStyle(.bordered)
            } else {
                Text(model.peers.isEmpty ? "Aguardando outras pessoas…" : model.peers.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
                Button("Sair da sala", action: model.leave).font(.caption)
            }
            if model.role == .guest {
                Label(model.clockReady ? "Relógio pronto" : "Sincronizando relógio", systemImage: "clock")
                    .font(.caption).foregroundStyle(mint)
                Text("Entrada automática na primeira sala próxima. Use uma sala por ambiente neste protótipo.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Andamento").font(.caption)
                    Slider(value: $model.bpm, in: 60...160, step: 5).disabled(model.running)
                    Text("\(Int(model.bpm))").font(.caption.monospacedDigit())
                }.tint(mint)
                Button(action: { model.running ? model.stop() : model.start() }) {
                    Label(model.running ? "Encerrar composição" : "Começar em 3 segundos", systemImage: model.running ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(sea)
            }
        }.padding(18).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
    }
}

struct PianoKeyboard: View {
    let lastNote: Int
    let play: (Int) -> Void
    private let white = MusicalNote.all.filter { !$0.sharp }
    private let black: [(Int, Int)] = [(61,1),(63,2),(66,4),(68,5),(70,6)]
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width / 8
            ZStack(alignment: .topLeading) {
                HStack(spacing: 2) {
                    ForEach(white) { note in
                        Button { play(note.midi) } label: {
                            VStack {
                                Spacer()
                                Text(note.name).font(.system(size: 13, weight: .semibold))
                                Text(note.midi == 72 ? "5" : "4").font(.caption2).opacity(0.5)
                            }.foregroundStyle(sea).padding(.bottom, 14)
                                .frame(maxWidth: .infinity).frame(height: geometry.size.height)
                                .background(lastNote == note.midi ? mint : Color(red: 0.95, green: 0.96, blue: 0.92), in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).accessibilityLabel("\(note.name), oitava \(note.midi == 72 ? 5 : 4)")
                    }
                }
                ForEach(black, id: \.0) { midi, boundary in
                    Button { play(midi) } label: {
                        VStack {
                            Spacer()
                            Text(MusicalNote.all[midi - 60].name).font(.system(size: 10, weight: .bold))
                        }.padding(.bottom, 12).frame(width: width * 0.64, height: geometry.size.height * 0.60)
                            .background(lastNote == midi ? Color.teal : Color(red: 0.10, green: 0.19, blue: 0.25), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.white)
                    }.buttonStyle(.plain).offset(x: width * CGFloat(boundary) - width * 0.32)
                        .accessibilityLabel("\(MusicalNote.all[midi - 60].name), oitava 4")
                }
            }
        }
    }
}

struct StaffView: View {
    let midi: Int
    let events: [NoteEvent]
    private func step(_ midi: Int) -> Int { [0,0,1,1,2,3,3,4,4,5,5,6,7][max(0,min(12,midi-60))] }
    var body: some View {
        Canvas { context, size in
            let left = 42.0, bottom = 80.0, gap = 12.0
            for line in 0..<5 {
                var p = Path(); let y = bottom - Double(line) * gap
                p.move(to: CGPoint(x: left, y: y)); p.addLine(to: CGPoint(x: size.width - 8, y: y))
                context.stroke(p, with: .color(.white.opacity(0.25)), lineWidth: 1)
            }
            context.draw(Text("𝄞").font(.system(size: 54)).foregroundColor(.white), at: CGPoint(x: 21, y: 60))
            let notes = events
            for event in notes {
                let x = left + 24 + Double(event.slot) * max(12, (size.width - left - 48) / 16)
                let y = bottom + gap - Double(step(event.midi)) * gap / 2
                if step(event.midi) == 0 {
                    var ledger = Path(); ledger.move(to: CGPoint(x: x-12, y: y)); ledger.addLine(to: CGPoint(x:x+12,y:y))
                    context.stroke(ledger, with: .color(.white.opacity(0.7)), lineWidth: 1)
                }
                context.fill(Path(ellipseIn: CGRect(x: x-7, y: y-4, width: 14, height: 9)), with: .color(mint))
                var stem = Path(); stem.move(to: CGPoint(x:x+6,y:y)); stem.addLine(to:CGPoint(x:x+6,y:y-28))
                context.stroke(stem, with:.color(mint),lineWidth:1.5)
                // Double flag: sixteenth notes in 4/4.
                var flag = Path(); flag.move(to: CGPoint(x:x+6,y:y-28)); flag.addQuadCurve(to: CGPoint(x:x+12,y:y-15), control: CGPoint(x:x+23,y:y-23))
                context.stroke(flag, with:.color(mint),lineWidth:2)
                context.stroke(flag.offsetBy(dx: 0, dy: 6), with:.color(mint),lineWidth:2)
                if [61,63,66,68,70].contains(event.midi) {
                    context.draw(Text("♯").font(.system(size: 19)).foregroundColor(mint), at:CGPoint(x:x-17,y:y))
                }
            }
        }.accessibilityLabel("Pauta em clave de Sol. Nota selecionada: \(MusicalNote.all[max(0,min(12,midi-60))].name)")
    }
}


/// Explicit buttons close the sheet before beginning a route change. Their state is
/// independent of the live meter; selection is not a binding to an asynchronous route.
private struct InputSelectionView: View {
    let options: [AudioInputOption]
    let activeUID: String
    let select: (String) -> Void
    let refresh: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Entradas reconhecidas pelo iOS") {
                    ForEach(options) { input in
                        Button {
                            select(input.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(input.name)
                                    if input.usb { Text("Interface USB").font(.caption).foregroundStyle(.secondary) }
                                    if input.bluetooth { Text("Entrada Bluetooth").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                if input.id == activeUID { Image(systemName: "checkmark").accessibilityLabel("Ativa no iOS") }
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.accessibilityIdentifier("input-" + input.id)
                    }
                    if options.isEmpty { Text("Nenhuma entrada disponível. Conecte a interface e atualize.") }
                }
                Section {
                    Text("Para um microfone Bluetooth aparecer, conecte o acessório nos Ajustes do iOS e ative a entrada no app. Dispositivos que oferecem apenas saída de som ou MIDI não são entradas de áudio. Bluetooth pode aumentar o atraso e alterar a qualidade do som.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Atualizar entradas", action: refresh)
            }
            .navigationTitle("Entrada de áudio")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fechar") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}
