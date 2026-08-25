import RadixCore
import SwiftUI

/// A row in the sidebar's drive tree: a folder, or the synthetic "System & other"
/// row that accounts for volume space the scan doesn't cover. Holds the value-type
/// `FileTree` (copy-on-write, so copies are cheap) rather than the store, keeping
/// key-path evaluation free of observation tracking and retain cycles.
///
/// `children` is computed lazily by `OutlineGroup` — only when a row is
/// materialized or expanded — and lists **subfolders only**, biggest first.
/// It is `nil` (not `[]`) for rows with no children so they get no chevron.
struct SidebarNode: Identifiable {
    enum Kind {
        case folder(FileTree.NodeID)
        /// Space used on the volume outside the scan (sealed System volume, VM,
        /// snapshots). Shown only under a volume root; not selectable.
        case other(bytes: Int64)
    }

    let kind: Kind
    let tree: FileTree
    /// For the root only: the "System & other" delta to append after its folders.
    var otherBytes: Int64?

    var id: FileTree.NodeID {
        if case .folder(let id) = kind { return id }
        return FileTree.none
    }

    var folderID: FileTree.NodeID? {
        if case .folder(let id) = kind { return id }
        return nil
    }

    var isOther: Bool { folderID == nil }

    var bytes: Int64 {
        switch kind {
        case .folder(let id): return tree.totalAllocatedSize(of: id)
        case .other(let bytes): return bytes
        }
    }

    func name(rootName: String) -> String {
        switch kind {
        case .folder(let id): return id == tree.rootID ? rootName : tree.name(of: id)
        case .other: return "System & other"
        }
    }

    var children: [SidebarNode]? {
        guard let folderID else { return nil }
        var rows = tree.childrenSorted(of: folderID, by: .size)
            .filter { tree.flags(of: $0).contains(.directory) }
            .map { SidebarNode(kind: .folder($0), tree: tree) }
        if let otherBytes, otherBytes > 0 {
            rows.append(SidebarNode(kind: .other(bytes: otherBytes), tree: tree))
        }
        return rows.isEmpty ? nil : rows
    }
}
