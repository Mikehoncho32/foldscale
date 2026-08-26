import Foundation

// MARK: - App leftovers

/// What's installed, in the forms support folders are named after.
struct InstalledIdentity {
    /// Lower-cased app names ("google chrome", "code") and file names sans `.app`.
    var names: Set<String> = []
    /// First words of those names ("google", "microsoft", "adobe").
    var firstWords: Set<String> = []
    /// Lower-cased bundle ids.
    var identifiers: Set<String> = []
    /// The first two reverse-DNS components of every id ("com.microsoft").
    var vendors: Set<String> = []

    mutating func add(name: String) {
        let lower = name.lowercased()
        guard !lower.isEmpty else { return }
        names.insert(lower)
        if let first = SmartListQuery.firstWord(of: lower), first.count >= 3 { firstWords.insert(first) }
    }

    mutating func add(identifier: String) {
        let lower = identifier.lowercased()
        identifiers.insert(lower)
        vendors.insert(SmartListQuery.vendor(of: lower))
    }
}

extension SmartListQuery {
    static let leftoverMinimumBytes: Int64 = 20_000_000
    static let leftoverSupportGroup = "Support data"
    static let leftoverContainersGroup = "Containers"
    static let leftoverGroupContainersGroup = "Group containers"

    /// Application Support folders that belong to tools which never live in
    /// /Applications, or to macOS itself under a plain name.
    static let leftoverDenyList: Set<String> = [
        "code", "crashreporter", "clouddocs", "mobilesync", "addressbook", "icloud", "knowledge",
        "syncservices", "dock", "fileprovider", "homebrew", "npm", "pip", "pnpm", "jetbrains", "mozilla",
        "steam", "app store", "callhistorydb", "callhistorytransactions", "knowledge-agent",
        "sharedfilelist", "audio", "bluetooth", "typography", "photos", "musiclibrary", "notes",
    ]

    /// Support data whose app is gone: `~/Library/Application Support/<Name>`,
    /// `~/Library/Containers/<bundle id>` and `~/Library/Group Containers/<team>.<id>`
    /// that no installed app claims. Caches and logs are left to Caches & Trash.
    mutating func appLeftovers() -> ([SmartListEntry], [String]) {
        let identity = installedIdentity()
        var entries: [SmartListEntry] = []
        entries += supportLeftovers(identity)
        entries += containerLeftovers(identity)
        return (
            entries,
            [Self.leftoverSupportGroup, Self.leftoverContainersGroup, Self.leftoverGroupContainersGroup]
        )
    }

    private func supportLeftovers(_ identity: InstalledIdentity) -> [SmartListEntry] {
        var entries: [SmartListEntry] = []
        guard let support = node(at: home("Library/Application Support")) else { return entries }
        let junk = Set(Self.developerJunkPaths.compactMap { node(at: home($0.path)) })
        tree.forEachChild(of: support) { folder in
            let name = tree.name(of: folder)
            guard tree.isDirectory(folder), isLeftoverBigEnough(folder), !junk.contains(folder),
                !Self.isOwnedSupportFolder(name, identity)
            else { return }
            entries.append(
                SmartListEntry(
                    node: folder, group: Self.leftoverSupportGroup, note: "\(name) isn't installed anymore",
                    safety: .reviewFirst))
        }
        return entries
    }

    private func containerLeftovers(_ identity: InstalledIdentity) -> [SmartListEntry] {
        var entries: [SmartListEntry] = []
        if let containers = node(at: home("Library/Containers")) {
            tree.forEachChild(of: containers) { container in
                let identifier = tree.name(of: container)
                guard tree.isDirectory(container), isLeftoverBigEnough(container),
                    !Self.isOwnedIdentifier(identifier, identity)
                else { return }
                entries.append(leftover(container, identifier, group: Self.leftoverContainersGroup))
            }
        }
        if let groups = node(at: home("Library/Group Containers")) {
            tree.forEachChild(of: groups) { container in
                let identifier = Self.strippingTeamID(tree.name(of: container))
                // Only reverse-DNS names can be judged; "UBF8T346G9.Office" stays.
                guard tree.isDirectory(container), isLeftoverBigEnough(container), identifier.contains("."),
                    !Self.isOwnedIdentifier(identifier, identity)
                else { return }
                entries.append(leftover(container, identifier, group: Self.leftoverGroupContainersGroup))
            }
        }
        return entries
    }

