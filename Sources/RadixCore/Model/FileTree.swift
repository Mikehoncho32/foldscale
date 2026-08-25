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
    //
    // Invariant: every node's parent has a LOWER index than the node (nodes are
    // appended in pre-order, and `replaceSubtree` appends whole subtrees at the
    // end). `finish()` and `liveMask()` rely on it.
    private var parentIDs: [NodeID]
    private var firstChildIDs: [NodeID]
    private var nextSiblingIDs: [NodeID]
    private var ownSizes: [Int64]
    private var totalSizes: [Int64]
    private var logicalSizes: [Int64]
    private var itemCounts: [Int64]
    private var modificationTimes: [Int64]
    private var nodeFlags: [NodeFlags]
    private var nameOffsets: [UInt32]
    private var nameLengths: [UInt16]
    private var nameStorage: [UInt8]
    /// Nodes trashed since the scan, hidden from the live tree and its totals.
    private var removed: Set<NodeID> = []

    /// The root node id, or `.none` for an empty tree.
    public let rootID: NodeID

    /// Total number of nodes in the tree.
    public var count: Int { parentIDs.count }

    /// Whether the tree has no nodes at all.
    public var isEmpty: Bool { parentIDs.isEmpty }

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

    /// Whether `node` is a valid, still-visible node: in range, not removed, and
    /// under no removed ancestor (`remove` marks only the node itself). Use this
    /// to validate ids held across trash/exclude — or across scans, since ids are
    /// dense indices that a new tree reuses.
    public func isLive(_ node: NodeID) -> Bool {
        guard node >= 0, Int(node) < count else { return false }
        var current = node
        while current != FileTree.none {
            if removed.contains(current) { return false }
            current = parentIDs[Int(current)]
        }
        return true
    }

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

// MARK: - Live refresh (path lookup, liveness, subtree splice)

extension FileTree {
    /// Resolves a path (name components from the root, root = `[]`) to a live node.
    /// Compares raw UTF-8 bytes against the shared name buffer, so walking a
    /// 50k-entry directory allocates no per-child strings. Returns `nil` if any
    /// component is missing or passes through a removed node.
    public func node(atPathComponents components: [String]) -> NodeID? {
        guard rootID != FileTree.none else { return nil }
        var current = rootID
        for component in components {
            let bytes = Array(component.utf8)
            var child = firstChildIDs[Int(current)]
            var found = FileTree.none
            while child != FileTree.none {
                if !removed.contains(child), nameMatches(child, bytes) {
                    found = child
                    break
                }
                child = nextSiblingIDs[Int(child)]
            }
            guard found != FileTree.none else { return nil }
            current = found
        }
        return current
    }

    /// One `Bool` per node: live iff not removed and its parent is live. A single
    /// forward pass (parents precede children), so whole-tree queries such as the
    /// smart lists can skip dead subtrees without a per-node ancestor walk.
    public func liveMask() -> [Bool] {
        var live = [Bool](repeating: true, count: count)
        guard !removed.isEmpty else { return live }
        for index in 0..<count {
            let parent = parentIDs[index]
            let parentLive = parent == FileTree.none || live[Int(parent)]
            live[index] = parentLive && !removed.contains(NodeID(index))
        }
        return live
    }

