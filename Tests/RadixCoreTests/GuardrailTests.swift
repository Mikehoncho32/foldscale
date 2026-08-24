import XCTest

/// Architectural & safety guardrails enforced as tests (handoff §6, §10.5).
///
/// These scan the on-disk source tree as text (they do not import the app), so
/// they run under plain `swift test` with no Xcode/app dependency. `#filePath`
/// anchors them to the repo checkout at compile time.
final class GuardrailTests: XCTestCase {

    /// RadixCore must remain Foundation-only — no UI frameworks may leak into the
    /// engine, so it stays unit-testable and reusable (handoff §3, §10.5).
    func testRadixCoreHasNoUIImports() throws {
        let sources = try Self.swiftFiles(under: Self.repoRoot.appendingPathComponent("Sources/RadixCore"))
        XCTAssertFalse(sources.isEmpty, "No RadixCore sources found — check #filePath anchoring")

        let banned = ["import SwiftUI", "import AppKit", "import UIKit", "import Cocoa"]
        for file in sources {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in banned where Self.containsImport(text, token) {
                XCTFail(
                    "\(file.lastPathComponent) has banned UI import via '\(token)'. RadixCore must be Foundation-only."
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

    // MARK: - Helpers

    /// This file lives at <root>/Tests/RadixCoreTests/GuardrailTests.swift.
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // RadixCoreTests
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
