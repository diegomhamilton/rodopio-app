import SwiftUI

struct ToneView: View {
    @State private var model: ToneModel
    @State private var profiles: ProfileSelectionModel
    @State private var profileName = ""

    init(controller: any AudioToneControlling, profileRepository: any InputProfileRepository) {
        _model = State(initialValue: ToneModel(controller: controller))
        _profiles = State(initialValue: ProfileSelectionModel(controller: controller, repository: profileRepository))
    }

    var body: some View {
        Form {
            Section("Instrument Profile") { ProfilePicker(model: profiles) }
            GainSection(title: "Input Gain", configuration: model.input, isBusy: model.isBusy) {
                await model.update($0, stage: .input)
                return model.input
            }
            GainSection(title: "Output Gain", configuration: model.output, isBusy: model.isBusy) {
                await model.update($0, stage: .output)
                return model.output
            }
            Section("Parametric EQ") {
                Toggle("Bypass EQ", isOn: Binding(
                    get: { model.equalizer.bypassed },
                    set: { value in Task { await model.updateEqualizer(EQConfiguration(bands: model.equalizer.bands, bypassed: value)) } }
                ))
                ForEach(Array(model.equalizer.bands.enumerated()), id: \.offset) { index, band in
                    EQBandEditor(index: index, band: band, isBusy: model.isBusy) { replacement in
                        var bands = model.equalizer.bands
                        guard bands.indices.contains(index) else { return }
                        if let replacement { bands[index] = replacement } else { bands.remove(at: index) }
                        await model.updateEqualizer(EQConfiguration(bands: bands, bypassed: model.equalizer.bypassed))
                    }
                }
                Button("Add Band") {
                    Task {
                        await model.updateEqualizer(EQConfiguration(bands: model.equalizer.bands + [EQDefaults.newBand], bypassed: model.equalizer.bypassed))
                    }
                }.disabled(model.equalizer.bands.count >= NativeEQLimits.maximumBands)
            }.disabled(model.isBusy)
            Section("Custom Profiles") {
                TextField("Profile name", text: $profileName)
                Button("Save Current Tone") { Task { await profiles.saveCurrent(name: profileName) } }
                    .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                ForEach(profiles.profiles.filter { $0.instrument == .custom && $0.id != BuiltInInputProfiles.customID }) { profile in
                    HStack {
                        Text(profile.name)
                        Spacer()
                        Button("Delete", role: .destructive) { Task { await profiles.delete(profile.id) } }
                    }
                }
            }.disabled(profiles.isBusy || model.isBusy)
            Section {
                Text("Start audio and enable Live Monitoring in Session to hear your instrument.")
                    .foregroundStyle(.secondary)
            }
            if let error = model.errorMessage {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Tone")
        .disabled(profiles.isBusy || model.isBusy)
        .task { await profiles.refresh(); await model.refresh() }
        .onChange(of: profiles.selectedID) { _, _ in Task { await model.refresh() } }
        .onChange(of: model.input) { _, _ in Task { await profiles.refreshSelection() } }
        .onChange(of: model.equalizer) { _, _ in Task { await profiles.refreshSelection() } }
    }

}

private struct GainSection: View {
    let title: String
    let configuration: GainConfiguration
    let isBusy: Bool
    let update: (GainConfiguration) async -> GainConfiguration
    @State private var draftDecibels: Double

    init(title: String, configuration: GainConfiguration, isBusy: Bool, update: @escaping (GainConfiguration) async -> GainConfiguration) {
        self.title = title
        self.configuration = configuration
        self.isBusy = isBusy
        self.update = update
        _draftDecibels = State(initialValue: Double(configuration.decibels))
    }

    var body: some View {
        Section(title) {
            LabeledContent("Gain", value: String(format: "%.1f dB", draftDecibels))
            Slider(value: $draftDecibels, in: -24...24, step: 0.5) { editing in
                if !editing {
                    Task {
                        let committed = await update(GainConfiguration(decibels: Float(draftDecibels), bypassed: configuration.bypassed))
                        draftDecibels = Double(committed.decibels)
                    }
                }
            }
            .accessibilityLabel(title)
            Toggle("Bypass", isOn: Binding(
                get: { configuration.bypassed },
                set: { value in
                    Task { _ = await update(GainConfiguration(decibels: configuration.decibels, bypassed: value)) }
                }
            ))
        }
        .disabled(isBusy)
        .onChange(of: configuration.decibels) { _, value in draftDecibels = Double(value) }
    }
}
