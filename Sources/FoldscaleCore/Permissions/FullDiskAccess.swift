import Foundation

/// Detects whether the app currently has **Full Disk Access** (handoff §5.7).
///
/// macOS exposes no API to query TCC directly, so the standard technique is to
/// probe a location that only an FDA-granted app can read — here the user's
/// `TCC.db`. Reading it is metadata-safe: a failure just means "not granted".
/// The deep-link URL opens the relevant System Settings pane.
public enum FullDiskAccess {
    /// The System Settings deep link for the Full Disk Access list. Undocumented
    /// and version-sensitive, so the UI also shows a manual fallback.
    public static let settingsURLString =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    /// Whether the app can read FDA-protected data right now.
    ///
    /// Returns `true` if the probe file is readable, `false` if it exists but is
    /// blocked, and `true` if the probe can't be found (indeterminate — never nag).
    public static func isGranted() -> Bool {
        let probe = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        guard FileManager.default.fileExists(atPath: probe.path) else { return true }
        guard let handle = try? FileHandle(forReadingFrom: probe) else { return false }
        try? handle.close()
        return true
    }
}
