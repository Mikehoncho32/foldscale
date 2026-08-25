import AppKit
import Foundation
import Observation
import RadixCore

/// The bridge between `RadixCore` and the UI: it owns the current scan, streams
/// live progress, keeps the tree fresh in the background, and exposes selection,
/// focus and volume stats. `@MainActor` so all mutations are safe to read from
/// SwiftUI/AppKit.
///
/// Loading model ("stale while refreshing"): the cached tree shows instantly; a
/// full refresh re-walks the root in the background and swaps the new tree in
/// underneath the user; focusing a folder quietly re-scans just that folder and
/// splices it in. Node ids are dense indices reused across trees, so the focus is
/// tracked by **path** and re-resolved before every publish.
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

    /// Bumped each time the published tree changes (new scan, swap, splice, trash…)
    /// so the outline reloads (a value-type `FileTree` has no identity to diff on).
    private(set) var generation = 0

    /// Bumped only when a **different root** is scanned. The sidebar re-keys on it
    /// (resetting expansion); background refreshes of the same root don't touch it.
    private(set) var scanSession = 0

    /// Directories the most recent scan couldn't read (permission denied).
    private(set) var deniedDirectories = 0

    /// Whether the app currently has Full Disk Access.
    private(set) var fdaGranted = FullDiskAccess.isGranted()

    /// Whether the FDA onboarding sheet is presented.
    var isShowingFDAOnboarding = false

    /// Whether the user dismissed the FDA suggestion banner for this scan.
    var fdaBannerDismissed = false

    /// Absolute paths the user excluded this session (they survive rescans).
    private(set) var sessionExclusions: Set<String> = []

    /// Node ids currently selected in the outline (kept in sync by the coordinator).
    var selection: Set<FileTree.NodeID> = []

    /// The node whose Get Info sheet is showing (set by a menu/button).
    var infoNode: FileTree.NodeID?

    /// Whether the trash-confirmation sheet is presented.
    var isConfirmingTrash = false

    // MARK: Focus (owned here so it can be re-resolved by path before a publish)

    /// Path components (from the root) of the focused folder; `[]` is the root.
    private(set) var focusPath: [String] = []

    /// The focused folder's id in the **current** tree — always valid to index.
    private(set) var focusedNode: FileTree.NodeID = FileTree.none

    // MARK: Refresh state

    /// A full background refresh of the current root is running.
    private(set) var isRefreshing = false
    private(set) var refreshProgress: ScanProgress?
    /// When each folder (by joined path) was last refreshed this session.
    private(set) var lastRefreshed: [String: Date] = [:]
    /// When the whole tree was last scanned (from the cache's timestamp on load).
    private(set) var lastFullRefresh: Date?

    /// The task-oriented sidebar lists, recomputed in the background after every
    /// tree change. Absent until the first computation finishes.
    private(set) var smartLists: [SmartListKind: SmartListResult] = [:]

    /// The `generation` the current `smartLists` were computed against. Views must
    /// not index the tree with entries from another generation (ids are reused).
    private(set) var smartListsGeneration = -1

    /// Whether `smartLists` match the tree currently on screen.
    var smartListsAreCurrent: Bool { smartListsGeneration == generation && !smartLists.isEmpty }

    private var scanTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var subtreeTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var smartListTask: Task<Void, Never>?
    private static let smartListDebounceNanos: UInt64 = 500_000_000

    private static let persistQueue = DispatchQueue(label: "io.github.mikehoncho32.radix.persist")
    private static let subtreeFreshness: TimeInterval = 60
    private static let subtreeDebounceNanos: UInt64 = 400_000_000
    private static let persistDebounceNanos: UInt64 = 3_000_000_000
    static let autoRefreshDefaultsKey = "autoRefreshOnLaunch"

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

    /// Refresh the last-scanned root in the background on launch (default on).
    var autoRefreshOnLaunch: Bool {
        get { UserDefaults.standard.object(forKey: Self.autoRefreshDefaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.autoRefreshDefaultsKey) }
    }

    // MARK: - Root identity

    /// Whether the scan root is a volume's mount point (e.g. "/" or "/Volumes/X").
    var rootIsVolumeRoot: Bool {
        guard let rootURL,
            let volume = try? rootURL.resourceValues(forKeys: [.volumeURLKey]).volume
        else { return false }
        return volume.standardizedFileURL.path == rootURL.standardizedFileURL.path
    }

    /// A human name for the scan root: the volume name ("Macintosh HD") when the
    /// root is a mount point, otherwise the folder name.
    var rootDisplayName: String {
        guard let rootURL else { return "Radix" }
        let volumeName =
            rootIsVolumeRoot ? try? rootURL.resourceValues(forKeys: [.volumeNameKey]).volumeName : nil
        if let volumeName { return volumeName }
        let name = rootURL.lastPathComponent
        return name.isEmpty ? "/" : name
    }

    /// Space in use on the volume that the scan didn't cover (the sealed System
    /// volume, VM, snapshots…). Only meaningful when scanning a volume root.
    var unscannedVolumeBytes: Int64? {
        guard rootIsVolumeRoot, let tree, let volume else { return nil }
        return max(0, volume.usedCapacity - tree.totalAllocatedSize(of: tree.rootID))
    }

    /// Total allocated bytes across the current selection (footer figure).
    var selectedTotalBytes: Int64 {
        guard let tree else { return 0 }
        return selection.reduce(0) { $0 + tree.totalAllocatedSize(of: $1) }
    }

    // MARK: - Scanning a root

    /// Starts (or restarts) a scan of `url` as a **new root**, streaming progress
    /// into `progress` and publishing the finished tree when complete.
    func openFolder(_ url: URL) {
        scanTask?.cancel()
        refreshTask?.cancel()
        subtreeTask?.cancel()
        smartListTask?.cancel()
        smartLists = [:]
        smartListsGeneration = -1
        isRefreshing = false
        rootURL = url
        tree = nil
        selection = []
        infoNode = nil
        progress = nil
        deniedDirectories = 0
        fdaBannerDismissed = false
        focusPath = []
        focusedNode = FileTree.none
        lastRefreshed = [:]
        phase = .scanning
        volume = VolumeStats.forVolume(containing: url)

        let options = ScanOptions(exclusions: currentExclusions)
        scanTask = Task { [weak self] in
            do {
                let stream = Scanner.scanStream(at: url, options: options)
                for try await event in stream {
                    switch event {
                    case .progress(let sample):
                        self?.progress = sample
                    case .completed(let tree, let denied):
                        self?.publishNewRoot(tree, denied: denied)
                    }
                }
            } catch let error as ScanError where error == .cancelled {
                // Superseded by a newer scan; ignore.
            } catch {
                self?.phase = .failed(String(describing: error))
            }
        }
    }

    private func publishNewRoot(_ tree: FileTree, denied: Int) {
        self.tree = tree
        focusPath = []
        focusedNode = tree.rootID
        deniedDirectories = denied
        phase = .done
        lastFullRefresh = Date()
        lastRefreshed = ["": Date()]
        bumpGeneration()
        scanSession += 1
        refreshFDA()
        schedulePersist()
        logIfRequested(tree)
    }

    /// Refreshes the current root: a full re-walk if a tree exists, else a scan.
    func rescan() {
        if tree != nil { refresh() } else if let rootURL { openFolder(rootURL) }
    }

    // MARK: - Background refresh (keeps the view)

    /// Re-walks the current root in the background and swaps the fresh tree in
    /// underneath the user, preserving focus (by path), selection and expansion.
    func refresh() {
        guard let rootURL, let tree, !isScanning, !isRefreshing else { return }
        subtreeTask?.cancel()
        isRefreshing = true
        refreshProgress = nil
        let options = ScanOptions(exclusions: currentExclusions, capacityHint: tree.count)
        refreshTask = Task { [weak self] in
            defer { self?.isRefreshing = false }
            do {
                let stream = Scanner.scanStream(at: rootURL, options: options)
                for try await event in stream {
                    switch event {
                    case .progress(let sample):
                        self?.refreshProgress = sample
                    case .completed(let fresh, let denied):
                        self?.swapTree(fresh, denied: denied)
                    }
                }
            } catch {
                // Cancelled or failed: keep showing the existing tree.
            }
        }
    }

    /// Publishes a freshly scanned tree for the same root. Re-resolves focus by path
    /// **before** bumping `generation`, and drops any view state whose ids may be out
    /// of range in the new tree.
    private func swapTree(_ fresh: FileTree, denied: Int) {
        focusedNode = fresh.node(atPathComponents: focusPath) ?? fresh.rootID
        if focusedNode == fresh.rootID { focusPath = [] }
        let previous = tree
        tree = fresh
        remapViewState(from: previous, to: fresh)
        deniedDirectories = denied
        lastFullRefresh = Date()
        lastRefreshed = ["": Date()]
        bumpGeneration()
        if let rootURL { volume = VolumeStats.forVolume(containing: rootURL) }
        refreshFDA()
        schedulePersist()
        logIfRequested(fresh)
    }

    /// Carries selection and the Get Info target across a tree change **by path**,
    /// so they keep pointing at the same items (ids are reused between trees;
    /// filtering by liveness alone could silently retarget them).
    private func remapViewState(from previous: FileTree?, to tree: FileTree) {
        guard let previous else {
            selection = []
            infoNode = nil
            isConfirmingTrash = false
            return
        }
        selection = Set(
            selection.compactMap { node in
                guard previous.isLive(node) else { return nil }
                return tree.node(atPathComponents: previous.pathComponentsFromRoot(of: node))
            })
        if let infoNode {
            self.infoNode =
                previous.isLive(infoNode)
                ? tree.node(atPathComponents: previous.pathComponentsFromRoot(of: infoNode)) : nil
        }
        if selection.isEmpty { isConfirmingTrash = false }
    }

    // MARK: - Focus & click-to-refresh

    /// Focuses a folder (the main pane shows its contents) and quietly refreshes it
    /// in the background if it hasn't been refreshed recently.
    func setFocus(_ node: FileTree.NodeID) {
        guard let tree else { return }
        let resolved = tree.isLive(node) ? node : tree.rootID
        focusedNode = resolved
        focusPath = tree.pathComponentsFromRoot(of: resolved)
        refreshSubtree(resolved)
    }

    /// Re-scans just `node`'s folder in the background and splices the result in.
    /// Debounced (rapid clicks start one scan), single in-flight, skipped for the
    /// root, during a full refresh, and when this folder or an ancestor is fresh.
    func refreshSubtree(_ node: FileTree.NodeID) {
        guard let tree, let rootURL, !isScanning, !isRefreshing,
            node != tree.rootID, tree.isLive(node),
            tree.flags(of: node).contains(.directory),
            let url = url(for: node)
        else { return }
        let components = tree.pathComponentsFromRoot(of: node)
        guard !isFresh(components) else { return }

        subtreeTask?.cancel()
        let options = ScanOptions(
            exclusions: currentExclusions,
            capacityHint: Int(tree.itemCount(of: node)) + 1,
            volumePolicyRoot: rootURL.path)
        subtreeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.subtreeDebounceNanos)
            guard !Task.isCancelled else { return }
            do {
                var result: FileTree?
                for try await event in Scanner.scanStream(at: url, options: options) {
                    if case .completed(let fresh, _) = event { result = fresh }
                }
                guard let result, !Task.isCancelled else { return }
                self?.splice(components, with: result)
            } catch {
                // Cancelled by a newer click, or the folder vanished: nothing to do.
            }
        }
    }

    /// Splices a fresh subtree at `components`, resolved against the **current**
    /// tree (safe even if a full refresh or a trash happened meanwhile).
    private func splice(_ components: [String], with subtree: FileTree) {
        guard var current = tree, let old = current.node(atPathComponents: components),
            old != current.rootID
        else { return }
        let new = current.replaceSubtree(at: old, with: subtree)
        guard new != old else { return }
        focusedNode = current.node(atPathComponents: focusPath) ?? current.rootID
        let previous = tree
        tree = current
        remapViewState(from: previous, to: current)
        lastRefreshed[Self.key(components)] = Date()
        bumpGeneration()
        schedulePersist()
    }

    private func isFresh(_ components: [String]) -> Bool {
        let now = Date()
        for depth in 0...components.count {
            let key = Self.key(Array(components.prefix(depth)))
            if let when = lastRefreshed[key], now.timeIntervalSince(when) < Self.subtreeFreshness {
                return true
            }
        }
        return false
    }

    /// When the folder at `node` (or its nearest refreshed ancestor) was last
    /// refreshed, falling back to the last full scan.
    func freshness(of node: FileTree.NodeID) -> Date? {
        guard let tree, tree.isLive(node) else { return lastFullRefresh }
        let components = tree.pathComponentsFromRoot(of: node)
        for depth in stride(from: components.count, through: 0, by: -1) {
            if let when = lastRefreshed[Self.key(Array(components.prefix(depth)))] { return when }
        }
        return lastFullRefresh
    }

    private static func key(_ components: [String]) -> String { components.joined(separator: "/") }

    private var currentExclusions: ScanExclusions {
        ScanExclusions(
            skippedPaths: ScanExclusions.default.skippedPaths.union(sessionExclusions),
            skippedNames: ScanExclusions.default.skippedNames)
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

    /// The live node for an on-disk URL, if it lies inside the current scan — so a
    /// Favorite like Desktop can be *jumped to* in the loaded tree instead of
    /// rescanned as a new root. `nil` when there's no tree or the URL is outside it.
    func node(for url: URL) -> FileTree.NodeID? {
        guard let tree, let rootURL else { return nil }
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == rootPath { return tree.rootID }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path.hasPrefix(prefix) else { return nil }
        let components = path.dropFirst(prefix.count).split(separator: "/").map(String.init)
        return tree.node(atPathComponents: components)
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
    /// Requests are re-resolved by path after the await, so a background refresh
    /// that completes mid-trash is never overwritten.
    @discardableResult
    func trash(_ nodes: Set<FileTree.NodeID>) async -> TrashOutcome {
        guard let tree, rootURL != nil else { return TrashOutcome() }
        let requests: [(path: [String], item: TrashItem)] = nodes.compactMap { node in
            guard tree.isLive(node), let url = url(for: node) else { return nil }
            return (
                tree.pathComponentsFromRoot(of: node),
                TrashItem(url: url, allocatedBytes: tree.totalAllocatedSize(of: node))
            )
        }
        let roots = protectedRoots
        let items = requests.map(\.item)
        let outcome = await Task.detached {
            TrashService.moveToTrash(
                items, isProtected: { ProtectedPaths.isProtected($0, additionalProtected: roots) })
        }.value

        let trashed = Set(outcome.trashed)
        guard var current = self.tree else { return outcome }
        for request in requests where trashed.contains(request.item.url) {
            if let node = current.node(atPathComponents: request.path) { current.remove(node) }
        }
        publishMutated(current)
        if let rootURL { volume = VolumeStats.forVolume(containing: rootURL) }
        return outcome
    }

    /// Total allocated bytes that trashing the current selection would reclaim.
    var selectionReclaimBytes: Int64 { selectedTotalBytes }

    /// Publishes an in-place mutation (trash/exclude) of the current tree.
    private func publishMutated(_ current: FileTree) {
        focusedNode = current.node(atPathComponents: focusPath) ?? current.rootID
        if focusedNode == current.rootID { focusPath = [] }
        tree = current
        selection = []
        infoNode = nil
        bumpGeneration()
        schedulePersist()
    }

    // MARK: - Full Disk Access

    /// Re-checks Full Disk Access (cheap; call after granting or on demand).
    func refreshFDA() { fdaGranted = FullDiskAccess.isGranted() }

    /// Whether to nudge the user toward Full Disk Access: the scan hit unreadable
    /// directories, access isn't granted, and the hint hasn't been dismissed.
    var shouldSuggestFDA: Bool { deniedDirectories > 0 && !fdaGranted && !fdaBannerDismissed }

    // MARK: - Exclusions

    /// Excludes nodes from the scan: hides them now (with re-totaling) and remembers
    /// their paths so a rescan skips them too (§4 context menu).
    func exclude(_ nodes: Set<FileTree.NodeID>) {
        guard var current = tree else { return }
        for node in nodes where current.isLive(node) {
            if let url = url(for: node) { sessionExclusions.insert(url.path) }
            current.remove(node)
        }
        publishMutated(current)
    }

    // MARK: - Generation & smart lists

    /// Publishes a tree change to the UI and queues a smart-list recomputation.
    private func bumpGeneration() {
        generation += 1
        scheduleSmartLists()
    }

    /// Recomputes every smart list off the main actor, debounced so bursts of
    /// splices/trashes run it once. Results are dropped if the tree moved on.
    private func scheduleSmartLists() {
        smartListTask?.cancel()
        guard let tree, let rootURL else {
            smartLists = [:]
            return
        }
        let expected = generation
        let context = SmartListContext(
            rootPath: rootURL.path, homePath: FileManager.default.homeDirectoryForCurrentUser.path)
        smartListTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.smartListDebounceNanos)
            guard !Task.isCancelled else { return }
            let results = await Task.detached(priority: .utility) {
                SmartListEngine.computeAll(in: tree, context: context, isCancelled: { Task.isCancelled })
            }.value
            guard !Task.isCancelled, let self, self.generation == expected, !results.isEmpty else { return }
            self.smartLists = results
            self.smartListsGeneration = expected
        }
    }

    // MARK: - Persistence

    /// Loads the last persisted scan — no rescan — so a relaunch shows prior results
    /// (handoff §5, item 10). The caller decides whether to `refresh()` afterwards.
    func loadCachedScan() {
        guard tree == nil, let snapshot = ScanCache.load() else { return }
        let root = URL(fileURLWithPath: snapshot.rootPath)
        rootURL = root
        tree = snapshot.tree
        focusPath = []
        focusedNode = snapshot.tree.rootID
        lastFullRefresh = snapshot.savedAt
        lastRefreshed = [:]
        bumpGeneration()
        scanSession += 1
        phase = .done
        volume = VolumeStats.forVolume(containing: root)
        refreshFDA()
    }

    /// Saves the tree after a short quiet period, so bursts of edits/refreshes don't
    /// each rewrite the (tens of MB) cache. All saves run on one serial queue.
    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.persistDebounceNanos)
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    private func persistNow() {
        guard let tree, let path = rootURL?.path else { return }
        Self.persistQueue.async { try? ScanCache.save(tree: tree, rootPath: path, savedAt: Date()) }
    }

    /// Writes any pending changes synchronously (call on app termination).
    func flushPersist() {
        persistTask?.cancel()
        persistNow()
        Self.persistQueue.sync {}
    }

    private func logIfRequested(_ tree: FileTree) {
        guard ProcessInfo.processInfo.environment["RADIX_LOG"] != nil else { return }
        let root = tree.rootID
        let line =
            "RADIX_SCAN_DONE count=\(tree.count) items=\(tree.itemCount(of: root)) "
            + "bytes=\(tree.totalAllocatedSize(of: root))\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
