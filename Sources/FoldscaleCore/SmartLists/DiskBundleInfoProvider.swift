import Foundation

/// Reads the small property lists the smart lists rely on. This is the only file
/// under `SmartLists/` that may read file contents (a guardrail test enforces it);
/// every read is bounded to a known plist path and a size cap.
public struct DiskBundleInfoProvider: BundleInfoProvider {
    /// Backup `Info.plist`s carry an app inventory and can grow to several MB.
    static let maximumPlistBytes: Int64 = 16_000_000

    public init() {}

    /// `Contents/Info.plist` of an app bundle.
    public func info(forBundleAt absolutePath: String) -> BundleInfo? {
        let url = URL(fileURLWithPath: absolutePath).appendingPathComponent("Contents/Info.plist")
        guard let dictionary = Self.plist(at: url) else { return nil }
        return BundleInfo(
            name: dictionary["CFBundleName"] as? String,
            identifier: dictionary["CFBundleIdentifier"] as? String,
            category: dictionary["LSApplicationCategoryType"] as? String)
    }

    /// `<UDID>/Info.plist` of an iOS/iPadOS backup folder.
    public func backupInfo(forBackupAt absolutePath: String) -> DeviceBackupInfo? {
        let url = URL(fileURLWithPath: absolutePath).appendingPathComponent("Info.plist")
        guard let dictionary = Self.plist(at: url) else { return nil }
        return DeviceBackupInfo(
            deviceName: dictionary["Device Name"] as? String,
            productName: dictionary["Product Name"] as? String,
            lastBackupDate: dictionary["Last Backup Date"] as? Date)
    }

    private static func plist(at url: URL) -> [String: Any]? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? Int64, size <= maximumPlistBytes,
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { return nil }
        return plist as? [String: Any]
    }
}
