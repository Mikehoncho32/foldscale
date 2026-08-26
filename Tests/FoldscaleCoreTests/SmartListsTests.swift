import Foundation
import XCTest

@testable import FoldscaleCore

/// Tests for the smart-list queries and the scan-cache serialization.
final class SmartListsTests: XCTestCase {
    private var cacheDirectory: URL!

    /// Point the cache at a throwaway directory so these tests never clobber the
    /// user's real scan cache in Application Support.
    override func setUp() {
        super.setUp()
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("foldscale-cache-test-\(UUID().uuidString)")
        ScanCache.directoryOverride = cacheDirectory
    }

    override func tearDown() {
        ScanCache.directoryOverride = nil
        try? FileManager.default.removeItem(at: cacheDirectory)
        super.tearDown()
    }

    // MARK: - Smart lists

    func testLargeFilesReturnsTopBySizeExcludingDirectories() {
        var builder = FileTreeBuilder()
        builder.enterDirectory(name: "root", meta: dir(0))
        builder.addLeaf(name: "small", meta: file(100))
        builder.addLeaf(name: "huge", meta: file(300))
        builder.addLeaf(name: "medium", meta: file(200))
        builder.enterDirectory(name: "subdir", meta: dir(999))  // a directory, must be excluded
        builder.leaveDirectory()
        builder.leaveDirectory()
        let tree = builder.finish()

        let top = SmartLists.largeFiles(in: tree, limit: 2).map { tree.name(of: $0) }
        XCTAssertEqual(top, ["huge", "medium"])
        XCTAssertFalse(
            SmartLists.largeFiles(in: tree).contains { tree.flags(of: $0).contains(.directory) })
    }

    func testOldAndBigFiltersBySizeAndModificationTime() {
        var builder = FileTreeBuilder()
        builder.enterDirectory(name: "root", meta: dir(0))
        builder.addLeaf(name: "new-big", meta: file(1000, mtime: 2_000_000_000))
        builder.addLeaf(name: "old-big", meta: file(1000, mtime: 1_000_000_000))
        builder.addLeaf(name: "old-small", meta: file(10, mtime: 1_000_000_000))
        builder.leaveDirectory()
        let tree = builder.finish()

        let cutoff = Date(timeIntervalSince1970: 1_500_000_000)
        let result = SmartLists.oldAndBig(in: tree, minBytes: 500, olderThan: cutoff)
            .map { tree.name(of: $0) }
        XCTAssertEqual(result, ["old-big"])
    }

    // MARK: - Cache round-trip

    func testFileTreeCodableRoundTrip() throws {
        var builder = FileTreeBuilder()
        builder.enterDirectory(name: "root", meta: dir(4096))
        builder.addLeaf(name: "a.txt", meta: file(8192))
        builder.enterDirectory(name: "sub", meta: dir(4096))
        builder.addLeaf(name: "b.bin", meta: file(40960))
        builder.leaveDirectory()
        builder.leaveDirectory()
        let original = builder.finish()

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(original)
        let restored = try PropertyListDecoder().decode(FileTree.self, from: data)

        XCTAssertEqual(restored.count, original.count)
        XCTAssertEqual(restored.rootID, original.rootID)
        XCTAssertEqual(
            restored.totalAllocatedSize(of: restored.rootID),
            original.totalAllocatedSize(of: original.rootID))
        XCTAssertEqual(restored.itemCount(of: restored.rootID), original.itemCount(of: original.rootID))
        XCTAssertEqual(
            restored.children(of: restored.rootID).map { restored.name(of: $0) },
            original.children(of: original.rootID).map { original.name(of: $0) })
        let sub = restored.children(of: restored.rootID).first { restored.name(of: $0) == "sub" }!
        XCTAssertEqual(restored.name(of: restored.children(of: sub)[0]), "b.bin")
    }

