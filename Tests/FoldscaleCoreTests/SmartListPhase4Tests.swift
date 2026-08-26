import Foundation
import XCTest

@testable import FoldscaleCore

/// Media libraries, Cloud files and App leftovers.
final class SmartListPhase4Tests: XCTestCase {
    typealias Spec = SmartListFixture.Spec
    private let gigabyte = SmartListFixture.gigabyte
    private let megabyte = SmartListFixture.megabyte

    // MARK: - Media libraries

    private func mediaTree() -> FileTree {
        SmartListFixture.build([
            .dir("Library", [.dir("Audio", [.dir("Apple Loops", [.file("loop.caf", bytes: 2 * gigabyte)])])]),
            SmartListFixture.home([
                .dir(
                    "Pictures",
                    [
                        .dir("Photos Library.photoslibrary", [.file("db", bytes: 5 * gigabyte)]),
                        .dir(
                            "Lightroom",
                            [
                                .file("Catalog.lrcat", bytes: 150 * megabyte),
                                .dir("Catalog Previews.lrdata", [.file("p", bytes: 2 * gigabyte)]),
                            ]),
                    ]),
                .dir(
                    "Movies",
                    [
                        .dir("Final.fcpbundle", [.file("render.mov", bytes: 9 * gigabyte)]),
                        .dir("TV", [.file("show.movpkg", bytes: 700 * megabyte)]),
                        .dir("Tiny.imovielibrary", [.file("x", bytes: 20 * megabyte)]),
                    ]),
                .dir(
                    "Music",
                    [
                        .dir(
                            "Music",
                            [
                                .dir("Media.localized", [.file("a.m4a", bytes: 1_200 * megabyte)]),
                                .dir("Music Library.musiclibrary", [.file("db", bytes: 300 * megabyte)]),
                            ])
                    ]),
                .dir(
                    "Library",
                    [
                        .dir(
                            "Group Containers",
                            [
                                .dir(
                                    "243LU875E5.groups.com.apple.podcasts",
                                    [.file("ep", bytes: 400 * megabyte)])
                            ])
                    ]),
            ]),
        ])
    }

    func testMediaLibrariesListsLibrariesNotProjects() {
        let tree = mediaTree()
        let result = SmartListFixture.compute(.mediaLibraries, tree)

        XCTAssertEqual(result.groups, ["Photos & video", "Music & audio", "Other"])
        XCTAssertEqual(
            SmartListFixture.names(result, in: tree, group: "Photos & video"),
            ["Photos Library.photoslibrary", "Catalog Previews.lrdata", "TV", "Catalog.lrcat"],
            "biggest first; the fcpbundle is a project, the tiny iMovie library is below the floor")
        XCTAssertEqual(
            SmartListFixture.names(result, in: tree, group: "Music & audio"), ["Apple Loops", "Music"],
            "the .musiclibrary inside ~/Music/Music is covered by its parent")
        XCTAssertEqual(
            SmartListFixture.names(result, in: tree, group: "Other"), ["243LU875E5.groups.com.apple.podcasts"]
        )
        XCTAssertEqual(result.entries(in: "Other").first?.displayName, "Podcasts")
        XCTAssertTrue(result.entries.allSatisfy { $0.safety == .informational })
        XCTAssertEqual(result.totalBytes, 0, "nothing here is reclaimable from Foldscale")
        XCTAssertEqual(result.displayBytes, result.footprintBytes)
        let expected = 5 * gigabyte + 2 * gigabyte + 700 * megabyte + 150 * megabyte
        XCTAssertEqual(result.footprintBytes, expected + 2 * gigabyte + 1_500 * megabyte + 400 * megabyte)
    }

    // MARK: - Cloud files

    private func cloudTree() -> FileTree {
        let dataless: NodeFlags = [.dataless]
        let placeholder: (String, Int64) -> Spec = { name, cloudBytes in
            .file(name, bytes: 0, logicalBytes: cloudBytes, flags: dataless)
        }
        return SmartListFixture.build([
            SmartListFixture.home([
                .dir(
                    "Library",
                    [
                        .dir(
                            "Mobile Documents",
                            [
                                .dir(
                                    "com~apple~CloudDocs",
                                    [
                                        .file("local.pdf", bytes: 400 * megabyte),
                                        .dir(
                                            "Photos",
                                            [
                                                placeholder("a.heic", 2 * gigabyte),
                                                placeholder("b.heic", 1 * gigabyte),
                                            ]),
                                        .file(".old.doc.icloud", bytes: 1_000),
                                    ]),
                                .dir("iCloud~com~apple~Keynote", [placeholder("deck.key", 200 * megabyte)]),
                                .dir("iCloud~tiny~app", [placeholder("x", 1 * megabyte)]),
                            ]),
                        .dir(
                            "Application Support", [.dir("CloudDocs", [.file("db", bytes: 300 * megabyte)])]),
                        .dir(
                            "CloudStorage",
                            [
                                .dir(
                                    "Dropbox-Personal",
                                    [
                                        .file("a", bytes: 2 * gigabyte), placeholder("b", 500 * megabyte),
                                        placeholder("c", 500 * megabyte),
                                    ]),
                                .dir("GoogleDrive-me@gmail.com", [placeholder("big", 5 * gigabyte)]),
                                .dir("ProtonDrive-me", [.file("f", bytes: 60 * megabyte)]),
                            ]),
                    ]),
                .dir("Dropbox", [.file("legacy", bytes: 100 * megabyte)]),
            ])
        ])
    }

