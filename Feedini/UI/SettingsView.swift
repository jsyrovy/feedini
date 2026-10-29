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
        }
        .frame(width: 640, height: 520)
    }
}

/// General: refresh interval and where source pages open.
struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences
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
                Toggle("Show the number of unread stories in the menu bar", isOn: $preferences.showsUnreadCount)
            } footer: {
                Text("Closing the window keeps Feedini in the menu bar; it keeps refreshing and organizing there.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
