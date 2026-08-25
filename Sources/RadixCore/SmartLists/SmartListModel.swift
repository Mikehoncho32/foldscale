import Foundation

/// The task-oriented lists in the sidebar — things a person is trying to do
/// (free up space, understand what's eating the disk, clean up after a project),
/// not file attributes. Order here is display order.
public enum SmartListKind: String, CaseIterable, Sendable, Codable {
    case downloads
    case cachesAndTrash
    case appsAndGames
    case bigProjects
    case videos

    /// Which sidebar section the list belongs to.
    public enum Section: Sendable {
        /// Actionable: things you can send to the Trash.
        case cleanUp
        /// Explanatory: what's here and how big it is.
        case whatsHere
    }

    public var section: Section {
        switch self {
        case .downloads, .cachesAndTrash: return .cleanUp
        case .appsAndGames, .bigProjects, .videos: return .whatsHere
        }
    }

    public var title: String {
        switch self {
        case .downloads: return "Downloads"
        case .cachesAndTrash: return "Caches & Trash"
        case .appsAndGames: return "Apps & games"
        case .bigProjects: return "Big projects"
        case .videos: return "Videos & recordings"
        }
    }

    /// One plain sentence shown at the top of the list.
    public var blurb: String {
        switch self {
        case .downloads:
            return "Installers, archives and big files you downloaded and forgot about."
        case .cachesAndTrash:
            return "Space macOS and your apps rebuild on their own — safe to clear."
        case .appsAndGames:
            return "Apps and games by their real footprint, including their support data."
        case .bigProjects:
            return
                "Your largest project folders, when you last touched them, and how much inside is rebuildable."
        case .videos:
            return "Large videos, with screen and meeting recordings grouped on top."
        }
    }

    public var systemImage: String {
        switch self {
        case .downloads: return "arrow.down.circle"
        case .cachesAndTrash: return "trash"
        case .appsAndGames: return "gamecontroller"
        case .bigProjects: return "folder.badge.gearshape"
        case .videos: return "film"
        }
    }

    /// The list's default safety, used for its badge.
    public var safety: SmartListSafety {
        switch self {
        case .downloads, .cachesAndTrash: return .safeToTrash
        case .appsAndGames, .bigProjects, .videos: return .reviewFirst
        }
    }
}

/// How careful the user should be before trashing an entry.
public enum SmartListSafety: Sendable {
    /// Regenerable or disposable — trashing it costs nothing.
    case safeToTrash
    /// Real data; look before you trash.
    case reviewFirst
    /// Shown to explain space; not something to trash from here.
    case informational

    public var label: String {
        switch self {
        case .safeToTrash: return "Safe to remove"
        case .reviewFirst: return "Review first"
        case .informational: return "Info"
        }
    }
}

/// One row of a smart list.
public struct SmartListEntry: Sendable, Equatable {
    public let node: FileTree.NodeID
    /// The group (section) the row sits under, e.g. "Installers & archives".
    public let group: String
    /// A short secondary line, e.g. "3 mo ago · already installed".
    public let note: String?
    public let safety: SmartListSafety
    /// Bytes counted with this entry but living elsewhere (an app's support data).
    public let extraBytes: Int64

    public init(
        node: FileTree.NodeID, group: String, note: String? = nil,
        safety: SmartListSafety, extraBytes: Int64 = 0
    ) {
        self.node = node
        self.group = group
        self.note = note
        self.safety = safety
        self.extraBytes = extraBytes
    }
}

/// A computed smart list: entries ranked biggest first, groups in display order.
public struct SmartListResult: Sendable {
    public let kind: SmartListKind
    public let entries: [SmartListEntry]
    public let groups: [String]
    public let totalBytes: Int64

    public init(kind: SmartListKind, entries: [SmartListEntry], groups: [String], totalBytes: Int64) {
        self.kind = kind
        self.entries = entries
        self.groups = groups
        self.totalBytes = totalBytes
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// Entries in one group, preserving rank order.
    public func entries(in group: String) -> [SmartListEntry] {
        entries.filter { $0.group == group }
    }
}

/// Where the scan sits on disk, so absolute paths like `~/Downloads` can be found
/// in a tree whose paths are relative to the scan root.
public struct SmartListContext: Sendable {
    public let rootPath: String
    public let homePath: String

    public init(rootPath: String, homePath: String) {
        self.rootPath = rootPath
        self.homePath = homePath
    }

    /// Path components of `absolutePath` relative to the scan root, or `nil` if it
    /// lies outside the scan.
    public func components(forAbsolutePath absolutePath: String) -> [String]? {
        let root = rootPath == "/" ? "" : rootPath
        if absolutePath == rootPath { return [] }
        guard absolutePath.hasPrefix(root + "/") else { return nil }
        return absolutePath.dropFirst(root.count + 1).split(separator: "/").map(String.init)
    }

    /// The live node for an absolute path, or `nil` when outside the scan or absent.
    public func node(forAbsolutePath absolutePath: String, in tree: FileTree) -> FileTree.NodeID? {
        guard let components = components(forAbsolutePath: absolutePath) else { return nil }
        return tree.node(atPathComponents: components)
    }

    /// The absolute on-disk path of a node.
    public func absolutePath(of node: FileTree.NodeID, in tree: FileTree) -> String {
        let root = rootPath == "/" ? "" : rootPath
        let relative = tree.pathComponentsFromRoot(of: node).joined(separator: "/")
        return relative.isEmpty ? rootPath : root + "/" + relative
    }

    /// `~`-relative form of an absolute path for display.
    public func displayPath(_ absolutePath: String) -> String {
        if absolutePath == homePath { return "~" }
        if absolutePath.hasPrefix(homePath + "/") {
            return "~" + absolutePath.dropFirst(homePath.count)
        }
        return absolutePath
    }
}

/// The bits of an app bundle's `Info.plist` the Apps list uses.
public struct BundleInfo: Sendable, Equatable {
    public var name: String?
    public var identifier: String?
    public var category: String?

    public init(name: String? = nil, identifier: String? = nil, category: String? = nil) {
        self.name = name
        self.identifier = identifier
        self.category = category
    }
}

/// Supplies bundle metadata for a bounded number of apps. Injectable so the engine
/// is testable without real `.app` bundles on disk.
public protocol BundleInfoProvider: Sendable {
    func info(forBundleAt absolutePath: String) -> BundleInfo?
}

/// Reads `Contents/Info.plist` from disk.
public struct DiskBundleInfoProvider: BundleInfoProvider {
    public init() {}

    public func info(forBundleAt absolutePath: String) -> BundleInfo? {
        let url = URL(fileURLWithPath: absolutePath).appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dictionary = plist as? [String: Any]
        else { return nil }
        return BundleInfo(
            name: dictionary["CFBundleName"] as? String,
            identifier: dictionary["CFBundleIdentifier"] as? String,
            category: dictionary["LSApplicationCategoryType"] as? String)
    }
}
