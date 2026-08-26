// swiftlint:disable identifier_name
import Foundation
import XCTest

@testable import RadixCore

/// Tests for the "Free up space" planner and the Developer junk list.
final class FreeUpPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let context = SmartListContext(rootPath: "/", homePath: "/Users/t")
    private let gigabyte: Int64 = 1_000_000_000
    private let megabyte: Int64 = 1_000_000

    // MARK: - Fixture

    /// root ── a(500 MB, dir) ── a1(300 MB); b(2 GB); c(1 GB); d(100 MB)
    private func makeTree() -> FileTree {
        var builder = FileTreeBuilder()
        builder.enterDirectory(name: "root", meta: meta(directory: true, bytes: 0))
        builder.enterDirectory(name: "a", meta: meta(directory: true, bytes: 200 * megabyte))
        builder.addLeaf(name: "a1", meta: meta(directory: false, bytes: 300 * megabyte))
        builder.leaveDirectory()
        builder.addLeaf(name: "b", meta: meta(directory: false, bytes: 2 * gigabyte))
        builder.addLeaf(name: "c", meta: meta(directory: false, bytes: 1 * gigabyte))
        builder.addLeaf(name: "d", meta: meta(directory: false, bytes: 100 * megabyte))
        builder.leaveDirectory()
        return builder.finish()
    }

    private func meta(directory: Bool, bytes: Int64, mtime: Int64 = 1_800_000_000) -> NodeMeta {
        NodeMeta(
            allocatedSize: bytes, logicalSize: bytes, modificationTime: mtime,
            flags: directory ? [.directory] : [], deviceID: 1, inode: 0, linkCount: 1)
    }

    private func node(_ tree: FileTree, _ path: [String]) -> FileTree.NodeID {
        tree.node(atPathComponents: path)!
    }

    private func lists(_ tree: FileTree) -> [SmartListKind: SmartListResult] {
        let a = node(tree, ["a"]), a1 = node(tree, ["a", "a1"]), b = node(tree, ["b"])
        let c = node(tree, ["c"]), d = node(tree, ["d"])
        return [
            .cachesAndTrash: SmartListResult(
                kind: .cachesAndTrash,
                entries: [
                    SmartListEntry(node: c, group: "App caches", safety: .safeToTrash),
                    SmartListEntry(node: d, group: "Trash", safety: .informational),
                ], groups: ["App caches", "Trash"], totalBytes: 0),
            .downloads: SmartListResult(
                kind: .downloads,
                entries: [
                    SmartListEntry(node: b, group: "Big and forgotten", safety: .reviewFirst),
                    SmartListEntry(node: a1, group: "Installers & archives", safety: .safeToTrash),
                ], groups: ["Installers & archives", "Big and forgotten"], totalBytes: 0),
            .bigProjects: SmartListResult(
                kind: .bigProjects,
                entries: [
                    SmartListEntry(node: a, group: "Code", safety: .reviewFirst),
                    SmartListEntry(node: c, group: "Other", safety: .reviewFirst),  // same node, less safe
                ], groups: ["Code", "Other"], totalBytes: 0),
        ]
    }

    // MARK: - Suggestions

    func testSuggestionsDedupeExcludeInformationalAndRankSafestFirst() {
        let tree = makeTree()
        let suggestions = FreeUpPlanner.suggestions(from: lists(tree), in: tree)
        let names = suggestions.map { tree.name(of: $0.node) }

        XCTAssertEqual(
            names, ["a1", "b", "c", "a"], "safe (installers) before review-first; big before small")
        XCTAssertFalse(names.contains("d"), "informational rows are never suggested")
        let c = suggestions.first { tree.name(of: $0.node) == "c" }!
        XCTAssertEqual(c.safety, .reviewFirst, "when lists disagree, the more cautious classification wins")
        XCTAssertEqual(c.source, .bigProjects)
    }

    // MARK: - Greedy pick

    func testGreedyPickCoversTargetWithSafeItemsOnlyByDefault() {
        let tree = makeTree()
        let suggestions = FreeUpPlanner.suggestions(from: lists(tree), in: tree)

        let small = FreeUpPlanner.greedySelection(target: 100 * megabyte, from: suggestions, in: tree)
        XCTAssertEqual(small, [node(tree, ["a", "a1"])], "the one safe item covers 100 MB")

        let large = FreeUpPlanner.greedySelection(target: 5 * gigabyte, from: suggestions, in: tree)
        XCTAssertEqual(large, [node(tree, ["a", "a1"])], "runs out of safe items and stops short")

        let withReview = FreeUpPlanner.greedySelection(
            target: 5 * gigabyte, from: suggestions, in: tree, includeReviewFirst: true)
        XCTAssertEqual(
            withReview, [node(tree, ["b"]), node(tree, ["c"]), node(tree, ["a"])],
            "review-first items join once allowed; picking folder a evicts its child a1 so nothing is counted twice"
        )
        XCTAssertEqual(
            FreeUpPlanner.reclaimTotal(of: withReview, in: tree), 2 * gigabyte + 1 * gigabyte + 500 * megabyte
        )
    }

    func testGreedyPickSkipsItemsUnderAnEarlierPick() {
        let tree = makeTree()
        let a = node(tree, ["a"]), a1 = node(tree, ["a", "a1"])
        let ordered = [
            SpaceSuggestion(
                node: a, source: .bigProjects, group: "Code", safety: .safeToTrash, note: nil,
                bytes: 500 * megabyte, priority: 0),
            SpaceSuggestion(
                node: a1, source: .downloads, group: "x", safety: .safeToTrash, note: nil,
                bytes: 300 * megabyte, priority: 1),
        ]
        XCTAssertEqual(FreeUpPlanner.greedySelection(target: 10 * gigabyte, from: ordered, in: tree), [a])
    }

    // MARK: - Reclaim total

    func testReclaimTotalCountsNestedItemsOnce() {
        let tree = makeTree()
        let a = node(tree, ["a"]), a1 = node(tree, ["a", "a1"]), b = node(tree, ["b"])
        XCTAssertEqual(FreeUpPlanner.reclaimTotal(of: [a, a1, b], in: tree), 500 * megabyte + 2 * gigabyte)
        XCTAssertEqual(FreeUpPlanner.reclaimTotal(of: [a1, b], in: tree), 300 * megabyte + 2 * gigabyte)
        XCTAssertEqual(FreeUpPlanner.reclaimTotal(of: [], in: tree), 0)
        XCTAssertEqual(FreeUpPlanner.outermost(of: [a, a1, b], in: tree), [a, b])
    }

    // MARK: - Developer junk list

    func testDeveloperJunkFindsToolCachesAndBuildFoldersInProjects() {
        var builder = FileTreeBuilder()
        builder.enterDirectory(name: "", meta: meta(directory: true, bytes: 0))
        builder.enterDirectory(name: "Users", meta: meta(directory: true, bytes: 0))
        builder.enterDirectory(name: "t", meta: meta(directory: true, bytes: 0))
        builder.enterDirectory(name: "Library", meta: meta(directory: true, bytes: 0))
        builder.enterDirectory(name: "Developer", meta: meta(directory: true, bytes: 0))
        builder.enterDirectory(name: "Xcode", meta: meta(directory: true, bytes: 0))
        builder.enterDirectory(name: "DerivedData", meta: meta(directory: true, bytes: 0))
        builder.addLeaf(name: "blob", meta: meta(directory: false, bytes: 9 * gigabyte))
        builder.leaveDirectory()
        builder.leaveDirectory()
        builder.leaveDirectory()
        builder.enterDirectory(name: "Caches", meta: meta(directory: true, bytes: 0))
        builder.enterDirectory(name: "Homebrew", meta: meta(directory: true, bytes: 0))
        builder.addLeaf(name: "bottle", meta: meta(directory: false, bytes: 10 * megabyte))  // below floor
        builder.leaveDirectory()
        builder.leaveDirectory()
        builder.leaveDirectory()
        builder.enterDirectory(name: "Movies", meta: meta(directory: true, bytes: 0))
        builder.enterDirectory(name: "Doc.fcpbundle", meta: meta(directory: true, bytes: 0))
        builder.enterDirectory(name: "build", meta: meta(directory: true, bytes: 0))
        builder.addLeaf(name: "not-junk", meta: meta(directory: false, bytes: 3 * gigabyte))
        builder.leaveDirectory()
        builder.leaveDirectory()
        builder.leaveDirectory()
        builder.enterDirectory(name: "Developer", meta: meta(directory: true, bytes: 0))
        builder.enterDirectory(name: "app", meta: meta(directory: true, bytes: 0))
        builder.addLeaf(name: "package.json", meta: meta(directory: false, bytes: 1))
        builder.enterDirectory(name: "node_modules", meta: meta(directory: true, bytes: 0))
        builder.addLeaf(name: "deps", meta: meta(directory: false, bytes: 700 * megabyte))
        builder.leaveDirectory()
        builder.leaveDirectory()
        builder.leaveDirectory()
        builder.leaveDirectory()
        builder.leaveDirectory()
        builder.leaveDirectory()
        let tree = builder.finish()

        struct NoBundles: BundleInfoProvider {
            func info(forBundleAt absolutePath: String) -> BundleInfo? { nil }
        }
        let result = SmartListEngine.compute(
            .developerJunk, in: tree, context: context, bundleInfo: NoBundles(), now: now)
        let byGroup = { (group: String) in result.entries(in: group).map { tree.name(of: $0.node) } }
        XCTAssertEqual(byGroup("Xcode"), ["DerivedData"])
        XCTAssertEqual(byGroup("Tool caches"), [], "Homebrew cache below the 50 MB floor")
        XCTAssertEqual(
            byGroup("Build output"), ["node_modules"],
            "a folder named 'build' inside a video project is not junk")
        XCTAssertEqual(result.entries(in: "Build output").first?.note, "in app · rebuilds on the next build")
        XCTAssertEqual(result.totalBytes, 9 * gigabyte + 700 * megabyte)
        XCTAssertEqual(result.groups, ["Build output", "Xcode"])
    }
}
// swiftlint:enable identifier_name
