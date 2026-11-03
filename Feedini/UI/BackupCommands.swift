import SwiftUI

/// File → Back Up Now, Restore from Backup… (in the main window).
struct BackupCommands: View {
    let model: AppModel
    let reader: Reader
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Divider()
        Button("Back Up Now") { model.backUpNow() }
            .disabled(!model.canBackUpNow)
        Button("Restore from Backup…") {
            openWindow.mainWindow()
            reader.isShowingRestore = true
        }
    }
}
