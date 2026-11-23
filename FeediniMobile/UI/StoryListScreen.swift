import SwiftUI

/// The stories and articles of All, newest first.
struct StoryListScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(ReadingSession.self) private var session

    var body: some View {
        List(session.entries) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.headline)
                    .foregroundStyle(entry.isRead ? .secondary : .primary)
                Text(source(of: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .overlay {
            if model.isLoaded && session.entries.isEmpty {
                ContentUnavailableView(
                    "No Articles", systemImage: "dot.radiowaves.up.forward",
                    description: Text("Feeds added on this iPhone will show here."))
            }
        }
        .refreshable { model.refreshNow() }
        .navigationTitle("All")
    }

    private func source(of entry: StoryEntry) -> String {
        let sources = entry.sourceArticles.map { model.library.sourceTitle(of: $0) }
        let count = entry.articles.count
        return ([count > 1 ? "\(count) articles" : nil] + sources).compactMap { $0 }.joined(separator: " · ")
    }
}
