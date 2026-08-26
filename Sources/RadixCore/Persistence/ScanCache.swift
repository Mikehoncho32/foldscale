import Foundation

/// A persisted scan: the tree plus where and when it was taken.
public struct ScanSnapshot: Codable, Sendable {
    /// Bump when `FileTree`'s on-disk layout changes, so old caches are rejected
    /// rather than misread (the format is a raw memory image — see ADR-0003).
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let rootPath: String
    public let savedAt: Date
    public let tree: FileTree

    public init(rootPath: String, savedAt: Date, tree: FileTree) {
        self.formatVersion = Self.currentFormatVersion
        self.rootPath = rootPath
        self.savedAt = savedAt
        self.tree = tree
    }
}

/// Persists the last scan so a relaunch shows results without forcing a rescan
/// (handoff §5, item 10). Stored in **Application Support** — not Caches — so macOS
/// won't purge it exactly when the disk is full and the user reaches for Radix
/// (see the §11 decision). Format is a binary property list of raw-array blobs
/// (ADR-0003).
public enum ScanCache {
    /// Test hook: when set, the cache lives here instead of Application Support, so
    /// unit tests never touch (or clobber) the user's real cache.
    static var directoryOverride: URL?

    /// `~/Library/Application Support/Radix/` (or the test override).
    public static var directory: URL {
        if let directoryOverride { return directoryOverride }
        let base =
            (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: false)) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Radix", isDirectory: true)
    }

    private static var fileURL: URL {
        directory.appendingPathComponent("last-scan.radixcache")
    }

    /// Writes the snapshot atomically, LZFSE-compressed. Callers run this off the
    /// main actor.
    public static func save(tree: FileTree, rootPath: String, savedAt: Date) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let plist = try encoder.encode(ScanSnapshot(rootPath: rootPath, savedAt: savedAt, tree: tree))
        let compressed = try (plist as NSData).compressed(using: .lzfse) as Data
        try compressed.write(to: fileURL, options: .atomic)
    }

    /// Loads the last snapshot, or `nil` if none/unreadable/incompatible.
    public static func load() -> ScanSnapshot? {
        guard let compressed = try? Data(contentsOf: fileURL),
            let plist = try? (compressed as NSData).decompressed(using: .lzfse) as Data,
            let snapshot = try? PropertyListDecoder().decode(ScanSnapshot.self, from: plist),
            snapshot.formatVersion == ScanSnapshot.currentFormatVersion
        else { return nil }
        return snapshot
    }
}
