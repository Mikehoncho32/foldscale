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
    private let gigabyte: Int64 = 1_000_000_000
    private let megabyte: Int64 = 1_000_000

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

    private func compute(
        _ kind: SmartListKind, _ tree: FileTree, bundles: [String: BundleInfo] = [:]
    ) -> SmartListResult {
        SmartListEngine.compute(
            kind, in: tree, context: context, bundleInfo: StubBundles(infos: bundles), now: now)
    }

    private struct StubBundles: BundleInfoProvider {
        let infos: [String: BundleInfo]
        func info(forBundleAt absolutePath: String) -> BundleInfo? { infos[absolutePath] }
    }

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
            .dir(
                "Applications",
                [
                    .dir("Slack.app", [.file("x", bytes: 1)]),
                    .dir("Adobe", [.dir("Photoshop.app", [.file("x", bytes: 1)])]),
                ]),
            home([
                .dir(
                    "Downloads",
                    [
                        .file("Slack-4.29.149-macOS.dmg", bytes: 150 * megabyte, mtimeDaysAgo: 90),
                        .file("Photoshop 25.zip", bytes: 30 * megabyte, mtimeDaysAgo: 9),
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
        let result = compute(.downloads, tree)

        XCTAssertEqual(
            names(result, in: tree, group: "Installers & archives"),
            ["movie.iso", "Slack-4.29.149-macOS.dmg", "Photoshop 25.zip", "Installer.pkg"],
            "biggest first; depth-limited so buried.zip is out")
        XCTAssertEqual(
            names(result, in: tree, group: "Big and forgotten"), ["dataset.bin"],
            "fresh.bin too new, photo.jpg too small")
        let note = { (name: String) in result.entries.first { tree.name(of: $0.node) == name }?.note }
        XCTAssertEqual(
            note("Slack-4.29.149-macOS.dmg"), "3 mo ago · already installed",
            "version cut at the first versioned separator")
        XCTAssertEqual(
            note("Photoshop 25.zip"), "9 d ago · already installed", "nested-once app counts as installed")
        XCTAssertEqual(note("movie.iso"), "10 d ago")
        XCTAssertEqual(result.groups, ["Installers & archives", "Big and forgotten"])

        let safety = { (name: String) in result.entries.first { tree.name(of: $0.node) == name }?.safety }
        XCTAssertEqual(safety("Slack-4.29.149-macOS.dmg"), .safeToTrash, "installed and old")
        XCTAssertEqual(
            safety("Photoshop 25.zip"), .safeToTrash, "an archive is safe only because its app is installed")
        XCTAssertEqual(
            safety("movie.iso"), .reviewFirst, "a bare archive with no installed app may be the only copy")
        XCTAssertEqual(safety("Installer.pkg"), .reviewFirst, "an installer from 5 days ago is still fresh")
        XCTAssertEqual(safety("dataset.bin"), .reviewFirst, "big forgotten files are real data")
    }

    func testProductNameStripsVersionsInMultiWordNames() {
        XCTAssertEqual(SmartListQuery.productName(from: "Google Chrome 120.0.6099.dmg"), "google chrome")
        XCTAssertEqual(SmartListQuery.productName(from: "iterm2-3_5_0.zip"), "iterm2")
        XCTAssertEqual(SmartListQuery.productName(from: "Xcode_15.2.xip"), "xcode")
        XCTAssertEqual(SmartListQuery.productName(from: "Radix-v1.0.0.dmg"), "radix")
        XCTAssertEqual(SmartListQuery.productName(from: "archive.tar.gz"), "archive")
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
        let result = compute(.cachesAndTrash, tree)

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
        let bundles = [
            "/Applications/Big.app": BundleInfo(
                name: "Big", identifier: "com.big.app", category: "public.app-category.productivity"),
            "/Applications/Game.app": BundleInfo(
                name: "Game", identifier: "com.game", category: "public.app-category.games"),
        ]
        let result = compute(.appsAndGames, tree, bundles: bundles)

        XCTAssertEqual(names(result, in: tree, group: "Games"), ["Elden Ring", "Hades", "Game.app"])
        XCTAssertEqual(
            names(result, in: tree, group: "Apps"), ["Photoshop.app", "Big.app", "Terminal.app"],
            "nested-once apps found; Contents/ isn't an app")
        let big = result.entries.first { tree.name(of: $0.node) == "Big.app" }!
        XCTAssertEqual(big.extraBytes, 700 * megabyte, "Application Support/Big + Containers/com.big.app")
        XCTAssertEqual(big.note, "+ 700 MB support data · updated 3 mo ago")
        XCTAssertEqual(result.groups, ["Games", "Apps"])
        XCTAssertEqual(
            result.entries.first.map { tree.name(of: $0.node) }, "Elden Ring", "ranked by real footprint")
    }

    func testSteamGamesAreNotCountedTwiceThroughSupportData() {
        let tree = build([
            .dir("Applications", [.dir("Steam.app", [.file("bin", bytes: 2 * gigabyte)])]),
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
                                                    [.dir("Dota 2", [.file("data", bytes: 50 * gigabyte)])])
                                            ]),
                                        .dir("shadercache", [.file("s", bytes: 1 * gigabyte)]),
                                    ])
                            ])
                    ])
            ]),
        ])
        let bundles = [
            "/Applications/Steam.app": BundleInfo(name: "Steam", identifier: "com.valvesoftware.steam")
        ]
        let result = compute(.appsAndGames, tree, bundles: bundles)

        let steam = result.entries.first { tree.name(of: $0.node) == "Steam.app" }!
        XCTAssertEqual(
            steam.extraBytes, 1 * gigabyte, "the listed game is subtracted from Steam's support data")
        XCTAssertEqual(
            result.totalBytes, 2 * gigabyte + 1 * gigabyte + 50 * gigabyte, "each byte counted once")
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
                    [.dir("Wedding.fcpbundle", [.file("media", bytes: 30 * gigabyte, mtimeDaysAgo: 400)])]),
                .dir(
                    "Music",
                    [
                        .dir(
                            "Album",
                            [.dir("Song.logicx", [.file("audio", bytes: 2 * gigabyte, mtimeDaysAgo: 10)])])
                    ]),
            ])
        ])
        let result = compute(.bigProjects, tree)

        XCTAssertEqual(
            names(result, in: tree, group: "Code"), ["radix"],
            "nested root not descended into; tiny below the floor; ~/Library skipped")
        XCTAssertEqual(
            names(result, in: tree, group: "Video"), ["Wedding.fcpbundle"],
            "a project bundle is the project itself")
        XCTAssertEqual(
            names(result, in: tree, group: "Audio"), ["Song.logicx"],
            "a folder holding a bundle is descended, not promoted")
        XCTAssertEqual(
            names(result, in: tree, group: "Other"), ["loose-big-folder"],
            "> 1 GB direct child of ~/Developer")
        let radix = result.entries.first { tree.name(of: $0.node) == "radix" }!
        XCTAssertEqual(
            radix.note, "last touched 20 d ago · 2 GB rebuildable",
            "junk excluded from last-touched, counted as rebuildable")
        XCTAssertEqual(result.groups, ["Code", "Video", "Audio", "Other"])
    }

    func testBigProjectsNeverPromotesTopLevelHomeFolders() {
        let tree = build([
            home([
                .dir(
                    "Movies",
                    [
                        .dir("iMovie Library.imovielibrary", [.file("media", bytes: 400 * gigabyte)]),
                        .dir("Archive-2019", [.file("old.mov", bytes: 80 * gigabyte, mtimeDaysAgo: 700)]),
                        .dir("Projects", [.dir("A.fcpbundle", [.file("media", bytes: 60 * gigabyte)])]),
                    ]),
                .dir("Documents", [.file("Edit.prproj", bytes: 2 * megabyte), .file("notes.txt", bytes: 1)]),
                .dir(
                    "Desktop",
                    [.dir("App.xcodeproj", [.file("p", bytes: 1)]), .file("big.bin", bytes: 3 * gigabyte)]),
            ])
        ])
        let result = compute(.bigProjects, tree)

        let listed = Set(names(result, in: tree))
        XCTAssertFalse(listed.contains("Movies"), "an iMovie library in ~/Movies must not swallow ~/Movies")
        XCTAssertFalse(
            listed.contains("Documents"), "a loose .prproj in ~/Documents must not promote ~/Documents")
        XCTAssertFalse(listed.contains("Desktop"), "an .xcodeproj on the Desktop must not promote ~/Desktop")
        XCTAssertEqual(
            names(result, in: tree, group: "Video"), ["iMovie Library.imovielibrary", "A.fcpbundle"],
            "bundles listed themselves, even one folder down")
        XCTAssertEqual(
            names(result, in: tree, group: "Other"), ["Archive-2019"], "big loose folder in ~/Movies")
        XCTAssertFalse(
            listed.contains("Projects"), "a folder holding project bundles is descended, not promoted")
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
                        .file("V8 engine demo.mov", bytes: 300 * megabyte),
                        .file("Recordings of nature.mov", bytes: 250 * megabyte),
                        .file("finalists.mov", bytes: 200 * megabyte),
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
        let result = compute(.videos, tree)

        XCTAssertEqual(
            names(result, in: tree, group: "Recordings"),
            ["Screen Recording 2026-08-01 at 10.00.00.mov", "video1.mp4"], "by name and by Zoom folder")
        XCTAssertEqual(
            names(result, in: tree, group: "Exports"), ["Cut_v3.MP4"],
            "version token, case-insensitive extension")
        XCTAssertEqual(
            names(result, in: tree, group: "Clips"),
            ["holiday.mov", "V8 engine demo.mov", "Recordings of nature.mov", "finalists.mov"],
            "leading V8, 'Recordings', and 'finalists' are not exports/recordings; tiny below floor; libraries pruned"
        )
        XCTAssertEqual(result.groups, ["Recordings", "Exports", "Clips"])
    }

    func testListsSkipDeadNodes() {
        var tree = build([
            home([.dir("Downloads", [.file("a.dmg", bytes: 10), .dir("sub", [.file("b.zip", bytes: 20)])])])
        ])
        let sub = context.node(forAbsolutePath: "/Users/t/Downloads/sub", in: tree)!
        tree.remove(sub)
        XCTAssertEqual(names(compute(.downloads, tree), in: tree), ["a.dmg"])
    }

    func testComputeAllStopsWhenCancelled() {
        let tree = build([home([.dir("Downloads", [.file("a.dmg", bytes: 10)])])])
        let results = SmartListEngine.computeAll(
            in: tree, context: context, bundleInfo: StubBundles(infos: [:]), now: now, isCancelled: { true })
        XCTAssertTrue(results.isEmpty)
    }

    func testForEachDescendantIsPreOrderAndPrunable() {
        let tree = build([
            .dir("a", [.file("a1", bytes: 1), .dir("b", [.file("b1", bytes: 1)]), .file("a2", bytes: 1)]),
            .file("z", bytes: 1),
        ])
        var visited: [String] = []
        tree.forEachDescendant(of: tree.rootID) { node in
            visited.append(tree.name(of: node))
            return tree.name(of: node) != "b"  // prune b's children
        }
        XCTAssertEqual(visited, ["a", "a1", "b", "a2", "z"])
    }
}
