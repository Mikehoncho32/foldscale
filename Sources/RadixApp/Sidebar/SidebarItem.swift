import RadixCore
import SwiftUI

/// Sidebar destinations: a folder in the drive tree, a place shortcut (Favorites /
/// Volumes), or a smart list — places you go, not features you toggle (handoff §4,
/// rule 5). The sidebar itself never changes shape when you pick one; only the
/// main area does.
enum SidebarItem: Hashable, Identifiable {
    case node(FileTree.NodeID)
    case place(URL)
    case largeFiles
    case oldAndBig

    var id: Self { self }

    var title: String {
        switch self {
        case .node: return "Folder"
        case .place(let url): return url.lastPathComponent
        case .largeFiles: return "Large files"
        case .oldAndBig: return "Old and big"
        }
    }

    var systemImage: String {
        switch self {
        case .node, .place: return "folder"
        case .largeFiles: return "doc.text.magnifyingglass"
        case .oldAndBig: return "clock.arrow.circlepath"
        }
    }

    var isSmartList: Bool {
        switch self {
        case .node, .place: return false
        case .largeFiles, .oldAndBig: return true
        }
    }

    /// The focused node id, if this item names one directly. A `.place` resolves
    /// to a node through the store instead.
    var nodeID: FileTree.NodeID? {
        if case .node(let id) = self { return id }
        return nil
    }
}
