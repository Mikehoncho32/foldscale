import RadixCore
import SwiftUI

/// Sidebar destinations: a folder in the drive tree (focuses the main pane on it)
/// or a smart list — places you go, not features you toggle (handoff §4, rule 5).
enum SidebarItem: Hashable, Identifiable {
    case node(FileTree.NodeID)
    case largeFiles
    case oldAndBig

    var id: Self { self }

    var title: String {
        switch self {
        case .node: return "Folder"
        case .largeFiles: return "Large files"
        case .oldAndBig: return "Old and big"
        }
    }

    var systemImage: String {
        switch self {
        case .node: return "folder"
        case .largeFiles: return "doc.text.magnifyingglass"
        case .oldAndBig: return "clock.arrow.circlepath"
        }
    }

    var isSmartList: Bool {
        if case .node = self { return false }
        return true
    }

    /// The focused node id, if this item is a folder.
    var nodeID: FileTree.NodeID? {
        if case .node(let id) = self { return id }
        return nil
    }
}