    /// Splices a freshly scanned `subtree` in place of the directory `old`: the new
    /// nodes are appended (preserving the index invariant), the parent's child chain
    /// is rewired to the new root in the same position, `old` is marked removed
    /// (its descendants become non-live), and every ancestor is re-totaled by the
    /// delta. Returns the new node id, or `old` unchanged when the request is
    /// invalid (the root, a dead node, a file, or an empty subtree).
    ///
    /// Known drift: a hard link whose first occurrence lies outside `subtree` is
    /// counted again inside it until the next full refresh.
    @discardableResult
    public mutating func replaceSubtree(at old: NodeID, with subtree: FileTree) -> NodeID {
        guard old != rootID, isLive(old), nodeFlags[Int(old)].contains(.directory),
            subtree.rootID != FileTree.none, !subtree.isEmpty
        else { return old }

        let base = NodeID(count)
        let nameBase = UInt32(nameStorage.count)
        func shifted(_ id: NodeID) -> NodeID { id == FileTree.none ? FileTree.none : id + base }

        parentIDs.append(contentsOf: subtree.parentIDs.map(shifted))
        firstChildIDs.append(contentsOf: subtree.firstChildIDs.map(shifted))
        nextSiblingIDs.append(contentsOf: subtree.nextSiblingIDs.map(shifted))
        ownSizes.append(contentsOf: subtree.ownSizes)
        totalSizes.append(contentsOf: subtree.totalSizes)
        logicalSizes.append(contentsOf: subtree.logicalSizes)
        itemCounts.append(contentsOf: subtree.itemCounts)
        modificationTimes.append(contentsOf: subtree.modificationTimes)
        nodeFlags.append(contentsOf: subtree.nodeFlags)
        nameOffsets.append(contentsOf: subtree.nameOffsets.map { $0 + nameBase })
        nameLengths.append(contentsOf: subtree.nameLengths)
        nameStorage.append(contentsOf: subtree.nameStorage)

        let new = subtree.rootID + base
        let parent = parentIDs[Int(old)]
        parentIDs[Int(new)] = parent
        nextSiblingIDs[Int(new)] = nextSiblingIDs[Int(old)]

        // Rewire through the RAW chain: a trashed sibling is still a link in it.
        if firstChildIDs[Int(parent)] == old {
            firstChildIDs[Int(parent)] = new
        } else {
            var previous = firstChildIDs[Int(parent)]
            while previous != FileTree.none, nextSiblingIDs[Int(previous)] != old {
                previous = nextSiblingIDs[Int(previous)]
            }
            if previous != FileTree.none { nextSiblingIDs[Int(previous)] = new }
        }

        // `old`'s totals are current (earlier removes already subtracted from it), and
        // a node counts as 1 item of its parent in both trees, so the deltas are exact.
        let bytesDelta = totalSizes[Int(new)] - totalSizes[Int(old)]
        let itemsDelta = itemCounts[Int(new)] - itemCounts[Int(old)]
        removed.insert(old)
        var ancestor = parent
        while ancestor != FileTree.none {
            totalSizes[Int(ancestor)] += bytesDelta
            itemCounts[Int(ancestor)] += itemsDelta
            ancestor = parentIDs[Int(ancestor)]
        }
        return new
    }

    private func nameMatches(_ node: NodeID, _ bytes: [UInt8]) -> Bool {
        let start = Int(nameOffsets[Int(node)])
        let length = Int(nameLengths[Int(node)])
        guard length == bytes.count else { return false }
        return nameStorage[start..<start + length].elementsEqual(bytes)
    }
}

// MARK: - Non-allocating traversal (for whole-tree queries such as the smart lists)

extension FileTree {
    /// The node's name as raw UTF-8 bytes — a slice of the shared buffer, so
    /// matching extensions or names over millions of nodes allocates nothing.
    public func nameUTF8(of node: NodeID) -> ArraySlice<UInt8> {
        let start = Int(nameOffsets[Int(node)])
        let length = Int(nameLengths[Int(node)])
        return nameStorage[start..<start + length]
    }

    /// Calls `body` for each live child, in insertion order, without building an array.
    public func forEachChild(of node: NodeID, _ body: (NodeID) -> Void) {
        var child = firstChildIDs[Int(node)]
        while child != FileTree.none {
            if !removed.contains(child) { body(child) }
            child = nextSiblingIDs[Int(child)]
        }
    }

    /// Pre-order walk over live descendants. `visit` returns whether to descend into
    /// that node (ignored for files), which lets callers prune bundles or subtrees.
    public func forEachDescendant(of node: NodeID, _ visit: (NodeID) -> Bool) {
        var child = firstChildIDs[Int(node)]
        while child != FileTree.none {
            if !removed.contains(child), visit(child), nodeFlags[Int(child)].contains(.directory) {
                forEachDescendant(of: child, visit)
            }
            child = nextSiblingIDs[Int(child)]
        }
    }

    /// Whether the node is a directory (cheaper than reading `flags(of:)` in hot loops).
    public func isDirectory(_ node: NodeID) -> Bool { nodeFlags[Int(node)].contains(.directory) }
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

// MARK: - Codable (scan cache)

extension FileTree: Codable {
    private enum Key: String, CodingKey {
        case rootID, parents, firstChild, nextSibling, ownSizes, totalSizes
        case logicalSizes, itemCounts, mtimes, flags, nameOffsets, nameLengths, nameStorage
        case removed
    }

