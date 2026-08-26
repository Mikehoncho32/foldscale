import SwiftUI

/// The Foldscale application entry point. Colors and fonts are never hardcoded, so
/// dark mode works for free (handoff §4, rule 10).
@main
struct FoldscaleApp: App {
    /// One updater for the app's lifetime (ADR-0005).
    private let updater = UpdaterModel()

    init() { ScanStore.migrateLegacyPreferences() }

    var body: some Scene {
        WindowGroup("Foldscale") {
            ContentView()
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updater)
            }
        }

        Settings {
            SettingsView(updater: updater)
        }
    }
}

/// Preferences (⌘,).
struct SettingsView: View {
    let updater: UpdaterModel
    @AppStorage(ScanStore.autoRefreshDefaultsKey) private var autoRefreshOnLaunch = true

    var body: some View {
        Form {
            Toggle("Keep the last scan up to date automatically", isOn: $autoRefreshOnLaunch)
            Text(
                "When on, Foldscale re-scans your last drive or folder in the background each time it "
                    + "opens, keeping what you see current. Folders you click are refreshed either way."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if updater.isEnabled {
                Divider()
                UpdateSettingsSection(updater: updater)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
