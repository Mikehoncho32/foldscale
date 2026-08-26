import XCTest

/// Architectural & safety guardrails enforced as tests (handoff §6, §10.5).
///
/// These scan the on-disk source tree as text (they do not import the app), so
/// they run under plain `swift test` with no Xcode/app dependency. `#filePath`
/// anchors them to the repo checkout at compile time.
final class GuardrailTests: XCTestCase {

    /// FoldscaleCore must remain Foundation-only — no UI frameworks may leak into the
    /// engine, so it stays unit-testable and reusable (handoff §3, §10.5).
    func testFoldscaleCoreHasNoUIImports() throws {
        let sources = try Self.swiftFiles(
            under: Self.repoRoot.appendingPathComponent("Sources/FoldscaleCore"))
        XCTAssertFalse(sources.isEmpty, "No FoldscaleCore sources found — check #filePath anchoring")

        let banned = ["import SwiftUI", "import AppKit", "import UIKit", "import Cocoa"]
        for file in sources {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in banned where Self.containsImport(text, token) {
                XCTFail(
                    "\(file.lastPathComponent) imports '\(token)'; FoldscaleCore must be Foundation-only."
                )
            }
        }
    }

    /// Safety rule (handoff §6): every deletion goes through
    /// `FileManager.trashItem`. `removeItem` must never appear in shipping sources.
    func testNoRemoveItemInSources() throws {
        let sources = try Self.swiftFiles(under: Self.repoRoot.appendingPathComponent("Sources"))
        for file in sources {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                text.contains("removeItem" + "("),
                "\(file.lastPathComponent) calls removeItem(. Use FileManager.trashItem instead (handoff §6)."
            )
        }
    }

    /// Safety rule (handoff §2.2): the scanner must be metadata-only. Reading a
    /// dataless cloud file's *contents* would materialize it (trigger a download),
    /// so content-reading APIs must never appear in the scanner.
    func testScannerNeverReadsFileContents() throws {
        let scannerDir = Self.repoRoot.appendingPathComponent("Sources/FoldscaleCore/Scanner")
        let banned = ["FileHandle", "Data(contentsOf", "String(contentsOf", "fopen(", "fread("]
        for file in try Self.swiftFiles(under: scannerDir) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in banned where text.contains(token) {
                XCTFail("\(file.lastPathComponent) uses '\(token)'; the scanner must be metadata-only.")
            }
        }
    }

    /// The smart lists reason about the scanned tree only. The single exception is
    /// `DiskBundleInfoProvider`, which reads bounded `Info.plist`s; nothing else under
    /// `SmartLists/` may touch file contents or the file system.
    func testSmartListQueriesNeverReadFiles() throws {
        let listsDir = Self.repoRoot.appendingPathComponent("Sources/FoldscaleCore/SmartLists")
        let banned = [
            "FileHandle", "Data(contentsOf", "String(contentsOf", "FileManager", "PropertyListSerialization",
            "fopen(",
        ]
        let files = try Self.swiftFiles(under: listsDir)
        XCTAssertFalse(files.isEmpty, "No SmartLists sources found — check #filePath anchoring")
        for file in files where file.lastPathComponent != "DiskBundleInfoProvider.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in banned where text.contains(token) {
                XCTFail(
                    "\(file.lastPathComponent) uses '\(token)'; only DiskBundleInfoProvider may read files.")
            }
        }
    }

    // MARK: - Helpers

    /// This file lives at <root>/Tests/FoldscaleCoreTests/GuardrailTests.swift.
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // FoldscaleCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // <root>

    static func swiftFiles(under directory: URL) throws -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil
            )
        else { return [] }
        var results: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            results.append(url)
        }
        return results
    }

    /// Matches an `import Foo` only as a real import line, ignoring incidental
    /// substrings (e.g. a comment mentioning the token).
    static func containsImport(_ text: String, _ token: String) -> Bool {
        text.split(separator: "\n").contains { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix(token)
        }
    }
}
