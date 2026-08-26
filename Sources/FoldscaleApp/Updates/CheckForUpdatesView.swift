import SwiftUI

/// The "Check for Updates…" menu item, disabled while Sparkle is busy or off.
struct CheckForUpdatesView: View {
    let updater: UpdaterModel

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}
