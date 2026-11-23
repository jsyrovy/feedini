import Foundation

/// Owns the library on the main actor; the page loader and the AI queues read it and change it through it.
@MainActor
protocol LibraryHost: AnyObject {
    var library: Library { get }
    func update(_ change: (inout Library) -> Void)
    /// The stored text of the article's source page (`Library.pageTextIDs`); `nil` when there is none or it can't be
    /// read anymore (then it is forgotten).
    func pageText(_ id: Article.ID) async -> String?
    /// Stores the text of the article's source page and lists it in `Library.pageTextIDs`.
    func storePageText(_ text: String, for id: Article.ID) async throws
}
