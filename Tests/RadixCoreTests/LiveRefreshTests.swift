import Foundation
import XCTest

@testable import RadixCore

/// Tests for the live-refresh foundation: path lookup, the subtree splice, the
/// liveness mask used by smart lists, and the scanner's hint / policy options.
final class LiveRefreshTests: XCTestCase {
    private var tempDirs: [URL] = []

    override func tearDown() {
        for dir in tempDirs { try? FileManager.default.removeItem(at: dir) }
        tempDirs.removeAll()
        super.tearDown()
    }

    // MARK: - Fixtures
    //
    // base:  root ── a.txt(100), sub ── x(10), y(20), z(5)
    // fresh: sub  ── p(1000), q ── r(7)

    private func makeBase() -> FileTree {
        var builder = FileTreeBuilder()
        builder.enterDirectory(name: "root", meta: dir())
        builder.addLeaf(name: "a.txt", meta: file(100))
        builder.enterDirectory(name: "sub", meta: dir())
        builder.addLeaf(name: "x", meta: file(10))
        builder.addLeaf(name: "y", meta: file(20))
        builder.leaveDirectory()
        builder.addLeaf(name: "z", meta: file(5))
        builder.leaveDirectory()
        return builder.finish()
    }

    private func makeFreshSub(named name: String = "sub") -> FileTree {
        var builder = FileTreeBuilder()
        builder.enterDirectory(name: name, meta: dir())
        builder.addLeaf(name: "p", meta: file(1000))
        builder.enterDirectory(name: "q", meta: dir())
        builder.addLeaf(name: "r", meta: file(7))
        builder.leaveDirectory()
        builder.leaveDirectory()
        return builder.finish()
    }

    /// The oracle: what the tree would look like if scanned from scratch after the
    /// change.
    private func makeExpectedAfterSplice() -> FileTree {
        var builder = FileTreeBuilder()
        builder.enterDirectory(name: "root", meta: dir())
        builder.addLeaf(name: "a.txt", meta: file(100))
        builder.enterDirectory(name: "sub", meta: dir())
        builder.addLeaf(name: "p", meta: file(1000))
        builder.enterDirectory(name: "q", meta: dir())
        builder.addLeaf(name: "r", meta: file(7))
        builder.leaveDirectory()
        builder.leaveDirectory()
        builder.addLeaf(name: "z", meta: file(5))
        builder.leaveDirectory()
        return builder.finish()
    }

    private func child(_ tree: FileTree, of parent: FileTree.NodeID, named name: String) -> FileTree.NodeID {
        tree.children(of: parent).first { tree.name(of: $0) == name }!
    }

    // MARK: - node(atPathComponents:)

    func testPathLookup() {
        var tree = makeBase()
        XCTAssertEqual(tree.node(atPathComponents: []), tree.rootID)
        let y = try? XCTUnwrap(tree.node(atPathComponents: ["sub", "y"]))
        XCTAssertEqual(y.map { tree.name(of: $0) }, "y")
        XCTAssertEqual(y.map { tree.totalAllocatedSize(of: $0) }, 20)
        XCTAssertNil(tree.node(atPathComponents: ["sub", "nope"]))
        XCTAssertNil(tree.node(atPathComponents: ["a.txt", "deeper"]))

        tree.remove(child(tree, of: tree.rootID, named: "sub"))
        XCTAssertNil(tree.node(atPathComponents: ["sub", "y"]), "path through a removed node")
        XCTAssertNotNil(tree.node(atPathComponents: ["z"]))
    }

    // MARK: - replaceSubtree

