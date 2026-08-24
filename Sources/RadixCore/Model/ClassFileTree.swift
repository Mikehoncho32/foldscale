import Foundation

/// A class-per-node tree — the ADR-0001 baseline that the struct-of-arrays layout
/// is measured against. Ergonomic (natural recursion, reference identity) but
/// higher per-node overhead: object header, ARC, and a child array per node.
public final class ClassFileNode {
    public let name: String
    public let flags: NodeFlags
    public let ownSize: Int64
    public let logicalSize: Int64
    public let modificationTime: Int64
    public private(set) var children: [ClassFileNode] = []
    public private(set) var totalSize: Int64
    public private(set) var itemCount: Int64 = 0

    init(name: String, meta: NodeMeta) {
        self.name = name
        self.flags = meta.flags
        self.ownSize = meta.flags.contains(.hardlinkDuplicate) ? 0 : meta.allocatedSize
        self.logicalSize = meta.logicalSize
        self.modificationTime = meta.modificationTime
        self.totalSize = meta.flags.contains(.hardlinkDuplicate) ? 0 : meta.allocatedSize
    }

    func addChild(_ child: ClassFileNode) {
        children.append(child)
    }

    /// Aggregates sizes and descendant counts bottom-up (recursive).
    func aggregate() {
        var total = ownSize
        var items: Int64 = 0
        for child in children {
            child.aggregate()
            total += child.totalSize
            items += child.itemCount + 1
        }
        totalSize = total
        itemCount = items
    }
}

/// Builds a ``ClassFileNode`` tree from a depth-first scan stream.
public struct ClassTreeBuilder: TreeBuilder {
    private var stack: [ClassFileNode] = []
    public private(set) var root: ClassFileNode?

    public init() {}

    public mutating func enterDirectory(name: UnsafeBufferPointer<UInt8>, meta: NodeMeta) {
        let node = ClassFileNode(name: String(decoding: name, as: UTF8.self), meta: meta)
        if let parent = stack.last {
            parent.addChild(node)
        } else {
            root = node
        }
        stack.append(node)
    }

    public mutating func addLeaf(name: UnsafeBufferPointer<UInt8>, meta: NodeMeta) {
        let node = ClassFileNode(name: String(decoding: name, as: UTF8.self), meta: meta)
        stack.last?.addChild(node)
    }

    public mutating func leaveDirectory() {
        stack.removeLast()
    }

    /// Finalizes: aggregates the tree and returns the root (or `nil` if empty).
    public mutating func finish() -> ClassFileNode? {
        root?.aggregate()
        return root
    }
}
