import AppKit
import RadixCore

/// The outline's right-click menu (handoff §4): Open · Reveal in Finder · Get Info ·
/// Copy Path · Exclude from Scan · Move to Trash. Right-clicking an unselected row
/// selects it first, like Finder.
extension FileOutlineView.Coordinator: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let outlineView else { return }
        let clicked = outlineView.clickedRow
        if clicked >= 0, !outlineView.selectedRowIndexes.contains(clicked) {
            outlineView.selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
        }
        guard !store.selection.isEmpty else { return }
        add(to: menu, "Open", #selector(menuOpen))
        add(to: menu, "Reveal in Finder", #selector(menuReveal))
        add(to: menu, "Get Info", #selector(menuGetInfo))
        add(to: menu, "Copy Path", #selector(menuCopyPath))
        add(to: menu, "Exclude from Scan", #selector(menuExclude))
        menu.addItem(.separator())
        let trashTitle =
            store.selectionHasProtected
            ? "Move to Trash (protected items skipped)" : "Move to Trash"
        add(to: menu, trashTitle, #selector(menuTrash))
    }

    private func add(to menu: NSMenu, _ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func menuOpen() { FileActions.open(store.urls(for: store.selection)) }
    @objc private func menuReveal() { FileActions.reveal(store.urls(for: store.selection)) }
    @objc private func menuCopyPath() { FileActions.copyPaths(store.urls(for: store.selection)) }
    @objc private func menuGetInfo() { store.infoNode = store.selection.first }
    @objc private func menuTrash() { store.isConfirmingTrash = true }
    @objc private func menuExclude() { store.exclude(store.selection) }
}
