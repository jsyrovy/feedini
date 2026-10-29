import SwiftUI

/// The main window: sidebar (selection), story list and detail.
struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(Reader.self) private var reader

    var body: some View {
        @Bindable var reader = reader
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
        .onAppear { AppDelegate.mainWindowIsOpen(true) }
        .onDisappear { AppDelegate.mainWindowIsOpen(false) }
        .sheet(isPresented: $reader.isShowingShortcuts) {
            ShortcutsView()
                .environment(model)
                .environment(reader)
        }
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") { model.refreshNow() }
                    .help("Refresh Now (R)")
                    .disabled(model.isRefreshing || model.library.feeds.isEmpty)
            }
        }
    }
}
