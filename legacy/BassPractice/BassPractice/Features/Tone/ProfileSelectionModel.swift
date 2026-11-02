import Foundation
import Observation

@MainActor @Observable
final class ProfileSelectionModel {
    private let controller: any AudioToneControlling
    private let repository: any InputProfileRepository
    private(set) var profiles = BuiltInInputProfiles.profiles
    private(set) var selectedID: UUID?
    private(set) var isBusy = false
    private(set) var errorMessage: String?

    init(controller: any AudioToneControlling, repository: any InputProfileRepository) {
        self.controller = controller
        self.repository = repository
    }

    func refresh() async {
        do { profiles = BuiltInInputProfiles.profiles + (try await repository.profiles()) }
        catch { errorMessage = "Custom profiles could not be loaded. Stored data was left unchanged." }
        await refreshSelection()
    }

    func refreshSelection() async {
        let current = await controller.selectedProfileID
        selectedID = profiles.contains(where: { $0.id == current }) ? current : nil
    }

    func select(_ id: UUID?) async {
        guard !isBusy, let id, let profile = profiles.first(where: { $0.id == id }) else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do { try await controller.applyProfile(profile) }
        catch { errorMessage = "Could not apply this profile to the current audio route. The previous tone was retained." }
        selectedID = await controller.selectedProfileID
    }

    func saveCurrent(name: String) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            let profile = try await controller.profileSnapshot(name: name)
            try await repository.save(profile)
            await refresh()
        } catch { errorMessage = "Could not save this profile. Enter a name and check profile storage." }
    }

    func delete(_ id: UUID) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do { try await repository.delete(id: id); await refresh() }
        catch { errorMessage = "Could not delete this profile. Stored data was left unchanged." }
    }
}
