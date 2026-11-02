import Foundation
import SwiftUI
import UIKit
import LinkPresentation
import UniformTypeIdentifiers

struct RecordingShare: Identifiable {
    let id = UUID()
    let files: [URL]
}

enum RecordingExport {
    /// File inspection and copying never run on the UI or realtime audio thread.
    static func prepare(files: [URL], recordingID: UUID) async throws -> [URL] {
        let worker = Task.detached(priority: .userInitiated) { () throws -> [URL] in
            guard !files.isEmpty else { throw CocoaError(.fileNoSuchFile) }
            let manager = FileManager.default
            let folder = manager.temporaryDirectory.appendingPathComponent("CirandaExport", isDirectory: true)
                .appendingPathComponent(recordingID.uuidString, isDirectory: true)
            let destinations = files.map { folder.appendingPathComponent($0.lastPathComponent) }
            try Task.checkCancellation()
            if destinations.allSatisfy({ manager.fileExists(atPath: $0.path) }) { return destinations }
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            do {
                for (source, target) in zip(files, destinations) {
                    try Task.checkCancellation()
                    guard source.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
                    if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }
                    try manager.copyItem(at: source, to: target)
                }
                try Task.checkCancellation()
                return destinations
            } catch {
                // Only this recording's temporary export copies are removed.
                try? manager.removeItem(at: folder)
                throw error
            }
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
}

/// Supply cheap metadata explicitly instead of eagerly generating audio previews.
private final class AudioFileShareItem: NSObject, UIActivityItemSource {
    let url: URL
    init(_ url: URL) { self.url = url }
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { url }
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { url }
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.data.identifier
    }
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata(); metadata.title = url.lastPathComponent
        return metadata
    }
}

struct RecordingShareSheet: UIViewControllerRepresentable {
    let files: [URL]
    let completion: (Bool, String?) -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: files.map { AudioFileShareItem($0) }, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            DispatchQueue.main.async { completion(completed, error?.localizedDescription) }
        }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
