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

    /// All live, non-directory nodes. Uses `liveMask()` so files under a trashed or
    /// replaced directory are excluded, not just directly-removed nodes.
    private static func nonDirectoryNodes(in tree: FileTree) -> [FileTree.NodeID] {
        let live = tree.liveMask()
        var nodes: [FileTree.NodeID] = []
        for index in 0..<tree.count where live[index] {
            let id = FileTree.NodeID(index)
            if !tree.flags(of: id).contains(.directory) { nodes.append(id) }
        }
        return nodes
    }
}