    func testCloudFilesCountsOnlineOnlyItemsPerProvider() {
        let tree = cloudTree()
        let result = SmartListFixture.compute(.cloudFiles, tree)

        XCTAssertEqual(result.groups, ["iCloud", "Dropbox", "Google Drive", "Other cloud"])
        let byName = Dictionary(uniqueKeysWithValues: result.entries.map { (tree.name(of: $0.node), $0) })
        XCTAssertEqual(
            Set(byName.keys),
            [
                "com~apple~CloudDocs", "iCloud~com~apple~Keynote", "CloudDocs", "Dropbox-Personal",
                "GoogleDrive-me@gmail.com", "ProtonDrive-me", "Dropbox",
            ], "the 1 MB container is below both floors")
        XCTAssertEqual(byName["com~apple~CloudDocs"]?.displayName, "iCloud Drive")
        XCTAssertEqual(byName["com~apple~CloudDocs"]?.note, "3 items online-only (3 GB in the cloud)")
        XCTAssertEqual(byName["iCloud~com~apple~Keynote"]?.displayName, "Keynote (iCloud)")
        XCTAssertEqual(byName["iCloud~com~apple~Keynote"]?.note, "1 item online-only (200 MB in the cloud)")
        XCTAssertEqual(byName["CloudDocs"]?.note, "Managed by macOS")
        XCTAssertEqual(byName["Dropbox-Personal"]?.displayName, "Dropbox (Personal)")
        XCTAssertEqual(byName["Dropbox-Personal"]?.group, "Dropbox")
        XCTAssertEqual(byName["GoogleDrive-me@gmail.com"]?.displayName, "Google Drive (me@gmail.com)")
        XCTAssertEqual(byName["GoogleDrive-me@gmail.com"]?.group, "Google Drive")
        XCTAssertEqual(byName["ProtonDrive-me"]?.group, "Other cloud")
        XCTAssertEqual(byName["ProtonDrive-me"]?.note, "All files stored locally")
        XCTAssertNil(byName["Dropbox"]?.displayName)
        XCTAssertEqual(
            result.entries.first.map { tree.name(of: $0.node) }, "Dropbox-Personal",
            "ranked by local footprint")
        XCTAssertTrue(result.entries.allSatisfy { $0.safety == .informational })
        XCTAssertEqual(result.totalBytes, 0)
        let local = 2 * gigabyte + 400 * megabyte + 300 * megabyte + 100 * megabyte + 60 * megabyte
        XCTAssertEqual(result.displayBytes, local + 1_000)
    }

    // MARK: - App leftovers

    private func leftoverTree() -> FileTree {
        let app: (String, Int64) -> Spec = { name, bytes in .dir(name, [.file("bin", bytes: bytes)]) }
        let folder: (String, Int64) -> Spec = { name, bytes in .dir(name, [.file("data", bytes: bytes)]) }
        return SmartListFixture.build([
            .dir(
                "Applications",
                [
                    app("Visual Studio Code.app", 500 * megabyte), app("Microsoft Word.app", 2 * gigabyte),
                    app("iTerm.app", 100 * megabyte), app("Slack.app", 300 * megabyte),
                    app("Sublime Text.app", 80 * megabyte),
                ]),
            SmartListFixture.home([
                .dir(
                    "Library",
                    [
                        .dir(
                            "Application Support",
                            [
                                folder("Code", 200 * megabyte), folder("Microsoft", 300 * megabyte),
                                folder("iTerm2", 50 * megabyte), folder("Sublime Text 3", 80 * megabyte),
                                folder("Sketch", 1_900 * megabyte), folder("Postman", 640 * megabyte),
                                folder("Homebrew", 2 * gigabyte), folder("MobileSync", 5 * gigabyte),
                                folder("com.apple.TCC", 30 * megabyte), folder("OldApp", 5 * megabyte),
                            ]),
                        .dir(
                            "Containers",
                            [
                                folder("com.microsoft.teams2", 900 * megabyte),
                                folder("com.bohemiancoding.sketch3", 1_200 * megabyte),
                                folder("com.apple.mail", 700 * megabyte),
                                folder("com.tinyspeck.slackmacgap", 100 * megabyte),
                            ]),
                        .dir(
                            "Group Containers",
                            [
                                folder("UBF8T346G9.Office", 400 * megabyte),
                                folder("UBF8T346G9.com.microsoft.oneauth", 60 * megabyte),
                                folder("2BUA8C4S2C.com.agilebits", 300 * megabyte),
                                folder("group.com.apple.notes", 90 * megabyte),
                                folder("group.com.tinyspeck.slackmacgap", 70 * megabyte),
                                folder("6N38VWS5BX.group.ru.keepcoder.telegram", 80 * megabyte),
                            ]),
                    ])
            ]),
        ])
    }

