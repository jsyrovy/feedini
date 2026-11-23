import SwiftUI

/// Removing feeds or deleting a folder, confirmed first (the sidebar, Settings → Feeds): what the dialog says.
enum Removal: Hashable, Identifiable {
    case feeds(Set<Feed.ID>)
    case folder(Folder.ID)

    var id: Self { self }

    var action: String {
        switch self {
        case .feeds: "Remove"
        case .folder: "Delete"
        }
    }

    func title(in library: Library) -> String {
        switch self {
        case .feeds(let ids) where ids.count == 1:
            "Remove “\(ids.first.flatMap(library.feed)?.title ?? "")”?"
        case .feeds(let ids):
            "Remove \(ids.count) feeds?"
        case .folder(let id):
            "Delete the folder “\(library.folder(id)?.name ?? "")”?"
        }
    }

    func message(in library: Library) -> String {
        switch self {
        case .feeds(let ids):
            let articles = ids.count == 1 ? "Its articles" : "Their articles"
            return switch library.savedArticleCount(of: ids) {
            case 0: "\(articles) are removed too."
            case 1: "\(articles) are removed too, except 1 saved article, which stays in Saved."
            case let count: "\(articles) are removed too, except \(count) saved articles, which stay in Saved."
            }
        case .folder(let id):
            return switch library.feeds.count(where: { $0.folderID == id }) {
            case 0: "It has no feeds."
            case 1: "Its feed stays, in no folder."
            case let count: "Its \(count) feeds stay, in no folder."
            }
        }
    }
}

extension View {
    /// Asks before removing feeds or deleting a folder, then does it and calls `onRemove`.
    func removalConfirmation(
        _ removal: Binding<Removal?>, model: AppModel, onRemove: @escaping () -> Void = {}
    ) -> some View {
        confirmationDialog(
            removal.wrappedValue?.title(in: model.library) ?? "", isPresented: removal.isPresent(),
            presenting: removal.wrappedValue
        ) { removal in
            Button(removal.action, role: .destructive) {
                switch removal {
                case .feeds(let ids): model.removeFeeds(ids)
                case .folder(let id): model.removeFolder(id)
                }
                onRemove()
            }
        } message: { removal in
            Text(removal.message(in: model.library))
        }
    }
}

extension Binding {
    /// Whether an optional value is set; setting `false` clears it.
    func isPresent<Wrapped: Sendable>() -> Binding<Bool> where Value == Wrapped? {
        Binding<Bool>(get: { wrappedValue != nil }, set: { if !$0 { wrappedValue = nil } })
    }
}
