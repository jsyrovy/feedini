import SwiftUI

/// The iOS app: a plain reader of the shared model, without AI. Feeds are refreshed while it is in the foreground.
@main
struct FeediniMobileApp: App {
    @State private var model: AppModel
    @State private var session: ReadingSession
    @State private var sync: MobileSync
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let model = AppModel(store: Self.store)
        _model = State(initialValue: model)
        _session = State(initialValue: ReadingSession(model: model))
        _sync = State(initialValue: MobileSync(model: model))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(session)
                .environment(sync)
                .task {
                    await model.start()
                    #if DEBUG
                        // Made-up articles never go to iCloud.
                        if Self.showsSampleLibrary {
                            model.update { $0 = SampleLibrary.make(now: .now) }
                            return
                        }
                    #endif
                    await sync.apply()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            guard model.isLoaded else { return }
            switch phase {
            case .active:
                model.startRefreshing()
            case .background:
                // Reading and then locking the iPhone is the usual case: changes are sent before iOS suspends
                // the app, in the time a background task gets.
                let task = UIApplication.shared.beginBackgroundTask(withName: "Save and sync")
                Task {
                    await model.flush()
                    await sync.controller.send()
                    await sync.controller.flush()
                    UIApplication.shared.endBackgroundTask(task)
                    // A running refresh may take longer than a background task; it ends while suspended.
                    await model.stopRefreshing()
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
