import AppKit
import Quartz

/// `NSOutlineView` subclass that adds spacebar Quick Look (handoff §4). Being the
/// first responder, it is where `QLPreviewPanel` finds its data source. The set of
/// preview URLs is supplied by the coordinator via `urlsForSelection`.
final class FoldscaleOutlineView: NSOutlineView {
    /// Returns the file URLs to preview — the current selection.
    var urlsForSelection: @MainActor () -> [URL] = { [] }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            toggleQuickLook()
            return
        }
        super.keyDown(with: event)
    }

    /// Shows or hides the Quick Look panel for the current selection.
    func toggleQuickLook() {
        guard !urlsForSelection().isEmpty, let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {}
}

extension FoldscaleOutlineView: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urlsForSelection().count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urlsForSelection()[index] as NSURL
    }
}

/// Lets non-AppKit views (the SwiftUI footer) trigger Quick Look on the outline
/// without a direct reference into `NSViewRepresentable` internals.
final class OutlineBridge {
    weak var outline: FoldscaleOutlineView?

    func quickLook() {
        guard let outline else { return }
        outline.window?.makeFirstResponder(outline)
        outline.toggleQuickLook()
    }
}
