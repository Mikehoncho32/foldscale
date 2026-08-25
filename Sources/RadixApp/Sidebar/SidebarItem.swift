import RadixCore
import SwiftUI

/// Sidebar destinations: a folder in the drive tree, a place shortcut (Favorites /
/// Drives), or a smart list — places you go, not features you toggle (handoff §4,
/// rule 5). The sidebar itself never changes shape when you pick one; only the
/// main area does.
enum SidebarItem: Hashable, Identifiable {
    case node(FileTree.NodeID)
    case place(URL)
    case smartList(SmartListKind)

    var id: Self { self }

    var isSmartList: Bool {
        if case .smartList = self { return true }
        return false
    }

    /// The focused node id, if this item names one directly. A `.place` resolves
    /// to a node through the store instead.
    var nodeID: FileTree.NodeID? {
        if case .node(let id) = self { return id }
        return nil
    }
}
