import Foundation

/// Namespace for **RadixCore** — the Foundation-only scanning and analysis engine
/// behind Radix, the Finder-native disk-space analyzer.
///
/// RadixCore contains no UI code. It exposes the recursive filesystem scanner,
/// the file-node model, exclusion rules, smart-list queries, the scan cache, and
/// safe file actions (all deletion routes through `FileManager.trashItem`). The
/// absence of `import SwiftUI` / `import AppKit` is enforced by a unit test so the
/// engine stays independently testable and reusable (e.g. for a future menu-bar mode).
public enum RadixCore {
    /// The semantic version of the RadixCore engine.
    public static let version = "1.1.0"
}
