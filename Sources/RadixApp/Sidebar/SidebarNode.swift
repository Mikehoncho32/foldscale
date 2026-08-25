import RadixCore
import SwiftUI

/// A folder row in the sidebar's drive tree. Holds the value-type `FileTree`
/// (copy-on-write, so copies are cheap) rather than the store, keeping key-path
/// evaluation free of observation tracking and retain cycles.
///
/// `children` is computed lazily by `OutlineGroup` — only when a row is
/// materialized or expanded — and lists **subfolders only**, biggest first.
/// It is `nil` (not `[]`) for folders with no subfolders so they get no chevron.
struct SidebarNode: Identifiable {
    let id: FileTree.NodeID
    let tree: FileTree

    var name: String { tree.name(of: id) }
    var bytes: Int64 { tree.totalAllocatedSize(of: id) }

    var children: [SidebarNode]? {
        let folders = tree.childrenSorted(of: id, by: .size)
            .filter { tree.flags(of: $0).contains(.directory) }
        guard !folders.isEmpty else { return nil }
        return folders.map { SidebarNode(id: $0, tree: tree) }
    }
}
