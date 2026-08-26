import Foundation

/// The kind of a filesystem node, determined from `st_mode` during traversal.
public enum NodeKind: Sendable {
    case directory
    case file
    case symlink
    case unreadable
}

/// Immutable metadata extracted from one `stat` result during a scan.
///
/// `NodeMeta.from(stat:kind:)` is a pure function, so size and flag decoding —
/// including cloud-placeholder (`SF_DATALESS`) detection — is unit-tested with a
/// hand-built `stat`, never touching the filesystem.
public struct NodeMeta: Sendable, Equatable {
    /// On-disk footprint in bytes (`st_blocks` × 512) — what actually frees up.
    public var allocatedSize: Int64
    /// Apparent size in bytes (`st_size`) — shown only in Get Info.
    public var logicalSize: Int64
    /// Last-modification time, seconds since the Unix epoch (`st_mtimespec`).
    public var modificationTime: Int64
    /// Type and state flags (directory / symlink / dataless / …).
    public var flags: NodeFlags
    /// `st_dev` — device id, one half of the hardlink-dedupe key.
    public var deviceID: Int64
    /// `st_ino` — inode number, the other half of the dedupe key.
    public var inode: UInt64
    /// `st_nlink` — number of hard links to this inode.
    public var linkCount: UInt64

    public init(
        allocatedSize: Int64,
        logicalSize: Int64,
        modificationTime: Int64,
        flags: NodeFlags,
        deviceID: Int64,
        inode: UInt64,
        linkCount: UInt64
    ) {
        self.allocatedSize = allocatedSize
        self.logicalSize = logicalSize
        self.modificationTime = modificationTime
        self.flags = flags
        self.deviceID = deviceID
        self.inode = inode
        self.linkCount = linkCount
    }
}

extension NodeMeta {
    /// POSIX fixes `st_blocks` at 512-byte units, independent of the filesystem's
    /// own block size.
    public static let blockUnit: Int64 = 512

    /// `SF_DATALESS` (`0x4000_0000`): the file is a dataless placeholder. Its
    /// `st_blocks` reflect only what is stored locally; reading the flag via
    /// `stat` does not materialize the file, but opening its contents would.
    public static let sfDataless: UInt32 = 0x4000_0000

    /// Builds metadata from a `stat` plus the node kind determined by the walker.
    /// Does not set `.hardlinkDuplicate`; the walker sets that after its
    /// `(deviceID, inode)` dedupe check.
    public static func from(stat entry: stat, kind: NodeKind) -> NodeMeta {
        var flags: NodeFlags = []
        switch kind {
        case .directory: flags.insert(.directory)
        case .symlink: flags.insert(.symlink)
        case .unreadable: flags.insert(.unreadable)
        case .file: break
        }
        if (entry.st_flags & sfDataless) != 0 {
            flags.insert(.dataless)
        }
        return NodeMeta(
            allocatedSize: Int64(entry.st_blocks) * blockUnit,
            logicalSize: Int64(entry.st_size),
            modificationTime: Int64(entry.st_mtimespec.tv_sec),
            flags: flags,
            deviceID: Int64(entry.st_dev),
            inode: UInt64(entry.st_ino),
            linkCount: UInt64(entry.st_nlink)
        )
    }
}
