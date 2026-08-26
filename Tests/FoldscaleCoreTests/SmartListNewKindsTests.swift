import Foundation
import XCTest

@testable import FoldscaleCore

/// The lists added after 1.2: phone backups and virtual machines, plus the
/// plumbing they needed (footprint vs reclaimable bytes, display names).
final class SmartListNewKindsTests: XCTestCase {
    typealias Spec = SmartListFixture.Spec
    private let gigabyte = SmartListFixture.gigabyte
    private let megabyte = SmartListFixture.megabyte

    // MARK: - Phone backups

    func testPhoneBackupsReadsDeviceNameAndFallsBackToFolderName() {
        let backups = "/Users/t/Library/Application Support/MobileSync/Backup"
        let tree = SmartListFixture.build([
            SmartListFixture.home([
                .dir(
                    "Library",
                    [
                        .dir(
                            "Application Support",
                            [
                                .dir(
                                    "MobileSync",
                                    [
                                        .dir(
                                            "Backup",
                                            [
                                                .dir(
                                                    "00008030-000A4D1E0C28802E", mtimeDaysAgo: 3,
                                                    [.file("Manifest.db", bytes: 12 * gigabyte)]),
                                                .dir(
                                                    "00008030-000A4D1E0C28802E-20260401-091500",
                                                    mtimeDaysAgo: 140,
                                                    [.file("Manifest.db", bytes: 6 * gigabyte)]),
                                                .dir(
                                                    "4a1c2f3e4d5c6b7a8f9e0d1c2b3a4f5e6d7c8b9a",
                                                    mtimeDaysAgo: 400,
                                                    [.file("Manifest.db", bytes: 2 * gigabyte)]),
                                                .dir(
                                                    "stale-unreadable",
                                                    [.file("Info.plist", bytes: 3 * megabyte)]),
                                            ])
                                    ])
                            ])
                    ])
            ])
        ])
        let lastBackup = SmartListFixture.now.addingTimeInterval(-95 * 86_400)
        let result = SmartListFixture.compute(
            .phoneBackups, tree,
            backups: [
                "\(backups)/00008030-000A4D1E0C28802E": DeviceBackupInfo(
                    deviceName: "Mark's iPhone", productName: "iPhone 15 Pro", lastBackupDate: lastBackup),
                "\(backups)/00008030-000A4D1E0C28802E-20260401-091500": DeviceBackupInfo(
                    deviceName: "Mark's iPhone", productName: "iPhone 15 Pro", lastBackupDate: nil),
            ])

        XCTAssertEqual(result.groups, ["iPhone & iPad backups"])
        XCTAssertEqual(
            SmartListFixture.names(result, in: tree),
            [
                "00008030-000A4D1E0C28802E", "00008030-000A4D1E0C28802E-20260401-091500",
                "4a1c2f3e4d5c6b7a8f9e0d1c2b3a4f5e6d7c8b9a",
            ], "biggest first; the tiny stale folder is below the floor")
        XCTAssertEqual(result.entries[0].displayName, "Mark's iPhone")
        XCTAssertEqual(result.entries[0].note, "iPhone 15 Pro · backed up 3 mo ago")
        XCTAssertEqual(result.entries[1].note, "iPhone 15 Pro · backed up 4 mo ago · archived copy")
        XCTAssertNil(result.entries[2].displayName, "no plist → folder name")
        XCTAssertEqual(result.entries[2].note, "backed up 1 yr ago")
        XCTAssertTrue(result.entries.allSatisfy { $0.safety == .reviewFirst })
        XCTAssertEqual(result.totalBytes, 20 * gigabyte)
        XCTAssertEqual(result.displayBytes, 20 * gigabyte)
    }

    func testArchivedBackupNamesAreRecognised() {
        XCTAssertTrue(SmartListQuery.isArchivedBackup("00008030-000A4D1E0C28802E-20260401-091500"))
        XCTAssertTrue(
            SmartListQuery.isArchivedBackup("4a1c2f3e4d5c6b7a8f9e0d1c2b3a4f5e6d7c8b9a-20250101-000000"))
        XCTAssertFalse(SmartListQuery.isArchivedBackup("00008030-000A4D1E0C28802E"))
        XCTAssertFalse(SmartListQuery.isArchivedBackup("4a1c2f3e4d5c6b7a8f9e0d1c2b3a4f5e6d7c8b9a"))
    }

