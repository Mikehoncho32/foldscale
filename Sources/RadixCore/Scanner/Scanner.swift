import Foundation

/// Entry points for scanning a directory tree into an in-memory model.
///
/// The scanner is metadata-only — it never opens file contents — so it is safe to
/// run over cloud-backed folders without triggering downloads (see
/// ``DirectoryWalker``). Deletion is never performed here.
public enum Scanner {
    /// Scans `url` into the default struct-of-arrays ``FileTree``.
    ///
    /// - Parameters:
    ///   - url: The directory to scan.
    ///   - options: Device policy and exclusions.
    ///   - isCancelled: Polled at each directory boundary; return `true` to abort.
    ///   - onProgress: Called periodically with a progress sample.
    @discardableResult
    public static func scan(
        at url: URL,
        options: ScanOptions = ScanOptions(),
        isCancelled: @escaping () -> Bool = { false },
        onProgress: @escaping (ScanProgress) -> Void = { _ in }
    ) throws -> FileTree {
        let walker = DirectoryWalker(
            builder: FileTreeBuilder(),
            options: options,
            isCancelled: isCancelled,
            onProgress: onProgress
        )
        try walker.run(rootPath: url.path)
        return walker.builder.finish()
    }

    /// Scans `url` into the class-per-node baseline tree. Used by the ADR-0001
    /// node-layout benchmark to compare against the struct-of-arrays layout.
    @discardableResult
    public static func scanClassTree(
        at url: URL,
        options: ScanOptions = ScanOptions()
    ) throws -> ClassFileNode? {
        let walker = DirectoryWalker(
            builder: ClassTreeBuilder(),
            options: options,
            isCancelled: { false },
            onProgress: { _ in }
        )
        try walker.run(rootPath: url.path)
        return walker.builder.finish()
    }

    /// A progressive scan: yields `.progress` samples as the tree fills in and a
    /// final `.completed` with the whole tree. Cancelling the consuming task
    /// cancels the scan (handoff §6: progressive UI, never a modal progress bar).
    public static func scanStream(
        at url: URL,
        options: ScanOptions = ScanOptions()
    ) -> AsyncThrowingStream<ScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let walker = DirectoryWalker(
                        builder: FileTreeBuilder(),
                        options: options,
                        isCancelled: { Task.isCancelled },
                        onProgress: { continuation.yield(.progress($0)) }
                    )
                    try walker.run(rootPath: url.path)
                    continuation.yield(
                        .completed(
                            walker.builder.finish(), deniedDirectories: walker.deniedDirectories))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
