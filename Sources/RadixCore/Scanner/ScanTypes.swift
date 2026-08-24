import Foundation

/// Options controlling a scan.
public struct ScanOptions: Sendable {
    /// When true, directories on a different device than the scan root are not
    /// descended into — the safe default that keeps a scan on its starting volume
    /// instead of wandering into other mounts. (The firmlink / whole-volume
    /// double-count edge cases are validated on-device; see the scanner ADR.)
    public var stayOnStartVolume: Bool

    /// Directory exclusion rules applied before descending.
    public var exclusions: ScanExclusions

    public init(stayOnStartVolume: Bool = true, exclusions: ScanExclusions = .default) {
        self.stayOnStartVolume = stayOnStartVolume
        self.exclusions = exclusions
    }
}

/// A periodic progress sample emitted while a scan runs.
public struct ScanProgress: Sendable {
    /// Number of nodes visited so far.
    public var nodesScanned: Int
    /// Sum of allocated bytes counted so far (hard-link duplicates excluded).
    public var bytesScanned: Int64
    /// The path most recently being scanned, for a subtle live indicator.
    public var currentPath: String

    public init(nodesScanned: Int, bytesScanned: Int64, currentPath: String) {
        self.nodesScanned = nodesScanned
        self.bytesScanned = bytesScanned
        self.currentPath = currentPath
    }
}

/// An event from the progressive (streaming) scan API.
public enum ScanEvent: Sendable {
    case progress(ScanProgress)
    case completed(FileTree)
}

/// Errors a scan can fail with.
public enum ScanError: Error, Sendable, Equatable {
    /// The scan root did not exist or could not be `stat`ed.
    case rootNotFound(String)
    /// The scan root exists but is not a directory.
    case rootNotADirectory(String)
    /// The scan was cancelled before completing.
    case cancelled
}

/// The `(device, inode)` identity used to dedupe hard links (and to guard against
/// visiting the same directory twice via firmlinks or cycles).
struct InodeKey: Hashable {
    let device: Int64
    let inode: UInt64
}