    func testPhoneBackupsIsEmptyWithoutTheFolder() {
        let tree = SmartListFixture.build([SmartListFixture.home([.dir("Documents", [])])])
        let result = SmartListFixture.compute(.phoneBackups, tree)
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.displayBytes, 0, "an empty list hides from the sidebar")
    }

    // MARK: - Virtual machines

    /// Nested folders for each path component with `leaf` inside the innermost.
    private func nested(_ path: [String], _ leaf: Spec) -> Spec {
        path.reversed().reduce(leaf) { inner, name in .dir(name, [inner]) }
    }

    /// A home folder with VMs from every supported tool, one below the floor, one
    /// relocated, and engine disks for Docker and Lima.
    private func virtualMachineTree() -> FileTree {
        SmartListFixture.build([
            SmartListFixture.home([
                .dir(
                    "Parallels",
                    [
                        .dir("Windows 11.pvm", mtimeDaysAgo: 20, [.file("disk.hdd", bytes: 40 * gigabyte)]),
                        .dir("tiny.pvm", [.file("disk.hdd", bytes: 5 * megabyte)]),
                    ]),
                nested(
                    ["Documents", "VMs"],
                    .dir("macOS test.vmwarevm", mtimeDaysAgo: 60, [.file("disk.vmdk", bytes: 30 * gigabyte)])),
                nested(
                    ["Documents", "Parallels"],
                    .dir("Ubuntu.pvm", mtimeDaysAgo: 5, [.file("disk.hdd", bytes: 9 * gigabyte)])),
                nested(
                    ["VirtualBox VMs"],
                    .dir("win10", mtimeDaysAgo: 300, [.file("win10.vdi", bytes: 25 * gigabyte)])),
                .dir(
                    ".lima",
                    [
                        .dir("default", [.file("diffdisk", bytes: 8 * gigabyte)]),
                        .dir("_config", [.file("user", bytes: 200 * megabyte)]),
                    ]),
                .dir(
                    "Library",
                    [
                        .dir(
                            "Containers",
                            [
                                nested(
                                    ["com.docker.docker", "Data", "vms", "0", "data"],
                                    .file("Docker.raw", bytes: 60 * gigabyte)),
                                nested(
                                    ["com.utmapp.UTM", "Data", "Documents"],
                                    .dir(
                                        "Fedora.utm", mtimeDaysAgo: 2,
                                        [.file("disk.qcow2", bytes: 12 * gigabyte)])),
                            ])
                    ]),
                .dir("Movies", [.dir("Not a VM.pvm", [.file("clip.mov", bytes: 1 * gigabyte)])]),
            ])
        ])
    }

    func testVirtualMachinesFindsDocumentsByPathAndSuffixAndMarksEnginesInformational() {
        let tree = virtualMachineTree()
        let result = SmartListFixture.compute(.virtualMachines, tree)

        XCTAssertEqual(result.groups, ["Virtual machines", "Containers"])
        XCTAssertEqual(
            SmartListFixture.names(result, in: tree, group: "Virtual machines"),
            ["Windows 11.pvm", "macOS test.vmwarevm", "win10", "Fedora.utm", "Ubuntu.pvm", "Not a VM.pvm"],
            "by path, by suffix under home, biggest first; tiny.pvm is below the floor")
        XCTAssertEqual(
            SmartListFixture.names(result, in: tree, group: "Containers"), ["Docker.raw", "default"])
        let vmNotes = result.entries(in: "Virtual machines").map(\.note)
        XCTAssertEqual(vmNotes[0], "Parallels · used 20 d ago")
        XCTAssertEqual(vmNotes[1], "VMware Fusion · used 2 mo ago")
        XCTAssertTrue(result.entries(in: "Virtual machines").allSatisfy { $0.safety == .reviewFirst })
        XCTAssertTrue(result.entries(in: "Containers").allSatisfy { $0.safety == .informational })
        XCTAssertEqual(result.entries(in: "Containers")[1].note, "Lima instance · `limactl delete default`")

        let vms: Int64 = (40 + 30 + 25 + 12 + 9 + 1) * gigabyte
        XCTAssertEqual(result.totalBytes, vms, "reclaimable excludes the engine disks")
        XCTAssertEqual(result.footprintBytes, vms + 68 * gigabyte)
        XCTAssertEqual(result.displayBytes, result.footprintBytes, "What's Here shows the whole footprint")
    }

    func testVideosIgnoreClipsInsideVirtualMachineBundles() {
        let tree = SmartListFixture.build([
            SmartListFixture.home([
                .dir("Parallels", [.dir("Windows 11.pvm", [.file("snapshot.mov", bytes: 2 * gigabyte)])]),
                .dir("Movies", [.file("holiday.mov", bytes: 2 * gigabyte)]),
            ])
        ])
        let result = SmartListFixture.compute(.videos, tree)
        XCTAssertEqual(SmartListFixture.names(result, in: tree), ["holiday.mov"])
    }

    // MARK: - Plumbing

    func testDisplayBytesUsesFootprintForWhatsHereAndReclaimableForCleanUp() {
        let tree = SmartListFixture.build([.file("a", bytes: 1)])
        let entries = [SmartListEntry(node: tree.rootID, group: "g", safety: .informational)]
        let cleanUp = SmartListResult(
            kind: .downloads, entries: entries, groups: ["g"], totalBytes: 0, footprintBytes: 7)
        let whatsHere = SmartListResult(
            kind: .virtualMachines, entries: entries, groups: ["g"], totalBytes: 0, footprintBytes: 7)
        XCTAssertEqual(cleanUp.displayBytes, 0)
        XCTAssertEqual(whatsHere.displayBytes, 7)
        XCTAssertEqual(
            SmartListResult(kind: .downloads, entries: [], groups: [], totalBytes: 3).footprintBytes, 3,
            "footprint defaults to the reclaimable total")
    }

    func testSortBytesOverridesSizeForRanking() {
        let tree = SmartListFixture.build([
            .file("big", bytes: 100 * gigabyte), .file("small", bytes: 1 * gigabyte),
        ])
        let big = tree.node(atPathComponents: ["big"])!
        let small = tree.node(atPathComponents: ["small"])!
        var query = SmartListQuery(
            tree: tree, context: SmartListFixture.context,
            bundleInfo: SmartListFixture.StubBundles(infos: [:]), now: SmartListFixture.now)
        let grewLittle = SmartListEntry(node: big, group: "g", safety: .informational, sortBytes: 1)
        let grewALot = SmartListEntry(node: small, group: "g", safety: .informational, sortBytes: 5)
        XCTAssertLessThan(query.weight(grewLittle), query.weight(grewALot))
        XCTAssertNil(query.bundleInfo(for: big), "no bundle → nil, cached")
        XCTAssertEqual(query.bundleInfoCache.count, 1)
    }

    // MARK: - What grew

    func testWhatGrewBucketsByWindowAndSuppressesExplainedAncestors() {
        let tree = SmartListFixture.build([
            SmartListFixture.home([
                .dir(
                    "Library",
                    [
                        .dir(
                            "Caches",
                            [
                                .dir("Homebrew", [.file("bottle", bytes: 3 * gigabyte)]),
                                .dir("pip", [.file("wheel", bytes: 200 * megabyte)]),
                            ])
                    ]),
                .dir("Movies", [.file("trip.mov", bytes: 10 * gigabyte)]),
                .dir("Downloads", [.file("big.zip", bytes: 1_500 * megabyte)]),
            ])
        ])
        let now = SmartListFixture.now
        let weekAgo = SizeHistory.Snapshot(
            date: now.addingTimeInterval(-8 * 86_400),
            entries: [
                "Users": 12_700 * megabyte, "Users/t": 12_700 * megabyte, "Users/t/Library": 1_200 * megabyte,
                "Users/t/Library/Caches": 1_200 * megabyte, "Users/t/Library/Caches/Homebrew": 1 * gigabyte,
                "Users/t/Library/Caches/pip": 200 * megabyte, "Users/t/Movies": 10 * gigabyte,
                "Users/t/Downloads": 1_500 * megabyte,
            ])
        let monthAgo = SizeHistory.Snapshot(
            date: now.addingTimeInterval(-40 * 86_400),
            entries: [
                "Users": 5_200 * megabyte, "Users/t": 5_200 * megabyte, "Users/t/Library": 1_200 * megabyte,
                "Users/t/Library/Caches": 1_200 * megabyte, "Users/t/Library/Caches/Homebrew": 1 * gigabyte,
                "Users/t/Library/Caches/pip": 200 * megabyte, "Users/t/Movies": 4 * gigabyte,
            ])
        let history = SizeHistory(rootPath: "/", snapshots: [monthAgo, weekAgo])

        let result = SmartListFixture.compute(.whatGrew, tree, history: history)

        XCTAssertEqual(
            SmartListFixture.names(result, in: tree, group: "Last week"), ["Homebrew"],
            "Caches, Library and the home folder grew by the same 2 GB — explained by Homebrew, so hidden")
        XCTAssertEqual(
            SmartListFixture.names(result, in: tree, group: "Last month"), ["Movies", "Downloads"],
            "ranked by growth: +6 GB, then the new 1.5 GB folder")
        XCTAssertEqual(result.groups, ["Last week", "Last month"])
        XCTAssertEqual(SmartListFixture.names(result, in: tree), ["Movies", "Homebrew", "Downloads"])
        XCTAssertTrue(result.entries(in: "Last week")[0].note?.hasPrefix("+2 GB since ") == true)
        XCTAssertTrue(result.entries(in: "Last month")[1].note?.hasPrefix("new since ") == true)
        XCTAssertEqual(result.totalBytes, 0, "informational — nothing to reclaim")
        XCTAssertEqual(result.footprintBytes, 9_500 * megabyte, "sidebar shows total growth")
        XCTAssertTrue(result.entries.allSatisfy { $0.safety == .informational })
    }

    func testWhatGrewIsEmptyWithoutHistoryOrForAnotherRoot() {
        let tree = SmartListFixture.build([
            SmartListFixture.home([.dir("Movies", [.file("trip.mov", bytes: 10 * gigabyte)])])
        ])
        XCTAssertTrue(SmartListFixture.compute(.whatGrew, tree).isEmpty)

        let elsewhere = SizeHistory(
            rootPath: "/Volumes/Other",
            snapshots: [
                SizeHistory.Snapshot(
                    date: SmartListFixture.now.addingTimeInterval(-10 * 86_400),
                    entries: ["Users/t/Movies": 0])
            ])
        XCTAssertTrue(SmartListFixture.compute(.whatGrew, tree, history: elsewhere).isEmpty)

        let onlyToday = SizeHistory(
            rootPath: "/",
            snapshots: [SizeHistory.Snapshot(date: SmartListFixture.now, entries: ["Users/t/Movies": 0])])
        XCTAssertTrue(
            SmartListFixture.compute(.whatGrew, tree, history: onlyToday).isEmpty,
            "today's own snapshot is never a baseline")
    }

    func testBundleInfoReadsAreMemoizedAndCapped() {
        let apps = (0..<(SmartListQuery.bundleInfoReadLimit + 5)).map { index -> Spec in
            .dir("App\(index).app", [.file("bin", bytes: 1 * megabyte)])
        }
        let tree = SmartListFixture.build([.dir("Applications", apps)])
        let counter = CountingBundles()
        var query = SmartListQuery(
            tree: tree, context: SmartListFixture.context, bundleInfo: counter, now: SmartListFixture.now)
        var seen = Set<FileTree.NodeID>()
        let nodes = query.collectApps(seen: &seen)
        for node in nodes { _ = query.bundleInfo(for: node) }
        for node in nodes { _ = query.bundleInfo(for: node) }
        XCTAssertEqual(counter.reads.value, SmartListQuery.bundleInfoReadLimit, "capped, and never re-read")
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.withLock { count } }
        func bump() { lock.withLock { count += 1 } }
    }

    private struct CountingBundles: BundleInfoProvider {
        let reads = Counter()
        func info(forBundleAt absolutePath: String) -> BundleInfo? {
            reads.bump()
            return BundleInfo(name: URL(fileURLWithPath: absolutePath).lastPathComponent)
        }
    }

    // MARK: - Media libraries

    func testMediaLibrariesListsLibrariesNotProjects() {
        let tree = SmartListFixture.build([
            .dir("Library", [.dir("Audio", [.dir("Apple Loops", [.file("loop.caf", bytes: 2 * gigabyte)])])]),
            SmartListFixture.home([
                .dir(
                    "Pictures",
                    [
                        .dir("Photos Library.photoslibrary", [.file("db", bytes: 5 * gigabyte)]),
                        .dir(
                            "Lightroom",
                            [
                                .file("Catalog.lrcat", bytes: 150 * megabyte),
                                .dir("Catalog Previews.lrdata", [.file("p", bytes: 2 * gigabyte)]),
                            ]),
                    ]),
                .dir(
                    "Movies",
                    [
                        .dir("Final.fcpbundle", [.file("render.mov", bytes: 9 * gigabyte)]),
                        .dir("TV", [.file("show.movpkg", bytes: 700 * megabyte)]),
                        .dir("Tiny.imovielibrary", [.file("x", bytes: 20 * megabyte)]),
                    ]),
                .dir(
                    "Music",
                    [
                        .dir(
                            "Music",
                            [
                                .dir("Media.localized", [.file("a.m4a", bytes: 1_200 * megabyte)]),
                                .dir("Music Library.musiclibrary", [.file("db", bytes: 300 * megabyte)]),
                            ])
                    ]),
                .dir(
                    "Library",
                    [
                        .dir(
                            "Group Containers",
                            [
                                .dir(
                                    "243LU875E5.groups.com.apple.podcasts",
                                    [.file("ep", bytes: 400 * megabyte)])
                            ])
                    ]),
            ]),
        ])
        let result = SmartListFixture.compute(.mediaLibraries, tree)

        XCTAssertEqual(result.groups, ["Photos & video", "Music & audio", "Other"])
        XCTAssertEqual(
            SmartListFixture.names(result, in: tree, group: "Photos & video"),
            ["Photos Library.photoslibrary", "Catalog Previews.lrdata", "TV", "Catalog.lrcat"],
            "biggest first; the fcpbundle is a project, the tiny iMovie library is below the floor")
        XCTAssertEqual(
            SmartListFixture.names(result, in: tree, group: "Music & audio"), ["Apple Loops", "Music"],
            "the .musiclibrary inside ~/Music/Music is covered by its parent")
        XCTAssertEqual(
            SmartListFixture.names(result, in: tree, group: "Other"), ["243LU875E5.groups.com.apple.podcasts"]
        )
        XCTAssertEqual(result.entries(in: "Other").first?.displayName, "Podcasts")
        XCTAssertTrue(result.entries.allSatisfy { $0.safety == .informational })
        XCTAssertEqual(result.totalBytes, 0, "nothing here is reclaimable from Foldscale")
        XCTAssertEqual(result.displayBytes, result.footprintBytes)
        XCTAssertEqual(
            result.footprintBytes,
            5 * gigabyte + 2 * gigabyte + 700 * megabyte + 150 * megabyte + 2 * gigabyte + 1_500 * megabyte
                + 400 * megabyte)
    }

    // MARK: - Cloud files

    func testCloudFilesCountsOnlineOnlyItemsPerProvider() {
        let dataless: NodeFlags = [.dataless]
        let tree = SmartListFixture.build([
            SmartListFixture.home([
                .dir(
                    "Library",
                    [
                        .dir(
                            "Mobile Documents",
                            [
                                .dir(
                                    "com~apple~CloudDocs",
                                    [
                                        .file("local.pdf", bytes: 400 * megabyte),
                                        .dir(
                                            "Photos",
                                            [
                                                .file(
                                                    "a.heic", bytes: 0, logicalBytes: 2 * gigabyte,
                                                    flags: dataless),
                                                .file(
                                                    "b.heic", bytes: 0, logicalBytes: 1 * gigabyte,
                                                    flags: dataless),
                                            ]),
                                        .file(".old.doc.icloud", bytes: 1_000),
                                    ]),
                                .dir(
                                    "iCloud~com~apple~Keynote",
                                    [
                                        .file(
                                            "deck.key", bytes: 0, logicalBytes: 200 * megabyte,
                                            flags: dataless)
                                    ]),
                                .dir(
                                    "iCloud~tiny~app",
                                    [.file("x", bytes: 0, logicalBytes: 1 * megabyte, flags: dataless)]),
                            ]),
                        .dir(
                            "Application Support", [.dir("CloudDocs", [.file("db", bytes: 300 * megabyte)])]),
                        .dir(
                            "CloudStorage",
                            [
                                .dir(
                                    "Dropbox-Personal",
                                    [
                                        .file("a", bytes: 2 * gigabyte),
                                        .file("b", bytes: 0, logicalBytes: 500 * megabyte, flags: dataless),
                                        .file("c", bytes: 0, logicalBytes: 500 * megabyte, flags: dataless),
                                    ]),
                                .dir(
                                    "GoogleDrive-me@gmail.com",
                                    [.file("big", bytes: 0, logicalBytes: 5 * gigabyte, flags: dataless)]),
                                .dir("ProtonDrive-me", [.file("f", bytes: 60 * megabyte)]),
                            ]),
                    ]),
                .dir("Dropbox", [.file("legacy", bytes: 100 * megabyte)]),
            ])
        ])
        let result = SmartListFixture.compute(.cloudFiles, tree)

        XCTAssertEqual(result.groups, ["iCloud", "Dropbox", "Google Drive", "Other cloud"])
        let byName = Dictionary(uniqueKeysWithValues: result.entries.map { (tree.name(of: $0.node), $0) })
        XCTAssertEqual(
            Set(byName.keys),
            [
                "com~apple~CloudDocs", "iCloud~com~apple~Keynote", "CloudDocs", "Dropbox-Personal",
                "GoogleDrive-me@gmail.com", "ProtonDrive-me", "Dropbox",
            ], "the 1 MB container is below both floors")
        XCTAssertEqual(byName["com~apple~CloudDocs"]?.displayName, "iCloud Drive")
        XCTAssertEqual(byName["com~apple~CloudDocs"]?.note, "3 items online-only (3 GB in the cloud)")
        XCTAssertEqual(byName["iCloud~com~apple~Keynote"]?.displayName, "Keynote (iCloud)")
        XCTAssertEqual(byName["iCloud~com~apple~Keynote"]?.note, "1 item online-only (200 MB in the cloud)")
        XCTAssertEqual(byName["CloudDocs"]?.note, "Managed by macOS")
        XCTAssertEqual(byName["Dropbox-Personal"]?.displayName, "Dropbox (Personal)")
        XCTAssertEqual(byName["Dropbox-Personal"]?.group, "Dropbox")
        XCTAssertEqual(byName["GoogleDrive-me@gmail.com"]?.displayName, "Google Drive (me@gmail.com)")
        XCTAssertEqual(byName["GoogleDrive-me@gmail.com"]?.group, "Google Drive")
        XCTAssertEqual(byName["ProtonDrive-me"]?.group, "Other cloud")
        XCTAssertEqual(byName["ProtonDrive-me"]?.note, "All files stored locally")
        XCTAssertNil(byName["Dropbox"]?.displayName)
        XCTAssertEqual(
            result.entries.first.map { tree.name(of: $0.node) }, "Dropbox-Personal",
            "ranked by local footprint")
        XCTAssertTrue(result.entries.allSatisfy { $0.safety == .informational })
        XCTAssertEqual(result.totalBytes, 0)
        XCTAssertEqual(
            result.displayBytes,
            2 * gigabyte + 400 * megabyte + 300 * megabyte + 100 * megabyte + 60 * megabyte + 1_000)
    }

    // MARK: - App leftovers

    func testAppLeftoversMatchesByNameIdentifierAndVendor() {
        let app: (String, Int64) -> Spec = { name, bytes in .dir(name, [.file("bin", bytes: bytes)]) }
        let folder: (String, Int64) -> Spec = { name, bytes in .dir(name, [.file("data", bytes: bytes)]) }
        let tree = SmartListFixture.build([
            .dir(
                "Applications",
                [
                    app("Visual Studio Code.app", 500 * megabyte), app("Microsoft Word.app", 2 * gigabyte),
                    app("iTerm.app", 100 * megabyte), app("Slack.app", 300 * megabyte),
                    app("Sublime Text.app", 80 * megabyte),
                ]),
            SmartListFixture.home([
                .dir(
                    "Library",
                    [
                        .dir(
                            "Application Support",
                            [
                                folder("Code", 200 * megabyte), folder("Microsoft", 300 * megabyte),
                                folder("iTerm2", 50 * megabyte), folder("Sublime Text 3", 80 * megabyte),
                                folder("Sketch", 1_900 * megabyte), folder("Postman", 640 * megabyte),
                                folder("Homebrew", 2 * gigabyte), folder("MobileSync", 5 * gigabyte),
                                folder("com.apple.TCC", 30 * megabyte), folder("OldApp", 5 * megabyte),
                            ]),
                        .dir(
                            "Containers",
                            [
                                folder("com.microsoft.teams2", 900 * megabyte),
                                folder("com.bohemiancoding.sketch3", 1_200 * megabyte),
                                folder("com.apple.mail", 700 * megabyte),
                                folder("com.tinyspeck.slackmacgap", 100 * megabyte),
                            ]),
                        .dir(
                            "Group Containers",
                            [
                                folder("UBF8T346G9.Office", 400 * megabyte),
                                folder("UBF8T346G9.com.microsoft.oneauth", 60 * megabyte),
                                folder("2BUA8C4S2C.com.agilebits", 300 * megabyte),
                                folder("group.com.apple.notes", 90 * megabyte),
                                folder("group.com.tinyspeck.slackmacgap", 70 * megabyte),
                                folder("6N38VWS5BX.group.ru.keepcoder.telegram", 80 * megabyte),
                            ]),
                    ])
            ]),
        ])
        let result = SmartListFixture.compute(
            .appLeftovers, tree,
            bundles: [
                "/Applications/Visual Studio Code.app": BundleInfo(
                    name: "Code", identifier: "com.microsoft.VSCode"),
                "/Applications/Microsoft Word.app": BundleInfo(
                    name: "Microsoft Word", identifier: "com.microsoft.Word"),
                "/Applications/iTerm.app": BundleInfo(name: "iTerm2", identifier: "com.googlecode.iterm2"),
                "/Applications/Slack.app": BundleInfo(name: "Slack", identifier: "com.tinyspeck.slackmacgap"),
                "/Applications/Sublime Text.app": BundleInfo(
                    name: "Sublime Text", identifier: "com.sublimetext.4"),
            ])

        XCTAssertEqual(result.groups, ["Support data", "Containers", "Group containers"])
        XCTAssertEqual(
            SmartListFixture.names(result, in: tree, group: "Support data"), ["Sketch", "Postman"],
            "Code/Microsoft/iTerm2/Sublime Text 3 are owned; Homebrew and MobileSync are tools; Apple's and tiny folders skipped"
        )
        XCTAssertEqual(
            SmartListFixture.names(result, in: tree, group: "Containers"), ["com.bohemiancoding.sketch3"],
            "Teams is covered by Microsoft's vendor prefix; Slack by its id; Mail is Apple's")
        XCTAssertEqual(
            SmartListFixture.names(result, in: tree, group: "Group containers"),
            ["2BUA8C4S2C.com.agilebits", "6N38VWS5BX.group.ru.keepcoder.telegram"],
            "a non-reverse-DNS group container is never judged; Slack's group container is owned via its id")
        XCTAssertEqual(result.entries(in: "Support data").first?.note, "Sketch isn't installed anymore")
        XCTAssertEqual(result.entries(in: "Containers").first?.note, "Sketch3 isn't installed anymore")
        XCTAssertEqual(
            result.entries(in: "Group containers").first?.note, "Agilebits isn't installed anymore")
        XCTAssertTrue(result.entries.allSatisfy { $0.safety == .reviewFirst })
        XCTAssertEqual(
            result.totalBytes,
            1_900 * megabyte + 640 * megabyte + 1_200 * megabyte + 300 * megabyte + 80 * megabyte)
        XCTAssertLessThan(
            FreeUpPlanner.priority(.appLeftovers, "Support data", .reviewFirst),
            FreeUpPlanner.priority(.bigProjects, "Code", .reviewFirst),
            "leftovers are picked before projects when 'Review first' is on")
    }

    func testLeftoverIdentifierHelpers() {
        XCTAssertEqual(
            SmartListQuery.strippingTeamID("UBF8T346G9.com.microsoft.office"), "com.microsoft.office")
        XCTAssertEqual(SmartListQuery.strippingTeamID("group.com.apple.notes"), "group.com.apple.notes")
        XCTAssertEqual(SmartListQuery.vendor(of: "com.microsoft.teams2"), "com.microsoft")
        XCTAssertEqual(SmartListQuery.owner(ofIdentifier: "com.bohemiancoding.sketch3"), "Sketch3")
        XCTAssertEqual(
            SmartListQuery.cloudProvider(folderName: "GoogleDrive-me@x.com").provider, "Google Drive")
        XCTAssertEqual(SmartListQuery.cloudProvider(folderName: "Box").account, nil)
        XCTAssertEqual(SmartListQuery.iCloudContainerName("iCloud~com~apple~Keynote"), "Keynote (iCloud)")
    }
}
