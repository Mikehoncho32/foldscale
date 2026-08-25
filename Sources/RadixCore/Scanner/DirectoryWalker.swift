import Foundation

/// Walks a directory tree with `opendir`/`readdir`/`fstatat`, driving a
/// ``TreeBuilder``. Metadata-only: it reads `stat` (which yields size, inode and
/// the `SF_DATALESS` flag) but **never opens file contents**, so scanning a
/// cloud-backed folder cannot trigger a download. Single-threaded depth-first;
/// directory handles are closed before descending to bound open file descriptors.
final class DirectoryWalker<Builder: TreeBuilder> {
    var builder: Builder

    private let options: ScanOptions
    private let isCancelled: () -> Bool
    private let onProgress: (ScanProgress) -> Void

    private var seen: Set<InodeKey> = []
    /// Devices a descent may enter (see `VolumePolicy`).
    private var allowedDevices: Set<Int64> = []
    private var nodesScanned = 0
    private var bytesScanned: Int64 = 0
    /// Directories skipped because they couldn't be opened (permission denied) —
    /// the signal that Full Disk Access would give more complete results (§5.7).
    private(set) var deniedDirectories = 0

    private static var progressInterval: Int { 5000 }
    private static var dot: CChar { 46 }  // ASCII '.'

    init(
        builder: Builder,
        options: ScanOptions,
        isCancelled: @escaping () -> Bool,
        onProgress: @escaping (ScanProgress) -> Void
    ) {
        self.builder = builder
        self.options = options
        self.isCancelled = isCancelled
        self.onProgress = onProgress
    }

    /// Scans the tree rooted at `rootPath` into `builder`.
    func run(rootPath: String) throws {
        var rootStat = stat()
        guard lstat(rootPath, &rootStat) == 0 else {
            throw ScanError.rootNotFound(rootPath)
        }
        guard nodeKind(mode: rootStat.st_mode) == .directory else {
            throw ScanError.rootNotADirectory(rootPath)
        }
        allowedDevices = VolumePolicy.allowedDevices(forRoot: rootPath, rootStat: rootStat)
        seen.insert(InodeKey(device: Int64(rootStat.st_dev), inode: UInt64(rootStat.st_ino)))

        // Fast readdir-only pre-count so the builder can pre-size its storage and
        // avoid ~2× geometric-growth overhead (ADR-0001). Also warms the cache.
        builder.reserveCapacity(countNodes(atPath: rootPath) + 1)

        let meta = NodeMeta.from(stat: rootStat, kind: .directory)
        builder.enterDirectory(name: (rootPath as NSString).lastPathComponent, meta: meta)
        count(bytes: meta.allocatedSize, path: rootPath)
        try scanChildren(atPath: rootPath)
        builder.leaveDirectory()
    }

    private struct PendingSubdir {
        let name: [UInt8]
        let path: String
        let meta: NodeMeta
    }

    private func scanChildren(atPath path: String) throws {
        guard let dirp = opendir(path) else {
            if errno == EACCES || errno == EPERM { deniedDirectories += 1 }
            return
        }
        let dirFD = dirfd(dirp)
        var pending: [PendingSubdir] = []
        while let entryPtr = readdir(dirp) {
            if isCancelled() {
                closedir(dirp)
                throw ScanError.cancelled
            }
            classify(entryPtr, dirFD: dirFD, path: path, pending: &pending)
        }
        closedir(dirp)
        try descend(into: pending)
    }

