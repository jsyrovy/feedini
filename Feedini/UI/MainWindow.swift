import SwiftUI

/// The main window: sidebar (selection), story list and detail.
struct MainWindow: View {
    var body: some View {
        NavigationSplitView {
            List {}
                .navigationSplitViewColumnWidth(min: 160, ideal: 200)
        } content: {
            ContentUnavailableView("No Articles", systemImage: "newspaper")
                .navigationSplitViewColumnWidth(min: 280, ideal: 360)
        } detail: {
            ContentUnavailableView("No Selection", systemImage: "doc.text")
        }
        .frame(minWidth: 800, minHeight: 480)
    }
}
