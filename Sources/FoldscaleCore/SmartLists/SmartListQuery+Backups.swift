import Foundation

// MARK: - Phone backups

extension SmartListQuery {
    static let backupsFolder = "Library/Application Support/MobileSync/Backup"
    static let backupMinimumBytes: Int64 = 100_000_000
    static let backupsGroup = "iPhone & iPad backups"

    /// Every backup folder Finder keeps for an iPhone or iPad — the current
    /// `<UDID>` and any `<UDID>-YYYYMMDD-HHMMSS` archived copy — named after the
    /// device when its `Info.plist` can be read. Without Full Disk Access the folder
    /// is unreadable and the list stays empty (the FDA banner explains that).
    mutating func phoneBackups() -> ([SmartListEntry], [String]) {
        var entries: [SmartListEntry] = []
        guard let root = node(at: home(Self.backupsFolder)) else { return (entries, [Self.backupsGroup]) }
        tree.forEachChild(of: root) { backup in
            guard tree.isDirectory(backup), tree.totalAllocatedSize(of: backup) >= Self.backupMinimumBytes
            else { return }
            let info = bundleInfo.backupInfo(forBackupAt: context.absolutePath(of: backup, in: tree))
            var notes: [String] = []
            if let product = info?.productName { notes.append(product) }
            if let date = info?.lastBackupDate {
                notes.append("backed up \(age(epoch: Int64(date.timeIntervalSince1970)))")
            } else {
                notes.append("backed up \(age(of: backup))")
            }
            if Self.isArchivedBackup(tree.name(of: backup)) { notes.append("archived copy") }
            entries.append(
                SmartListEntry(
                    node: backup, group: Self.backupsGroup, note: notes.joined(separator: " · "),
                    safety: .reviewFirst, displayName: info?.deviceName ?? info?.productName))
        }
        return (entries, [Self.backupsGroup])
    }

    /// Finder names an archived copy `<UDID>-YYYYMMDD-HHMMSS` (UDIDs themselves may
    /// contain one dash, e.g. `00008030-000A4D1E0C28802E`).
    static func isArchivedBackup(_ folderName: String) -> Bool {
        let parts = folderName.split(separator: "-")
        guard parts.count >= 3, let time = parts.last, let day = parts.dropLast().last else { return false }
        return day.count == 8 && time.count == 6 && day.allSatisfy(\.isNumber) && time.allSatisfy(\.isNumber)
    }
}