    /// Classifies one directory entry (metadata-only `stat`): add a leaf, or queue
    /// a subdirectory for later descent.
    private func classify(
        _ entryPtr: UnsafeMutablePointer<dirent>,
        dirFD: Int32,
        path: String,
        pending: inout [PendingSubdir]
    ) {
        let nameLen = Int(entryPtr.pointee.d_namlen)
        if nameLen == 0 { return }
        var dname = entryPtr.pointee.d_name
        if dname.0 == Self.dot, nameLen == 1 || (nameLen == 2 && dname.1 == Self.dot) { return }

        var childStat = stat()
        let statOK = withUnsafeBytes(of: &dname) { raw in
            fstatat(
                dirFD, raw.baseAddress!.assumingMemoryBound(to: CChar.self),
                &childStat, AT_SYMLINK_NOFOLLOW
            ) == 0
        }
        guard statOK else {
            addLeaf(
                nameBytes: &dname, length: nameLen, meta: NodeMeta.from(stat: childStat, kind: .unreadable))
            count(bytes: 0, path: path)
            return
        }

        let kind = nodeKind(mode: childStat.st_mode)
        if kind == .directory {
            if options.stayOnStartVolume, !allowedDevices.contains(Int64(childStat.st_dev)) { return }
            let nameBytes = copyName(&dname, length: nameLen)
            let childPath = joinPath(path, String(decoding: nameBytes, as: UTF8.self))
            if options.exclusions.shouldSkipDirectory(path: childPath) { return }
            let key = InodeKey(device: Int64(childStat.st_dev), inode: UInt64(childStat.st_ino))
            guard seen.insert(key).inserted else { return }  // firmlink / cycle guard
            pending.append(
                PendingSubdir(
                    name: nameBytes, path: childPath,
                    meta: NodeMeta.from(stat: childStat, kind: .directory)))
            return
        }

        var meta = NodeMeta.from(stat: childStat, kind: kind)
        if kind == .file, childStat.st_nlink > 1 {
            let key = InodeKey(device: Int64(childStat.st_dev), inode: UInt64(childStat.st_ino))
            if !seen.insert(key).inserted { meta.flags.insert(.hardlinkDuplicate) }
        }
        addLeaf(nameBytes: &dname, length: nameLen, meta: meta)
        count(bytes: meta.flags.contains(.hardlinkDuplicate) ? 0 : meta.allocatedSize, path: path)
    }

    private func descend(into subdirs: [PendingSubdir]) throws {
        for subdir in subdirs {
            if isCancelled() { throw ScanError.cancelled }
            subdir.name.withUnsafeBufferPointer { builder.enterDirectory(name: $0, meta: subdir.meta) }
            count(bytes: subdir.meta.allocatedSize, path: subdir.path)
            try scanChildren(atPath: subdir.path)
            builder.leaveDirectory()
        }
    }

    /// Counts entries with `readdir` only (no `stat`) to size the builder. Uses
    /// `d_type` to recurse and honours directory exclusions; the device filter is
    /// skipped here, so this is an upper-bound hint, which is what we want.
    private func countNodes(atPath path: String) -> Int {
        guard let dirp = opendir(path) else { return 0 }
        var total = 0
        var subdirs: [String] = []
        while let entryPtr = readdir(dirp) {
            let nameLen = Int(entryPtr.pointee.d_namlen)
            if nameLen == 0 { continue }
            var dname = entryPtr.pointee.d_name
            if dname.0 == Self.dot, nameLen == 1 || (nameLen == 2 && dname.1 == Self.dot) {
                continue
            }
            total += 1
            if entryPtr.pointee.d_type == DT_DIR {
                let childPath = joinPath(
                    path, String(decoding: copyName(&dname, length: nameLen), as: UTF8.self))
                if !options.exclusions.shouldSkipDirectory(path: childPath) {
                    subdirs.append(childPath)
                }
            }
        }
        closedir(dirp)
        for subdir in subdirs { total += countNodes(atPath: subdir) }
        return total
    }

    // MARK: - Helpers

    private func addLeaf<Tuple>(nameBytes: inout Tuple, length: Int, meta: NodeMeta) {
        withUnsafeBytes(of: &nameBytes) { raw in
            let buffer = UnsafeBufferPointer(
                start: raw.baseAddress!.assumingMemoryBound(to: UInt8.self),
                count: length
            )
            builder.addLeaf(name: buffer, meta: meta)
        }
    }

    private func copyName<Tuple>(_ nameBytes: inout Tuple, length: Int) -> [UInt8] {
        withUnsafeBytes(of: &nameBytes) { raw in
            Array(
                UnsafeBufferPointer(
                    start: raw.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    count: length
                )
            )
        }
    }

    private func nodeKind(mode: mode_t) -> NodeKind {
        switch mode & S_IFMT {
        case S_IFDIR: return .directory
        case S_IFLNK: return .symlink
        default: return .file
        }
    }

    private func joinPath(_ directory: String, _ name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }

    private func count(bytes: Int64, path: String) {
        nodesScanned += 1
        bytesScanned += bytes
        if nodesScanned % Self.progressInterval == 0 {
            onProgress(
                ScanProgress(nodesScanned: nodesScanned, bytesScanned: bytesScanned, currentPath: path)
            )
        }
    }
}
