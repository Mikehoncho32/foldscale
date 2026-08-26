import AppKit
import FoldscaleCore

/// A stable reference identity for a `FileTree` node, so `NSOutlineView` (which
/// keys expansion/selection state by object identity) can track value-type nodes.
/// Exactly one instance is cached per node id for the lifetime of a loaded tree.
final class OutlineNode: NSObject {
    let id: FileTree.NodeID

    init(id: FileTree.NodeID) {
        self.id = id
    }
}