    private func leftover(_ node: FileTree.NodeID, _ identifier: String, group: String) -> SmartListEntry {
        SmartListEntry(
            node: node, group: group, note: "\(Self.owner(ofIdentifier: identifier)) isn't installed anymore",
            safety: .reviewFirst)
    }

    /// Names, ids and vendors of every installed app, read once per computation.
    mutating func installedIdentity() -> InstalledIdentity {
        if let cached = installedIdentityCache { return cached }
        var identity = InstalledIdentity()
        var seen = Set<FileTree.NodeID>()
        for app in collectApps(seen: &seen) {
            identity.add(name: Self.appName(tree.name(of: app)))
            if let info = bundleInfo(for: app) {
                if let name = info.name { identity.add(name: name) }
                if let identifier = info.identifier { identity.add(identifier: identifier) }
            }
        }
        installedIdentityCache = identity
        return identity
    }

    private func isLeftoverBigEnough(_ node: FileTree.NodeID) -> Bool {
        tree.totalAllocatedSize(of: node) >= Self.leftoverMinimumBytes
    }

    /// An `Application Support/<Name>` folder is owned when an installed app's name,
    /// bundle id, vendor or brand (first word) matches — or when it's Apple's or a
    /// known non-app tool's. Only a folder nothing claims is a leftover.
    static func isOwnedSupportFolder(_ folderName: String, _ identity: InstalledIdentity) -> Bool {
        let folder = folderName.lowercased()
        if folder.hasPrefix("com.apple") || folder.hasPrefix("apple") || leftoverDenyList.contains(folder) {
            return true
        }
        if identity.names.contains(folder) || identity.identifiers.contains(folder) { return true }
        if let first = firstWord(of: folder), identity.firstWords.contains(first) { return true }
        if identity.names.contains(where: { $0.count >= 3 && (folder.hasPrefix($0) || $0.hasPrefix(folder)) })
        {
            return true
        }
        return identity.identifiers.contains { id in
            id.split(separator: ".").last.map(String.init) == folder || vendor(of: id) == folder
        }
    }

    /// A container is owned when its id, or its vendor, belongs to an installed app.
    /// App-group ids (`group.ru.keepcoder.Telegram`) are judged without the prefix.
    static func isOwnedIdentifier(_ identifier: String, _ identity: InstalledIdentity) -> Bool {
        let id = strippingGroupPrefix(identifier.lowercased())
        if id.hasPrefix("com.apple.") { return true }
        return identity.identifiers.contains(id) || identity.vendors.contains(vendor(of: id))
    }

    static func strippingGroupPrefix(_ identifier: String) -> String {
        identifier.hasPrefix("group.") ? String(identifier.dropFirst("group.".count)) : identifier
    }

    /// `UBF8T346G9.com.microsoft.office` → `com.microsoft.office`.
    static func strippingTeamID(_ name: String) -> String {
        guard let dot = name.firstIndex(of: "."), name.distance(from: name.startIndex, to: dot) == 10,
            name[..<dot].allSatisfy({ $0.isUppercase || $0.isNumber })
        else { return name }
        return String(name[name.index(after: dot)...])
    }

    /// `com.bohemiancoding.sketch3` → "Sketch3", for the note.
    static func owner(ofIdentifier identifier: String) -> String {
        let last = identifier.split(separator: ".").last.map(String.init) ?? identifier
        return last.prefix(1).uppercased() + last.dropFirst()
    }

    static func vendor(of identifier: String) -> String {
        let parts = identifier.lowercased().split(separator: ".")
        return parts.count >= 2 ? parts[0] + "." + parts[1] : identifier.lowercased()
    }

    static func firstWord(of name: String) -> String? {
        name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" }).first.map(String.init)
    }
}
