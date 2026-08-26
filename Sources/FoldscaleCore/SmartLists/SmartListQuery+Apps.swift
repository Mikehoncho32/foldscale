import Foundation

// MARK: - Apps & games

extension SmartListQuery {
    static let appFolders = ["/Applications", "/Applications/Utilities"]
    static let bundleInfoLimit = 200
    static let steamCommon = SmartListBytes.bytes("common")
    static let steamApps = SmartListBytes.bytes("steamapps")
    static let gameFolderNames = SmartListBytes.bytes(["Epic Games", "GOG Games"])

    /// Apps by real footprint (bundle + support data) and games from Steam/Epic/GOG
    /// folders or the App Store games category.
    mutating func appsAndGames() -> ([SmartListEntry], [String]) {
        var seen = Set<FileTree.NodeID>()
        let apps = collectApps(seen: &seen)
        let games = collectGames(seen: &seen)
        var entries: [SmartListEntry] = []

        let ranked = apps.sorted { tree.totalAllocatedSize(of: $0) > tree.totalAllocatedSize(of: $1) }
        for (index, app) in ranked.enumerated() {
            entries.append(appEntry(app, readBundleInfo: index < Self.bundleInfoLimit, games: games))
        }
        for game in games {
            entries.append(
                SmartListEntry(
                    node: game, group: "Games", note: "updated \(age(of: game))", safety: .reviewFirst))
        }
        return (entries, ["Games", "Apps"])
    }

    /// `.app` bundles directly in the app folders, or one folder down (Adobe/…),
    /// never inside another bundle. Shared with the Downloads "already installed" tag.
    func collectApps(seen: inout Set<FileTree.NodeID>) -> [FileTree.NodeID] {
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
                SmartListBytes.equals(name, Self.steamCommon)
                && SmartListBytes.equals(tree.nameUTF8(of: tree.parent(of: node)), Self.steamApps)
            guard isSteam || SmartListBytes.equalsAny(name, Self.gameFolderNames) else { return true }
            tree.forEachChild(of: node) { game in
                if tree.isDirectory(game), seen.insert(game).inserted { games.append(game) }
            }
            return false
        }
        return games
    }

    private mutating func appEntry(
        _ app: FileTree.NodeID, readBundleInfo: Bool, games: [FileTree.NodeID]
    ) -> SmartListEntry {
        var group = "Apps"
        var extra: Int64 = 0
        var notes = ["updated \(age(of: app))"]
        if readBundleInfo, let info = bundleInfo(for: app) {
            if info.category?.lowercased().contains("games") == true { group = "Games" }
            extra = supportBytes(
                name: info.name ?? Self.appName(tree.name(of: app)), identifier: info.identifier, games: games
            )
            if extra > 0 { notes.insert("+ \(Self.format(extra)) support data", at: 0) }
        }
        return SmartListEntry(
            node: app, group: group, note: notes.joined(separator: " · "), safety: .reviewFirst,
            extraBytes: extra)
    }

    /// Support data that belongs to an app. Each folder is attributed to at most one
    /// app, and games listed on their own (e.g. Steam's `steamapps/common/*` inside
    /// Steam's support folder) are subtracted so nothing is counted twice.
    private mutating func supportBytes(name: String, identifier: String?, games: [FileTree.NodeID]) -> Int64 {
        var candidates = [home("Library/Application Support/\(name)")]
        if let identifier {
            candidates += [
                home("Library/Application Support/\(identifier)"),
                home("Library/Containers/\(identifier)"),
                home("Library/Caches/\(identifier)"),
            ]
        }
        var total: Int64 = 0
        for path in candidates {
            guard let node = node(at: path), claimedSupportNodes.insert(node).inserted else { continue }
            total += tree.totalAllocatedSize(of: node)
            for game in games where ancestors(of: game).contains(node) {
                total -= tree.totalAllocatedSize(of: game)
            }
        }
        return max(0, total)
    }

    static func appName(_ bundleName: String) -> String {
        bundleName.hasSuffix(".app") ? String(bundleName.dropLast(4)) : bundleName
    }
}
