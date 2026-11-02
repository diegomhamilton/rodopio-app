import SwiftUI

struct EQBandEditor: View {
    let index: Int
    let band: EQBand
    let isBusy: Bool
    let update: (EQBand?) async -> Void
    @State private var frequency: Float
    @State private var gain: Float
    @State private var q: Float
    @State private var enabled: Bool
    @State private var errorMessage: String?

    init(index: Int, band: EQBand, isBusy: Bool, update: @escaping (EQBand?) async -> Void) {
        self.index = index
        self.band = band
        self.isBusy = isBusy
        self.update = update
        _frequency = State(initialValue: band.frequencyHertz)
        _gain = State(initialValue: band.gainDecibels)
        _q = State(initialValue: band.q)
        _enabled = State(initialValue: band.enabled)
    }

    var body: some View {
        DisclosureGroup("Band \(index + 1) · \(Int(band.frequencyHertz)) Hz · \(String(format: "%+.1f", band.gainDecibels)) dB") {
            LabeledContent("Frequency (Hz)") { TextField("Hz", value: $frequency, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            LabeledContent("Gain (dB)") { TextField("dB", value: $gain, format: .number).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing) }
            LabeledContent("Q") { TextField("Q", value: $q, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            Toggle("Enabled", isOn: $enabled)
            Button("Apply Band") {
                Task {
                    do {
                        let replacement = try EQBand(frequencyHertz: frequency, gainDecibels: gain, q: q, enabled: enabled)
                        errorMessage = nil
                        await update(replacement)
                    } catch { errorMessage = "Enter finite values, with positive frequency and Q." }
                }
            }
            Button("Remove Band", role: .destructive) { Task { await update(nil) } }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .disabled(isBusy)
        .onChange(of: band) { _, value in
            frequency = value.frequencyHertz; gain = value.gainDecibels; q = value.q; enabled = value.enabled
        }
    }
}
