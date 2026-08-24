import Foundation

/// A scanned filesystem tree stored as a struct-of-arrays for low per-node
/// overhead and cache-friendly traversal at very large scale (target: < 150 MB
/// RSS for 1M nodes — see ADR-0001). Names live in one shared UTF-8 buffer,
/// referenced by `(offset, length)` per node instead of as individual `String`s.
public struct FileTree: Sendable {
    /// A node identifier: an index into the parallel arrays.
    public typealias NodeID = Int32

    /// Sentinel meaning "no node" (no parent / no child / no sibling).
    public static let none: NodeID = -1

    // Parallel arrays, each indexed by a NodeID in `0 ..< count`.
    private let parentIDs: [NodeID]
    private let firstChildIDs: [NodeID]
    private let nextSiblingIDs: [NodeID]
    private let ownSizes: [Int64]
    private var totalSizes: [Int64]
    private let logicalSizes: [Int64]
    private var itemCounts: [Int64]
    private let modificationTimes: [Int64]
    private let nodeFlags: [NodeFlags]
    private let nameOffsets: [UInt32]
    private let nameLengths: [UInt16]
    private let nameStorage: [UInt8]
    /// Nodes trashed since the scan, hidden from the live tree and its totals.
    private var removed: Set<NodeID> = []

    /// The root node id, or `.none` for an empty tree.
    public let rootID: NodeID

    /// Total number of nodes in the tree.
    public var count: Int { parentIDs.count }

    init(
        parentIDs: [NodeID],
        firstChildIDs: [NodeID],
        nextSiblingIDs: [NodeID],
        ownSizes: [Int64],
        totalSizes: [Int64],
        logicalSizes: [Int64],
        itemCounts: [Int64],
        modificationTimes: [Int64],
        nodeFlags: [NodeFlags],
        nameOffsets: [UInt32],
        nameLengths: [UInt16],
        nameStorage: [UInt8],
        rootID: NodeID
    ) {
        self.parentIDs = parentIDs
        self.firstChildIDs = firstChildIDs
        self.nextSiblingIDs = nextSiblingIDs
        self.ownSizes = ownSizes
        self.totalSizes = totalSizes
        self.logicalSizes = logicalSizes
        self.itemCounts = itemCounts
        self.modificationTimes = modificationTimes
        self.nodeFlags = nodeFlags
        self.nameOffsets = nameOffsets
        self.nameLengths = nameLengths
        self.nameStorage = nameStorage
        self.rootID = rootID
    }
}

extension FileTree {
    /// The node's entry name (last path component).
    public func name(of node: NodeID) -> String {
        let start = Int(nameOffsets[Int(node)])
        let length = Int(nameLengths[Int(node)])
        guard length > 0 else { return "" }
        return String(decoding: nameStorage[start..<start + length], as: UTF8.self)
    }

    /// The parent node id, or `.none` for the root.
    public func parent(of node: NodeID) -> NodeID { parentIDs[Int(node)] }

    /// Aggregated on-disk size of the node and all its descendants, in bytes.
    public func totalAllocatedSize(of node: NodeID) -> Int64 { totalSizes[Int(node)] }

    /// The node's own on-disk size, in bytes (0 for a deduped hard link).
    public func ownAllocatedSize(of node: NodeID) -> Int64 { ownSizes[Int(node)] }

    /// The node's own apparent size (`st_size`), in bytes.
    public func logicalSize(of node: NodeID) -> Int64 { logicalSizes[Int(node)] }

    /// Number of descendant nodes under this node (files + directories).
    public func itemCount(of node: NodeID) -> Int64 { itemCounts[Int(node)] }

    /// Number of direct children of this node (excluding trashed ones).
    public func childCount(of node: NodeID) -> Int {
        var count = 0
        var child = firstChildIDs[Int(node)]
        while child != FileTree.none {
            if !removed.contains(child) { count += 1 }
            child = nextSiblingIDs[Int(child)]
        }
        return count
    }

