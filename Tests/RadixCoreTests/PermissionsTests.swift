import Foundation
import XCTest

@testable import RadixCore

/// Tests for permission handling: the denied-directory count that drives the FDA
/// suggestion, and the FDA probe itself.
final class PermissionsTests: XCTestCase {
    private var tempDirs: [URL] = []

    override func tearDown() {
        for dir in tempDirs { try? FileManager.default.removeItem(at: dir) }
        tempDirs.removeAll()
        super.tearDown()
    }

    func testUnreadableDirectoryIsCountedAsDenied() throws {
        try XCTSkipIf(getuid() == 0, "Running as root bypasses permission bits")
        let root = try makeTempDir()
        let locked = root.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
        try Data(count: 128).write(to: locked.appendingPathComponent("secret.bin"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        }

        let walker = DirectoryWalker(
            builder: FileTreeBuilder(), options: ScanOptions(exclusions: .none),
            isCancelled: { false }, onProgress: { _ in })
        try walker.run(rootPath: root.path)

        XCTAssertGreaterThanOrEqual(walker.deniedDirectories, 1)
    }

    func testFullDiskAccessProbeRunsAndHasDeepLink() {
        // Must return a Bool without crashing regardless of the machine's grant state.
        _ = FullDiskAccess.isGranted()
        XCTAssertTrue(FullDiskAccess.settingsURLString.hasPrefix("x-apple.systempreferences:"))
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("radix-perms-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        return dir
    }
}
