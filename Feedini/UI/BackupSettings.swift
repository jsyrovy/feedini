import SwiftUI

/// Backup: automatic backups to iCloud Drive, Back Up Now, restoring.
struct BackupSettings: View {
    @Environment(AppModel.self) private var model
    @State private var isRestoring = false

    var body: some View {
        @Bindable var preferences = model.preferences
        let backups = model.backups
        Form {
            Section {
                Toggle("Back up to iCloud Drive automatically", isOn: $preferences.backsUp)
                Picker("Back up:", selection: $preferences.backupFrequency) {
                    Text("Every hour").tag(BackupFrequency.hourly)
                    Text("Every day").tag(BackupFrequency.daily)
                    Text("Every week").tag(BackupFrequency.weekly)
                }
                .disabled(!preferences.backsUp)
            } footer: {
                Text(
                    "Backups go to iCloud Drive → Feedini → Backups, with the library and the settings, not the texts "
                        + "of source pages (P). Every backup of the last day is kept, then one a day for two weeks "
                        + "and one a week for two months."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section {
                // Unknown while automatic backups are off: looking would touch iCloud Drive.
                if preferences.backsUp || backups.lastBackup != nil {
                    LabeledContent("Last backup:", value: lastBackup)
                }
                if let problem = backups.problem {
                    Text(problem).font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button("Back Up Now") { model.backUpNow() }
                        .disabled(!model.canBackUpNow)
                    Button("Restore…") { isRestoring = true }
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.open(backups.store.directory) }
                        .disabled(backups.lastBackup == nil)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isRestoring) {
            RestoreSheet()
                .environment(model)
        }
    }

    private var lastBackup: String {
        let backups = model.backups
        if backups.isBackingUp {
            return "Backing up…"
        }
        guard let date = backups.lastBackup else { return "None yet" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