    func testScanCacheSaveAndLoad() throws {
        var builder = FileTreeBuilder()
        builder.enterDirectory(name: "root", meta: dir(4096))
        builder.addLeaf(name: "x.bin", meta: file(12345))
        builder.leaveDirectory()
        let tree = builder.finish()

        let when = Date(timeIntervalSince1970: 1_700_000_000)
        try ScanCache.save(tree: tree, rootPath: "/tmp/root", savedAt: when)
        let snapshot = try XCTUnwrap(ScanCache.load())

        XCTAssertEqual(snapshot.rootPath, "/tmp/root")
        XCTAssertEqual(snapshot.savedAt.timeIntervalSince1970, when.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(
            snapshot.tree.totalAllocatedSize(of: snapshot.tree.rootID),
            tree.totalAllocatedSize(of: tree.rootID))
    }

    func testSmartListsSkipRemovedNodes() {
        var builder = FileTreeBuilder()
        builder.enterDirectory(name: "root", meta: dir(0))
        builder.addLeaf(name: "huge", meta: file(1_000_000))
        builder.addLeaf(name: "big", meta: file(500_000))
        builder.leaveDirectory()
        var tree = builder.finish()
        let huge = tree.children(of: tree.rootID).first { tree.name(of: $0) == "huge" }!

        XCTAssertEqual(SmartLists.largeFiles(in: tree).map { tree.name(of: $0) }, ["huge", "big"])
        tree.remove(huge)
        XCTAssertEqual(SmartLists.largeFiles(in: tree).map { tree.name(of: $0) }, ["big"])
    }

    func testCachePreservesRemovedSet() throws {
        var builder = FileTreeBuilder()
        builder.enterDirectory(name: "root", meta: dir(0))
        builder.addLeaf(name: "keep", meta: file(100))
        builder.addLeaf(name: "gone", meta: file(200))
        builder.leaveDirectory()
        var tree = builder.finish()
        let gone = tree.children(of: tree.rootID).first { tree.name(of: $0) == "gone" }!
        tree.remove(gone)

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let restored = try PropertyListDecoder().decode(FileTree.self, from: encoder.encode(tree))

        XCTAssertTrue(restored.isRemoved(gone))
        XCTAssertEqual(
            restored.children(of: restored.rootID).map { restored.name(of: $0) }, ["keep"])
        XCTAssertEqual(
            restored.totalAllocatedSize(of: restored.rootID),
            tree.totalAllocatedSize(of: tree.rootID))
    }

    func testScanCacheLoadFailsSoftOnGarbage() throws {
        try FileManager.default.createDirectory(
            at: ScanCache.directory, withIntermediateDirectories: true)
        let fileURL = ScanCache.directory.appendingPathComponent("last-scan.foldscalecache")
        try Data([0x00, 0x01, 0x02, 0x03, 0x04]).write(to: fileURL)  // not LZFSE / not a plist
        XCTAssertNil(ScanCache.load(), "A corrupt cache must load as nil, forcing a fresh scan")
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Helpers

    private func dir(_ allocated: Int64) -> NodeMeta {
        NodeMeta(
            allocatedSize: allocated, logicalSize: allocated, modificationTime: 0,
            flags: [.directory], deviceID: 1, inode: 0, linkCount: 1)
    }

    private func file(_ allocated: Int64, mtime: Int64 = 0) -> NodeMeta {
        NodeMeta(
            allocatedSize: allocated, logicalSize: allocated, modificationTime: mtime,
            flags: [], deviceID: 1, inode: 0, linkCount: 1)
    }

    func testAdoptsRadixCacheOnFirstLoad() throws {
        let fileManager = FileManager.default
        let legacy = ScanCache.directory.deletingLastPathComponent()
            .appendingPathComponent("legacy-radix-\(UUID().uuidString)", isDirectory: true)
        ScanCache.legacyDirectoryOverride = legacy
        defer {
            ScanCache.legacyDirectoryOverride = nil
            try? fileManager.removeItem(at: legacy)
        }
        var builder = FileTreeBuilder()
        builder.enterDirectory(
            name: "root",
            meta: NodeMeta(
                allocatedSize: 0, logicalSize: 0, modificationTime: 0, flags: [.directory],
                deviceID: 1, inode: 1, linkCount: 1))
        builder.leaveDirectory()
        // Save a cache, then move it to where Radix 1.1 kept it.
        try ScanCache.save(tree: builder.finish(), rootPath: "/", savedAt: Date())
        try fileManager.createDirectory(at: legacy, withIntermediateDirectories: true)
        try fileManager.moveItem(
            at: ScanCache.directory.appendingPathComponent("last-scan.foldscalecache"),
            to: legacy.appendingPathComponent("last-scan.radixcache"))
        try fileManager.removeItem(at: ScanCache.directory)  // as on a fresh 1.2 install

        XCTAssertEqual(ScanCache.load()?.rootPath, "/")
        XCTAssertFalse(fileManager.fileExists(atPath: legacy.path), "old folder was renamed, not copied")
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: ScanCache.directory.appendingPathComponent("last-scan.foldscalecache").path))
    }
}