    private let leftoverBundles: [String: BundleInfo] = [
        "/Applications/Visual Studio Code.app": BundleInfo(name: "Code", identifier: "com.microsoft.VSCode"),
        "/Applications/Microsoft Word.app": BundleInfo(
            name: "Microsoft Word", identifier: "com.microsoft.Word"),
        "/Applications/iTerm.app": BundleInfo(name: "iTerm2", identifier: "com.googlecode.iterm2"),
        "/Applications/Slack.app": BundleInfo(name: "Slack", identifier: "com.tinyspeck.slackmacgap"),
        "/Applications/Sublime Text.app": BundleInfo(name: "Sublime Text", identifier: "com.sublimetext.4"),
    ]

    func testAppLeftoversMatchesByNameIdentifierAndVendor() {
        let tree = leftoverTree()
        let result = SmartListFixture.compute(.appLeftovers, tree, bundles: leftoverBundles)

        XCTAssertEqual(result.groups, ["Support data", "Containers", "Group containers"])
        XCTAssertEqual(
            SmartListFixture.names(result, in: tree, group: "Support data"), ["Sketch", "Postman"],
            "Code/Microsoft/iTerm2/Sublime Text 3 are owned; Homebrew and MobileSync are tools; Apple's skipped"
        )
        XCTAssertEqual(
            SmartListFixture.names(result, in: tree, group: "Containers"), ["com.bohemiancoding.sketch3"],
            "Teams is covered by Microsoft's vendor prefix; Slack by its id; Mail is Apple's")
        XCTAssertEqual(
            SmartListFixture.names(result, in: tree, group: "Group containers"),
            ["2BUA8C4S2C.com.agilebits", "6N38VWS5BX.group.ru.keepcoder.telegram"],
            "a non-reverse-DNS group container is never judged; Slack's group container is owned via its id")
        XCTAssertEqual(result.entries(in: "Support data").first?.note, "Sketch isn't installed anymore")
        XCTAssertEqual(result.entries(in: "Containers").first?.note, "Sketch3 isn't installed anymore")
        XCTAssertEqual(
            result.entries(in: "Group containers").first?.note, "Agilebits isn't installed anymore")
        XCTAssertTrue(result.entries.allSatisfy { $0.safety == .reviewFirst })
        XCTAssertEqual(
            result.totalBytes,
            1_900 * megabyte + 640 * megabyte + 1_200 * megabyte + 300 * megabyte + 80 * megabyte)
        XCTAssertLessThan(
            FreeUpPlanner.priority(.appLeftovers, "Support data", .reviewFirst),
            FreeUpPlanner.priority(.bigProjects, "Code", .reviewFirst),
            "leftovers are picked before projects when 'Review first' is on")
    }

    func testLeftoverAndCloudNameHelpers() {
        XCTAssertEqual(
            SmartListQuery.strippingTeamID("UBF8T346G9.com.microsoft.office"), "com.microsoft.office")
        XCTAssertEqual(SmartListQuery.strippingTeamID("group.com.apple.notes"), "group.com.apple.notes")
        XCTAssertEqual(
            SmartListQuery.strippingGroupPrefix("group.ru.keepcoder.telegram"), "ru.keepcoder.telegram")
        XCTAssertEqual(SmartListQuery.vendor(of: "com.microsoft.teams2"), "com.microsoft")
        XCTAssertEqual(SmartListQuery.owner(ofIdentifier: "com.bohemiancoding.sketch3"), "Sketch3")
        XCTAssertEqual(
            SmartListQuery.cloudProvider(folderName: "GoogleDrive-me@x.com").provider, "Google Drive")
        XCTAssertNil(SmartListQuery.cloudProvider(folderName: "Box").account)
        XCTAssertEqual(SmartListQuery.iCloudContainerName("iCloud~com~apple~Keynote"), "Keynote (iCloud)")
    }
}
