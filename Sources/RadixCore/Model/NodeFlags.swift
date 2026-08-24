import Foundation

/// Bit flags describing a scanned filesystem node's type and state.
public struct NodeFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// The node is a directory.
    public static let directory = NodeFlags(rawValue: 1 << 0)

    /// The node is a symbolic link. Radix records it but never follows it.
    public static let symlink = NodeFlags(rawValue: 1 << 1)

    /// The node is a dataless cloud placeholder (`SF_DATALESS`) — an online-only
    /// iCloud/Dropbox/OneDrive file. Its size reflects the local footprint only,
    /// and Radix never opens it (which would trigger a download).
    public static let dataless = NodeFlags(rawValue: 1 << 2)

    /// A second-or-later hard link to an inode already counted elsewhere. Its
    /// allocated size is not added again to ancestor totals (deduped).
    public static let hardlinkDuplicate = NodeFlags(rawValue: 1 << 3)

    /// The node could not be read (permission denied or `stat` failed).
    public static let unreadable = NodeFlags(rawValue: 1 << 4)
}
