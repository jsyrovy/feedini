import SwiftUI

/// Where the navigation stack is: a list of the sidebar, an item of a list.
enum Route: Hashable {
    case list(SidebarSelection)
    case entry(ListRow)
}

/// Sidebar → list → detail in one navigation stack (iPhone). Opening a row reads it (`ReadingSession.visit`); going
/// back to the sidebar leaves the list, so it shows only unread items next time.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(ReadingSession.self) private var session
    @State private var path: [Route] = []
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            SidebarScreen(isShowingSettings: $isShowingSettings)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .list(let selection): StoryListScreen(selection: selection)
                    case .entry(let row): EntryDetailScreen(row: row)
                    }
                }
        }
        .onChange(of: path) { _, new in
            if new.isEmpty {
                session.leaveList()
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsScreen()
        }
        .task {
            #if DEBUG
                openDebugScreen()
            #endif
        }
    }

    #if DEBUG
        /// `-screen list|story|article|saved|settings` with `-sampleLibrary`: a screen to look at in the simulator;
        /// `-saveLink <address>` saves a page and opens it (its text loads in the hidden web view).
        private func openDebugScreen() {
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-saveLink"), index + 1 < arguments.count {
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard let id = try? model.saveLink(arguments[index + 1]).articleID else { return }
                    session.selection = .saved
                    path = [.list(.saved), .entry(.story(.savedArticle(id)))]
                }
                return
            }
            guard let index = arguments.firstIndex(of: "-screen"), index + 1 < arguments.count else { return }
            Task {
                // After the sample library is in.
                try? await Task.sleep(for: .milliseconds(300))
                switch arguments[index + 1] {
                case "saved":
                    path = [.list(.saved)]
                case "story", "article":
                    path = [.list(.all)]
                    session.selection = .all
                    let wanted = arguments[index + 1] == "story"
                    if let entry = session.entries.first(where: { $0.isMultiArticle == wanted }) {
                        path.append(.entry(.story(entry.id)))
                    }
                case "list":
                    path = [.list(.all)]
                case "settings":
                    isShowingSettings = true
                default:
                    break
                }
            }
        }
    #endif
}
