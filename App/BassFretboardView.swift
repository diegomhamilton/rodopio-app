import SwiftUI

/// Pitch alone cannot identify the string used: every compatible position is shown.
struct BassFretboardView: View {
    let detectedMIDI: Int?
    @State private var lastFret = 12
    private let openStrings = [28, 33, 38, 43] // E1 A1 D2 G2, low to high, left to right.
    private let accent = Color(red: 0.47, green: 0.91, blue: 0.74)
    private let names = ["Dó", "Dó♯", "Ré", "Ré♯", "Mi", "Fá", "Fá♯", "Sol", "Sol♯", "Lá", "Lá♯", "Si"]
    private func noteName(_ midi: Int) -> String { names[midi % 12] + String(midi / 12 - 1) }
    private var positions: [String] {
        guard let midi = detectedMIDI else { return [] }
        return openStrings.enumerated().compactMap { string, open in
            let fret = midi - open
            return (0...lastFret).contains(fret) ? "\(["Mi", "Lá", "Ré", "Sol"][string]), \(fret == 0 ? "solta" : "casa \(fret)")" : nil
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Braço do baixo").font(.headline)
                Spacer()
                Picker("Casas visíveis", selection: $lastFret) {
                    Text("12 casas").tag(12)
                    Text("24 casas").tag(24)
                }.pickerStyle(.menu).tint(accent)
            }
            Text("4 cordas · Mi1–Lá1–Ré2–Sol2 · pestana no topo")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 0) {
                Text("Casa").font(.caption2).frame(width: 38)
                ForEach(Array(openStrings.enumerated()), id: \.offset) { _, midi in
                    Text(noteName(midi)).font(.caption.bold()).frame(maxWidth: .infinity)
                }
            }
            VStack(spacing: 0) {
                ForEach(0...lastFret, id: \.self) { fret in
                    HStack(spacing: 0) {
                        Text(fret == 0 ? "Solta" : "\(fret)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle([3, 5, 7, 9, 12, 15, 17, 19, 21, 24].contains(fret) ? accent : .secondary)
                            .frame(width: 38)
                        ForEach(Array(openStrings.enumerated()), id: \.offset) { index, open in
                            let active = detectedMIDI == open + fret
                            ZStack {
                                Rectangle().fill(.white.opacity(0.45))
                                    .frame(width: CGFloat(4 - index) * 0.65 + 0.6)
                                if active {
                                    Text(noteName(open + fret)).font(.caption2.bold())
                                        .foregroundStyle(Color(red: 0.06, green: 0.13, blue: 0.19))
                                        .frame(width: 44, height: 30)
                                        .background(accent, in: Capsule())
                                } else if [3, 5, 7, 9, 12, 15, 17, 19, 21, 24].contains(fret) {
                                    Circle().fill(.white.opacity(0.12)).frame(width: fret % 12 == 0 ? 7 : 4)
                                }
                            }.frame(maxWidth: .infinity).frame(height: 38)
                                .accessibilityHidden(true)
                        }
                    }
                    .background(fret == 0 ? Color.white.opacity(0.08) : Color.brown.opacity(0.18))
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(.white.opacity(fret == 0 ? 0.65 : 0.2)).frame(height: fret == 0 ? 4 : 1)
                            .padding(.leading, 38)
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: 430).frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Braço vertical, cordas Mi, Lá, Ré e Sol da esquerda para a direita. " + positionDescription)
            Text(positionDescription).font(.subheadline).foregroundStyle(accent)
            Text("A nota capturada mantém a oitava original. As marcas mostram posições possíveis; o áudio não identifica qual corda ou casa foi tocada.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var positionDescription: String {
        guard let midi = detectedMIDI else { return "Toque uma nota isolada para ver suas posições no braço." }
        if positions.isEmpty { return "\(noteName(midi)): fora das \(lastFret) casas exibidas." }
        return "\(noteName(midi)): " + positions.joined(separator: " · ")
    }
}

struct InstrumentPanel: View {
    @ObservedObject var model: SessionModel
    @State private var showBass = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Instrumento visual", selection: $showBass) {
                Text("Baixo").tag(true)
                Text("Teclado").tag(false)
            }.pickerStyle(.segmented)
            if showBass {
                BassFretboardView(detectedMIDI: model.detectedMIDI)
            } else {
                Picker("Modo de tocar", selection: $model.composing) {
                    Text("Explorar sons").tag(false)
                    Text("Compor juntos").tag(true)
                }.pickerStyle(.segmented)
                Text(model.composing ? "Toque no ritmo. Sua nota entrará em um compasso futuro." : "Toque para ouvir. As notas aparecem na pauta em clave de Sol.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                PianoKeyboard(lastNote: model.lastNote, play: model.play).frame(height: 180)
                Text("Dó4 → Dó5 · 8 teclas naturais + 5 sustenidos")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
