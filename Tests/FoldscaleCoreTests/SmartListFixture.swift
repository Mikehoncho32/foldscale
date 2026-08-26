import Foundation

@testable import FoldscaleCore

/// Shared synthetic-tree DSL for smart-list tests: trees rooted at "/" with the
/// home folder at /Users/t and a fixed `now`, so ages are deterministic.
enum SmartListFixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let epochNow: Int64 = 1_800_000_000
    static let day: Int64 = 86_400
    static let context = SmartListContext(rootPath: "/", homePath: "/Users/t")
    static let gigabyte: Int64 = 1_000_000_000
    static let megabyte: Int64 = 1_000_000

    indirect enum Spec {
        case dir(String, mtimeDaysAgo: Int64 = 0, [Spec])
        case file(
            String, bytes: Int64, mtimeDaysAgo: Int64 = 0, logicalBytes: Int64? = nil,
            flags: NodeFlags = [])
    }

    static func build(_ children: [Spec]) -> FileTree {
        var builder = FileTreeBuilder()
        builder.enterDirectory(name: "", meta: meta(directory: true, bytes: 0, mtime: epochNow))
        for child in children { add(child, to: &builder) }
        builder.leaveDirectory()
        return builder.finish()
    }

    private static func add(_ spec: Spec, to builder: inout FileTreeBuilder) {
        switch spec {
        case .dir(let name, let daysAgo, let children):
            builder.enterDirectory(
                name: name, meta: meta(directory: true, bytes: 0, mtime: epochNow - daysAgo * day))
            for child in children { add(child, to: &builder) }
            builder.leaveDirectory()
        case .file(let name, let bytes, let daysAgo, let logicalBytes, let flags):
            builder.addLeaf(
                name: name,
                meta: meta(
                    directory: false, bytes: bytes, mtime: epochNow - daysAgo * day,
                    logicalBytes: logicalBytes, flags: flags))
        }
    }

    private static func meta(
        directory: Bool, bytes: Int64, mtime: Int64, logicalBytes: Int64? = nil, flags: NodeFlags = []
    ) -> NodeMeta {
        NodeMeta(
            allocatedSize: bytes, logicalSize: logicalBytes ?? bytes, modificationTime: mtime,
            flags: directory ? [.directory] : flags, deviceID: 1, inode: 0, linkCount: 1)
    }

    static func home(_ children: [Spec]) -> Spec { .dir("Users", [.dir("t", children)]) }

    static func names(_ result: SmartListResult, in tree: FileTree, group: String? = nil) -> [String] {
        (group.map { result.entries(in: $0) } ?? result.entries).map { tree.name(of: $0.node) }
    }

    static func compute(
        _ kind: SmartListKind, _ tree: FileTree, bundles: [String: BundleInfo] = [:],
        backups: [String: DeviceBackupInfo] = [:], history: SizeHistory? = nil
    ) -> SmartListResult {
        SmartListEngine.compute(
            kind, in: tree, context: context, bundleInfo: StubBundles(infos: bundles, backups: backups),
            history: history, now: now)
    }

    struct StubBundles: BundleInfoProvider {
        let infos: [String: BundleInfo]
        var backups: [String: DeviceBackupInfo] = [:]
        func info(forBundleAt absolutePath: String) -> BundleInfo? { infos[absolutePath] }
        func backupInfo(forBackupAt absolutePath: String) -> DeviceBackupInfo? { backups[absolutePath] }
    }
}
