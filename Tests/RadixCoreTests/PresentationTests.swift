import Foundation
import XCTest

@testable import RadixCore

/// Tests for the sort, volume, and formatting helpers used by the outline view.
final class PresentationTests: XCTestCase {

    // MARK: - Sorting

    /// root ── alpha(size 100, mtime 300), zebra(size 300, mtime 100),
    ///         mango(dir, +child 100 → total 150, items 1, mtime 200)
    private func makeSortTree() -> FileTree {
        var builder = FileTreeBuilder()
        builder.enterDirectory(name: "root", meta: dir(4096))
        builder.addLeaf(name: "alpha", meta: file(100, mtime: 300))
        builder.addLeaf(name: "zebra", meta: file(300, mtime: 100))
        builder.enterDirectory(name: "mango", meta: dir(50, mtime: 200))
        builder.addLeaf(name: "child", meta: file(100, mtime: 200))
        builder.leaveDirectory()
        builder.leaveDirectory()
        return builder.finish()
    }

    func testSortBySizeDescendingIsDefault() {
        let tree = makeSortTree()
        let names = tree.childrenSorted(of: tree.rootID, by: .size).map { tree.name(of: $0) }
        XCTAssertEqual(names, ["zebra", "mango", "alpha"])  // 300, 150, 100
    }

    func testSortByNameAscending() {
        let tree = makeSortTree()
        let names = tree.childrenSorted(of: tree.rootID, by: .name, ascending: true)
            .map { tree.name(of: $0) }
        XCTAssertEqual(names, ["alpha", "mango", "zebra"])
    }

    func testSortByModifiedDescending() {
        let tree = makeSortTree()
        let names = tree.childrenSorted(of: tree.rootID, by: .modified).map { tree.name(of: $0) }
        XCTAssertEqual(names, ["alpha", "mango", "zebra"])  // mtime 300, 200, 100
    }

    func testSortByItemsPutsDirectoryFirst() {
        let tree = makeSortTree()
        let first = tree.childrenSorted(of: tree.rootID, by: .items).first
        XCTAssertEqual(tree.name(of: first!), "mango")  // only node with descendants
    }

    // MARK: - DisplayFormat

    func testByteFormatting() {
        XCTAssertTrue(DisplayFormat.bytes(2_000_000_000).contains("GB"))
        XCTAssertTrue(DisplayFormat.bytes(5_000_000).contains("MB"))
    }

    func testItemCountGrouping() {
        let formatted = DisplayFormat.itemCount(812_404)
        XCTAssertTrue(formatted.contains("812"))
        XCTAssertTrue(formatted.contains("404"))
        XCTAssertGreaterThan(formatted.count, 6)  // includes a grouping separator
    }

    func testRelativeModifiedBuckets() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            DisplayFormat.relativeModified(epochSeconds: 1_700_000_000, now: now), "Today")
        let threeDaysAgo = Int64(now.timeIntervalSince1970) - 3 * 86_400
        XCTAssertEqual(DisplayFormat.relativeModified(epochSeconds: threeDaysAgo, now: now), "3d ago")
        // A date years earlier falls through to a formatted date, not a bucket word.
        let old = DisplayFormat.relativeModified(epochSeconds: 1_000_000_000, now: now)
        XCTAssertFalse(["Today", "Yesterday"].contains(old))
    }

    // MARK: - VolumeStats

    func testVolumeStatsForRootVolume() throws {
        let stats = try XCTUnwrap(VolumeStats.forVolume(containing: URL(fileURLWithPath: "/")))
        XCTAssertGreaterThan(stats.totalCapacity, 0)
        XCTAssertGreaterThanOrEqual(stats.availableCapacity, 0)
        XCTAssertGreaterThanOrEqual(stats.purgeable, 0)
        XCTAssertLessThanOrEqual(stats.usedCapacity, stats.totalCapacity)
    }

    // MARK: - Helpers

    private func dir(_ allocated: Int64, mtime: Int64 = 0) -> NodeMeta {
        NodeMeta(
            allocatedSize: allocated, logicalSize: allocated, modificationTime: mtime,
            flags: [.directory], deviceID: 1, inode: 0, linkCount: 1)
    }

    private func file(_ allocated: Int64, mtime: Int64 = 0) -> NodeMeta {
        NodeMeta(
            allocatedSize: allocated, logicalSize: allocated, modificationTime: mtime,
            flags: [], deviceID: 1, inode: 0, linkCount: 1)
    }
}