    /// Whether the node has been trashed (hidden from the live tree).
    public func isRemoved(_ node: NodeID) -> Bool { removed.contains(node) }

    /// Last-modification time, seconds since the Unix epoch.
    public func modificationTime(of node: NodeID) -> Int64 { modificationTimes[Int(node)] }

    /// Type and state flags for the node.
    public func flags(of node: NodeID) -> NodeFlags { nodeFlags[Int(node)] }

    /// The node's children, in insertion order (excluding trashed ones).
    public func children(of node: NodeID) -> [NodeID] {
        var result: [NodeID] = []
        var child = firstChildIDs[Int(node)]
        while child != FileTree.none {
            if !removed.contains(child) { result.append(child) }
            child = nextSiblingIDs[Int(child)]
        }
        return result
    }

    /// The node's children sorted by aggregated size, largest first — the default
    /// ordering at every depth (handoff §4, rule 2).
    public func childrenSortedBySize(of node: NodeID) -> [NodeID] {
        children(of: node).sorted { totalSizes[Int($0)] > totalSizes[Int($1)] }
    }

    /// Full path from the root, joined with "/".
    public func path(of node: NodeID) -> String {
        var components: [String] = []
        var current = node
        while current != FileTree.none {
            components.append(name(of: current))
            current = parentIDs[Int(current)]
        }
        return components.reversed().joined(separator: "/")
    }

    /// Path components from the scan root down to `node`, **excluding** the root's
    /// own name — so `rootURL.appendingPathComponent(...)` rebuilds the file's URL
    /// regardless of what the root is (a folder, or "/").
    public func pathComponentsFromRoot(of node: NodeID) -> [String] {
        var components: [String] = []
        var current = node
        while current != FileTree.none, current != rootID {
            components.append(name(of: current))
            current = parentIDs[Int(current)]
        }
        return components.reversed()
    }

    /// Removes a trashed node, subtracting its subtree's allocated size and item
    /// count from every ancestor so the tree re-totals instantly, no rescan
    /// (handoff §4, rule 9). Idempotent; a node under an already-removed ancestor
    /// is a no-op, so trashing overlapping selections never double-counts.
    public mutating func remove(_ node: NodeID) {
        guard node != FileTree.none, node != rootID, !removed.contains(node) else { return }
        var ancestor = parentIDs[Int(node)]
        while ancestor != FileTree.none {
            if removed.contains(ancestor) { return }
            ancestor = parentIDs[Int(ancestor)]
        }
        let subtreeBytes = totalSizes[Int(node)]
        let subtreeItems = itemCounts[Int(node)] + 1
        removed.insert(node)
        ancestor = parentIDs[Int(node)]
        while ancestor != FileTree.none {
            totalSizes[Int(ancestor)] -= subtreeBytes
            itemCounts[Int(ancestor)] -= subtreeItems
            ancestor = parentIDs[Int(ancestor)]
        }
    }
}

/// Builds a ``FileTree`` (struct-of-arrays) from a depth-first scan stream.
public struct FileTreeBuilder: TreeBuilder {
    private var parentIDs: [FileTree.NodeID] = []
    private var firstChildIDs: [FileTree.NodeID] = []
    private var nextSiblingIDs: [FileTree.NodeID] = []
    private var lastChildIDs: [FileTree.NodeID] = []  // build-time only
    private var ownSizes: [Int64] = []
    private var logicalSizes: [Int64] = []
    private var itemCounts: [Int64] = []
    private var modificationTimes: [Int64] = []
    private var nodeFlags: [NodeFlags] = []
    private var nameOffsets: [UInt32] = []
    private var nameLengths: [UInt16] = []
    private var nameStorage: [UInt8] = []
    private var openStack: [FileTree.NodeID] = []
    private var rootID: FileTree.NodeID = FileTree.none

    public init(reservingCapacity capacity: Int = 0) {
        reserveCapacity(capacity)
    }

