import FoldscaleCore
import Foundation

/// Canned bundle and backup metadata for the demo drive (`FOLDSCALE_DEMO=1`), so
/// smart lists that read `Info.plist`s look right without any real files. Keyed
/// by the last path component, which is all the demo tree needs.
struct DemoMetadataProvider: BundleInfoProvider {
    private static let apps: [String: BundleInfo] = [
        "Xcode.app": BundleInfo(name: "Xcode", identifier: "com.apple.dt.Xcode", category: "developer-tools"),
        "Final Cut Pro.app": BundleInfo(
            name: "Final Cut Pro", identifier: "com.apple.FinalCut", category: "video"),
        "Microsoft Word.app": BundleInfo(
            name: "Microsoft Word", identifier: "com.microsoft.Word", category: "productivity"),
        "Microsoft Excel.app": BundleInfo(
            name: "Microsoft Excel", identifier: "com.microsoft.Excel", category: "productivity"),
        "Logic Pro.app": BundleInfo(name: "Logic Pro", identifier: "com.apple.logic10", category: "music"),
        "Docker.app": BundleInfo(
            name: "Docker", identifier: "com.docker.docker", category: "developer-tools"),
        "Google Chrome.app": BundleInfo(
            name: "Chrome", identifier: "com.google.Chrome", category: "productivity"),
        "Blender.app": BundleInfo(
            name: "Blender", identifier: "org.blenderfoundation.blender", category: "graphics"),
        "Visual Studio Code.app": BundleInfo(
            name: "Code", identifier: "com.microsoft.VSCode", category: "developer-tools"),
        "Figma.app": BundleInfo(name: "Figma", identifier: "com.figma.Desktop", category: "graphics"),
        "Slack.app": BundleInfo(name: "Slack", identifier: "com.tinyspeck.slackmacgap", category: "business"),
        "Spotify.app": BundleInfo(name: "Spotify", identifier: "com.spotify.client", category: "music"),
        "Discord.app": BundleInfo(
            name: "Discord", identifier: "com.hnc.Discord", category: "social-networking"),
        "zoom.us.app": BundleInfo(name: "zoom.us", identifier: "us.zoom.xos", category: "business"),
        "Steam.app": BundleInfo(name: "Steam", identifier: "com.valvesoftware.steam", category: "games"),
        "Arc.app": BundleInfo(
            name: "Arc", identifier: "company.thebrowser.Browser", category: "productivity"),
    ]

    func info(forBundleAt absolutePath: String) -> BundleInfo? {
        Self.apps[URL(fileURLWithPath: absolutePath).lastPathComponent]
    }

    func backupInfo(forBackupAt absolutePath: String) -> DeviceBackupInfo? {
        let folder = URL(fileURLWithPath: absolutePath).lastPathComponent
        guard folder.hasPrefix("00008030-000A4D1E0C28802E") else { return nil }
        let daysAgo: Double = folder.count > 25 ? 147 : 95
        return DeviceBackupInfo(
            deviceName: "Mark's iPhone", productName: "iPhone 15 Pro",
            lastBackupDate: Date().addingTimeInterval(-daysAgo * 86_400))
    }
}
