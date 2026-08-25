import Foundation

// MARK: - Downloads

extension SmartListQuery {
    static let installerExtensions = SmartListBytes.bytes([
        "dmg", "pkg", "mpkg", "zip", "iso", "xip", "ipsw", "rar", "7z", "tar", "gz", "tgz",
    ])
    static let forgottenMinimumBytes: Int64 = 200_000_000
    static let forgottenAge: TimeInterval = 30 * 86_400

    /// Installers and archives, plus big files untouched for a month, in Downloads
    /// and on the Desktop (depth ≤ 3).
    mutating func downloads() -> ([SmartListEntry], [String]) {
        let installers = "Installers & archives"
        let forgotten = "Big and forgotten"
        var entries: [SmartListEntry] = []
        let installed = appNames()
        for folder in [home("Downloads"), home("Desktop")] {
            guard let root = node(at: folder) else { continue }
            walk(root, maxDepth: 3) { node in
                guard !tree.isDirectory(node) else { return }
                if SmartListBytes.hasExtension(tree.nameUTF8(of: node), in: Self.installerExtensions) {
                    var note = age(of: node)
                    if installed.contains(Self.productName(from: tree.name(of: node))) {
                        note += " · already installed"
                    }
                    entries.append(
                        SmartListEntry(node: node, group: installers, note: note, safety: .safeToTrash))
                } else if tree.totalAllocatedSize(of: node) >= Self.forgottenMinimumBytes,
                    ageSeconds(of: node) >= Self.forgottenAge
                {
                    entries.append(
                        SmartListEntry(
                            node: node, group: forgotten, note: age(of: node), safety: .safeToTrash))
                }
            }
        }
        return (entries, [installers, forgotten])
    }

    /// "Slack-4.29.149-macOS.dmg" → "slack"; "Google Chrome 120.zip" → "google chrome".
    /// Cuts at the first separator that is followed by a version-shaped token.
    static func productName(from fileName: String) -> String {
        var base = (fileName as NSString).deletingPathExtension.lowercased()
        if base.hasSuffix(".tar") { base = String(base.dropLast(4)) }
        var index = base.startIndex
        while index < base.endIndex {
            if "-_ ".contains(base[index]) {
                let tail = base[base.index(after: index)...]
                let startsWithVersion =
                    tail.first?.isNumber == true
                    || (tail.hasPrefix("v") && tail.dropFirst().first?.isNumber == true)
                if startsWithVersion { return String(base[..<index]) }
            }
            index = base.index(after: index)
        }
        return base
    }

    /// Lower-cased names of installed apps (the same discovery as Apps & games),
    /// cached for the query's lifetime.
    mutating func appNames() -> Set<String> {
        if let installedAppNames { return installedAppNames }
        var seen = Set<FileTree.NodeID>()
        let names = Set(collectApps(seen: &seen).map { Self.appName(tree.name(of: $0)).lowercased() })
        installedAppNames = names
        return names
    }
}

// MARK: - Caches & Trash

extension SmartListQuery {
    static let cacheMinimumBytes: Int64 = 50_000_000

    /// The Trash, app caches (≥ 50 MB), logs and Mail downloads — all regenerable.
    mutating func cachesAndTrash() -> ([SmartListEntry], [String]) {
        let groups = ["Trash", "App caches", "Logs", "Mail downloads", "System caches"]
        var entries: [SmartListEntry] = []

        if let trash = nonEmptyNode(at: home(".Trash")) {
            entries.append(
                SmartListEntry(
                    node: trash, group: "Trash", note: "Empty the Trash in Finder to reclaim this",
                    safety: .informational))
        }
        if let caches = node(at: home("Library/Caches")) {
            tree.forEachChild(of: caches) { child in
                if tree.totalAllocatedSize(of: child) >= Self.cacheMinimumBytes {
                    entries.append(SmartListEntry(node: child, group: "App caches", safety: .safeToTrash))
                }
            }
        }
        entries += containerCacheEntries()
        if let logs = nonEmptyNode(at: home("Library/Logs")) {
            entries.append(SmartListEntry(node: logs, group: "Logs", safety: .safeToTrash))
        }
        let mailDownloads = home("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")
        if let mail = nonEmptyNode(at: mailDownloads) {
            entries.append(
                SmartListEntry(
                    node: mail, group: "Mail downloads", note: "Attachments Mail has saved",
                    safety: .safeToTrash))
        }
        if let system = nonEmptyNode(at: "/Library/Caches") {
            entries.append(
                SmartListEntry(
                    node: system, group: "System caches", note: "Managed by macOS", safety: .informational))
        }
        return (entries, groups)
    }

    /// Sandboxed apps keep caches at `~/Library/Containers/<id>/Data/Library/Caches`.
    private func containerCacheEntries() -> [SmartListEntry] {
        guard let containers = node(at: home("Library/Containers")) else { return [] }
        var entries: [SmartListEntry] = []
        tree.forEachChild(of: containers) { container in
            let path = tree.pathComponentsFromRoot(of: container) + ["Data", "Library", "Caches"]
            guard let cache = tree.node(atPathComponents: path),
                tree.totalAllocatedSize(of: cache) >= Self.cacheMinimumBytes
            else { return }
            entries.append(
                SmartListEntry(
                    node: cache, group: "App caches", note: tree.name(of: container), safety: .safeToTrash))
        }
        return entries
    }

    private func nonEmptyNode(at absolutePath: String) -> FileTree.NodeID? {
        guard let node = node(at: absolutePath), tree.totalAllocatedSize(of: node) > 0 else { return nil }
        return node
    }
}
