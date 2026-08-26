import FoldscaleCore
import Foundation

private let kb: Int64 = 1_000
private let mb: Int64 = 1_000_000
private let gb: Int64 = 1_000_000_000

/// A hand-written, realistic Mac for screenshots and demos (`FOLDSCALE_DEMO=1`), so
/// marketing images never show anyone's real files. It's what a working
/// developer's 256 GB laptop tends to look like; dates are relative to now so the
/// smart lists ("forgotten", "last touched") read naturally.
enum DemoTree {
    /// Builds the demo drive with the user's home folder at `homePath`, so the
    /// sidebar Favorites resolve into it.
    static func make(homePath: String) -> FileTree {
        var gen = Generator(now: Int64(Date().timeIntervalSince1970))
        let homeComponents = Array(URL(fileURLWithPath: homePath).pathComponents.dropFirst())
        gen.dir("/", days: 1) { gen in
            applications(&gen)
            gen.dir("Library", days: 3) { gen in
                gen.blob("Developer", 3_200 * mb, files: 4_000, days: 40)
                gen.blob("Application Support", 2_100 * mb, files: 3_500, days: 2)
                gen.blob("Caches", 1_400 * mb, files: 900, days: 1)
                gen.blob("Apple", 1_100 * mb, files: 1_200, days: 60)
                gen.blob("Audio", 600 * mb, files: 300, days: 200)
                gen.blob("Fonts", 120 * mb, files: 400, days: 300)
            }
            gen.dir("System", days: 20) { gen in gen.blob("Library", 8_200 * mb, files: 25_000, days: 20) }
            gen.dir("private", days: 1) { gen in
                gen.dir("var", days: 1) { gen in
                    gen.blob("vm", 3_000 * mb, files: 2, days: 0)
                    gen.blob("folders", 1_600 * mb, files: 2_400, days: 0)
                    gen.blob("log", 480 * mb, files: 300, days: 0)
                }
                gen.blob("tmp", 40 * mb, files: 60, days: 0)
            }
            gen.dir("usr", days: 90) { gen in gen.blob("local", 1_500 * mb, files: 6_000, days: 8) }
            gen.dir("opt", days: 8) { gen in gen.blob("homebrew", 2_800 * mb, files: 18_000, days: 8) }
            gen.nest(homeComponents, days: 0) { gen in home(&gen) }
        }
        return gen.finish()
    }

    /// A plausible past for the demo drive so "What grew" has rows: snapshots from
    /// 8, 31 and 75 days ago, derived from today's sizes minus what grew since
    /// (the folder and every ancestor shrink together; a missing key means the
    /// folder didn't exist yet).
    static func history(for tree: FileTree, homePath: String, now: Date) -> SizeHistory {
        let home = URL(fileURLWithPath: homePath).pathComponents.dropFirst().joined(separator: "/")
        let today = SizeHistory.Snapshot.capture(tree, date: now)
        let steps: [(daysAgo: Int, grew: [String: Int64], absent: [String])] = [
            (
                8,
                [
                    "\(home)/Library/Developer/Xcode/DerivedData": 3_100 * mb,
                    "\(home)/Downloads": 1_900 * mb,
                    "\(home)/Library/Caches/Homebrew": 900 * mb,
                ], []
            ),
            (
                31,
                [
                    "\(home)/Library/Containers/com.docker.docker": 4_200 * mb,
                    "\(home)/Pictures/Photos Library.photoslibrary": 2_400 * mb,
                    "\(home)/Movies/Summer Trip 2026.fcpbundle": 6_000 * mb,
                ], ["\(home)/Parallels"]
            ),
            (
                75,
                [
                    "\(home)/Library/Application Support/Steam": 6_400 * mb,
                    "\(home)/Developer/ml-experiments": 5_500 * mb,
                ], ["\(home)/Library/Application Support/MobileSync"]
            ),
        ]
        var snapshots: [SizeHistory.Snapshot] = []
        var shrink: [String: Int64] = [:]
        var absent: Set<String> = []
        for step in steps {
            for (path, bytes) in step.grew { shrink[path, default: 0] += bytes }
            absent.formUnion(step.absent)
            var entries = today.entries
            for (path, bytes) in shrink {
                for key in entries.keys where key == path || path.hasPrefix(key + "/") {
                    entries[key] = max(0, (entries[key] ?? 0) - bytes)
                }
            }
            for gone in absent {
                for key in entries.keys where key == gone || key.hasPrefix(gone + "/") {
                    entries[key] = nil
                }
            }
            snapshots.append(
                SizeHistory.Snapshot(
                    date: now.addingTimeInterval(-Double(step.daysAgo) * 86_400), entries: entries))
        }
        return SizeHistory(rootPath: "/", snapshots: snapshots)
    }

