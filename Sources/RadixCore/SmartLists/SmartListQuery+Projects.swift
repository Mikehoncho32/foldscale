import Foundation

// MARK: - Big projects

extension SmartListQuery {
    /// A folder holding one of these is a code project.
    static let codeMarkerNames = SmartListBytes.bytes([
        ".git", "package.json", "Package.swift", "Cargo.toml", "pyproject.toml", "go.mod",
    ])
    static let codeMarkerSuffixes = SmartListBytes.bytes([".xcodeproj", ".xcworkspace", ".uproject"])
    /// Small document files whose containing folder is the project.
    static let videoMarkerSuffixes = SmartListBytes.bytes([".prproj", ".drp", ".aep"])
    static let audioMarkerSuffixes = SmartListBytes.bytes([".als"])
    /// Directory bundles that hold the project's media — the bundle *is* the project.
    static let videoBundleSuffixes = SmartListBytes.bytes([".fcpbundle", ".imovielibrary"])
    static let audioBundleSuffixes = SmartListBytes.bytes([".logicx"])
    static let libraryName = SmartListBytes.bytes("Library")
    /// Standard home folders: never promoted to a project themselves (an iMovie
    /// library in ~/Movies must not swallow ~/Movies), always descended.
    static let homeReservedNames = SmartListBytes.bytes([
        "Documents", "Desktop", "Downloads", "Movies", "Music", "Pictures", "Public", "Applications",
    ])
    static let projectMinimumBytes: Int64 = 250_000_000
    static let looseProjectMinimumBytes: Int64 = 1_000_000_000
    static let looseProjectParents = ["Documents", "Desktop", "Projects", "Developer", "Movies", "Music"]

    /// Project roots under home, with last-touched and rebuildable-junk figures:
    /// project bundles (Final Cut, iMovie, Logic) are listed as themselves; folders
    /// holding a marker file are projects — except the top-level home folders
    /// (~/Movies, ~/Documents…), which are never promoted, so an iMovie library
    /// sitting in ~/Movies doesn't swallow the whole folder; and big loose folders
    /// in the usual places count when they hold no project bundles of their own.
    mutating func bigProjects() -> ([SmartListEntry], [String]) {
        let groups = ["Code", "Video", "Audio", "Other"]
        let entries = projectRoots().compactMap { projectEntry($0.node, group: $0.group) }
        return (entries, groups)
    }

    /// Every project root under home with its kind. Shared by Big projects and
    /// Developer junk (which looks for build folders inside these roots).
    func projectRoots() -> [(node: FileTree.NodeID, group: String)] {
        guard let homeNode = node(at: context.homePath) else { return [] }
        let looseParents = Set(Self.looseProjectParents.compactMap { node(at: home($0)) })
        var roots: [(node: FileTree.NodeID, group: String)] = []

        func visit(_ parent: FileTree.NodeID, depth: Int) {
            tree.forEachChild(of: parent) { child in
                guard tree.isDirectory(child) else { return }
                let name = tree.nameUTF8(of: child)
                if depth == 0 {
                    // At the top of home: skip ~/Library and dot-folders (46 = "."); the
                    // standard folders are containers, never projects themselves.
                    if SmartListBytes.equals(name, Self.libraryName) || name.first == 46 { return }
                    if SmartListBytes.equalsAny(name, Self.homeReservedNames) {
                        visit(child, depth: depth + 1)
                        return
                    }
                }
                if let group = Self.bundleProjectKind(name) {
                    roots.append((child, group))
                } else if SmartListBytes.isAppBundle(name) || SmartListBytes.isLibraryBundle(name)
                    || SmartListBytes.equalsAny(name, Self.codeJunkFolderNames)
                {
                    return  // bundles and dependency/build folders never hold "projects" of yours
                } else if let group = markerProjectKind(of: child) {
                    roots.append((child, group))
                } else if looseParents.contains(parent), !containsProjectBundle(child),
                    tree.totalAllocatedSize(of: child) >= Self.looseProjectMinimumBytes
                {
                    roots.append((child, "Other"))
                } else {
                    visit(child, depth: depth + 1)
                }
            }
        }
        visit(homeNode, depth: 0)
        return roots
    }

    private func projectEntry(_ node: FileTree.NodeID, group: String) -> SmartListEntry? {
        guard tree.totalAllocatedSize(of: node) >= Self.projectMinimumBytes else { return nil }
        let (lastTouched, rebuildable) = projectStats(node, junkNames: Self.junkFolderNames(for: group))
        var note = "last touched \(age(epoch: lastTouched))"
        if rebuildable > 0 { note += " · \(Self.format(rebuildable)) rebuildable" }
        return SmartListEntry(node: node, group: group, note: note, safety: .reviewFirst)
    }

    private static func bundleProjectKind(_ name: ArraySlice<UInt8>) -> String? {
        if SmartListBytes.hasAnySuffix(name, videoBundleSuffixes) { return "Video" }
        if SmartListBytes.hasAnySuffix(name, audioBundleSuffixes) { return "Audio" }
        return nil
    }

    /// The project kind if `node` holds a marker child (byte compares only).
    private func markerProjectKind(of node: FileTree.NodeID) -> String? {
        var kind: String?
        tree.forEachChild(of: node) { child in
            guard kind == nil else { return }
            let name = tree.nameUTF8(of: child)
            guard name.count <= 24 else { return }
            if SmartListBytes.equalsAny(name, Self.codeMarkerNames)
                || SmartListBytes.hasAnySuffix(name, Self.codeMarkerSuffixes)
            {
                kind = "Code"
            } else if SmartListBytes.hasAnySuffix(name, Self.videoMarkerSuffixes) {
                kind = "Video"
            } else if SmartListBytes.hasAnySuffix(name, Self.audioMarkerSuffixes) {
                kind = "Audio"
            }
        }
        return kind
    }

    private func containsProjectBundle(_ node: FileTree.NodeID) -> Bool {
        var found = false
        tree.forEachChild(of: node) { child in
            if !found, tree.isDirectory(child), Self.bundleProjectKind(tree.nameUTF8(of: child)) != nil {
                found = true
            }
        }
        return found
    }

    /// Latest **file** modification time excluding junk folders (folder mtimes
    /// change whenever a build adds or removes an entry, so they don't count), and
    /// the bytes of junk inside.
    private func projectStats(
        _ node: FileTree.NodeID, junkNames: [[UInt8]]
    ) -> (lastTouched: Int64, rebuildable: Int64) {
        var latest: Int64 = 0
        var junk: Int64 = 0
        tree.forEachDescendant(of: node) { child in
            if tree.isDirectory(child) {
                if SmartListBytes.equalsAny(tree.nameUTF8(of: child), junkNames) {
                    junk += tree.totalAllocatedSize(of: child)
                    return false
                }
                return true
            }
            latest = max(latest, tree.modificationTime(of: child))
            return false
        }
        return (latest == 0 ? tree.modificationTime(of: node) : latest, junk)
    }
}
