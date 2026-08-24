import Foundation

/// Queries over a scanned `FileTree` that power the sidebar's smart lists — places
/// you go, not features you toggle (handoff §4, rule 5). Pure and unit-tested.
public enum SmartLists {
    /// The `limit` largest non-directory nodes, biggest first (§4: "Large files").
    public static func largeFiles(in tree: FileTree, limit: Int = 200) -> [FileTree.NodeID] {
        var files = nonDirectoryNodes(in: tree)
        files.sort { tree.totalAllocatedSize(of: $0) > tree.totalAllocatedSize(of: $1) }
        return Array(files.prefix(limit))
    }

    /// Non-directory nodes at least `minBytes` in size whose modification time is
    /// older than `olderThan` (§4: "Old and big"). Uses `st_mtime`, not `st_atime`,
    /// which is unreliable on APFS (see the planning notes).
    public static func oldAndBig(
        in tree: FileTree,
        minBytes: Int64 = 1_000_000_000,
        olderThan cutoff: Date
    ) -> [FileTree.NodeID] {
        let cutoffEpoch = Int64(cutoff.timeIntervalSince1970)
        var result = nonDirectoryNodes(in: tree).filter { node in
            tree.totalAllocatedSize(of: node) >= minBytes
                && tree.modificationTime(of: node) < cutoffEpoch
        }
        result.sort { tree.totalAllocatedSize(of: $0) > tree.totalAllocatedSize(of: $1) }
        return result
    }

    private static func nonDirectoryNodes(in tree: FileTree) -> [FileTree.NodeID] {
        var nodes: [FileTree.NodeID] = []
        var id: FileTree.NodeID = 0
        while id < FileTree.NodeID(tree.count) {
            if !tree.isRemoved(id), !tree.flags(of: id).contains(.directory) {
                nodes.append(id)
            }
            id += 1
        }
        return nodes
    }
}
