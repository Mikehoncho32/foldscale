import RadixCore
import SwiftUI

/// Sidebar destinations: a folder in the drive tree, a place shortcut (Favorites /
/// Drives), a smart list, or the "Free up space" flow — places you go, not features
/// you toggle (handoff §4, rule 5). The sidebar itself never changes shape when you
/// pick one; only the main area does.
enum SidebarItem: Hashable, Identifiable {
    case node(FileTree.NodeID)
    case place(URL)
    case smartList(SmartListKind)
    case freeUpSpace

    var id: Self { self }

    /// Destinations that replace the outline with their own view.
    var isSmartList: Bool {
        switch self {
        case .smartList, .freeUpSpace: return true
        case .node, .place: return false
        }
    }

    /// The focused node id, if this item names one directly. A `.place` resolves
    /// to a node through the store instead.
    var nodeID: FileTree.NodeID? {
        if case .node(let id) = self { return id }
        return nil
    }
}
