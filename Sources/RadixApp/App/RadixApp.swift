import SwiftUI

/// The Radix application entry point. Colors and fonts are never hardcoded, so
/// dark mode works for free (handoff §4, rule 10).
@main
struct RadixApp: App {
    var body: some Scene {
        WindowGroup("Radix") {
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
                "When on, Radix re-scans your last drive or folder in the background each time it "
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
