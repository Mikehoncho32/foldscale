import Foundation
import Observation
import RadixCore

/// The bridge between `RadixCore` and the UI: it owns the current scan, streams
/// live progress, and exposes selection and volume stats. `@MainActor` so all
/// mutations are safe to read from SwiftUI/AppKit.
@MainActor
@Observable
final class ScanStore {
    enum Phase: Equatable {
        case idle
        case scanning
        case done
        case failed(String)
    }

    private(set) var tree: FileTree?
    private(set) var rootURL: URL?
    private(set) var phase: Phase = .idle
    private(set) var progress: ScanProgress?
    private(set) var volume: VolumeStats?

    /// Bumped each time a new tree is published, so the outline view knows to reload
    /// (a value-type `FileTree` has no identity to diff on).
    private(set) var generation = 0

    /// Node ids currently selected in the outline (kept in sync by the coordinator).
    var selection: Set<FileTree.NodeID> = []

    /// The node whose Get Info sheet is showing (set by a menu/button).
    var infoNode: FileTree.NodeID?

    /// Whether the trash-confirmation sheet is presented.
    var isConfirmingTrash = false

    private var scanTask: Task<Void, Never>?

    /// App-specific roots that must never be trashed: the app bundle and its
    /// Application Support directory (handoff §6).
    private let protectedRoots: [URL] = {
        var roots = [Bundle.main.bundleURL]
        let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        if let support {
            roots.append(support.appendingPathComponent("Radix"))
        }
        return roots
    }()

    var isScanning: Bool { phase == .scanning }

    /// Total allocated bytes across the current selection (footer figure).
    var selectedTotalBytes: Int64 {
        guard let tree else { return 0 }
        return selection.reduce(0) { $0 + tree.totalAllocatedSize(of: $1) }
    }

    /// Starts (or restarts) a scan of `url`, streaming progress into `progress` and
    /// publishing the finished tree when complete.
    func openFolder(_ url: URL) {
        scanTask?.cancel()
        rootURL = url
        tree = nil
        selection = []
        progress = nil
        phase = .scanning
        volume = VolumeStats.forVolume(containing: url)

        scanTask = Task { [weak self] in
            do {
                for try await event in Scanner.scanStream(at: url) {
                    switch event {
                    case .progress(let sample):
                        self?.progress = sample
                    case .completed(let tree):
                        self?.tree = tree
                        self?.generation += 1
                        self?.phase = .done
                        if ProcessInfo.processInfo.environment["RADIX_LOG"] != nil {
                            let root = tree.rootID
                            let line =
                                "RADIX_SCAN_DONE count=\(tree.count) "
                                + "items=\(tree.itemCount(of: root)) "
                                + "bytes=\(tree.totalAllocatedSize(of: root))\n"
                            FileHandle.standardError.write(Data(line.utf8))
                        }
                    }
                }
            } catch let error as ScanError where error == .cancelled {
                // Superseded by a newer scan; ignore.
            } catch {
                self?.phase = .failed(String(describing: error))
            }
        }
    }

    /// Re-scans the current root.
    func rescan() {
        guard let rootURL else { return }
        openFolder(rootURL)
    }

    // MARK: - Node URLs & protection

    /// The on-disk URL for a node, rebuilt from the scan root.
    func url(for node: FileTree.NodeID) -> URL? {
        guard let tree, let rootURL else { return nil }
        var url = rootURL
        for component in tree.pathComponentsFromRoot(of: node) {
            url.appendPathComponent(component)
        }
        return url
    }

    /// File URLs for a set of nodes (order unspecified).
    func urls(for nodes: some Sequence<FileTree.NodeID>) -> [URL] {
        nodes.compactMap { url(for: $0) }
    }

    /// Whether a node is protected from trashing (handoff §6).
    func isProtected(_ node: FileTree.NodeID) -> Bool {
        guard let url = url(for: node) else { return true }
        return ProtectedPaths.isProtected(url, additionalProtected: protectedRoots)
    }

    /// Whether any node in the current selection is protected.
    var selectionHasProtected: Bool { selection.contains { isProtected($0) } }

    // MARK: - Trash

    /// Moves the given nodes to the Trash (off the main actor), then re-totals the
    /// tree and refreshes free space in place — no rescan (handoff §4, rule 9).
    @discardableResult
    func trash(_ nodes: Set<FileTree.NodeID>) async -> TrashOutcome {
        guard let tree, rootURL != nil else { return TrashOutcome() }
        let requests: [(node: FileTree.NodeID, item: TrashItem)] = nodes.compactMap { node in
            guard !tree.isRemoved(node), let url = url(for: node) else { return nil }
            return (node, TrashItem(url: url, allocatedBytes: tree.totalAllocatedSize(of: node)))
        }
        let roots = protectedRoots
        let items = requests.map(\.item)
        let outcome = await Task.detached {
            TrashService.moveToTrash(
                items, isProtected: { ProtectedPaths.isProtected($0, additionalProtected: roots) })
        }.value

        let trashed = Set(outcome.trashed)
        var updated = tree
        for request in requests where trashed.contains(request.item.url) {
            updated.remove(request.node)
        }
        self.tree = updated
        generation += 1
        selection = []
        if let rootURL { volume = VolumeStats.forVolume(containing: rootURL) }
        return outcome
    }

    /// Total allocated bytes that trashing the current selection would reclaim.
    var selectionReclaimBytes: Int64 { selectedTotalBytes }
}
