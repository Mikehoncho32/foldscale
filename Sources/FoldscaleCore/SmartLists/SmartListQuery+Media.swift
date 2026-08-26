import Foundation

// MARK: - Media libraries

extension SmartListQuery {
    static let mediaMinimumBytes: Int64 = 100_000_000
    static let mediaPhotosGroup = "Photos & video"
    static let mediaMusicGroup = "Music & audio"
    static let mediaOtherGroup = "Other"

    /// An app-managed library at a known place. Paths starting with "/" are absolute;
    /// the rest are relative to home.
    struct MediaPath {
        let path: String
        let group: String
        let note: String
        let displayName: String?
        init(_ path: String, _ group: String, _ note: String, displayName: String? = nil) {
            self.path = path
            self.group = group
            self.note = note
            self.displayName = displayName
        }
    }

    static let mediaPaths: [MediaPath] = [
        MediaPath("Music/Music", mediaMusicGroup, "Downloaded music · manage in Music"),
        MediaPath("Music/iTunes", mediaMusicGroup, "Legacy iTunes library"),
        MediaPath(
            "/Library/Application Support/GarageBand", mediaMusicGroup,
            "Sound library · remove in GarageBand › Sound Library"),
        MediaPath(
            "/Library/Application Support/Logic", mediaMusicGroup,
            "Sound library · remove in Logic Pro › Sound Library"),
        MediaPath("/Library/Audio/Apple Loops", mediaMusicGroup, "Apple Loops · part of the sound library"),
        MediaPath("Library/Audio/Apple Loops", mediaMusicGroup, "Apple Loops · part of the sound library"),
        MediaPath("Movies/TV", mediaPhotosGroup, "Downloaded shows · remove in TV"),
        MediaPath("Pictures/Photo Booth Library", mediaPhotosGroup, "Managed by Photo Booth"),
        MediaPath(
            "Library/Group Containers/243LU875E5.groups.com.apple.podcasts", mediaOtherGroup,
            "Downloaded episodes · Podcasts › Settings", displayName: "Podcasts"),
        MediaPath(
            "Library/Containers/com.apple.BKAgentService", mediaOtherGroup,
            "Downloaded books · remove in Books", displayName: "Books"),
    ]

    /// A library bundle recognised by its suffix.
    struct MediaBundleKind {
        let suffix: [UInt8]
        let group: String
        let note: String
        init(_ suffix: String, _ group: String, _ note: String) {
            self.suffix = SmartListBytes.bytes(suffix)
            self.group = group
            self.note = note
        }
    }

    /// Library bundles found anywhere a few levels under home. `.fcpbundle` and
    /// `.logicx` are deliberately absent: they're projects, listed by Big projects.
    static let mediaBundleKinds: [MediaBundleKind] = [
        MediaBundleKind(
            ".photoslibrary", mediaPhotosGroup,
            "Managed by Photos · remove items in the app, then empty Recently Deleted"),
        MediaBundleKind(".imovielibrary", mediaPhotosGroup, "iMovie library · delete events in iMovie"),
        MediaBundleKind(".aplibrary", mediaPhotosGroup, "Aperture library"),
        MediaBundleKind(".lrlibrary", mediaPhotosGroup, "Lightroom library"),
        MediaBundleKind(".lrdata", mediaPhotosGroup, "Lightroom previews and caches · they regenerate"),
        MediaBundleKind(".lrcat", mediaPhotosGroup, "Lightroom catalog"),
        MediaBundleKind(".cocatalog", mediaPhotosGroup, "Capture One catalog"),
        MediaBundleKind(".musiclibrary", mediaMusicGroup, "Music library · manage in Music"),
    ]

    /// Photos, Music, TV, Podcasts, Books and pro-app libraries: big, app-managed, and
    /// only safely shrunk from inside the app — so every row is informational.
    mutating func mediaLibraries() -> ([SmartListEntry], [String]) {
        var listed = Set<FileTree.NodeID>()
        var entries: [SmartListEntry] = []
        for known in Self.mediaPaths {
            let absolute = known.path.hasPrefix("/") ? known.path : home(known.path)
            guard let node = node(at: absolute), isMediaBigEnough(node), listed.insert(node).inserted
            else { continue }
            entries.append(
                SmartListEntry(
                    node: node, group: known.group, note: known.note, safety: .informational,
                    displayName: known.displayName))
        }
        entries += mediaBundleEntries(listed: &listed)
        return (entries, [Self.mediaPhotosGroup, Self.mediaMusicGroup, Self.mediaOtherGroup])
    }

    /// Library bundles up to three levels under home (not Library, not dot-folders);
    /// a bundle inside something already listed is skipped, so nothing counts twice.
    private func mediaBundleEntries(listed: inout Set<FileTree.NodeID>) -> [SmartListEntry] {
        var entries: [SmartListEntry] = []
        guard let homeNode = node(at: context.homePath) else { return entries }
        tree.forEachChild(of: homeNode) { child in
            let name = tree.name(of: child)
            guard tree.isDirectory(child), name != "Library", !name.hasPrefix(".") else { return }
            walk(child, maxDepth: 3) { candidate in
                guard let kind = Self.mediaBundleKind(for: tree.nameUTF8(of: candidate)),
                    isMediaBigEnough(candidate),
                    !ancestors(of: candidate).contains(where: listed.contains),
                    listed.insert(candidate).inserted
                else { return }
                entries.append(
                    SmartListEntry(
                        node: candidate, group: kind.group, note: kind.note, safety: .informational))
            }
        }
        return entries
    }

    private func isMediaBigEnough(_ node: FileTree.NodeID) -> Bool {
        tree.totalAllocatedSize(of: node) >= Self.mediaMinimumBytes
    }

    private static func mediaBundleKind(for name: ArraySlice<UInt8>) -> MediaBundleKind? {
        mediaBundleKinds.first { SmartListBytes.hasSuffix(name, $0.suffix) }
    }
}
