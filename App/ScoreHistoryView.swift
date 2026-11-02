import SwiftUI

struct ScoreHistoryView: View {
    @ObservedObject var model: SessionModel
    @State private var follow = true
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("O que você tocou").font(.headline)
                Spacer()
                Button("Limpar", action: model.clearScore).font(.caption)
                    .disabled(model.scoreHistory.bars.isEmpty)
            }
            Text("Registro local · últimas 32 pautas · mantido ao parar").font(.caption).foregroundStyle(.secondary)
            if model.scoreHistory.bars.isEmpty {
                Text("Toque no teclado ou no baixo para começar a registrar.")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 20)
            } else {
                Toggle("Acompanhar novos compassos", isOn: $follow).font(.caption)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 16) {
                            ForEach(model.scoreHistory.bars) { bar in
                                VStack(alignment: .leading) {
                                    Text("Trecho \(String(bar.take.uuidString.prefix(4))) · compasso \(bar.index + 1)")
                                        .font(.caption).foregroundStyle(.secondary)
                                    StaffView(midi: model.lastNote, events: bar.events)
                                        .frame(width: 760, height: 125)
                                }.id(bar.id)
                            }
                        }
                    }
                    .onChange(of: model.scoreHistory.bars.last?.id) { _, id in
                        if follow, let id { proxy.scrollTo(id, anchor: .leading) }
                    }
                    .onChange(of: follow) { _, enabled in
                        if enabled, let id = model.scoreHistory.bars.last?.id { proxy.scrollTo(id, anchor: .leading) }
                    }
                    .onAppear {
                        if follow, let id = model.scoreHistory.bars.last?.id { proxy.scrollTo(id, anchor: .leading) }
                    }
                }
            }
            Text("Baixo transposto para Dó4–Dó5. Posições em semicolcheias; duração e ligaduras ainda não são transcritas. Histórico disponível enquanto o app estiver aberto.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
