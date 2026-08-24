import Foundation

/// The non-negotiable safety gate for deletion (handoff §6): Radix refuses to move
/// certain locations to the Trash. This logic is pure and Foundation-only so it is
/// exhaustively unit-tested; the UI shows a "protected" state rather than offering a
/// disabled button.
public enum ProtectedPaths {
    /// System locations whose contents must never be trashed. Note that top-level
    /// `/Library` is protected but a user's `~/Library` is **not** (users routinely
    /// clean caches there) — the prefix match is anchored to absolute roots.
    public static let systemPrefixes = [
        "/System",
        "/Library",
        "/usr",
        "/bin",
        "/sbin",
        "/private",
        "/Applications/Utilities",
    ]

    /// Whether `url` must be protected from trashing.
    ///
    /// - Parameters:
    ///   - url: The candidate to trash.
    ///   - additionalProtected: App-specific roots to also protect — typically the
    ///     app's own bundle and its Application Support directory.
    public static func isProtected(_ url: URL, additionalProtected: [URL] = []) -> Bool {
        let path = url.standardizedFileURL.path
        // Never trash a volume root or the filesystem root.
        if path == "/" || path.isEmpty { return true }
        for prefix in systemPrefixes where matches(path, prefix) { return true }
        for extra in additionalProtected where matches(path, extra.standardizedFileURL.path) {
            return true
        }
        return false
    }

    /// True when `path` equals `root` or lies within it (avoiding false matches like
    /// "/LibraryFoo" against "/Library").
    private static func matches(_ path: String, _ root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}
