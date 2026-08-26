import AppKit
import FoldscaleCore
import SwiftUI

/// Stages the window for screenshots when `FOLDSCALE_DEMO` is set: a fixed window size
/// (`FOLDSCALE_WINDOW=1280x800`), an explicit appearance (`FOLDSCALE_APPEARANCE=dark|light`),
/// a destination (`FOLDSCALE_DEMO_VIEW=home|drive|freeup|<SmartListKind raw value>`) and
/// outline rows to expand (`FOLDSCALE_DEMO_EXPAND=1,3`, zero-based, in the focused folder).
@MainActor
enum DemoStaging {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["FOLDSCALE_DEMO"] != nil }

    static func apply(store: ScanStore, bridge: OutlineBridge, select: @escaping (SidebarItem?) -> Void) {
        let env = ProcessInfo.processInfo.environment
        if let appearance = env["FOLDSCALE_APPEARANCE"] {
            NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        }
        let size = parseSize(env["FOLDSCALE_WINDOW"]) ?? NSSize(width: 1280, height: 800)
        // Twice: the window may not exist yet on the first tick, and state
        // restoration can re-apply a saved frame after it does.
        for delay in [0.3, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let window = NSApp.windows.first(where: { $0.title == "Macintosh HD" || $0.isVisible })
                else { return }
                window.setContentSize(size)
                window.center()
                // The sidebar width is user-persisted; pin it so labels never truncate.
                if let split = firstSplitView(in: window.contentView) {
                    split.setPosition(280, ofDividerAt: 0)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if let view = env["FOLDSCALE_DEMO_VIEW"], let item = destination(view, store: store) {
                select(item)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard let outline = bridge.outline, let rows = env["FOLDSCALE_DEMO_EXPAND"] else { return }
            // Bottom-up, so earlier expansions don't shift the indexes still to come.
            for row in rows.split(separator: ",").compactMap({ Int($0) }).sorted(by: >) {
                if let item = outline.item(atRow: row) { outline.expandItem(item) }
            }
        }
    }

    private static func destination(_ view: String, store: ScanStore) -> SidebarItem? {
        switch view {
        case "home": return .place(FileManager.default.homeDirectoryForCurrentUser)
        case "drive": return store.tree.map { .node($0.rootID) }
        case "freeup": return .freeUpSpace
        default: return SmartListKind(rawValue: view).map { .smartList($0) }
        }
    }

    private static func firstSplitView(in view: NSView?) -> NSSplitView? {
        guard let view else { return nil }
        if let split = view as? NSSplitView { return split }
        for child in view.subviews {
            if let found = firstSplitView(in: child) { return found }
        }
        return nil
    }

    private static func parseSize(_ text: String?) -> NSSize? {
        guard let parts = text?.split(separator: "x"), parts.count == 2,
            let width = Double(parts[0]), let height = Double(parts[1])
        else { return nil }
        return NSSize(width: width, height: height)
    }
}
