import SwiftUI

struct ProfilePicker: View {
    let model: ProfileSelectionModel
    var body: some View {
        Picker("Instrument", selection: Binding(
            get: { model.selectedID },
            set: { id in Task { await model.select(id) } }
        )) {
            Text("Edited tone").tag(UUID?.none)
            ForEach(model.profiles) { Text($0.name).tag(Optional($0.id)) }
        }.disabled(model.isBusy)
        if let error = model.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
    }
}
