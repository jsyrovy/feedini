import SwiftUI

/// The main window: sidebar (selection), story list and detail.
struct MainWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 160, ideal: 210)
        } content: {
            StoryListView()
                .navigationSplitViewColumnWidth(min: 300, ideal: 380)
        } detail: {
            DetailView()
        }
        .frame(minWidth: 900, minHeight: 500)
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") { model.refreshNow() }
                    .help("Refresh Now (R)")
                    .disabled(model.isRefreshing || model.library.feeds.isEmpty)
            }
        }
    }
}
