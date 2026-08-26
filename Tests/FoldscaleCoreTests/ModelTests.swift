import Foundation
import XCTest

@testable import FoldscaleCore

/// Tests for the node model and aggregation — no filesystem access; builders are
/// driven with synthetic streams and metadata is decoded from hand-built `stat`s.
final class ModelTests: XCTestCase {

    // MARK: - NodeMeta decoding

    func testAllocatedSizeIsBlocksTimes512() {
        var entry = stat()
        entry.st_blocks = 8  // 8 * 512 = 4096
        entry.st_size = 100
        let meta = NodeMeta.from(stat: entry, kind: .file)
        XCTAssertEqual(meta.allocatedSize, 4096)
        XCTAssertEqual(meta.logicalSize, 100)
        XCTAssertFalse(meta.flags.contains(.directory))
    }

    func testDatalessFlagIsDecodedFromStFlags() {
        var entry = stat()
        entry.st_blocks = 0  // fully evicted cloud file: no local footprint
        entry.st_size = 5_000_000  // large apparent size
        entry.st_flags = NodeMeta.sfDataless
        let meta = NodeMeta.from(stat: entry, kind: .file)
        XCTAssertTrue(meta.flags.contains(.dataless))
        XCTAssertEqual(meta.allocatedSize, 0, "Dataless file counts local footprint only")
        XCTAssertEqual(meta.logicalSize, 5_000_000)
    }

    func testDirectoryAndSymlinkKindsSetFlags() {
        var entry = stat()
        XCTAssertTrue(NodeMeta.from(stat: entry, kind: .directory).flags.contains(.directory))
        XCTAssertTrue(NodeMeta.from(stat: entry, kind: .symlink).flags.contains(.symlink))
        entry.st_ino = 99
        XCTAssertEqual(NodeMeta.from(stat: entry, kind: .file).inode, 99)
    }

    // MARK: - Aggregation

    /// Drives a builder through a fixed tree shape used by several tests.
    ///
    /// ```
    /// root(4096)
    /// ├── a.txt(8192)
    /// ├── sub(4096) ── b.bin(40960), c.bin(4096)
    /// └── big(4096) ── d.dat(1048576)
    /// ```
    private func buildSampleTree<Builder: TreeBuilder>(_ builder: inout Builder) {
        builder.enterDirectory(name: "root", meta: dir(4096))
        builder.addLeaf(name: "a.txt", meta: file(8192))
        builder.enterDirectory(name: "sub", meta: dir(4096))
        builder.addLeaf(name: "b.bin", meta: file(40960))
        builder.addLeaf(name: "c.bin", meta: file(4096))
        builder.leaveDirectory()
        builder.enterDirectory(name: "big", meta: dir(4096))
        builder.addLeaf(name: "d.dat", meta: file(1_048_576))
        builder.leaveDirectory()
        builder.leaveDirectory()
    }

    private let expectedTotal: Int64 = 4096 + 8192 + (4096 + 40960 + 4096) + (4096 + 1_048_576)

    func testStructOfArraysAggregation() {
        var builder = FileTreeBuilder()
        buildSampleTree(&builder)
        let tree = builder.finish()
        let root = tree.rootID

        XCTAssertEqual(tree.count, 7)
        XCTAssertEqual(tree.name(of: root), "root")
        XCTAssertEqual(tree.totalAllocatedSize(of: root), expectedTotal)
        XCTAssertEqual(tree.itemCount(of: root), 6)

        let byName = Dictionary(uniqueKeysWithValues: tree.children(of: root).map { (tree.name(of: $0), $0) })
        XCTAssertEqual(tree.totalAllocatedSize(of: byName["sub"]!), 49152)
        XCTAssertEqual(tree.itemCount(of: byName["sub"]!), 2)
        XCTAssertEqual(tree.totalAllocatedSize(of: byName["big"]!), 1_052_672)

        // Default ordering at every depth is size-descending.
        let sorted = tree.childrenSortedBySize(of: root).map { tree.name(of: $0) }
        XCTAssertEqual(sorted, ["big", "sub", "a.txt"])

        XCTAssertEqual(tree.path(of: byName["big"]!), "root/big")
    }

    func testHardlinkDuplicateContributesZero() {
        var builder = FileTreeBuilder()
        builder.enterDirectory(name: "root", meta: dir(4096))
        builder.addLeaf(name: "original", meta: file(1_000_000))
        builder.addLeaf(name: "hardlink", meta: file(1_000_000, flags: [.hardlinkDuplicate]))
        builder.leaveDirectory()
        let tree = builder.finish()
        // Counted once: root own (4096) + original (1_000_000) + duplicate (0).
        XCTAssertEqual(tree.totalAllocatedSize(of: tree.rootID), 4096 + 1_000_000)
    }

    func testStructOfArraysAndClassLayoutsAgree() {
        var soaBuilder = FileTreeBuilder()
        buildSampleTree(&soaBuilder)
        let tree = soaBuilder.finish()

        var classBuilder = ClassTreeBuilder()
        buildSampleTree(&classBuilder)
        let root = classBuilder.finish()

        XCTAssertNotNil(root)
        XCTAssertEqual(tree.totalAllocatedSize(of: tree.rootID), root?.totalSize)
        XCTAssertEqual(tree.itemCount(of: tree.rootID), root?.itemCount)
    }

    func testEmptyDirectoryTree() {
        var builder = FileTreeBuilder()
        builder.enterDirectory(name: "empty", meta: dir(4096))
        builder.leaveDirectory()
        let tree = builder.finish()
        XCTAssertEqual(tree.count, 1)
        XCTAssertEqual(tree.totalAllocatedSize(of: tree.rootID), 4096)
        XCTAssertEqual(tree.itemCount(of: tree.rootID), 0)
    }

    // MARK: - Helpers

    private func dir(_ allocated: Int64) -> NodeMeta {
        NodeMeta(
            allocatedSize: allocated, logicalSize: allocated, modificationTime: 0,
            flags: [.directory], deviceID: 1, inode: 0, linkCount: 1
        )
    }

    private func file(_ allocated: Int64, flags: NodeFlags = []) -> NodeMeta {
        NodeMeta(
            allocatedSize: allocated, logicalSize: allocated, modificationTime: 0,
            flags: flags, deviceID: 1, inode: 0, linkCount: 1
        )
    }
}
