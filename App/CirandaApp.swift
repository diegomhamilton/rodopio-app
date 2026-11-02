import SwiftUI

@main
struct CirandaApp: App {
    @StateObject private var model = SessionModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .preferredColorScheme(.dark)
                .onChange(of: phase) { _, value in
                    // Prototype has no background session / host migration.
                    if value == .background { model.leave() }
                }
        }
    }
}
