import SwiftUI

struct LibraryView: View {
    let sessionRepository: any SessionRepository
    let workspace: SessionModel

    var body: some View {
        List {
            Section(workspace.sessionName) {
                if workspace.recordings.isEmpty {
                    Text("No recordings in this session. Record a phrase on Practice.").foregroundStyle(.secondary)
                }
                ForEach(workspace.recordings.sorted { $0.createdAt > $1.createdAt }) { recording in
                    RecordingRow(recording: recording, model: workspace)
                }
            }
            Section {
                NavigationLink {
                    AudioSettingsView(model: workspace)
                } label: {
                    Label(workspace.state == .stopped ? "Output not yet confirmed" : workspace.route.outputDescription, systemImage: "speaker.wave.2")
                }
                PlaybackNotice(model: workspace)
                WorkspaceNotices(model: workspace)
            }
        }
        .navigationTitle("Recordings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Sessions") { SessionLibraryView(sessionRepository: sessionRepository, workspace: workspace) }
            }
        }
    }
}

struct SessionLibraryView: View {
    let sessionRepository: any SessionRepository
    let workspace: SessionModel
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [PracticeSession] = []
    @State private var failure: String?
    @State private var renaming: PracticeSession?
    @State private var name = ""
    @State private var deleting: PracticeSession?

    var body: some View {
        List {
            if let failure { Text(failure).foregroundStyle(.red) }
            if let notice = workspace.storageNotice { Text(notice).foregroundStyle(.secondary) }
            Button("New Session", systemImage: "plus") {
                Task {
                    await workspace.newSession()
                    await reload()
                    if workspace.errorMessage == nil { dismiss() }
                }
            }.disabled(workspace.isBusy || workspace.isRecording)
            if workspace.isRecording { Text("Finish recording before changing sessions.").foregroundStyle(.secondary) }
            ForEach(sessions) { session in
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.name).font(.headline)
                    Text("\(session.recordings.count) recordings · \(session.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                    if let notice = session.recoveryNotice { Text(notice).font(.caption) }
                    HStack {
                        Button(session.id == workspace.practiceSessionID ? "Current Session" : "Open") {
                            Task {
                                await workspace.openSession(id: session.id)
                                await reload()
                                if workspace.practiceSessionID == session.id && workspace.errorMessage == nil { dismiss() }
                            }
                        }.disabled(session.id == workspace.practiceSessionID)
                        Spacer()
                        Button("Rename") { name = session.name; renaming = session }
                        Button("Delete", role: .destructive) { deleting = session }
                    }.buttonStyle(.borderless).disabled(workspace.isBusy || workspace.isRecording)
                }.padding(.vertical, 4)
            }
            if sessions.isEmpty && failure == nil { Text("Your saved practice sessions appear here.").foregroundStyle(.secondary) }
            if let error = workspace.errorMessage { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Sessions")
        .task(id: workspace.lastSavedAt) { await reload() }
        .refreshable { await reload() }
        .sheet(item: $renaming) { session in
            NavigationStack {
                Form { TextField("Session name", text: $name) }
                    .navigationTitle("Rename Session")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { renaming = nil } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                Task { await workspace.renameSession(id: session.id, name: name); renaming = nil; await reload() }
                            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
            }
        }
        .confirmationDialog("Delete this session and its recordings?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            if let session = deleting {
                Button("Delete \(session.name)", role: .destructive) {
                    Task { await workspace.deleteSession(id: session.id); deleting = nil; await reload() }
                }
            }
        }
    }

    private func reload() async {
        do {
            let stored = try await sessionRepository.sessions()
            guard !Task.isCancelled else { return }
            sessions = stored
            failure = nil
        }
        catch { failure = "Could not load saved sessions: \(error)" }
    }
}
