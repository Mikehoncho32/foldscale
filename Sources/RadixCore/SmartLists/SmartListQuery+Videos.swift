import Foundation

// MARK: - Videos & recordings

extension SmartListQuery {
    static let videoExtensions = SmartListBytes.bytes([
        "mov", "mp4", "m4v", "mkv", "avi", "webm", "mts", "mxf", "braw", "r3d",
    ])
    static let videoMinimumBytes: Int64 = 100_000_000
    static let exportTokens: Set<String> = ["export", "final", "master", "render", "bounce"]

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
        let tokens = Self.tokens(of: lower)
        let inRecordingFolder = ancestors(of: node).contains { recordingFolders.contains($0) }
        let looksRecorded =
            lower.contains("screen recording") || lower.contains("zoom_")
            || (tokens.contains("gmt") && tokens.contains("recording"))
        if inRecordingFolder || looksRecorded { return "Recordings" }
        if tokens.contains(where: { Self.exportTokens.contains($0) }) || Self.hasVersionToken(tokens) {
            return "Exports"
        }
        return "Clips"
    }

    static func tokens(of lower: String) -> [String] {
        lower.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// "cut_v3.mov", "final v12" — a `v` + digits token that isn't the leading word
    /// (so "V8 engine demo" doesn't count).
    static func hasVersionToken(_ tokens: [String]) -> Bool {
        tokens.dropFirst().contains {
            $0.count >= 2 && $0.first == "v" && $0.dropFirst().allSatisfy(\.isNumber)
        }
    }
}
