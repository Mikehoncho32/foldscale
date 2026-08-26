import Foundation

/// Persists `SizeHistory` next to the scan cache as a small binary property list.
/// Fail-soft: anything unreadable, incompatible or belonging to another root starts
/// a fresh history. Callers run `record` off the main actor.
public enum SizeHistoryStore {
    static var fileURL: URL { ScanCache.directory.appendingPathComponent("size-history.plist") }

    public static func load(rootPath: String) -> SizeHistory? {
        guard let data = try? Data(contentsOf: fileURL),
            let history = try? PropertyListDecoder().decode(SizeHistory.self, from: data),
            history.formatVersion == SizeHistory.currentFormatVersion, history.rootPath == rootPath
        else { return nil }
        return history
    }

    public static func save(_ history: SizeHistory) throws {
        try FileManager.default.createDirectory(at: ScanCache.directory, withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(history).write(to: fileURL, options: .atomic)
    }

    /// Captures `tree` as today's snapshot, merges it into the stored history for
    /// `rootPath` (or a new one), saves, and returns the result — even if the save
    /// failed, so the caller still has something to show.
    @discardableResult
    public static func record(tree: FileTree, rootPath: String, now: Date = Date()) -> SizeHistory {
        var history = load(rootPath: rootPath) ?? SizeHistory(rootPath: rootPath)
        history.record(SizeHistory.Snapshot.capture(tree, date: now))
        try? save(history)
        return history
    }
}