    /// Encodes each parallel array as one raw-bytes `Data` blob (trivial element
    /// types), which is fast and compact — the basis of the ADR-0003 cache format.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(rootID, forKey: .rootID)
        try container.encode(Self.blob(parentIDs), forKey: .parents)
        try container.encode(Self.blob(firstChildIDs), forKey: .firstChild)
        try container.encode(Self.blob(nextSiblingIDs), forKey: .nextSibling)
        try container.encode(Self.blob(ownSizes), forKey: .ownSizes)
        try container.encode(Self.blob(totalSizes), forKey: .totalSizes)
        try container.encode(Self.blob(logicalSizes), forKey: .logicalSizes)
        try container.encode(Self.blob(itemCounts), forKey: .itemCounts)
        try container.encode(Self.blob(modificationTimes), forKey: .mtimes)
        try container.encode(Self.blob(nodeFlags), forKey: .flags)
        try container.encode(Self.blob(nameOffsets), forKey: .nameOffsets)
        try container.encode(Self.blob(nameLengths), forKey: .nameLengths)
        try container.encode(Data(nameStorage), forKey: .nameStorage)
        try container.encode(Self.blob(Array(removed)), forKey: .removed)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        rootID = try container.decode(Int32.self, forKey: .rootID)
        parentIDs = try Self.array(container.decode(Data.self, forKey: .parents))
        firstChildIDs = try Self.array(container.decode(Data.self, forKey: .firstChild))
        nextSiblingIDs = try Self.array(container.decode(Data.self, forKey: .nextSibling))
        ownSizes = try Self.array(container.decode(Data.self, forKey: .ownSizes))
        totalSizes = try Self.array(container.decode(Data.self, forKey: .totalSizes))
        logicalSizes = try Self.array(container.decode(Data.self, forKey: .logicalSizes))
        itemCounts = try Self.array(container.decode(Data.self, forKey: .itemCounts))
        modificationTimes = try Self.array(container.decode(Data.self, forKey: .mtimes))
        nodeFlags = try Self.array(container.decode(Data.self, forKey: .flags))
        nameOffsets = try Self.array(container.decode(Data.self, forKey: .nameOffsets))
        nameLengths = try Self.array(container.decode(Data.self, forKey: .nameLengths))
        nameStorage = [UInt8](try container.decode(Data.self, forKey: .nameStorage))
        let removedData = try container.decodeIfPresent(Data.self, forKey: .removed) ?? Data()
        removed = Set(try Self.array(removedData) as [NodeID])
        try Self.validate(self, codingPath: container.codingPath)
    }

    private static func blob<T>(_ array: [T]) -> Data {
        array.withUnsafeBytes { Data($0) }
    }

    /// Reconstructs `[T]` from a raw-bytes blob, rejecting a size that isn't an
    /// exact multiple of the element stride (catches a corrupt/truncated cache).
    private static func array<T>(_ data: Data) throws -> [T] {
        let stride = MemoryLayout<T>.stride
        guard data.count % stride == 0 else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "cache blob size not a multiple of stride"))
        }
        let count = data.count / stride
        return [T](unsafeUninitializedCapacity: count) { buffer, initialized in
            data.copyBytes(to: UnsafeMutableRawBufferPointer(buffer))
            initialized = count
        }
    }

    /// Rejects a structurally-inconsistent decoded tree (mismatched array lengths
    /// or name offsets past the storage end) so a corrupt cache fails to load —
    /// forcing a fresh scan — instead of crashing later in `name(of:)`.
    private static func validate(_ tree: FileTree, codingPath: [CodingKey]) throws {
        func fail(_ message: String) -> DecodingError {
            DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: message))
        }
        let count = tree.parentIDs.count
        let sameLength =
            [
                tree.firstChildIDs.count, tree.nextSiblingIDs.count, tree.ownSizes.count,
                tree.totalSizes.count, tree.logicalSizes.count, tree.itemCounts.count,
                tree.modificationTimes.count, tree.nodeFlags.count, tree.nameOffsets.count,
                tree.nameLengths.count,
            ].allSatisfy { $0 == count }
        guard sameLength else { throw fail("inconsistent array lengths") }
        guard tree.rootID == FileTree.none || (tree.rootID >= 0 && Int(tree.rootID) < count) else {
            throw fail("root id out of range")
        }
        let storageCount = tree.nameStorage.count
        for index in 0..<count
        where Int(tree.nameOffsets[index]) + Int(tree.nameLengths[index]) > storageCount {
            throw fail("name offset out of bounds")
        }
    }
}
