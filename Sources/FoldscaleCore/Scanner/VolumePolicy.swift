import Foundation

/// Decides which device ids a scan may descend into when
/// `ScanOptions.stayOnStartVolume` is on.
///
/// Modern macOS splits the boot disk into a sealed System volume and a Data
/// volume joined by firmlinks (`/Users`, `/Applications`, `/Library`, …). On some
/// releases those firmlinked directories report the Data volume's `st_dev`, which
/// differs from `/`'s — a naive "same device as the root" rule would then skip all
/// user data in a whole-drive scan. So when the root is `/`, the Data volume's
/// device is allowed too. This cannot double count: `ScanExclusions.default`
/// already skips `/System` (so `/System/Volumes/Data` is never entered) and the
/// walker dedupes directories by `(device, inode)`.
enum VolumePolicy {
    /// The Data volume's mount point on Catalina and later.
    static let dataVolumePath = "/System/Volumes/Data"

    /// Device ids a scan rooted at `rootPath` (whose `stat` is `rootStat`) may enter.
    static func allowedDevices(forRoot rootPath: String, rootStat: stat) -> Set<Int64> {
        var devices: Set<Int64> = [Int64(rootStat.st_dev)]
        guard rootPath == "/" else { return devices }
        var dataStat = stat()
        if lstat(dataVolumePath, &dataStat) == 0 {
            devices.insert(Int64(dataStat.st_dev))
        }
        return devices
    }
}