    func testSpliceMatchesScratchBuiltOracle() {
        var tree = makeBase()
        let expected = makeExpectedAfterSplice()
        let old = child(tree, of: tree.rootID, named: "sub")
        let oldCount = tree.count

        let new = tree.replaceSubtree(at: old, with: makeFreshSub())

        XCTAssertNotEqual(new, old)
        XCTAssertEqual(tree.count, oldCount + 4, "fresh subtree nodes were appended")
        XCTAssertEqual(
            tree.totalAllocatedSize(of: tree.rootID), expected.totalAllocatedSize(of: expected.rootID))
        XCTAssertEqual(tree.itemCount(of: tree.rootID), expected.itemCount(of: expected.rootID))
        XCTAssertEqual(tree.totalAllocatedSize(of: tree.rootID), 100 + 1007 + 5)
        XCTAssertEqual(tree.itemCount(of: tree.rootID), 6)

        // Same position in the parent, same name, new contents resolvable by path.
        XCTAssertEqual(tree.children(of: tree.rootID).map { tree.name(of: $0) }, ["a.txt", "sub", "z"])
        XCTAssertEqual(tree.children(of: tree.rootID)[1], new)
        XCTAssertEqual(tree.name(of: new), "sub")
        let leaf = tree.node(atPathComponents: ["sub", "q", "r"])
        XCTAssertEqual(leaf.map { tree.totalAllocatedSize(of: $0) }, 7)
        XCTAssertEqual(tree.path(of: leaf!), "root/sub/q/r")

        // Old subtree is dead; new one is live.
        XCTAssertTrue(tree.isRemoved(old))
        XCTAssertFalse(tree.isLive(old))
        XCTAssertTrue(tree.isLive(new))
        XCTAssertTrue(tree.isLive(leaf!))
        let live = tree.liveMask()
        XCTAssertEqual(live.filter { $0 }.count, 7, "root, a.txt, new sub, p, q, r, z")
    }

    func testSpliceAfterPriorRemoveInsideOldSubtreeUsesCurrentTotals() {
        var tree = makeBase()
        let old = child(tree, of: tree.rootID, named: "sub")
        tree.remove(child(tree, of: old, named: "x"))
        XCTAssertEqual(tree.totalAllocatedSize(of: tree.rootID), 125)

        tree.replaceSubtree(at: old, with: makeFreshSub())
        XCTAssertEqual(tree.totalAllocatedSize(of: tree.rootID), 1112)
        XCTAssertEqual(tree.itemCount(of: tree.rootID), 6)
    }

    func testSpliceSiblingPositionsWithTrashedPriorSibling() {
        func fixture() -> (FileTree, [FileTree.NodeID]) {
            var builder = FileTreeBuilder()
            builder.enterDirectory(name: "root", meta: dir())
            for name in ["d1", "d2", "d3"] {
                builder.enterDirectory(name: name, meta: dir())
                builder.addLeaf(name: "f", meta: file(1))
                builder.leaveDirectory()
            }
            builder.leaveDirectory()
            let tree = builder.finish()
            return (tree, tree.children(of: tree.rootID))
        }
        for (index, name) in ["d1", "d2", "d3"].enumerated() {
            var (tree, dirs) = fixture()
            let new = tree.replaceSubtree(at: dirs[index], with: makeFreshSub(named: name))
            let names = tree.children(of: tree.rootID).map { tree.name(of: $0) }
            XCTAssertEqual(names, ["d1", "d2", "d3"], "order preserved when replacing \(name)")
            XCTAssertEqual(tree.children(of: tree.rootID)[index], new)
        }
        // A trashed earlier sibling is still a link in the raw chain.
        var (tree, dirs) = fixture()
        tree.remove(dirs[0])
        let new = tree.replaceSubtree(at: dirs[1], with: makeFreshSub(named: "d2"))
        XCTAssertEqual(tree.children(of: tree.rootID), [new, dirs[2]])
        XCTAssertEqual(tree.totalAllocatedSize(of: tree.rootID), 1007 + 1)
    }

    func testSpliceGuardsAreNoOps() {
        var tree = makeBase()
        let root = tree.rootID
        let before = tree.count
        XCTAssertEqual(tree.replaceSubtree(at: root, with: makeFreshSub()), root)
        let aTxt = child(tree, of: root, named: "a.txt")
        XCTAssertEqual(tree.replaceSubtree(at: aTxt, with: makeFreshSub()), aTxt, "files can't be replaced")
        let sub = child(tree, of: root, named: "sub")
        var emptyBuilder = FileTreeBuilder()
        let emptyTree = emptyBuilder.finish()
        XCTAssertEqual(tree.replaceSubtree(at: sub, with: emptyTree), sub, "empty subtree")
        tree.remove(sub)
        XCTAssertEqual(tree.replaceSubtree(at: sub, with: makeFreshSub()), sub, "dead node")
        XCTAssertEqual(tree.count, before)
    }

