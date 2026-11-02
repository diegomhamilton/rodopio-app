import SwiftUI

struct AudioStreamingPanel: View {
    @ObservedObject var model: SessionModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Áudio real entre aparelhos", systemImage: "antenna.radiowaves.left.and.right").font(.headline)
            Picker("Transporte", selection: Binding(get: { model.transportBackend }, set: model.selectTransportBackend)) {
                ForEach(TransportBackend.allCases) { backend in Text(backend.rawValue).tag(backend) }
            }.pickerStyle(.segmented).disabled(model.role != .solo || model.running || model.inputBusy)
            Text("Selecione o mesmo transporte nos dois aparelhos antes de criar/entrar na sala.")
                .font(.caption2).foregroundStyle(.secondary)
            if model.transportBackend == .network {
                Text("Network UDP experimental: áudio sem criptografia ou autenticação. Use uma rede local confiável para este teste.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Toggle("Transmitir áudio real", isOn: Binding(get: { model.transmittingAudio }, set: model.setAudioTransmission))
                .disabled(!model.inputActive || model.role == .solo || model.inputBusy)
            Text("Crie ou entre numa sala, ative a entrada e transmita. O outro aparelho recebe o som original do canal selecionado, sem precisar iniciar uma composição.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Use fones com fio nos dois aparelhos para evitar realimentação. Só a entrada local é enviada; o áudio recebido nunca é retransmitido.")
                .font(.caption).foregroundStyle(.secondary)
            if model.remoteAudioTracks.isEmpty {
                Text("Aguardando áudio de um aparelho conectado…").font(.caption)
            }
            ForEach(model.remoteAudioTracks) { track in
                VStack(alignment: .leading, spacing: 7) {
                    Text(track.name).font(.subheadline.bold())
                    ProgressView(value: min(1, track.peak)).accessibilityLabel("Pico da entrada remota")
                    Toggle("Silenciar", isOn: Binding(get: { track.muted }, set: { model.setRemoteAudioMuted(track.id, muted: $0) }))
                    HStack {
                        Text("Volume").font(.caption)
                        Slider(value: Binding(get: { Double(track.volume) }, set: { model.setRemoteAudioVolume(track.id, volume: Float($0)) }), in: 0...1)
                    }
                    Text(String(format: "%llu pacotes · %llu lacunas · %llu descartes · jitter %.1f ms · fila %.1f ms", track.received, track.missing, track.late, track.jitterMS, track.bufferedMS))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }.padding(10).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            }
            ForEach(Array(model.transportMetrics.enumerated()), id: \.offset) { _, metric in
                Text(String(format: "%@ · %@ · %d RTTs · mediana %.1f ms · p95 %.1f ms · variação %.1f ms · %llu lacunas de áudio · %llu reenvios de controle", metric.transport, metric.peer, metric.roundTrips, metric.rttMedianMS, metric.rttP95MS, metric.rttVariationMS, metric.audioMissing, metric.controlRetries))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text("Experimental · PCM mono · teste inicial entre anfitrião e participante. Jitter e fila não medem a latência acústica total.")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(18).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
    }
}
