import SwiftUI

/// The Settings window.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Feeds", systemImage: "dot.radiowaves.up.forward") {
                FeedsSettings()
            }
            Tab("General", systemImage: "gearshape") {
                GeneralSettings()
            }
            Tab("AI", systemImage: "sparkles") {
                AISettings()
            }
            Tab("Sync", systemImage: "arrow.triangle.2.circlepath.icloud") {
                SyncSettings()
            }
            Tab("Backup", systemImage: "externaldrive.badge.icloud") {
                BackupSettings()
            }
        }
        .frame(width: 640, height: 520)
    }
}

/// General: refresh interval and where source pages open.
struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(MacServices.self) private var mac

    var body: some View {
        @Bindable var preferences = model.preferences
        @Bindable var macPreferences = mac.preferences
        Form {
            Picker("Refresh every:", selection: $preferences.refreshMinutes) {
                ForEach(Preferences.refreshMinutesChoices, id: \.self) { minutes in
                    Text(minutes == 60 ? "1 hour" : "\(minutes) minutes").tag(minutes)
                }
            }
            Picker("Open articles in:", selection: $preferences.pageOpening) {
                Text("Feedini window").tag(Preferences.PageOpening.window)
                Text("Default browser").tag(Preferences.PageOpening.browser)
            }
            Text("V or Enter opens an article's page this way, Shift+V or Shift+Enter the other way.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Section {
                Toggle("Open at login", isOn: launchAtLogin)
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.orange)
                }
                Toggle("Show the number of unread stories in the menu bar", isOn: $macPreferences.showsUnreadCount)
            } footer: {
                Text("Closing the window keeps Feedini in the menu bar; it keeps refreshing and organizing there.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            UpdateSettings(preferences: macPreferences, updates: mac.updates)
        }
        .formStyle(.grouped)
        .onAppear { isLoginItem = LoginItem.isEnabled }
    }

    @State private var isLoginItem = false
    @State private var loginError: String?

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { isLoginItem },
            set: { enabled in
                loginError = LoginItem.setEnabled(enabled)
                isLoginItem = LoginItem.isEnabled
            })
    }
}

/// "Check for updates daily", "Check Now" and what the last check found.
private struct UpdateSettings: View {
    @Bindable var preferences: MacPreferences
    let updates: UpdateChecker

    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            LabeledContent("Version", value: RuntimeEnvironment.versionDescription)
                .textSelection(.enabled)
            HStack {
                Toggle("Check for updates daily", isOn: $preferences.checksForUpdates)
                Spacer()
                Button("Check Now") {
                    Task { await updates.checkNow() }
                }
                .disabled(updates.state == .checking)
            }
            status
        } footer: {
            Text("Asks GitHub for the latest release. Feedini never installs it itself.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// What the last check found; nothing before the first one.
    @ViewBuilder private var status: some View {
        switch updates.state {
        case .unchecked:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking for updates…")
            }
            .foregroundStyle(.secondary)
        case .upToDate:
            // The version is the row above.
            Label("Feedini is up to date", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .available(let release):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Feedini \(release.version.description) is available", systemImage: "arrow.down.circle")
                    Spacer()
                    Button("Download") { openURL(release.pageURL) }
                }
                if HomebrewCask.isInstalled {
                    Text("With Homebrew: \(Text(HomebrewCask.upgradeCommand).monospaced())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}
