import Foundation

/// Rules deciding which directories a scan skips entirely — never descended into,
/// never counted. These are *scan* exclusions (OS noise, other volumes), distinct
/// from the *trash-protection* rules used later by delete actions.
public struct ScanExclusions: Sendable {
    /// Absolute directory paths whose entire subtree is skipped.
    public var skippedPaths: Set<String>

    /// Directory basenames skipped wherever they appear.
    public var skippedNames: Set<String>

    public init(skippedPaths: Set<String> = [], skippedNames: Set<String> = []) {
        self.skippedPaths = skippedPaths
        self.skippedNames = skippedNames
    }

    /// Whether the directory at `path` should be skipped.
    public func shouldSkipDirectory(path: String) -> Bool {
        if skippedPaths.contains(path) { return true }
        return skippedNames.contains((path as NSString).lastPathComponent)
    }

    /// Default exclusions: OS-managed content that isn't user-reclaimable and can
    /// be dangerous or misleading to traverse (handoff §5, §6). Note that modern
    /// Time Machine local snapshots are APFS snapshots outside the file namespace,
    /// so they never appear in a normal walk and need no path rule here.
    public static let `default` = ScanExclusions(
        skippedPaths: [
            "/System",
            "/private/var/vm",  // swapfile / sleepimage
            "/Volumes",  // other mounted volumes
            "/.vol",
        ],
        skippedNames: [
            ".Trashes",
            ".Spotlight-V100",
            ".fseventsd",
            ".DocumentRevisions-V100",
            ".MobileBackups",
        ]
    )

    /// No exclusions — used by tests that must count everything.
    public static let none = ScanExclusions()
}
