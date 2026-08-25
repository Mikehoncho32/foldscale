import Foundation

// MARK: - Videos & recordings

extension SmartListQuery {
    static let videoExtensions = SmartListBytes.set([
        "mov", "mp4", "m4v", "mkv", "avi", "webm", "mts", "mxf", "braw", "r3d",
    ])
    static let videoMinimumBytes: Int64 = 100_000_000
    static let recordingTokens = ["screen recording", "simulator screen recording", "zoom_"]
    static let exportTokens = ["export", "final", "master", "render", "bounce"]

    /// Videos ≥ 100 MB anywhere (libraries and app bundles pruned), grouped into
    /// recordings, exports and clips.
    mutating func videos() -> ([SmartListEntry], [String]) {
        let recordingFolders = Set(
            ["Documents/Zoom", "Movies/OBS", "Movies/Loom"].compactMap { node(at: home($0)) })
        var entries: [SmartListEntry] = []
        tree.forEachDescendant(of: tree.rootID) { node in
            let name = tree.nameUTF8(of: node)
            if tree.isDirectory(node) {
                return !(SmartListBytes.isAppBundle(name) || SmartListBytes.isLibraryBundle(name))
            }
            guard tree.totalAllocatedSize(of: node) >= Self.videoMinimumBytes,
                SmartListBytes.hasExtension(name, in: Self.videoExtensions)
            else { return false }
            let group = videoGroup(of: node, recordingFolders: recordingFolders)
            entries.append(
                SmartListEntry(node: node, group: group, note: age(of: node), safety: .reviewFirst))
            return false
        }
        return (entries, ["Recordings", "Exports", "Clips"])
    }

    private func videoGroup(of node: FileTree.NodeID, recordingFolders: Set<FileTree.NodeID>) -> String {
        let lower = tree.name(of: node).lowercased()
        let inRecordingFolder = ancestors(of: node).contains { recordingFolders.contains($0) }
        let looksRecorded =
            Self.recordingTokens.contains { lower.contains($0) }
            || (lower.contains("gmt") && lower.contains("recording"))
        if inRecordingFolder || looksRecorded { return "Recordings" }
        if Self.exportTokens.contains(where: { lower.contains($0) }) || Self.hasVersionToken(lower) {
            return "Exports"
        }
        return "Clips"
    }

    /// "cut_v3.mov", "final v12" — a `v` followed by digits as its own token.
    static func hasVersionToken(_ lower: String) -> Bool {
        let tokens = lower.split { !$0.isLetter && !$0.isNumber }
        return tokens.contains { $0.count >= 2 && $0.first == "v" && $0.dropFirst().allSatisfy(\.isNumber) }
    }
}
