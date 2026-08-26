import Foundation

/// Namespace for **FoldscaleCore** — the Foundation-only scanning and analysis engine
/// behind Foldscale, the Finder-native disk-space analyzer.
///
/// FoldscaleCore contains no UI code. It exposes the recursive filesystem scanner,
/// the file-node model, exclusion rules, smart-list queries, the scan cache, and
/// safe file actions (all deletion routes through `FileManager.trashItem`). The
/// absence of `import SwiftUI` / `import AppKit` is enforced by a unit test so the
/// engine stays independently testable and reusable (e.g. for a future menu-bar mode).
public enum FoldscaleCore {
    /// The semantic version of the FoldscaleCore engine.
    public static let version = "1.2.0"
}
