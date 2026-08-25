import Foundation

// MARK: - Big projects

extension SmartListQuery {
    static let projectMarkerNames: Set<String> = [
        ".git", "package.json", "Package.swift", "Cargo.toml", "pyproject.toml", "go.mod",
    ]
    static let codeMarkerSuffixes = [".xcodeproj", ".xcworkspace", ".uproject"]
    static let videoMarkerSuffixes = [".fcpbundle", ".imovielibrary", ".prproj", ".drp", ".aep"]
    static let audioMarkerSuffixes = [".logicx", ".als"]
    static let projectMinimumBytes: Int64 = 250_000_000
    static let looseProjectMinimumBytes: Int64 = 1_000_000_000
    static let looseProjectParents = ["Documents", "Desktop", "Projects", "Developer", "Movies", "Music"]
    static let junkFolderNames: Set<String> = [
        "node_modules", "Pods", ".build", "build", "dist", ".next", "target", "DerivedData",
        "Render Files", "Transcoded Media", "Media Cache", "Media Cache Files", "Peak Files", "Proxy",
    ]

    /// Project roots under home (marker files, project bundles, or big loose folders
    /// in the usual places), with last-touched and rebuildable-junk figures.
    mutating func bigProjects() -> ([SmartListEntry], [String]) {
        let groups = ["Code", "Video", "Audio", "Other"]
        guard let homeNode = node(at: context.homePath) else { return ([], groups) }
        let looseParents = Set(Self.looseProjectParents.compactMap { node(at: home($0)) })
        var entries: [SmartListEntry] = []

        func visit(_ parent: FileTree.NodeID, depth: Int) {
            tree.forEachChild(of: parent) { child in
                guard tree.isDirectory(child) else { return }
                let name = tree.nameUTF8(of: child)
                // At the top of home, skip ~/Library and dot-folders (46 = ".").
                if depth == 0, SmartListBytes.equals(name, "Library") || name.first == 46 { return }
                if let group = projectKind(of: child) {
                    if let entry = projectEntry(child, group: group) { entries.append(entry) }
                } else if looseParents.contains(parent),
                    tree.totalAllocatedSize(of: child) >= Self.looseProjectMinimumBytes
                {
                    if let entry = projectEntry(child, group: "Other") { entries.append(entry) }
                } else if !SmartListBytes.isLibraryBundle(name), !SmartListBytes.isAppBundle(name) {
                    visit(child, depth: depth + 1)
                }
            }
        }
        visit(homeNode, depth: 0)
        return (entries, groups)
    }

    private func projectEntry(_ node: FileTree.NodeID, group: String) -> SmartListEntry? {
        guard tree.totalAllocatedSize(of: node) >= Self.projectMinimumBytes else { return nil }
        let (lastTouched, rebuildable) = projectStats(node)
        var note = "last touched \(age(epoch: lastTouched))"
        if rebuildable > 0 { note += " · \(Self.format(rebuildable)) rebuildable" }
        return SmartListEntry(node: node, group: group, note: note, safety: .reviewFirst)
    }

    /// The project kind if `node` is a project root (a folder holding a marker child).
    private func projectKind(of node: FileTree.NodeID) -> String? {
        var kind: String?
        tree.forEachChild(of: node) { child in
            guard kind == nil else { return }
            let name = tree.nameUTF8(of: child)
            if Self.projectMarkerNames.contains(tree.name(of: child))
                || Self.codeMarkerSuffixes.contains(where: { SmartListBytes.hasSuffix(name, $0) })
            {
                kind = "Code"
            } else if Self.videoMarkerSuffixes.contains(where: { SmartListBytes.hasSuffix(name, $0) }) {
                kind = "Video"
            } else if Self.audioMarkerSuffixes.contains(where: { SmartListBytes.hasSuffix(name, $0) }) {
                kind = "Audio"
            }
        }
        return kind
    }

    /// Latest **file** modification time excluding junk folders (folder mtimes
    /// change whenever a build adds or removes an entry, so they don't count), and
    /// the bytes of junk inside.
    private func projectStats(_ node: FileTree.NodeID) -> (lastTouched: Int64, rebuildable: Int64) {
        var latest: Int64 = 0
        var junk: Int64 = 0
        tree.forEachDescendant(of: node) { child in
            if tree.isDirectory(child) {
                if Self.junkFolderNames.contains(tree.name(of: child)) {
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