    private static func applications(_ gen: inout Generator) {
        gen.dir("Applications", days: 4) { gen in
            gen.blob("Xcode.app", 9_900 * mb, files: 20_000, days: 20)
            gen.blob("Final Cut Pro.app", 3_900 * mb, files: 2_200, days: 45)
            gen.blob("Microsoft Word.app", 2_100 * mb, files: 1_800, days: 15)
            gen.blob("Microsoft Excel.app", 1_900 * mb, files: 1_700, days: 15)
            gen.blob("Logic Pro.app", 1_600 * mb, files: 1_400, days: 70)
            gen.blob("Docker.app", 1_300 * mb, files: 900, days: 9)
            gen.blob("Google Chrome.app", 1_200 * mb, files: 1_100, days: 2)
            gen.blob("Blender.app", 950 * mb, files: 3_000, days: 120)
            gen.blob("Visual Studio Code.app", 540 * mb, files: 2_600, days: 1)
            gen.blob("Figma.app", 420 * mb, files: 300, days: 6)
            gen.blob("Slack.app", 380 * mb, files: 280, days: 3)
            gen.blob("Spotify.app", 310 * mb, files: 240, days: 5)
            gen.blob("Discord.app", 290 * mb, files: 260, days: 4)
            gen.blob("zoom.us.app", 260 * mb, files: 200, days: 30)
            gen.blob("Steam.app", 210 * mb, files: 150, days: 5)
            gen.blob("Utilities", 20 * mb, files: 40, days: 300)
        }
    }

    private static func home(_ gen: inout Generator) {
        gen.dir("Movies", days: 12) { gen in
            gen.dir("Summer Trip 2026.fcpbundle", days: 12) { gen in
                gen.blob("Render Files", 5_900 * mb, files: 420, days: 12, ext: ".mov")
                gen.blob("Transcoded Media", 3_600 * mb, files: 160, days: 14, ext: ".mov")
                gen.blob("Original Media", 3_800 * mb, files: 140, days: 18, ext: ".MOV")
                gen.file("CurrentVersion.fcpevent", 12 * mb, days: 12)
            }
            gen.dir("Drone footage", days: 60) { gen in
                gen.file("DJI_0042.MP4", 2_900 * mb, days: 60)
                gen.file("DJI_0043.MP4", 2_100 * mb, days: 60)
                gen.file("DJI_0044.MP4", 1_200 * mb, days: 60)
            }
            gen.file("Podcast ep12 final.mp4", 2_600 * mb, days: 45)
            gen.file("Screen Recording 2026-06-14 at 10.22.03.mov", 1_900 * mb, days: 73)
            gen.file("zoom_2026-05-02 13.02.11.mp4", 1_300 * mb, days: 116)
        }
        library(&gen)
        developer(&gen)
        gen.dir("Downloads", days: 1) { gen in
            gen.file("raw-photos-June.zip", 3_700 * mb, days: 62)
            gen.file("Xcode_16.4.xip", 3_200 * mb, days: 88)
            gen.file("ubuntu-24.04-live-server-arm64.iso", 2_100 * mb, days: 140)
            gen.file("lecture-recording.mp4", 1_900 * mb, days: 51)
            gen.file("Docker.dmg", 620 * mb, days: 33)
            gen.file("Blender-4.2-macos-arm64.dmg", 340 * mb, days: 120)
            gen.file("Slack-4.39.dmg", 180 * mb, days: 200)
            gen.file("Figma.zip", 120 * mb, days: 15)
            gen.file("node-v22.6.0.pkg", 70 * mb, days: 24)
            gen.file("IMG_4471.HEIC", 4 * mb, days: 3)
            gen.file("Onboarding.pdf", 3 * mb, days: 9)
            gen.file("Invoice-2026-07.pdf", 200 * kb, days: 20)
        }
        gen.dir("Pictures", days: 5) { gen in
            gen.blob("Photos Library.photoslibrary", 8_200 * mb, files: 8_000, days: 1, ext: ".heic")
            gen.blob("Lightroom", 800 * mb, files: 260, days: 40, ext: ".dng")
        }
        gen.dir("Documents", days: 2) { gen in
            gen.blob("Zoom", 2_300 * mb, files: 14, days: 25, ext: ".mp4")
            gen.blob("Thesis", 1_100 * mb, files: 180, days: 400, ext: ".pdf")
            gen.blob("Scans", 900 * mb, files: 320, days: 150, ext: ".pdf")
            gen.blob("Tax 2025", 300 * mb, files: 60, days: 130, ext: ".pdf")
            gen.blob("Notes", 40 * mb, files: 220, days: 1, ext: ".md")
        }
        gen.dir("Music", days: 30) { gen in
            gen.dir("Logic", days: 30) { gen in
                gen.blob("Demo Track.logicx", 1_800 * mb, files: 90, days: 30, ext: ".wav")
                gen.blob("Podcast Intro.logicx", 1_300 * mb, files: 60, days: 210, ext: ".wav")
            }
            gen.blob("Music Library", 1_200 * mb, files: 900, days: 100, ext: ".m4a")
        }
        gen.blob(".Trash", 3_300 * mb, files: 48, days: 6)
        gen.dir("Desktop", days: 0) { gen in
            gen.file("old-backup.zip", 900 * mb, days: 240)
            gen.file("presentation.key", 640 * mb, days: 4)
            gen.file("Mockups.fig", 210 * mb, days: 2)
            gen.file("Screenshot 2026-08-12 at 09.14.55.png", 4 * mb, days: 14)
        }
        gen.dir("Applications", days: 50) { gen in gen.blob("Arc.app", 480 * mb, files: 300, days: 50) }
        gen.dir("Parallels", days: 21) { gen in
            gen.blob("Windows 11.pvm", 16_000 * mb, files: 12, days: 21, ext: ".hdd")
        }
        gen.blob("Public", 1 * mb, files: 3, days: 500)
        gen.file(".zsh_history", 400 * kb, days: 0)
    }

