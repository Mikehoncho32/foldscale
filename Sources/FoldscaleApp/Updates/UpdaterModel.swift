import Combine
import Sparkle
import SwiftUI

/// Owns the Sparkle updater for the app's lifetime (ADR-0005). Created once in
/// `FoldscaleApp.init`; the "Check for Updates…" menu item and Settings read it.
///
/// Sparkle never touches the network until the user has answered its permission
/// prompt (shown on the second launch), and it sends no system profile.
@MainActor
@Observable
final class UpdaterModel {
    /// Demo mode (website screenshots) must never check for updates. Debug builds
    /// skip the updater too — a dev build being offered the shipping release from the
    /// live feed is noise — unless `FOLDSCALE_APPCAST_URL` points at a test feed.
    nonisolated static var shouldRun: Bool {
        if DemoStaging.isEnabled { return false }
        #if DEBUG
        return ProcessInfo.processInfo.environment["FOLDSCALE_APPCAST_URL"] != nil
        #else
        return true
        #endif
    }

    /// False when the updater was never started (demo / Debug): the menu item is
    /// disabled and the Settings section hidden.
    let isEnabled: Bool
    private(set) var canCheckForUpdates = false

    var automaticallyChecksForUpdates: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }
    var automaticallyDownloadsUpdates: Bool {
        didSet { controller.updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates }
    }

    private let controller: SPUStandardUpdaterController
    private let delegate = UpdaterDelegate()
    private var cancellables = Set<AnyCancellable>()

    init(enabled: Bool = UpdaterModel.shouldRun) {
        isEnabled = enabled
        controller = SPUStandardUpdaterController(
            startingUpdater: enabled, updaterDelegate: delegate, userDriverDelegate: nil)
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = controller.updater.automaticallyDownloadsUpdates
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &cancellables)
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}
