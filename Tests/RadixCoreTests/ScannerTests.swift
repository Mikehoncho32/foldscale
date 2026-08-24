import Foundation
import XCTest

@testable import RadixCore

/// Filesystem-backed scanner tests. Each builds a temporary fixture tree, scans
/// it, and checks behaviour — most importantly `du`-parity, the ground-truth
/// oracle for allocated-size aggregation.
final class ScannerTests: XCTestCase {
    private var tempDirs: [URL] = []

    override func tearDown() {
        for dir in tempDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDirs.removeAll()
        super.tearDown()
    }

    // MARK: - du parity (the oracle)

    func testTotalAllocatedMatchesDu() throws {
        let root = try makeFixture()
        let tree = try Scanner.scan(at: root, options: ScanOptions(exclusions: .none))
        let duBytes = try duAllocatedBytes(root)
        XCTAssertEqual(
            tree.totalAllocatedSize(of: tree.rootID), duBytes,
            "RadixCore's aggregated allocated size must match `du` exactly"
        )
    }

    // MARK: - Hard links

    func testHardlinkCountedOnceAndFlagged() throws {
        let root = try makeTempDir()
        try writeFile(root.appendingPathComponent("original.bin"), bytes: 200_000)
        try hardlink(
            from: root.appendingPathComponent("original.bin"),
            to: root.appendingPathComponent("clone.bin")
        )
        let tree = try Scanner.scan(at: root, options: ScanOptions(exclusions: .none))

        let children = childrenByName(tree, of: tree.rootID)
        let originalFlags = tree.flags(of: children["original.bin"]!)
        let cloneFlags = tree.flags(of: children["clone.bin"]!)
        // Exactly one of the two links is marked the duplicate.
        XCTAssertTrue(
            originalFlags.contains(.hardlinkDuplicate) != cloneFlags.contains(.hardlinkDuplicate),
            "Exactly one hard link should be flagged as the duplicate"
        )
        // 200_000 bytes → 204_800 allocated (50 × 4 KiB), counted once, + root dir block.
        XCTAssertEqual(tree.totalAllocatedSize(of: tree.rootID), try duAllocatedBytes(root))
    }

    // MARK: - Symlinks

    func testSymlinkNotFollowed() throws {
        let root = try makeTempDir()
        let realDir = root.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: false)
        try writeFile(realDir.appendingPathComponent("inside.dat"), bytes: 100_000)
        try makeSymlink(at: root.appendingPathComponent("link"), to: realDir)

