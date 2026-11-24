import SwiftUI
import UniformTypeIdentifiers

/// What an OPML import did, for a report: added, not added with the reason, or why it failed.
struct ImportReport: Identifiable {
    let id = UUID()
    var added = 0
    var skipped: [(title: String, address: String, reason: String)] = []
    var error: String?
    /// The errors as text for the clipboard.
    var errorReport: String?

    init(result: FeedSubscriber.ImportResult) {
        added = result.added.count
        skipped = result.skipped.map { ($0.entry.title, $0.entry.feedURL, $0.failure.message) }
        errorReport = result.errorReport
    }

    init(error: String) {
        self.error = error
        errorReport = error
    }

    /// The file types offered for OPML import and export.
    static let opmlTypes: [UTType] = [UTType(filenameExtension: "opml") ?? .xml, .xml]

    /// Imports the feeds of an OPML file the user picked (its URL may be security-scoped).
    @MainActor
    static func importing(from url: URL, into model: AppModel) async -> ImportReport {
        let data: Data
        do {
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access { url.stopAccessingSecurityScopedResource() }
            }
            data = try Data(contentsOf: url)
        } catch {
            return ImportReport(error: error.localizedDescription)
        }
        do {
            return ImportReport(result: try await model.importOPML(data))
        } catch {
            return ImportReport(error: "This isn't an OPML file.")
        }
    }

    /// The title of the import's outcome.
    var summary: String {
        error ?? (added == 1 ? "Added 1 feed." : "Added \(added) feeds.")
    }
}

/// A feed of an OPML file that wasn't added, with the reason.
struct SkippedFeedRow: View {
    let item: (title: String, address: String, reason: String)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title).fontWeight(.medium)
            Text(item.address).font(.caption).foregroundStyle(.secondary)
            Text(item.reason).font(.caption).foregroundStyle(.orange)
        }
    }
}