    /// Pre-sizes the parallel arrays to avoid geometric-growth overhead. Names
    /// (variable length) are estimated at ~16 bytes per node.
    public mutating func reserveCapacity(_ minimumCapacity: Int) {
        guard minimumCapacity > parentIDs.capacity else { return }
        parentIDs.reserveCapacity(minimumCapacity)
        firstChildIDs.reserveCapacity(minimumCapacity)
        nextSiblingIDs.reserveCapacity(minimumCapacity)
        lastChildIDs.reserveCapacity(minimumCapacity)
        ownSizes.reserveCapacity(minimumCapacity)
        logicalSizes.reserveCapacity(minimumCapacity)
        itemCounts.reserveCapacity(minimumCapacity)
        modificationTimes.reserveCapacity(minimumCapacity)
        nodeFlags.reserveCapacity(minimumCapacity)
        nameOffsets.reserveCapacity(minimumCapacity)
        nameLengths.reserveCapacity(minimumCapacity)
        nameStorage.reserveCapacity(minimumCapacity * 16)
    }

    private mutating func makeNode(
        name: UnsafeBufferPointer<UInt8>,
        meta: NodeMeta
    ) -> FileTree.NodeID {
        let node = FileTree.NodeID(parentIDs.count)
        let parent = openStack.last ?? FileTree.none
        parentIDs.append(parent)
        firstChildIDs.append(FileTree.none)
        nextSiblingIDs.append(FileTree.none)
        lastChildIDs.append(FileTree.none)
        ownSizes.append(meta.flags.contains(.hardlinkDuplicate) ? 0 : meta.allocatedSize)
        logicalSizes.append(meta.logicalSize)
        itemCounts.append(0)
        modificationTimes.append(meta.modificationTime)
        nodeFlags.append(meta.flags)
        nameOffsets.append(UInt32(nameStorage.count))
        nameLengths.append(UInt16(min(name.count, Int(UInt16.max))))
        nameStorage.append(contentsOf: name)

        if parent != FileTree.none {
            let parentIdx = Int(parent)
            if firstChildIDs[parentIdx] == FileTree.none {
                firstChildIDs[parentIdx] = node
            } else {
                nextSiblingIDs[Int(lastChildIDs[parentIdx])] = node
            }
            lastChildIDs[parentIdx] = node
        } else {
            rootID = node
        }
        return node
    }

    public mutating func enterDirectory(name: UnsafeBufferPointer<UInt8>, meta: NodeMeta) {
        openStack.append(makeNode(name: name, meta: meta))
    }

    public mutating func addLeaf(name: UnsafeBufferPointer<UInt8>, meta: NodeMeta) {
        _ = makeNode(name: name, meta: meta)
    }

    public mutating func leaveDirectory() {
        openStack.removeLast()
    }

    /// Finalizes the tree: aggregates sizes and item counts bottom-up in a single
    /// reverse pass. Children always have a higher index than their parent
    /// (nodes are appended in pre-order), so iterating from the last node down
    /// guarantees a child is fully summed before its parent is visited.
    public mutating func finish() -> FileTree {
        var totalSizes = ownSizes
        let nodeCount = parentIDs.count
        if nodeCount > 1 {
            var index = nodeCount - 1
            while index >= 1 {
                let parentIdx = Int(parentIDs[index])
                totalSizes[parentIdx] += totalSizes[index]
                itemCounts[parentIdx] += itemCounts[index] + 1
                index -= 1
            }
        }
        return FileTree(
            parentIDs: parentIDs,
            firstChildIDs: firstChildIDs,
            nextSiblingIDs: nextSiblingIDs,
            ownSizes: ownSizes,
            totalSizes: totalSizes,
            logicalSizes: logicalSizes,
            itemCounts: itemCounts,
            modificationTimes: modificationTimes,
            nodeFlags: nodeFlags,
            nameOffsets: nameOffsets,
            nameLengths: nameLengths,
            nameStorage: nameStorage,
            rootID: rootID
        )
    }
}