    private static func library(_ gen: inout Generator) {
        gen.dir("Library", days: 0) { gen in
            gen.dir("Application Support", days: 0) { gen in
                gen.dir("Steam", days: 5) { gen in
                    gen.dir("steamapps", days: 5) { gen in
                        gen.dir("common", days: 5) { gen in
                            gen.blob("Hades II", 6_400 * mb, files: 3_200, days: 5)
                            gen.blob("Hollow Knight Silksong", 4_600 * mb, files: 2_100, days: 40)
                            gen.blob("Stardew Valley", 1_200 * mb, files: 1_400, days: 300)
                        }
                        gen.blob("shadercache", 200 * mb, files: 400, days: 5)
                    }
                }
                gen.dir("Google", days: 0) { gen in gen.blob("Chrome", 2_300 * mb, files: 5_000, days: 0) }
                gen.blob("Code", 1_100 * mb, files: 4_200, days: 1)
                gen.blob("Slack", 860 * mb, files: 1_200, days: 0)
                gen.blob("discord", 710 * mb, files: 800, days: 0)
                gen.blob("Zoom", 310 * mb, files: 200, days: 25)
                gen.dir("MobileSync", days: 95) { gen in
                    gen.dir("Backup", days: 95) { gen in
                        gen.blob("00008030-000A4D1E0C28802E", 14_200 * mb, files: 41_000, days: 95)
                        gen.blob(
                            "00008030-000A4D1E0C28802E-20260401-091500", 6_400 * mb, files: 26_000, days: 147)
                    }
                }
            }
            gen.dir("Caches", days: 0) { gen in
                gen.blob("Homebrew", 2_000 * mb, files: 260, days: 8)
                gen.blob("com.apple.dt.Xcode", 1_900 * mb, files: 3_000, days: 0)
                gen.dir("Google", days: 0) { gen in gen.blob("Chrome", 1_300 * mb, files: 7_000, days: 0) }
                gen.blob("pip", 620 * mb, files: 900, days: 9)
                gen.blob("com.spotify.client", 560 * mb, files: 1_500, days: 5)
            }
            gen.dir("Developer", days: 2) { gen in
                gen.dir("Xcode", days: 2) { gen in
                    gen.blob("DerivedData", 4_100 * mb, files: 12_000, days: 2)
                    gen.blob("Archives", 1_500 * mb, files: 60, days: 30)
                }
                gen.dir("CoreSimulator", days: 10) { gen in
                    gen.blob("Devices", 1_300 * mb, files: 2_800, days: 10)
                }
            }
            containers(&gen)
            gen.blob("Mail", 900 * mb, files: 9_000, days: 0)
            gen.blob("Logs", 340 * mb, files: 700, days: 0)
        }
    }

    /// `~/Library/Containers`: Docker's VM disk, a UTM machine, and two Apple containers.
    private static func containers(_ gen: inout Generator) {
        gen.dir("Containers", days: 0) { gen in
            gen.nest(["com.docker.docker", "Data", "vms", "0", "data"], days: 2) { gen in
                gen.file("Docker.raw", 5_900 * mb, days: 2)
            }
            gen.nest(["com.utmapp.UTM", "Data", "Documents"], days: 12) { gen in
                gen.blob("Ubuntu 24.04.utm", 6_500 * mb, files: 6, days: 12, ext: ".qcow2")
            }
            gen.blob("com.apple.mail", 700 * mb, files: 2_000, days: 0)
            gen.blob("com.apple.Safari", 300 * mb, files: 600, days: 0)
        }
    }

