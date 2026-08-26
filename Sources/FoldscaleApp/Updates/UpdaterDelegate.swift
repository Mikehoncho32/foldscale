import Foundation
import Sparkle

/// Two hooks: a feed override for end-to-end tests (`FOLDSCALE_APPCAST_URL`), and
/// suppression of Sparkle's permission prompt while testing so the flow is
/// deterministic. Anyone who can set an env var on a Mac can already replace the
/// app; the EdDSA signature still protects the update *content*.
final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    private var testFeed: String? { ProcessInfo.processInfo.environment["FOLDSCALE_APPCAST_URL"] }

    /// `nil` → Sparkle uses `SUFeedURL` from Info.plist.
    func feedURLString(for updater: SPUUpdater) -> String? { testFeed }

    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        testFeed == nil
    }
}
