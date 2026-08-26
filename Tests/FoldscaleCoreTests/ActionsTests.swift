import Foundation
import XCTest

@testable import FoldscaleCore

/// Tests for the safety-critical action layer: protected paths, the trash service,
/// and live re-totaling.
final class ActionsTests: XCTestCase {
    private var tempDirs: [URL] = []

    override func tearDown() {
        for dir in tempDirs { try? FileManager.default.removeItem(at: dir) }
        tempDirs.removeAll()
        super.tearDown()
    }

    // MARK: - ProtectedPaths

    func testSystemLocationsAreProtected() {
        for path in [
            "/", "/System/Library", "/usr/bin/env", "/bin/ls", "/private/var/x",
            "/Library/Preferences", "/Applications/Utilities/Terminal.app",
        ] {
            XCTAssertTrue(
                ProtectedPaths.isProtected(URL(fileURLWithPath: path)), "\(path) should be protected")
        }
    }

    func testUserLocationsAreNotProtected() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for url in [
            home.appendingPathComponent("Library/Caches/foo"),
            home.appendingPathComponent("Downloads/big.zip"),
            URL(fileURLWithPath: "/Applications/SomeApp.app"),
            URL(fileURLWithPath: "/LibraryFoo/x"),
        ] {
            XCTAssertFalse(ProtectedPaths.isProtected(url), "\(url.path) should NOT be protected")
        }
    }

    func testAdditionalProtectedRoots() {
        let bundle = URL(fileURLWithPath: "/Applications/Foldscale.app")
        let inside = bundle.appendingPathComponent("Contents/MacOS/Foldscale")
        XCTAssertTrue(ProtectedPaths.isProtected(inside, additionalProtected: [bundle]))
        XCTAssertFalse(ProtectedPaths.isProtected(inside))
    }

    // MARK: - TrashService

    func testMoveToTrashReclaimsAndRemovesOriginals() throws {
        let dir = try makeTempDir()
        let fileA = dir.appendingPathComponent("a.bin")
        let fileB = dir.appendingPathComponent("b.bin")
        try Data(count: 4096).write(to: fileA)
        try Data(count: 8192).write(to: fileB)

        let outcome = TrashService.moveToTrash(
            [TrashItem(url: fileA, allocatedBytes: 4096), TrashItem(url: fileB, allocatedBytes: 8192)],
            isProtected: { _ in false })

        XCTAssertEqual(outcome.trashed.count, 2)
        XCTAssertEqual(outcome.reclaimedBytes, 12288)
        XCTAssertTrue(outcome.failed.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileA.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileB.path))

        // Don't pollute the user's Trash with test artifacts.
        for location in outcome.trashedLocations { try? FileManager.default.removeItem(at: location) }
    }

    func testMoveToTrashRefusesProtected() throws {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("keep.bin")
        try Data(count: 1024).write(to: file)

        let outcome = TrashService.moveToTrash(
            [TrashItem(url: file, allocatedBytes: 1024)], isProtected: { _ in true })

        XCTAssertEqual(outcome.refused, [file])
        XCTAssertTrue(outcome.trashed.isEmpty)
        XCTAssertEqual(outcome.reclaimedBytes, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "Protected file untouched")
    }

    // MARK: - Live re-total

    func testRemoveRetotalsAncestors() {
        var builder = FileTreeBuilder()
        builder.enterDirectory(name: "root", meta: dir(0))
        builder.addLeaf(name: "keep", meta: file(100))
        builder.enterDirectory(name: "big", meta: dir(0))
        builder.addLeaf(name: "a", meta: file(1000))
        builder.addLeaf(name: "b", meta: file(2000))
        builder.leaveDirectory()
        builder.leaveDirectory()
        var tree = builder.finish()
        let root = tree.rootID
        let byName = Dictionary(uniqueKeysWithValues: tree.children(of: root).map { (tree.name(of: $0), $0) })
        let big = byName["big"]!

        XCTAssertEqual(tree.totalAllocatedSize(of: root), 3100)
        XCTAssertEqual(tree.itemCount(of: root), 4)

        tree.remove(big)

        XCTAssertEqual(tree.totalAllocatedSize(of: root), 100, "root total drops by the big subtree")
        XCTAssertEqual(tree.itemCount(of: root), 1)
        XCTAssertTrue(tree.isRemoved(big))
        XCTAssertEqual(tree.children(of: root).map { tree.name(of: $0) }, ["keep"])
    }

    func testPathComponentsFromRootExcludeRoot() {
        var builder = FileTreeBuilder()
        builder.enterDirectory(name: "Desktop", meta: dir(0))
        builder.enterDirectory(name: "sub", meta: dir(0))
        builder.addLeaf(name: "file.txt", meta: file(10))
        builder.leaveDirectory()
        builder.leaveDirectory()
        let tree = builder.finish()
        let sub = tree.children(of: tree.rootID)[0]
        let file = tree.children(of: sub)[0]
        XCTAssertEqual(tree.pathComponentsFromRoot(of: file), ["sub", "file.txt"])
        XCTAssertEqual(tree.pathComponentsFromRoot(of: tree.rootID), [])
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("foldscale-actions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        return dir
    }

    private func dir(_ allocated: Int64) -> NodeMeta {
        NodeMeta(
            allocatedSize: allocated, logicalSize: allocated, modificationTime: 0,
            flags: [.directory], deviceID: 1, inode: 0, linkCount: 1)
    }

    private func file(_ allocated: Int64) -> NodeMeta {
        NodeMeta(
            allocatedSize: allocated, logicalSize: allocated, modificationTime: 0,
            flags: [], deviceID: 1, inode: 0, linkCount: 1)
    }
}
