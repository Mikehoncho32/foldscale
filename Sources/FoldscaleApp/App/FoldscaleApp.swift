import SwiftUI

/// The Foldscale application entry point. Colors and fonts are never hardcoded, so
/// dark mode works for free (handoff §4, rule 10).
@main
struct FoldscaleApp: App {
    init() { ScanStore.migrateLegacyPreferences() }

    var body: some Scene {
        WindowGroup("Foldscale") {
            ContentView()
        }
        .windowStyle(.titleBar)

        Settings {
            SettingsView()
        }
    }
}

/// Preferences (⌘,).
struct SettingsView: View {
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
        }
        .padding(20)
        .frame(width: 440)
    }
}
