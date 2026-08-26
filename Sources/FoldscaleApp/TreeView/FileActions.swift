import AppKit

/// Thin AppKit wrappers for the non-destructive file actions (handoff §4). These
/// live in the app, not `FoldscaleCore`, because they depend on AppKit
/// (`NSWorkspace` / `NSPasteboard`). Deletion is deliberately not here — it goes
/// through `FoldscaleCore.TrashService`.
enum FileActions {
    /// Reveals the URLs in Finder, selecting them.
    static func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Opens each URL with its default application.
    static func open(_ urls: [URL]) {
        for url in urls { NSWorkspace.shared.open(url) }
    }

    /// Copies the URLs' paths (newline-separated) to the general pasteboard.
    static func copyPaths(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }
}
