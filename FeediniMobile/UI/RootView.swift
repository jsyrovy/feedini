import SafariServices
import SwiftUI

/// Where the navigation stack is: a list of the sidebar, an item of a list.
enum Route: Hashable {
    case list(SidebarSelection)
    case entry(ListRow)
}

/// Where the app is: the navigation stack and the source page open in Safari's view over it. The page belongs to the
/// root, not to a list or detail, so neither a change of the library nor a row scrolled away closes it.
@MainActor
@Observable
final class Navigation {
    var path: [Route] = []
    var page: URL?
}

/// Sidebar → list → detail in one navigation stack (iPhone). Opening a row reads it (`ReadingSession.open`); going
/// back to the sidebar leaves the list, so it shows only unread items next time.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(ReadingSession.self) private var session
    @State private var navigation = Navigation()
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack(path: $navigation.path) {
            SidebarScreen(isShowingSettings: $isShowingSettings)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .list(let selection): StoryListScreen(selection: selection)
                    case .entry(let row): EntryDetailScreen(row: row)
                    }
                }
        }
        .environment(navigation)
        .onChange(of: navigation.path) { _, new in
            if new.isEmpty {
                session.leaveList()
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsScreen()
        }
        .sheet(item: $navigation.page) { url in
            SafariView(url: url).ignoresSafeArea()
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
                    navigation.path = [.list(.saved), .entry(.story(.savedArticle(id)))]
                }
                return
            }
            guard let index = arguments.firstIndex(of: "-screen"), index + 1 < arguments.count else { return }
            Task {
                // After the sample library is in.
                try? await Task.sleep(for: .milliseconds(300))
                switch arguments[index + 1] {
                case "saved":
                    navigation.path = [.list(.saved)]
                case "story", "article":
                    navigation.path = [.list(.all)]
                    session.selection = .all
                    let wanted = arguments[index + 1] == "story"
                    if let entry = session.entries.first(where: { $0.isMultiArticle == wanted }) {
                        navigation.path.append(.entry(.story(entry.id)))
                    }
                case "list":
                    navigation.path = [.list(.all)]
                case "settings":
                    isShowingSettings = true
                default:
                    break
                }
            }
        }
    #endif
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// A web page in Safari's view inside the app (the user's Safari logins and cookies don't apply).
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
