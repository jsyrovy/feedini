import SwiftUI

/// The iOS app: a plain reader of the shared model, without AI. Feeds are refreshed while it is in the foreground.
@main
struct FeediniMobileApp: App {
    @State private var model: AppModel
    @State private var session: ReadingSession
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let model = AppModel(store: Self.store)
        _model = State(initialValue: model)
        _session = State(initialValue: ReadingSession(model: model))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
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
        .onChange(of: scenePhase) { _, phase in
            guard model.isLoaded else { return }
            switch phase {
            case .active:
                model.startRefreshing()
            case .background:
                Task {
                    await model.stopRefreshing()
                    await model.flush()
                }
            default:
                break
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
