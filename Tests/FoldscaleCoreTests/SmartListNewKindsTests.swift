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
}
