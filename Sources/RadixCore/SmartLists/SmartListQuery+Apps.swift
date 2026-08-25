import Foundation

// MARK: - Apps & games

extension SmartListQuery {
    static let appFolders = ["/Applications", "/Applications/Utilities"]
    static let bundleInfoLimit = 200
    static let gameFolderNames: Set<String> = ["Epic Games", "GOG Games"]

    /// Apps by real footprint (bundle + support data) and games from Steam/Epic/GOG
    /// folders or the App Store games category.
    mutating func appsAndGames() -> ([SmartListEntry], [String]) {
        var seen = Set<FileTree.NodeID>()
        let apps = collectApps(seen: &seen)
        let games = collectGames(seen: &seen)
        var entries: [SmartListEntry] = []

        let ranked = apps.sorted { tree.totalAllocatedSize(of: $0) > tree.totalAllocatedSize(of: $1) }
        for (index, app) in ranked.enumerated() {
            entries.append(appEntry(app, readBundleInfo: index < Self.bundleInfoLimit))
        }
        for game in games {
            entries.append(
                SmartListEntry(
                    node: game, group: "Games", note: "updated \(age(of: game))", safety: .reviewFirst))
        }
        return (entries, ["Games", "Apps"])
    }

    /// `.app` bundles directly in the app folders, or one folder down (Adobe/…),
    /// never inside another bundle.
    private func collectApps(seen: inout Set<FileTree.NodeID>) -> [FileTree.NodeID] {
        var apps: [FileTree.NodeID] = []
        for folder in Self.appFolders + [home("Applications")] {
            guard let root = node(at: folder) else { continue }
            tree.forEachChild(of: root) { child in
                if SmartListBytes.isAppBundle(tree.nameUTF8(of: child)) {
                    if seen.insert(child).inserted { apps.append(child) }
                } else if tree.isDirectory(child) {
                    tree.forEachChild(of: child) { nested in
                        if SmartListBytes.isAppBundle(tree.nameUTF8(of: nested)), seen.insert(nested).inserted
                        {
                            apps.append(nested)
                        }
                    }
                }
            }
        }
        return apps
    }

    /// Children of any `steamapps/common`, `Epic Games` or `GOG Games` folder.
    private func collectGames(seen: inout Set<FileTree.NodeID>) -> [FileTree.NodeID] {
        var games: [FileTree.NodeID] = []
        tree.forEachDescendant(of: tree.rootID) { node in
            guard tree.isDirectory(node) else { return false }
            let name = tree.nameUTF8(of: node)
            if SmartListBytes.isAppBundle(name) || SmartListBytes.isLibraryBundle(name) { return false }
            let isSteam =
                SmartListBytes.equals(name, "common")
                && SmartListBytes.equals(tree.nameUTF8(of: tree.parent(of: node)), "steamapps")
            guard isSteam || Self.gameFolderNames.contains(tree.name(of: node)) else { return true }
            tree.forEachChild(of: node) { game in
                if tree.isDirectory(game), seen.insert(game).inserted { games.append(game) }
            }
            return false
        }
        return games
    }

    private func appEntry(_ app: FileTree.NodeID, readBundleInfo: Bool) -> SmartListEntry {
        var group = "Apps"
        var extra: Int64 = 0
        var notes = ["updated \(age(of: app))"]
        if readBundleInfo, let info = bundleInfo.info(forBundleAt: context.absolutePath(of: app, in: tree)) {
            if info.category?.lowercased().contains("games") == true { group = "Games" }
            extra = supportBytes(
                name: info.name ?? Self.appName(tree.name(of: app)), identifier: info.identifier)
            if extra > 0 { notes.insert("+ \(Self.format(extra)) support data", at: 0) }
        }
        return SmartListEntry(
            node: app, group: group, note: notes.joined(separator: " · "), safety: .reviewFirst,
            extraBytes: extra)
    }

    /// Support data that belongs to an app, deduplicated by node.
    private func supportBytes(name: String, identifier: String?) -> Int64 {
        var candidates = [home("Library/Application Support/\(name)")]
        if let identifier {
            candidates += [
                home("Library/Application Support/\(identifier)"),
                home("Library/Containers/\(identifier)"),
                home("Library/Caches/\(identifier)"),
            ]
        }
        var seen = Set<FileTree.NodeID>()
        return candidates.reduce(Int64(0)) { sum, path in
            guard let node = node(at: path), seen.insert(node).inserted else { return sum }
            return sum + tree.totalAllocatedSize(of: node)
        }
    }

    static func appName(_ bundleName: String) -> String {
        bundleName.hasSuffix(".app") ? String(bundleName.dropLast(4)) : bundleName
    }
}
