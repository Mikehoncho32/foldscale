import Foundation

/// Computes the task-oriented smart lists from a scanned tree. Each list is one
/// bounded traversal using the non-allocating `FileTree` helpers, plus (for apps)
/// a bounded number of `Info.plist` reads through the injected provider. The
/// per-list rules live in the `SmartListQuery` extensions (one file each).
public enum SmartListEngine {
    /// Computes every list. Runs on a background thread; the tree is a value.
    /// `isCancelled` is polled between lists so a superseded run stops early.
    public static func computeAll(
        in tree: FileTree, context: SmartListContext,
        bundleInfo: BundleInfoProvider = DiskBundleInfoProvider(), now: Date = Date(),
        isCancelled: () -> Bool = { false }
    ) -> [SmartListKind: SmartListResult] {
        var results: [SmartListKind: SmartListResult] = [:]
        for kind in SmartListKind.allCases {
            if isCancelled() { return [:] }
            results[kind] = compute(kind, in: tree, context: context, bundleInfo: bundleInfo, now: now)
        }
        return results
    }

    public static func compute(
        _ kind: SmartListKind, in tree: FileTree, context: SmartListContext,
        bundleInfo: BundleInfoProvider = DiskBundleInfoProvider(), now: Date = Date()
    ) -> SmartListResult {
        var query = SmartListQuery(tree: tree, context: context, bundleInfo: bundleInfo, now: now)
        let (entries, groups): ([SmartListEntry], [String])
        switch kind {
        case .downloads: (entries, groups) = query.downloads()
        case .cachesAndTrash: (entries, groups) = query.cachesAndTrash()
        case .developerJunk: (entries, groups) = query.developerJunk()
        case .appsAndGames: (entries, groups) = query.appsAndGames()
        case .bigProjects: (entries, groups) = query.bigProjects()
        case .videos: (entries, groups) = query.videos()
        }
        let ranked = entries.sorted { query.weight($0) > query.weight($1) }
        let total = ranked.reduce(Int64(0)) { $0 + query.weight($1) }
        let usedGroups = groups.filter { group in ranked.contains { $0.group == group } }
        return SmartListResult(kind: kind, entries: ranked, groups: usedGroups, totalBytes: total)
    }
}

/// One computation's working state: the tree, where it lives, and lazily built
/// lookups shared between lists. Each list is implemented in its own extension.
struct SmartListQuery {
    let tree: FileTree
    let context: SmartListContext
    let bundleInfo: BundleInfoProvider
    let now: Date

    /// Lower-cased names of installed apps ("slack"), built on first use.
    var installedAppNames: Set<String>?
    /// Support-data folders already attributed to an app, so two apps sharing a
    /// folder (or the same app installed twice) never count it twice.
    var claimedSupportNodes: Set<FileTree.NodeID> = []

    init(tree: FileTree, context: SmartListContext, bundleInfo: BundleInfoProvider, now: Date) {
        self.tree = tree
        self.context = context
        self.bundleInfo = bundleInfo
        self.now = now
    }

    /// An entry's ranking weight: its own size plus any attached bytes.
    func weight(_ entry: SmartListEntry) -> Int64 {
        tree.totalAllocatedSize(of: entry.node) + entry.extraBytes
    }

    // MARK: Shared helpers

    func home(_ relative: String) -> String { context.homePath + "/" + relative }

    /// The node for an absolute path inside the scan, or `nil`.
    func node(at absolutePath: String) -> FileTree.NodeID? {
        context.node(forAbsolutePath: absolutePath, in: tree)
    }

    func ancestors(of node: FileTree.NodeID) -> [FileTree.NodeID] {
        var result: [FileTree.NodeID] = []
        var current = tree.parent(of: node)
        while current != FileTree.none {
            result.append(current)
            current = tree.parent(of: current)
        }
        return result
    }

    /// Depth-limited pre-order walk (depth 1 = direct children).
    func walk(_ node: FileTree.NodeID, maxDepth: Int, depth: Int = 1, _ body: (FileTree.NodeID) -> Void) {
        tree.forEachChild(of: node) { child in
            body(child)
            if depth < maxDepth, tree.isDirectory(child) {
                walk(child, maxDepth: maxDepth, depth: depth + 1, body)
            }
        }
    }

    func ageSeconds(of node: FileTree.NodeID) -> TimeInterval {
        now.timeIntervalSince1970 - TimeInterval(tree.modificationTime(of: node))
    }

    func age(of node: FileTree.NodeID) -> String { age(epoch: tree.modificationTime(of: node)) }

    func age(epoch: Int64) -> String {
        let days = Int((now.timeIntervalSince1970 - TimeInterval(epoch)) / 86_400)
        switch days {
        case ..<1: return "today"
        case 1..<30: return "\(days) d ago"
        case 30..<365: return "\(days / 30) mo ago"
        default: return "\(days / 365) yr ago"
        }
    }

    static func format(_ bytes: Int64) -> String { DisplayFormat.bytes(bytes) }
}

// MARK: - Byte-level name matching (no String allocation per node)

/// Name tests over the tree's raw UTF-8 bytes. Every candidate is precomputed as
/// bytes once, so hot loops over millions of nodes allocate nothing.
enum SmartListBytes {
    static func bytes(_ string: String) -> [UInt8] { Array(string.utf8) }
    static func bytes(_ strings: [String]) -> [[UInt8]] { strings.map(bytes) }

    /// Case-insensitive match of the name's extension against lowercase candidates.
    static func hasExtension(_ name: ArraySlice<UInt8>, in candidates: [[UInt8]]) -> Bool {
        guard let dot = name.lastIndex(of: 46), dot > name.startIndex else { return false }  // '.'
        let ext = name[(dot + 1)...]
        guard !ext.isEmpty, ext.count <= 5 else { return false }
        return candidates.contains { candidate in
            candidate.count == ext.count && zip(candidate, ext).allSatisfy { $0 == lowercased($1) }
        }
    }

    static func hasSuffix(_ name: ArraySlice<UInt8>, _ suffix: [UInt8]) -> Bool {
        name.count >= suffix.count && name.suffix(suffix.count).elementsEqual(suffix)
    }

    static func hasAnySuffix(_ name: ArraySlice<UInt8>, _ suffixes: [[UInt8]]) -> Bool {
        suffixes.contains { hasSuffix(name, $0) }
    }

    static func equals(_ name: ArraySlice<UInt8>, _ bytes: [UInt8]) -> Bool {
        name.elementsEqual(bytes)
    }

    static func equalsAny(_ name: ArraySlice<UInt8>, _ candidates: [[UInt8]]) -> Bool {
        candidates.contains { name.elementsEqual($0) }
    }

    private static func lowercased(_ byte: UInt8) -> UInt8 { byte >= 65 && byte <= 90 ? byte + 32 : byte }

    static let appSuffix = bytes(".app")
    static let libraryBundleSuffixes = bytes([
        ".photoslibrary", ".imovielibrary", ".fcpbundle", ".logicx", ".musiclibrary", ".tvlibrary",
    ])

    static func isAppBundle(_ name: ArraySlice<UInt8>) -> Bool { hasSuffix(name, appSuffix) }
    static func isLibraryBundle(_ name: ArraySlice<UInt8>) -> Bool {
        hasAnySuffix(name, libraryBundleSuffixes)
    }
}
