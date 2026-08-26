import Foundation

/// Consumes a depth-first pre/post-order stream of filesystem nodes and builds a
/// tree. Both node layouts implement it — the struct-of-arrays `FileTreeBuilder`
/// and the `ClassTreeBuilder` baseline — so a single walk can drive either. That
/// is the basis of the ADR-0001 node-layout benchmark.
///
/// The `name` buffer handed to `enterDirectory`/`addLeaf` is valid only for the
/// duration of that call; a builder must copy it before returning.
public protocol TreeBuilder {
    /// Hint the expected node count so storage can be pre-sized. Optional; the
    /// default does nothing. The struct-of-arrays builder uses it to avoid the
    /// ~2× overhead of geometric array growth (see ADR-0001).
    mutating func reserveCapacity(_ minimumCapacity: Int)

    /// Open a directory node (pre-order); paired with a later `leaveDirectory()`.
    mutating func enterDirectory(name: UnsafeBufferPointer<UInt8>, meta: NodeMeta)

    /// Add a non-directory node (file / symlink / other).
    mutating func addLeaf(name: UnsafeBufferPointer<UInt8>, meta: NodeMeta)

    /// Close the most-recently-opened directory (post-order).
    mutating func leaveDirectory()
}

extension TreeBuilder {
    /// No-op default: layouts that don't benefit from pre-sizing ignore the hint.
    public mutating func reserveCapacity(_ minimumCapacity: Int) {}

    /// Convenience for tests: open a directory using a Swift `String` name.
    public mutating func enterDirectory(name: String, meta: NodeMeta) {
        let bytes = Array(name.utf8)
        bytes.withUnsafeBufferPointer { enterDirectory(name: $0, meta: meta) }
    }

    /// Convenience for tests: add a leaf using a Swift `String` name.
    public mutating func addLeaf(name: String, meta: NodeMeta) {
        let bytes = Array(name.utf8)
        bytes.withUnsafeBufferPointer { addLeaf(name: $0, meta: meta) }
    }
}
