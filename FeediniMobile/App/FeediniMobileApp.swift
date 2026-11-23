import SwiftUI

/// The iOS app: a plain reader of the shared model, without AI. For now only the list of All.
@main
struct FeediniMobileApp: App {
    @State private var model: AppModel
    @State private var session: ReadingSession

    init() {
        let model = AppModel(store: Self.store)
        _model = State(initialValue: model)
        _session = State(initialValue: ReadingSession(model: model))
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                StoryListScreen()
            }
            .environment(model)
            .environment(session)
            .task {
                await model.start()
                #if DEBUG
                    if Self.showsSampleLibrary {
                        model.update { $0 = SampleLibrary.make(now: .now) }
                    }
                #endif
            }
        }
    }

    /// The library in the app's container; in Debug with `-sampleLibrary` a temporary one with made-up articles.
    private static var store: LibraryStore {
        #if DEBUG
            if showsSampleLibrary {
                return LibraryStore(
                    fileURL: FileManager.default.temporaryDirectory.appending(path: "sample-\(UUID().uuidString).json"))
            }
        #endif
        return LibraryStore()
    }

    #if DEBUG
        private static var showsSampleLibrary: Bool {
            ProcessInfo.processInfo.arguments.contains(SampleLibrary.argument)
        }
    #endif
}
