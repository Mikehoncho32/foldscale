import Foundation
import XCTest

@testable import FoldscaleCore

/// Tests for node-id validation across trash/exclude (`isLive`) and the
/// whole-drive device policy used by the sidebar's drive tree.
final class TreeNavigationTests: XCTestCase {

    // MARK: - isLive

    func testIsLiveRejectsOutOfRangeAndRemovedAndDescendantsOfRemoved() {
        var builder = FileTreeBuilder()
        builder.enterDirectory(name: "root", meta: dir())
        builder.enterDirectory(name: "sub", meta: dir())
        builder.addLeaf(name: "b.bin", meta: file(100))
        builder.leaveDirectory()
        builder.addLeaf(name: "keep", meta: file(10))
        builder.leaveDirectory()
        var tree = builder.finish()

        let root = tree.rootID
        let sub = tree.children(of: root).first { tree.name(of: $0) == "sub" }!
        let inner = tree.children(of: sub)[0]
        let keep = tree.children(of: root).first { tree.name(of: $0) == "keep" }!

        XCTAssertTrue(tree.isLive(root))
        XCTAssertTrue(tree.isLive(inner))
        XCTAssertFalse(tree.isLive(-1))
        XCTAssertFalse(tree.isLive(FileTree.NodeID(tree.count)), "id past the end is not live")

        tree.remove(sub)
        XCTAssertFalse(tree.isLive(sub), "removed node")
        XCTAssertFalse(tree.isLive(inner), "descendant of a removed node")
        XCTAssertTrue(tree.isLive(keep))
        XCTAssertTrue(tree.isLive(root))
    }

    // MARK: - VolumePolicy

    func testAllowedDevicesForOrdinaryFolderIsJustItsDevice() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("foldscale-nav-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var entry = stat()
        XCTAssertEqual(lstat(dir.path, &entry), 0)
        XCTAssertEqual(VolumePolicy.allowedDevices(forRoot: dir.path, rootStat: entry), [Int64(entry.st_dev)])
    }

    func testAllowedDevicesForRootIncludesDataVolume() throws {
        var rootStat = stat()
        XCTAssertEqual(lstat("/", &rootStat), 0)
        let allowed = VolumePolicy.allowedDevices(forRoot: "/", rootStat: rootStat)
        XCTAssertTrue(allowed.contains(Int64(rootStat.st_dev)))

        var dataStat = stat()
        try XCTSkipIf(lstat(VolumePolicy.dataVolumePath, &dataStat) != 0, "no Data volume on this system")
        XCTAssertTrue(
            allowed.contains(Int64(dataStat.st_dev)),
            "a whole-drive scan must be allowed into the Data volume (firmlinked user folders)")
    }

    // MARK: - Helpers

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
