import Foundation

/// The task-oriented lists in the sidebar — things a person is trying to do
/// (free up space, understand what's eating the disk, clean up after a project),
/// not file attributes. Order here is display order.
public enum SmartListKind: String, CaseIterable, Sendable, Codable {
    case downloads
    case cachesAndTrash
    case developerJunk
    case appsAndGames
    case bigProjects
    case videos
    case phoneBackups
    case virtualMachines
    case whatGrew

    /// Which sidebar section the list belongs to.
    public enum Section: Sendable {
        /// Actionable: things you can send to the Trash.
        case cleanUp
        /// Explanatory: what's here and how big it is.
        case whatsHere
    }

    public var section: Section {
        switch self {
        case .downloads, .cachesAndTrash, .developerJunk: return .cleanUp
        case .appsAndGames, .bigProjects, .videos, .phoneBackups, .virtualMachines, .whatGrew:
            return .whatsHere
        }
    }

    public var title: String {
        switch self {
        case .downloads: return "Downloads"
        case .cachesAndTrash: return "Caches & Trash"
        case .developerJunk: return "Developer junk"
        case .appsAndGames: return "Apps & games"
        case .bigProjects: return "Big projects"
        case .videos: return "Videos & recordings"
        case .phoneBackups: return "Phone backups"
        case .virtualMachines: return "Virtual machines"
        case .whatGrew: return "What grew"
        }
    }

    /// One plain sentence shown at the top of the list.
    public var blurb: String {
        switch self {
        case .downloads:
            return "Installers, archives and big files you downloaded and forgot about."
        case .cachesAndTrash:
            return "Space macOS and your apps rebuild on their own — safe to clear."
        case .developerJunk:
            return "Build output and tool caches that come back on the next build — safe to clear."
        case .appsAndGames:
            return "Apps and games by their real footprint, including their support data."
        case .bigProjects:
            return
                "Your largest project folders, when you last touched them, and how much inside is rebuildable."
        case .videos:
            return "Large videos, with screen and meeting recordings grouped on top."
        case .phoneBackups:
            return
                "iPhone and iPad backups kept on this Mac. Old ones can go; the next backup recreates them."
        case .virtualMachines:
            return
                "Virtual machines and container disks — often the biggest single items on a developer's Mac."
        case .whatGrew:
            return "Folders that got bigger since an earlier scan."
        }
    }

    public var systemImage: String {
        switch self {
        case .downloads: return "arrow.down.circle"
        case .cachesAndTrash: return "trash"
        case .developerJunk: return "hammer"
        case .appsAndGames: return "gamecontroller"
        case .bigProjects: return "folder.badge.gearshape"
        case .videos: return "film"
        case .phoneBackups: return "iphone"
        case .virtualMachines: return "pc"
        case .whatGrew: return "chart.line.uptrend.xyaxis"
        }
    }

    /// The list's default safety, used for its badge.
    public var safety: SmartListSafety {
        switch self {
        case .downloads, .cachesAndTrash, .developerJunk: return .safeToTrash
        case .appsAndGames, .bigProjects, .videos, .phoneBackups, .virtualMachines: return .reviewFirst
        case .whatGrew: return .informational
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
    /// A friendlier name than the folder's (a backup's device name); `nil` = the node's name.
    public let displayName: String?
    /// Ranks the row by this instead of its size (growth, for "What grew"); `nil` = size.
    public let sortBytes: Int64?

    public init(
        node: FileTree.NodeID, group: String, note: String? = nil,
        safety: SmartListSafety, extraBytes: Int64 = 0, displayName: String? = nil,
        sortBytes: Int64? = nil
    ) {
        self.node = node
        self.group = group
        self.note = note
        self.safety = safety
        self.extraBytes = extraBytes
        self.displayName = displayName
        self.sortBytes = sortBytes
    }
}

/// A computed smart list: entries ranked biggest first, groups in display order.
public struct SmartListResult: Sendable {
    public let kind: SmartListKind
    public let entries: [SmartListEntry]
    public let groups: [String]
    /// Reclaimable bytes: every row except informational ones (what Free up space can act on).
    public let totalBytes: Int64
    /// Everything the list describes, informational rows included.
    public let footprintBytes: Int64

    public init(
        kind: SmartListKind, entries: [SmartListEntry], groups: [String], totalBytes: Int64,
        footprintBytes: Int64? = nil
    ) {
        self.kind = kind
        self.entries = entries
        self.groups = groups
        self.totalBytes = totalBytes
        self.footprintBytes = footprintBytes ?? totalBytes
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// The number the sidebar and header show: what you could reclaim for Clean Up
    /// lists, what's there for What's Here lists (which may be entirely informational).
    public var displayBytes: Int64 {
        kind.section == .whatsHere ? footprintBytes : totalBytes
    }

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

/// What an iOS/iPadOS backup folder's `Info.plist` says about the device.
public struct DeviceBackupInfo: Sendable, Equatable {
    public var deviceName: String?
    public var productName: String?
    public var lastBackupDate: Date?

    public init(deviceName: String? = nil, productName: String? = nil, lastBackupDate: Date? = nil) {
        self.deviceName = deviceName
        self.productName = productName
        self.lastBackupDate = lastBackupDate
    }
}

/// Supplies metadata read from a bounded number of small property lists (an app's
/// `Info.plist`, a device backup's `Info.plist`). Injectable so the engine is
/// testable without real bundles on disk; the on-disk implementation is
/// `DiskBundleInfoProvider`, the only smart-list code allowed to touch files.
public protocol BundleInfoProvider: Sendable {
    func info(forBundleAt absolutePath: String) -> BundleInfo?
    func backupInfo(forBackupAt absolutePath: String) -> DeviceBackupInfo?
}

extension BundleInfoProvider {
    public func backupInfo(forBackupAt absolutePath: String) -> DeviceBackupInfo? { nil }
}
