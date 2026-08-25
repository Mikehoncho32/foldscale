import Foundation
import XCTest

@testable import RadixCore

/// Tests for the task-oriented smart lists, on synthetic trees rooted at "/" with
/// the home folder at /Users/t. `now` is fixed so ages are deterministic.
final class SmartListEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let context = SmartListContext(rootPath: "/", homePath: "/Users/t")
    private var day: Int64 { 86_400 }
    private var epochNow: Int64 { Int64(1_800_000_000) }

    // MARK: - Fixture DSL

    indirect enum Spec {
        case dir(String, mtimeDaysAgo: Int64 = 0, [Spec])
        case file(String, bytes: Int64, mtimeDaysAgo: Int64 = 0)
    }

    private func build(_ children: [Spec]) -> FileTree {
        var builder = FileTreeBuilder()
        builder.enterDirectory(name: "", meta: meta(directory: true, bytes: 0, mtime: epochNow))
        for child in children { add(child, to: &builder) }
        builder.leaveDirectory()
        return builder.finish()
    }

    private func add(_ spec: Spec, to builder: inout FileTreeBuilder) {
        switch spec {
        case .dir(let name, let daysAgo, let children):
            builder.enterDirectory(
                name: name, meta: meta(directory: true, bytes: 0, mtime: epochNow - daysAgo * day))
            for child in children { add(child, to: &builder) }
            builder.leaveDirectory()
        case .file(let name, let bytes, let daysAgo):
            builder.addLeaf(
                name: name, meta: meta(directory: false, bytes: bytes, mtime: epochNow - daysAgo * day))
        }
    }

    private func meta(directory: Bool, bytes: Int64, mtime: Int64) -> NodeMeta {
        NodeMeta(
            allocatedSize: bytes, logicalSize: bytes, modificationTime: mtime,
            flags: directory ? [.directory] : [], deviceID: 1, inode: 0, linkCount: 1)
    }

    private func home(_ children: [Spec]) -> Spec { .dir("Users", [.dir("t", children)]) }

    private func names(_ result: SmartListResult, in tree: FileTree, group: String? = nil) -> [String] {
        (group.map { result.entries(in: $0) } ?? result.entries).map { tree.name(of: $0.node) }
    }

    private struct StubBundles: BundleInfoProvider {
        let infos: [String: BundleInfo]
        func info(forBundleAt absolutePath: String) -> BundleInfo? { infos[absolutePath] }
    }

    private let gigabyte: Int64 = 1_000_000_000
    private let megabyte: Int64 = 1_000_000

    // MARK: - Context

    func testContextMapsAbsolutePathsIntoTheTree() {
        let tree = build([home([.dir("Downloads", [.file("a.dmg", bytes: 10)])])])
        let node = context.node(forAbsolutePath: "/Users/t/Downloads/a.dmg", in: tree)
        XCTAssertEqual(node.map { tree.name(of: $0) }, "a.dmg")
        XCTAssertEqual(context.absolutePath(of: node!, in: tree), "/Users/t/Downloads/a.dmg")
        XCTAssertEqual(context.displayPath("/Users/t/Downloads"), "~/Downloads")
        XCTAssertNil(context.node(forAbsolutePath: "/Users/t/Nope", in: tree))

        let folderScan = SmartListContext(rootPath: "/Users/t", homePath: "/Users/t")
        XCTAssertNil(folderScan.components(forAbsolutePath: "/Applications"), "outside the scan")
        XCTAssertEqual(folderScan.components(forAbsolutePath: "/Users/t/Downloads"), ["Downloads"])
    }

    // MARK: - Downloads

    func testDownloadsPicksInstallersAndForgottenBigFiles() {
        let tree = build([
            .dir("Applications", [.dir("Slack.app", [.file("x", bytes: 1)])]),
            home([
                .dir(
                    "Downloads",
                    [
                        .file("Slack-4.29.149.dmg", bytes: 150 * megabyte, mtimeDaysAgo: 90),
                        .file("photo.jpg", bytes: 3 * megabyte, mtimeDaysAgo: 400),
                        .file("movie.iso", bytes: 4 * gigabyte, mtimeDaysAgo: 10),
                        .file("dataset.bin", bytes: 900 * megabyte, mtimeDaysAgo: 45),
                        .file("fresh.bin", bytes: 900 * megabyte, mtimeDaysAgo: 2),
                        .dir(
                            "deep",
                            [
                                .dir(
                                    "deeper",
                                    [.dir("deepest", [.file("buried.zip", bytes: 5, mtimeDaysAgo: 1)])])
                            ]),
                    ]),
                .dir("Desktop", [.file("Installer.pkg", bytes: 20 * megabyte, mtimeDaysAgo: 5)]),
            ]),
        ])
        let result = SmartListEngine.compute(
            .downloads, in: tree, context: context, bundleInfo: StubBundles(infos: [:]), now: now)

        XCTAssertEqual(
            names(result, in: tree, group: "Installers & archives"),
            ["movie.iso", "Slack-4.29.149.dmg", "Installer.pkg"],
            "biggest first; depth-limited so buried.zip is out")
        XCTAssertEqual(
            names(result, in: tree, group: "Big and forgotten"), ["dataset.bin"],
            "fresh.bin is too new, photo.jpg too small")
        let slack = result.entries.first { tree.name(of: $0.node) == "Slack-4.29.149.dmg" }!
        XCTAssertEqual(slack.note, "3 mo ago · already installed")
        XCTAssertEqual(result.groups, ["Installers & archives", "Big and forgotten"])
        XCTAssertEqual(result.totalBytes, 4 * gigabyte + 150 * megabyte + 20 * megabyte + 900 * megabyte)
    }

    // MARK: - Caches & Trash

    func testCachesAndTrashGroupsAndThresholds() {
        let tree = build([
            .dir("Library", [.dir("Caches", [.file("sys", bytes: 10 * megabyte)])]),
            home([
                .dir(".Trash", [.file("old.mov", bytes: 2 * gigabyte)]),
                .dir(
                    "Library",
                    [
                        .dir(
                            "Caches",
                            [
                                .dir("com.big.app", [.file("c", bytes: 300 * megabyte)]),
                                .dir("com.tiny.app", [.file("c", bytes: 1 * megabyte)]),
                            ]),
                        .dir(
                            "Containers",
                            [
                                .dir(
                                    "com.sandboxed.app",
                                    [
                                        .dir(
                                            "Data",
                                            [
                                                .dir(
                                                    "Library",
                                                    [.dir("Caches", [.file("c", bytes: 80 * megabyte)])])
                                            ])
                                    ])
                            ]),
                        .dir("Logs", [.file("a.log", bytes: 5 * megabyte)]),
                    ]),
            ]),
        ])
        let result = SmartListEngine.compute(
            .cachesAndTrash, in: tree, context: context, bundleInfo: StubBundles(infos: [:]), now: now)

        XCTAssertEqual(names(result, in: tree, group: "Trash"), [".Trash"])
        XCTAssertEqual(result.entries(in: "Trash").first?.safety, .informational)
        XCTAssertEqual(
            Set(names(result, in: tree, group: "App caches")), ["com.big.app", "Caches"],
            "tiny cache excluded; container cache included")
        XCTAssertEqual(
            result.entries(in: "App caches").first { tree.name(of: $0.node) == "Caches" }?.note,
            "com.sandboxed.app")
        XCTAssertEqual(names(result, in: tree, group: "Logs"), ["Logs"])
        XCTAssertEqual(result.entries(in: "System caches").first?.safety, .informational)
        XCTAssertEqual(result.groups, ["Trash", "App caches", "Logs", "System caches"])
    }

    // MARK: - Apps & games

    func testAppsAndGamesFindsBundlesGroupsGamesAndAttachesSupportData() {
        let tree = build([
            .dir(
                "Applications",
                [
                    .dir(
                        "Big.app", mtimeDaysAgo: 100, [.dir("Contents", [.file("bin", bytes: 3 * gigabyte)])]),
                    .dir("Utilities", [.dir("Terminal.app", [.file("bin", bytes: 50 * megabyte)])]),
                    .dir("Adobe", [.dir("Photoshop.app", [.file("bin", bytes: 4 * gigabyte)])]),
                    .dir("Game.app", [.file("bin", bytes: 1 * gigabyte)]),
                ]),
            home([
                .dir(
                    "Library",
                    [
                        .dir(
                            "Application Support",
                            [
                                .dir(
                                    "Steam",
                                    [
                                        .dir(
                                            "steamapps",
                                            [
                                                .dir(
                                                    "common",
                                                    [
                                                        .dir(
                                                            "Elden Ring", mtimeDaysAgo: 30,
                                                            [.file("data", bytes: 60 * gigabyte)]),
                                                        .dir("Hades", [.file("data", bytes: 8 * gigabyte)]),
                                                    ])
                                            ])
                                    ]),
                                .dir("Big", [.file("support", bytes: 500 * megabyte)]),
                            ]),
                        .dir("Containers", [.dir("com.big.app", [.file("data", bytes: 200 * megabyte)])]),
                    ])
            ]),
        ])
        let stub = StubBundles(infos: [
            "/Applications/Big.app": BundleInfo(
                name: "Big", identifier: "com.big.app", category: "public.app-category.productivity"),
            "/Applications/Game.app": BundleInfo(
                name: "Game", identifier: "com.game", category: "public.app-category.games"),
        ])
        let result = SmartListEngine.compute(
            .appsAndGames, in: tree, context: context, bundleInfo: stub, now: now)

        XCTAssertEqual(names(result, in: tree, group: "Games"), ["Elden Ring", "Hades", "Game.app"])
        XCTAssertEqual(
            names(result, in: tree, group: "Apps"), ["Photoshop.app", "Big.app", "Terminal.app"],
            "nested-once apps found, Contents/ not treated as an app")
        let big = result.entries.first { tree.name(of: $0.node) == "Big.app" }!
        XCTAssertEqual(big.extraBytes, 700 * megabyte, "Application Support/Big + Containers/com.big.app")
        XCTAssertEqual(big.note, "+ 700 MB support data · updated 3 mo ago")
        XCTAssertEqual(result.groups, ["Games", "Apps"])
        XCTAssertEqual(
            result.entries.first.map { tree.name(of: $0.node) }, "Elden Ring", "ranked by real footprint")
    }

    // MARK: - Big projects

    func testBigProjectsDetectsRootsAndStats() {
        let tree = build([
            home([
                .dir(
                    "Library",
                    [
                        .dir(
                            "Developer",
                            [.dir("Xcode", [.dir("HugeThing", [.file("x", bytes: 9 * gigabyte)])])])
                    ]),
                .dir(
                    "Developer",
                    [
                        .dir(
                            "radix", mtimeDaysAgo: 300,
                            [
                                .file("Package.swift", bytes: 1, mtimeDaysAgo: 200),
                                .dir("Sources", [.file("a.swift", bytes: 400 * megabyte, mtimeDaysAgo: 20)]),
                                .dir(".build", [.file("obj", bytes: 2 * gigabyte, mtimeDaysAgo: 1)]),
                                .dir(
                                    "Vendor",
                                    [
                                        .dir(
                                            "nested",
                                            [
                                                .file(".git", bytes: 1, mtimeDaysAgo: 250),
                                                .file("v", bytes: 300 * megabyte, mtimeDaysAgo: 250),
                                            ])
                                    ]),
                            ]),
                        .dir("tiny", [.file(".git", bytes: 1), .file("a", bytes: 10 * megabyte)]),
                        .dir("loose-big-folder", [.file("blob", bytes: 3 * gigabyte, mtimeDaysAgo: 500)]),
                    ]),
                .dir(
                    "Movies",
                    [.dir("Wedding", [.file("Wedding.fcpbundle", bytes: 30 * gigabyte, mtimeDaysAgo: 400)])]),
                .dir("Music", [.dir("Album", [.file("Song.logicx", bytes: 2 * gigabyte, mtimeDaysAgo: 10)])]),
            ])
        ])
        let result = SmartListEngine.compute(
            .bigProjects, in: tree, context: context, bundleInfo: StubBundles(infos: [:]), now: now)

        XCTAssertEqual(
            names(result, in: tree, group: "Code"), ["radix"],
            "nested root not descended into; tiny below the floor; ~/Library skipped")
        XCTAssertEqual(names(result, in: tree, group: "Video"), ["Wedding"])
        XCTAssertEqual(names(result, in: tree, group: "Audio"), ["Album"])
        XCTAssertEqual(
            names(result, in: tree, group: "Other"), ["loose-big-folder"],
            "> 1 GB direct child of ~/Developer")
        let radix = result.entries.first { tree.name(of: $0.node) == "radix" }!
        XCTAssertEqual(
            radix.note, "last touched 20 d ago · 2 GB rebuildable",
            "junk excluded from last-touched, counted as rebuildable")
        XCTAssertEqual(result.groups, ["Code", "Video", "Audio", "Other"])
    }

    // MARK: - Videos

    func testVideosGroupsRecordingsExportsClipsAndPrunesLibraries() {
        let tree = build([
            home([
                .dir(
                    "Desktop",
                    [
                        .file(
                            "Screen Recording 2026-08-01 at 10.00.00.mov", bytes: 700 * megabyte,
                            mtimeDaysAgo: 3),
                        .file("Cut_v3.MP4", bytes: 2 * gigabyte, mtimeDaysAgo: 40),
                        .file("holiday.mov", bytes: 5 * gigabyte, mtimeDaysAgo: 200),
                        .file("tiny.mov", bytes: 5 * megabyte),
                    ]),
                .dir(
                    "Documents",
                    [.dir("Zoom", [.dir("2026-08-01 Meeting", [.file("video1.mp4", bytes: 400 * megabyte)])])]
                ),
                .dir(
                    "Pictures",
                    [.dir("Photos Library.photoslibrary", [.file("clip.mov", bytes: 9 * gigabyte)])]),
                .dir("Movies", [.dir("Final.fcpbundle", [.file("render.mov", bytes: 9 * gigabyte)])]),
            ])
        ])
        let result = SmartListEngine.compute(
            .videos, in: tree, context: context, bundleInfo: StubBundles(infos: [:]), now: now)

        XCTAssertEqual(
            names(result, in: tree, group: "Recordings"),
            ["Screen Recording 2026-08-01 at 10.00.00.mov", "video1.mp4"], "by name and by Zoom folder")
        XCTAssertEqual(
            names(result, in: tree, group: "Exports"), ["Cut_v3.MP4"],
            "version token, case-insensitive extension")
        XCTAssertEqual(
            names(result, in: tree, group: "Clips"), ["holiday.mov"],
            "tiny.mov below floor; library contents pruned")
        XCTAssertEqual(result.groups, ["Recordings", "Exports", "Clips"])
    }

    func testListsSkipDeadNodes() {
        var tree = build([
            home([.dir("Downloads", [.file("a.dmg", bytes: 10), .dir("sub", [.file("b.zip", bytes: 20)])])])
        ])
        let sub = context.node(forAbsolutePath: "/Users/t/Downloads/sub", in: tree)!
        tree.remove(sub)
        let result = SmartListEngine.compute(
            .downloads, in: tree, context: context, bundleInfo: StubBundles(infos: [:]), now: now)
        XCTAssertEqual(names(result, in: tree), ["a.dmg"])
    }
}