    private static func developer(_ gen: inout Generator) {
        gen.dir("Developer", days: 0) { gen in
            gen.dir("ml-experiments", days: 9) { gen in
                gen.blob("data", 5_600 * mb, files: 120, days: 9, ext: ".parquet")
                gen.blob(".venv", 1_900 * mb, files: 21_000, days: 9)
                gen.blob("notebooks", 820 * mb, files: 30, days: 9, ext: ".ipynb")
                gen.blob(".git", 60 * mb, files: 600, days: 9)
                gen.file("pyproject.toml", 2 * kb, days: 9)
            }
            gen.dir("storefront", days: 3) { gen in
                gen.blob("node_modules", 3_800 * mb, files: 30_000, days: 3)
                gen.blob(".next", 1_200 * mb, files: 2_400, days: 3)
                gen.blob("src", 1_100 * mb, files: 900, days: 3, ext: ".tsx")
                gen.blob(".git", 380 * mb, files: 1_800, days: 3)
                gen.file("package.json", 3 * kb, days: 3)
            }
            gen.dir("foldscale", days: 0) { gen in
                gen.blob(".build", 1_300 * mb, files: 4_000, days: 0)
                gen.blob(".git", 40 * mb, files: 500, days: 0)
                gen.blob("Sources", 2 * mb, files: 60, days: 0, ext: ".swift")
                gen.blob("Tests", 1 * mb, files: 20, days: 0, ext: ".swift")
                gen.file("Package.swift", 1 * kb, days: 0)
            }
            gen.dir("ios-weather", days: 210) { gen in
                gen.blob("Assets", 590 * mb, files: 300, days: 210, ext: ".png")
                gen.blob("Pods", 580 * mb, files: 6_000, days: 210)
                gen.blob(".git", 200 * mb, files: 900, days: 210)
                gen.blob("Sources", 30 * mb, files: 140, days: 210, ext: ".swift")
                gen.blob("Weather.xcodeproj", 1 * mb, files: 8, days: 210)
            }
            gen.blob("dotfiles", 12 * mb, files: 40, days: 60)
        }
    }
}

/// A tiny DSL over `FileTreeBuilder`: nested folders, named files, and "blobs" —
/// folders of generated files totalling a size, so bundles and caches have real
/// item counts without spelling out every file.
private struct Generator {
    private var builder = FileTreeBuilder()
    private let now: Int64
    private var inode: UInt64 = 1
    private var seed: UInt64 = 0x9E37_79B9_7F4A_7C15

    init(now: Int64) { self.now = now }

    mutating func finish() -> FileTree { builder.finish() }

    mutating func dir(_ name: String, days: Int, _ body: (inout Generator) -> Void) {
        builder.enterDirectory(name: name, meta: meta(bytes: 4 * kb, days: days, directory: true))
        body(&self)
        builder.leaveDirectory()
    }

    /// Nested folders for each path component, then `body` inside the innermost.
    mutating func nest(_ components: [String], days: Int, _ body: (inout Generator) -> Void) {
        guard let first = components.first else {
            body(&self)
            return
        }
        dir(first, days: days) { gen in gen.nest(Array(components.dropFirst()), days: days, body) }
    }

    mutating func file(_ name: String, _ bytes: Int64, days: Int) {
        builder.addLeaf(name: name, meta: meta(bytes: bytes, days: days, directory: false))
    }

    mutating func blob(_ name: String, _ bytes: Int64, files count: Int, days: Int, ext: String = "") {
        dir(name, days: days) { gen in gen.files(count, total: bytes, days: days, ext: ext) }
    }

    private mutating func files(_ count: Int, total: Int64, days: Int, ext: String) {
        guard count > 0 else { return }
        let weights = (0..<count).map { _ in Double(1 + random() % 99) }
        let sum = weights.reduce(0, +)
        for index in 0..<count {
            let bytes = max(4 * kb, Int64(Double(total) * weights[index] / sum))
            let name = "\(ext.isEmpty ? "chunk" : "clip")-\(index + 1)\(ext.isEmpty ? ".bin" : ext)"
            file(name, bytes, days: days + Int(random() % 20))
        }
    }

    private mutating func random() -> UInt64 {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return seed >> 33
    }

    private mutating func meta(bytes: Int64, days: Int, directory: Bool) -> NodeMeta {
        inode += 1
        return NodeMeta(
            allocatedSize: bytes, logicalSize: bytes,
            modificationTime: now - Int64(days) * 86_400,
            flags: directory ? [.directory] : [], deviceID: 1, inode: inode, linkCount: 1)
    }
}