    func testInvariantHoldsAfterTwoSplicesAndSurvivesCodable() throws {
        var tree = makeBase()
        let first = tree.replaceSubtree(at: child(tree, of: tree.rootID, named: "sub"), with: makeFreshSub())
        let second = tree.replaceSubtree(at: first, with: makeFreshSub())
        XCTAssertNotEqual(first, second)
        for index in 1..<tree.count {
            XCTAssertLessThan(tree.parent(of: FileTree.NodeID(index)), FileTree.NodeID(index))
        }
        XCTAssertEqual(tree.totalAllocatedSize(of: tree.rootID), 1112)

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let restored = try PropertyListDecoder().decode(FileTree.self, from: encoder.encode(tree))
        XCTAssertEqual(restored.totalAllocatedSize(of: restored.rootID), 1112)
        XCTAssertEqual(
            restored.children(of: restored.rootID).map { restored.name(of: $0) }, ["a.txt", "sub", "z"])
        XCTAssertTrue(restored.isRemoved(first))
        XCTAssertEqual(restored.node(atPathComponents: ["sub", "q", "r"]).map { restored.name(of: $0) }, "r")
    }

    // MARK: - Smart lists use liveness

    func testSmartListsExcludeFilesUnderRemovedDirectoryAndDeadSubtrees() {
        var tree = makeBase()
        let sub = child(tree, of: tree.rootID, named: "sub")
        XCTAssertTrue(SmartLists.largeFiles(in: tree).map { tree.name(of: $0) }.contains("y"))

        tree.remove(sub)
        XCTAssertFalse(
            SmartLists.largeFiles(in: tree).map { tree.name(of: $0) }.contains("y"),
            "files under a trashed directory must not be listed")

        var spliced = makeBase()
        spliced.replaceSubtree(at: child(spliced, of: spliced.rootID, named: "sub"), with: makeFreshSub())
        let names = SmartLists.largeFiles(in: spliced).map { spliced.name(of: $0) }
        XCTAssertEqual(names, ["p", "a.txt", "r", "z"])
    }

    // MARK: - Scanner options

    func testCapacityHintSkipsPrecountAndYieldsSameTree() throws {
        let root = try makeTempTree()
        let reference = try Scanner.scan(at: root, options: ScanOptions(exclusions: .none))
        for hint in [1, 10_000] {
            let walker = DirectoryWalker(
                builder: FileTreeBuilder(),
                options: ScanOptions(exclusions: .none, capacityHint: hint),
                isCancelled: { false }, onProgress: { _ in })
            try walker.run(rootPath: root.path)
            let tree = walker.builder.finish()
            XCTAssertFalse(walker.didPrecount, "hint \(hint)")
            XCTAssertEqual(tree.count, reference.count)
            XCTAssertEqual(
                tree.totalAllocatedSize(of: tree.rootID), reference.totalAllocatedSize(of: reference.rootID))
        }
        let plain = DirectoryWalker(
            builder: FileTreeBuilder(), options: ScanOptions(exclusions: .none),
            isCancelled: { false }, onProgress: { _ in })
        try plain.run(rootPath: root.path)
        XCTAssertTrue(plain.didPrecount)
    }

    func testVolumePolicyRootAppliesFullScanDevices() throws {
        let root = try makeTempTree()
        let walker = DirectoryWalker(
            builder: FileTreeBuilder(),
            options: ScanOptions(exclusions: .none, volumePolicyRoot: "/"),
            isCancelled: { false }, onProgress: { _ in })
        try walker.run(rootPath: root.path)

        var rootStat = stat()
        XCTAssertEqual(lstat("/", &rootStat), 0)
        let expected = VolumePolicy.allowedDevices(forRoot: "/", rootStat: rootStat)
        XCTAssertTrue(walker.allowedDevices.isSuperset(of: expected))
        var own = stat()
        XCTAssertEqual(lstat(root.path, &own), 0)
        XCTAssertTrue(
            walker.allowedDevices.contains(Int64(own.st_dev)), "the subtree's own device stays allowed")
    }

    // MARK: - Helpers

    private func makeTempTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("radix-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data(count: 20_000).write(to: root.appendingPathComponent("a.bin"))
        try Data(count: 5_000).write(to: root.appendingPathComponent("sub/b.bin"))
        tempDirs.append(root)
        return root
    }

    private func dir() -> NodeMeta {
        NodeMeta(
            allocatedSize: 0, logicalSize: 0, modificationTime: 0,
            flags: [.directory], deviceID: 1, inode: 0, linkCount: 1)
    }

    private func file(_ allocated: Int64) -> NodeMeta {
        NodeMeta(
            allocatedSize: allocated, logicalSize: allocated, modificationTime: 0,
            flags: [], deviceID: 1, inode: 0, linkCount: 1)
    }
}
