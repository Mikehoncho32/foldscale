import Foundation

// MARK: - Cloud files

extension SmartListQuery {
    static let cloudMinimumBytes: Int64 = 50_000_000
    static let cloudGroups = ["iCloud", "Dropbox", "Google Drive", "OneDrive", "Box", "Other cloud"]
    static let cloudOtherGroup = "Other cloud"
    /// Pre-File-Provider iCloud placeholders: `.name.ext.icloud`.
    static let legacyPlaceholderSuffix = SmartListBytes.bytes(".icloud")
    /// Sync folders older clients keep directly under home.
    static let legacyCloudFolders = [
        (folder: "Dropbox", group: "Dropbox"), (folder: "Google Drive", group: "Google Drive"),
        (folder: "OneDrive", group: "OneDrive"), (folder: "Box Sync", group: "Box"),
    ]

    /// What each cloud service keeps on this Mac versus only in the cloud. Trashing a
    /// synced file deletes it everywhere, so every row is informational.
    mutating func cloudFiles() -> ([SmartListEntry], [String]) {
        var entries: [SmartListEntry] = []
        if let mobile = node(at: home("Library/Mobile Documents")) {
            tree.forEachChild(of: mobile) { container in
                guard tree.isDirectory(container) else { return }
                let name = tree.name(of: container)
                let display = name == "com~apple~CloudDocs" ? "iCloud Drive" : Self.iCloudContainerName(name)
                if let entry = cloudEntry(container, group: "iCloud", displayName: display) {
                    entries.append(entry)
                }
            }
        }
        if let cache = node(at: home("Library/Application Support/CloudDocs")),
            let entry = cloudEntry(
                cache, group: "iCloud", displayName: "iCloud sync cache", note: "Managed by macOS")
        {
            entries.append(entry)
        }
        if let storage = node(at: home("Library/CloudStorage")) {
            tree.forEachChild(of: storage) { folder in
                guard tree.isDirectory(folder) else { return }
                let (provider, account) = Self.cloudProvider(folderName: tree.name(of: folder))
                let group = Self.cloudGroups.contains(provider) ? provider : Self.cloudOtherGroup
                let display = account.map { "\(provider) (\($0))" } ?? provider
                if let entry = cloudEntry(folder, group: group, displayName: display) {
                    entries.append(entry)
                }
            }
        }
        for legacy in Self.legacyCloudFolders {
            guard let folder = node(at: home(legacy.folder)), tree.isDirectory(folder),
                let entry = cloudEntry(folder, group: legacy.group, displayName: nil)
            else { continue }
            entries.append(entry)
        }
        return (entries, Self.cloudGroups)
    }

    /// One synced root: its local footprint, plus how much is only in the cloud. Roots
    /// with under 50 MB either locally or remotely are noise and skipped.
    private func cloudEntry(
        _ root: FileTree.NodeID, group: String, displayName: String?, note: String? = nil
    ) -> SmartListEntry? {
        let stats = cloudStats(of: root)
        let local = tree.totalAllocatedSize(of: root)
        guard local >= Self.cloudMinimumBytes || stats.remoteBytes >= Self.cloudMinimumBytes else {
            return nil
        }
        var line = note ?? "All files stored locally"
        if note == nil, stats.onlineOnly > 0 {
            let items =
                stats.onlineOnly == 1 ? "1 item" : "\(DisplayFormat.itemCount(Int64(stats.onlineOnly))) items"
            line = "\(items) online-only"
            if stats.remoteBytes > 0 { line += " (\(Self.format(stats.remoteBytes)) in the cloud)" }
        }
        return SmartListEntry(
            node: root, group: group, note: line, safety: .informational, displayName: displayName)
    }

    /// Counts placeholders under `root` and sums their cloud size. Dataless *files* are
    /// the modern kind (their logical size is the remote size); a dataless folder is
    /// descended, never counted.
    func cloudStats(of root: FileTree.NodeID) -> (onlineOnly: Int, remoteBytes: Int64) {
        var count = 0
        var remote: Int64 = 0
        tree.forEachDescendant(of: root) { node in
            if tree.isDirectory(node) { return true }
            if tree.flags(of: node).contains(.dataless) {
                count += 1
                remote += tree.logicalSize(of: node)
            } else {
                let name = tree.nameUTF8(of: node)
                let isHidden = name.first == 46  // '.'
                if isHidden, SmartListBytes.hasSuffix(name, Self.legacyPlaceholderSuffix) { count += 1 }
            }
            return false
        }
        return (count, remote)
    }

    /// `~/Library/CloudStorage/<Provider>-<account>` → ("Dropbox", "Personal").
    static func cloudProvider(folderName: String) -> (provider: String, account: String?) {
        var raw = folderName[...]
        var account: String?
        if let dash = folderName.firstIndex(of: "-") {
            raw = folderName[..<dash]
            let rest = folderName[folderName.index(after: dash)...]
            account = rest.isEmpty ? nil : String(rest)
        }
        return (raw == "GoogleDrive" ? "Google Drive" : String(raw), account)
    }

    /// `iCloud~com~apple~Keynote` → "Keynote (iCloud)".
    static func iCloudContainerName(_ folderName: String) -> String? {
        guard let last = folderName.split(separator: "~").last, !last.isEmpty else { return nil }
        return "\(last.prefix(1).uppercased())\(last.dropFirst()) (iCloud)"
    }
}
