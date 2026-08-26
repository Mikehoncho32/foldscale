import Foundation

// MARK: - Developer junk

extension SmartListQuery {
    /// A known tool cache or build product under home.
    struct JunkPath {
        let path: String
        let group: String
        let note: String
        init(_ path: String, _ group: String, _ note: String) {
            self.path = path
            self.group = group
            self.note = note
        }
    }

    /// Tool caches and build products under home that regenerate on the next build.
    static let developerJunkPaths: [JunkPath] = [
        JunkPath("Library/Developer/Xcode/DerivedData", "Xcode", "Rebuilt by Xcode on the next build"),
        JunkPath("Library/Developer/Xcode/Archives", "Xcode", "App archives; keep the ones you still ship"),
        JunkPath(
            "Library/Developer/Xcode/iOS DeviceSupport", "Xcode", "Re-downloaded when a device connects"),
        JunkPath("Library/Developer/CoreSimulator/Devices", "Xcode", "Simulators; recreated on demand"),
        JunkPath("Library/Developer/CoreSimulator/Caches", "Xcode", "Simulator caches"),
        JunkPath("Library/Caches/com.apple.dt.Xcode", "Xcode", "Xcode caches"),
        JunkPath("Library/Caches/Homebrew", "Tool caches", "Downloaded bottles; Homebrew re-fetches them"),
        JunkPath("Library/Caches/CocoaPods", "Tool caches", "Pod specs and downloads"),
        JunkPath("Library/Caches/org.swift.swiftpm", "Tool caches", "Swift package cache"),
        JunkPath("Library/Caches/pip", "Tool caches", "Python package cache"),
        JunkPath("Library/Caches/Yarn", "Tool caches", "Yarn package cache"),
        JunkPath(".npm", "Tool caches", "npm package cache"),
        JunkPath(".cache", "Tool caches", "Shared tool cache"),
        JunkPath(".cargo/registry", "Tool caches", "Rust crate cache"),
        JunkPath(".gradle/caches", "Tool caches", "Gradle cache"),
        JunkPath(".m2/repository", "Tool caches", "Maven repository cache"),
        JunkPath("go/pkg/mod", "Tool caches", "Go module cache"),
        JunkPath("Library/pnpm", "Tool caches", "pnpm store"),
        JunkPath(".docker", "Tool caches", "Docker data; prune from Docker instead"),
    ]
    static let developerJunkMinimumBytes: Int64 = 50_000_000

    /// Known tool caches plus build folders (`node_modules`, `.build`, `target`…)
    /// inside the projects Big projects found.
    mutating func developerJunk() -> ([SmartListEntry], [String]) {
        let groups = ["Build output", "Xcode", "Tool caches"]
        var entries: [SmartListEntry] = []
        var seen = Set<FileTree.NodeID>()

        for item in Self.developerJunkPaths {
            guard let node = node(at: home(item.path)), seen.insert(node).inserted,
                tree.totalAllocatedSize(of: node) >= Self.developerJunkMinimumBytes
            else { continue }
            let safety: SmartListSafety = item.path == ".docker" ? .informational : .safeToTrash
            entries.append(SmartListEntry(node: node, group: item.group, note: item.note, safety: safety))
        }

        for root in projectRoots() {
            let projectName = tree.name(of: root.node)
            tree.forEachDescendant(of: root.node) { child in
                guard tree.isDirectory(child) else { return false }
                guard SmartListBytes.equalsAny(tree.nameUTF8(of: child), Self.junkFolderNames) else {
                    return true
                }
                if seen.insert(child).inserted,
                    tree.totalAllocatedSize(of: child) >= Self.developerJunkMinimumBytes
                {
                    entries.append(
                        SmartListEntry(
                            node: child, group: "Build output",
                            note: "in \(projectName) · rebuilds on the next build",
                            safety: .safeToTrash))
                }
                return false
            }
        }
        return (entries, groups)
    }
}
