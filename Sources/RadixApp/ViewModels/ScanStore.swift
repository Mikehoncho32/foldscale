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

    private var scanTask: Task<Void, Never>?

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
}
