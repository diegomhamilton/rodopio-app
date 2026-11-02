import SwiftUI

enum AppDestination: String, CaseIterable {
    case session
    case tone
    case library

    static func initial(arguments: [String]) -> AppDestination {
        guard let flagIndex = arguments.firstIndex(of: "-initial-tab"),
              arguments.indices.contains(flagIndex + 1),
              let destination = AppDestination(rawValue: arguments[flagIndex + 1]) else {
            return .session
        }

        return destination
    }
}

struct AppShellView: View {
    @Environment(\.scenePhase) private var scenePhase
    let dependencies: AppDependencies
    private let initialTone: Bool
    @State private var selection: AppDestination
    @State private var sessionModel: SessionModel

    init(
        dependencies: AppDependencies,
        initialDestination: AppDestination = .initial(arguments: ProcessInfo.processInfo.arguments)
    ) {
        self.dependencies = dependencies
        initialTone = initialDestination == .tone
        _selection = State(initialValue: initialDestination == .tone ? .session : initialDestination)
        _sessionModel = State(initialValue: SessionModel(engine: dependencies.audioEngine, session: dependencies.audioSession, files: dependencies.audioFileStore, repository: dependencies.sessionRepository))
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                SessionView(model: sessionModel, toneController: dependencies.gainController, profileRepository: dependencies.profileRepository, showToneInitially: initialTone)
            }
            .tabItem {
                Label("Practice", systemImage: "waveform")
            }
            .tag(AppDestination.session)

            NavigationStack {
                LibraryView(sessionRepository: dependencies.sessionRepository, workspace: sessionModel)
            }
            .tabItem {
                Label("Recordings", systemImage: "music.note.list")
            }
            .tag(AppDestination.library)
        }
        .task { await sessionModel.observe() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Task { await sessionModel.stopPlayback() } }
        }
        .disabled(!sessionModel.isWorkspaceReady)
    }
}

#Preview {
    AppShellView(dependencies: .live())
}