        let tree = try Scanner.scan(at: root, options: ScanOptions(exclusions: .none))
        let children = childrenByName(tree, of: tree.rootID)
        let linkID = try XCTUnwrap(children["link"])
        XCTAssertTrue(tree.flags(of: linkID).contains(.symlink))
        XCTAssertEqual(tree.itemCount(of: linkID), 0, "A symlink must not be traversed")
    }

    // MARK: - Allocated vs logical

    func testAllocatedIsBlockAlignedAndLogicalIsExact() throws {
        let root = try makeTempDir()
        try writeFile(root.appendingPathComponent("ten.txt"), bytes: 10)
        let tree = try Scanner.scan(at: root, options: ScanOptions(exclusions: .none))
        let file = try XCTUnwrap(childrenByName(tree, of: tree.rootID)["ten.txt"])
        XCTAssertEqual(tree.logicalSize(of: file), 10)
        XCTAssertGreaterThanOrEqual(tree.ownAllocatedSize(of: file), 10)
        XCTAssertEqual(tree.ownAllocatedSize(of: file) % 4096, 0, "APFS allocations are 4 KiB-aligned")
    }

    // MARK: - Exclusions

    func testExcludedDirectoryIsNotCounted() throws {
        let root = try makeTempDir()
        let junk = root.appendingPathComponent("junk")
        try FileManager.default.createDirectory(at: junk, withIntermediateDirectories: false)
        try writeFile(junk.appendingPathComponent("big.bin"), bytes: 500_000)
        try writeFile(root.appendingPathComponent("keep.txt"), bytes: 4096)

        let options = ScanOptions(exclusions: ScanExclusions(skippedNames: ["junk"]))
        let tree = try Scanner.scan(at: root, options: options)
        let names = Set(childrenByName(tree, of: tree.rootID).keys)
        XCTAssertFalse(names.contains("junk"), "Excluded directory must not appear")
        XCTAssertTrue(names.contains("keep.txt"))
    }

    // MARK: - Cancellation

    func testCancellationThrows() throws {
        let root = try makeFixture()
        XCTAssertThrowsError(
            try Scanner.scan(at: root, options: ScanOptions(exclusions: .none), isCancelled: { true })
        ) { error in
            XCTAssertEqual(error as? ScanError, .cancelled)
        }
    }

    // MARK: - Layout equivalence on a real tree

    func testStructOfArraysAndClassAgreeOnRealTree() throws {
        let root = try makeFixture()
        let tree = try Scanner.scan(at: root, options: ScanOptions(exclusions: .none))
        let classRoot = try XCTUnwrap(
            Scanner.scanClassTree(at: root, options: ScanOptions(exclusions: .none)))
        XCTAssertEqual(tree.totalAllocatedSize(of: tree.rootID), classRoot.totalSize)
        XCTAssertEqual(tree.itemCount(of: tree.rootID), classRoot.itemCount)
    }

    // MARK: - Root errors

    func testRootNotFound() {
        let missing = URL(fileURLWithPath: "/nope/does/not/exist/radix-\(UUID().uuidString)")
        XCTAssertThrowsError(try Scanner.scan(at: missing)) { error in
            guard case .rootNotFound = (error as? ScanError) else {
                return XCTFail("Expected rootNotFound, got \(error)")
            }
        }
    }

    func testRootNotADirectory() throws {
        let root = try makeTempDir()
        let file = root.appendingPathComponent("a-file.txt")
        try writeFile(file, bytes: 1)
        XCTAssertThrowsError(try Scanner.scan(at: file)) { error in
            guard case .rootNotADirectory = (error as? ScanError) else {
                return XCTFail("Expected rootNotADirectory, got \(error)")
            }
        }
    }

    // MARK: - Fixture helpers

    /// Builds a tree with a large file, a small file, a nested dir, a hard link,
    /// and a symlink — the standard fixture for parity and layout tests.
    private func makeFixture() throws -> URL {
        let root = try makeTempDir()
        try writeFile(root.appendingPathComponent("big.bin"), bytes: 300_000)
        try writeFile(root.appendingPathComponent("small.txt"), bytes: 10)
        let sub = root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
        try writeFile(sub.appendingPathComponent("nested.dat"), bytes: 50_000)
        try hardlink(
            from: root.appendingPathComponent("big.bin"),
            to: root.appendingPathComponent("big.hardlink")
        )
        try makeSymlink(at: root.appendingPathComponent("sub.symlink"), to: sub)
        return root
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("radix-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        return dir
    }

    private func writeFile(_ url: URL, bytes: Int) throws {
        try Data(count: bytes).write(to: url)
    }

    private func hardlink(from source: URL, to destination: URL) throws {
        guard link(source.path, destination.path) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }

    private func makeSymlink(at linkURL: URL, to target: URL) throws {
        guard symlink(target.path, linkURL.path) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }

    private func childrenByName(_ tree: FileTree, of node: FileTree.NodeID) -> [String: FileTree.NodeID] {
        Dictionary(uniqueKeysWithValues: tree.children(of: node).map { (tree.name(of: $0), $0) })
    }

    /// Ground truth: `du -k -s` (allocated KiB), converted to bytes.
    private func duAllocatedBytes(_ url: URL) throws -> Int64 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-k", "-s", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        let firstField = output.split(whereSeparator: { $0 == "\t" || $0 == " " || $0 == "\n" }).first
        let kib = Int64(firstField ?? "0") ?? 0
        return kib * 1024
    }
}
