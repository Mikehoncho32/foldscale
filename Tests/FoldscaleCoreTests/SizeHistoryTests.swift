import Foundation
import XCTest

@testable import FoldscaleCore

/// The size ledger behind "What grew" (ADR-0006): what a snapshot keeps, how the
/// history thins itself, which baseline a window picks, and the on-disk store.
final class SizeHistoryTests: XCTestCase {
    typealias Spec = SmartListFixture.Spec
    private let now = SmartListFixture.now
    private let day: TimeInterval = 86_400
    private let megabyte = SmartListFixture.megabyte
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("size-history-tests-\(UUID().uuidString)", isDirectory: true)
        ScanCache.directoryOverride = directory
    }

    override func tearDown() {
        ScanCache.directoryOverride = nil
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    // MARK: - Snapshot.capture

    func testCaptureKeepsDirectoriesAboveTheFloorWithinDepthAndCap() {
        let tree = SmartListFixture.build([
            .dir(
                "big",
                [
                    .dir(
                        "child",
                        [
                            .dir(
                                "grandchild",
                                [.dir("d4", [.dir("d5", [.dir("d6", [.file("f", bytes: 900 * megabyte)])])])])
                        ]),
                    .file("data", bytes: 100 * megabyte),
                ]),
            .dir("small", [.file("f", bytes: 10 * megabyte)]),
            .file("loose", bytes: 5_000 * megabyte),
        ])
        let snapshot = SizeHistory.Snapshot.capture(tree, date: now)
        XCTAssertEqual(
            Set(snapshot.entries.keys),
            [
                "big", "big/child", "big/child/grandchild", "big/child/grandchild/d4",
                "big/child/grandchild/d4/d5",
            ],
            "files and folders under 50 MB are skipped; depth stops at 5")
        XCTAssertEqual(snapshot.entries["big"], 1_000 * megabyte)

        let capped = SizeHistory.Snapshot.capture(tree, date: now, maxEntries: 2)
        XCTAssertEqual(Set(capped.entries.keys), ["big", "big/child"], "the largest entries survive the cap")
    }

    // MARK: - record / thinning

    func testRecordReplacesSameDayAndThinsThePast() {
        var history = SizeHistory(rootPath: "/")
        for daysAgo in [100, 23, 20, 10, 3, 0] {
            history.record(snapshot(daysAgo: daysAgo, bytes: Int64(daysAgo)))
        }
        XCTAssertEqual(
            history.snapshots.map(\.entries["x"]), [23, 10, 3, 0],
            "older than 90 d dropped; 20 d is within 6 d of the kept 23 d; the last 14 d all stay")

        history.record(snapshot(daysAgo: 0, bytes: 99, hoursLater: 2))
        XCTAssertEqual(history.snapshots.map(\.entries["x"]), [23, 10, 3, 99], "same day replaces")
    }

    func testBaselineSelectionAndFallback() {
        var history = SizeHistory(rootPath: "/")
        for daysAgo in [23, 10, 3, 0] { history.record(snapshot(daysAgo: daysAgo, bytes: Int64(daysAgo))) }

        XCTAssertEqual(history.baseline(olderThan: 7 * day, now: now)?.entries["x"], 10, "newest ≥ 7 d old")
        XCTAssertNil(history.baseline(olderThan: 30 * day, now: now))
        XCTAssertEqual(history.oldestBefore(day: now)?.entries["x"], 23)

        let young = SizeHistory(rootPath: "/", snapshots: [snapshot(daysAgo: 0, bytes: 1)])
        XCTAssertNil(young.oldestBefore(day: now), "nothing but today → no baseline at all")
    }

    // MARK: - Store

    func testStoreRoundTripsAndStartsFreshOnGarbageOrAnotherRoot() throws {
        let tree = SmartListFixture.build([.dir("big", [.file("f", bytes: 900 * megabyte)])])
        let recorded = SizeHistoryStore.record(tree: tree, rootPath: "/", now: now)
        XCTAssertEqual(recorded.snapshots.count, 1)
        XCTAssertEqual(SizeHistoryStore.load(rootPath: "/"), recorded)
        XCTAssertNil(SizeHistoryStore.load(rootPath: "/Volumes/Other"), "one history per root")

        try Data("not a plist".utf8).write(to: SizeHistoryStore.fileURL)
        XCTAssertNil(SizeHistoryStore.load(rootPath: "/"))
        let fresh = SizeHistoryStore.record(tree: tree, rootPath: "/", now: now)
        XCTAssertEqual(fresh.snapshots.count, 1, "garbage is replaced, not appended to")
    }

    func testHistoryFileStaysSmallAfterThirtyDaysOfDailyScans() throws {
        // 3 500 candidate folders → capped at 3 000 per snapshot, ~2 KB of path text each day.
        let folders = (0..<3_500).map { index -> Spec in
            .dir("folder-\(index)", [.file("f", bytes: (60 + Int64(index)) * megabyte)])
        }
        let tree = SmartListFixture.build(folders)
        var history: SizeHistory?
        for daysAgo in stride(from: 30, through: 0, by: -1) {
            history = SizeHistoryStore.record(
                tree: tree, rootPath: "/", now: now.addingTimeInterval(-Double(daysAgo) * day))
        }
        let size = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: SizeHistoryStore.fileURL.path)[.size] as? Int64)
        let kept = try XCTUnwrap(history).snapshots.count
        print("size-history.plist after 30 daily scans: \(size) bytes, \(kept) snapshots")
        XCTAssertLessThan(size, 5_000_000)
        XCTAssertEqual(kept, 18, "15 recent days (0…14) + one per 6 d before that (20, 26, 30 → 3)")
        XCTAssertEqual(try XCTUnwrap(history).snapshots.last?.entries.count, 3_000)
    }

    private func snapshot(daysAgo: Int, bytes: Int64, hoursLater: Double = 0) -> SizeHistory.Snapshot {
        SizeHistory.Snapshot(
            date: now.addingTimeInterval(-Double(daysAgo) * day + hoursLater * 3_600), entries: ["x": bytes])
    }
}
