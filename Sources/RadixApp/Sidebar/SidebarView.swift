import RadixCore
import SwiftUI

/// The sidebar. First comes the **drive tree** — the scanned drive/folder at the
/// top with its total, then its subfolders as an expandable, biggest-first
/// directory tree (like Cursor's or Xcode's navigator); selecting a folder focuses
/// the main pane on it. Below: the smart lists, then one-click scan shortcuts
/// (Favorites, mounted Volumes).
struct SidebarView: View {
    let store: ScanStore
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            driveSection

            Section("Smart Lists") {
                Label(SidebarItem.largeFiles.title, systemImage: SidebarItem.largeFiles.systemImage)
                    .tag(SidebarItem.largeFiles)
                Label(SidebarItem.oldAndBig.title, systemImage: SidebarItem.oldAndBig.systemImage)
                    .tag(SidebarItem.oldAndBig)
            }

            Section("Favorites") {
                ForEach(favorites, id: \.self) { url in
                    placeRow(url, icon: favoriteIcon(url))
                }
            }

            if !volumes.isEmpty {
                Section("Volumes") {
                    ForEach(volumes, id: \.self) { url in
                        placeRow(url, icon: "externaldrive", label: volumeName(url))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
        // Ids are reused across scans; re-keying the list resets expansion state.
        .id(store.scanSession)
    }

    // MARK: - Drive tree

    @ViewBuilder private var driveSection: some View {
        Section("Drive") {
            if let tree = store.tree {
                let root = SidebarNode(id: tree.rootID, tree: tree)
                // The root is a plain row (not inside OutlineGroup) so its first level
                // is always visible — OutlineGroup can't start expanded on macOS 14.
                treeRow(name: store.rootDisplayName, bytes: root.bytes, icon: driveIcon, bold: true)
                    .tag(SidebarItem.node(root.id))
                OutlineGroup(root.children ?? [], children: \.children) { node in
                    treeRow(name: node.name, bytes: node.bytes, icon: "folder")
                        .tag(SidebarItem.node(node.id))
                }
                if let other = store.unscannedVolumeBytes, other > 0 {
                    treeRow(name: "System & other", bytes: other, icon: "gearshape", dimmed: true)
                        .selectionDisabled(true)
                        .help(
                            "Space used by the sealed System volume, VM, snapshots and caches Radix doesn't scan"
                        )
                }
            } else if store.isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning \(store.rootDisplayName)…").foregroundStyle(.secondary)
                }
            } else {
                bootVolumeButton
            }
        }
    }

    /// The un-scanned boot volume, shown before any scan exists. Clicking scans the
    /// whole drive; nothing scans automatically on launch (handoff §6).
    private var bootVolumeButton: some View {
        let root = URL(fileURLWithPath: "/")
        let stats = VolumeStats.forVolume(containing: root)
        let name = (try? root.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? "Macintosh HD"
        return Button {
            store.openFolder(root)
            selection = nil
        } label: {
            HStack(spacing: 6) {
                Image(systemName: driveIcon)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                    if let stats {
                        Text(
                            "\(DisplayFormat.bytes(stats.usedCapacity)) used of "
                                + DisplayFormat.bytes(stats.totalCapacity)
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("Scan").font(.caption).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func treeRow(
        name: String, bytes: Int64, icon: String, bold: Bool = false, dimmed: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(dimmed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
            Text(name)
                .fontWeight(bold ? .semibold : .regular)
                .foregroundStyle(dimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(DisplayFormat.bytes(bytes))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var driveIcon: String { store.rootIsVolumeRoot || store.tree == nil ? "internaldrive" : "folder" }

    // MARK: - Places

    private func placeRow(_ url: URL, icon: String, label: String? = nil) -> some View {
        Button {
            store.openFolder(url)
            selection = nil
        } label: {
            Label(label ?? displayName(url), systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var favorites: [URL] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        return [
            home,
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Documents"),
        ]
        .filter { fileManager.fileExists(atPath: $0.path) }
    }

    private var volumes: [URL] {
        FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey],
            options: [.skipHiddenVolumes]) ?? []
    }

    private func displayName(_ url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? "/" : name
    }

    private func volumeName(_ url: URL) -> String {
        (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? displayName(url)
    }

    private func favoriteIcon(_ url: URL) -> String {
        switch url.lastPathComponent {
        case "Desktop": return "menubar.dock.rectangle"
        case "Downloads": return "arrow.down.circle"
        case "Documents": return "doc"
        default: return "house"
        }
    }
}
