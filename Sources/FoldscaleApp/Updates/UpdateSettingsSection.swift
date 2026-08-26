import SwiftUI

/// Settings › update preferences. Callers hide it when the updater is off.
struct UpdateSettingsSection: View {
    @Bindable var updater: UpdaterModel

    var body: some View {
        Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
        Toggle("Download and install updates automatically", isOn: $updater.automaticallyDownloadsUpdates)
            .disabled(!updater.automaticallyChecksForUpdates)
        Text(
            "Once a day Foldscale fetches a small file from foldscale.com to see whether a newer "
                + "version exists. Nothing about you or your files is sent."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
