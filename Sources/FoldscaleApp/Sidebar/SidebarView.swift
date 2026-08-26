import FoldscaleCore
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

            Section("Favorites") {
                ForEach(favorites, id: \.self) { url in
                    placeRow(url, icon: favoriteIcon(url))
                }
            }

            smartListSection("Clean Up", .cleanUp)
            smartListSection("What's Here", .whatsHere)

            if !volumes.isEmpty {
                Section("Drives") {
                    ForEach(volumes, id: \.self) { url in
                        placeRow(url, icon: "externaldrive", label: volumeName(url))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // Wide enough that "Macintosh HD · 182.86 GB" doesn't truncate at the default.
        .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        // Ids are reused across scans; re-keying the list resets expansion state.
        .id(store.scanSession)
    }

    // MARK: - Smart lists

    /// A section of task-oriented lists. Rows appear only once computed and
    /// non-empty, so nobody sees "Virtual machines · 0 B"; an empty section hides.
    @ViewBuilder private func smartListSection(
        _ title: String, _ section: SmartListKind.Section
    )
        -> some View
    {
        let kinds = SmartListKind.allCases.filter { kind in
            kind.section == section && (store.smartLists[kind]?.totalBytes ?? 0) > 0
        }
        let showsFreeUp = section == .cleanUp && store.tree != nil
        if !kinds.isEmpty || showsFreeUp {
            Section(title) {
                if showsFreeUp {
                    // The goal flow: "I need X GB" → a ranked, pre-ticked checklist.
                    Label("Free up space", systemImage: "sparkles")
                        .tag(SidebarItem.freeUpSpace)
                }
                ForEach(kinds, id: \.self) { kind in
                    treeRow(
                        name: kind.title, bytes: store.smartLists[kind]?.totalBytes ?? 0,
                        icon: kind.systemImage
                    )
                    .tag(SidebarItem.smartList(kind))
                }
            }
        }
    }

    // MARK: - Drive tree

    @ViewBuilder private var driveSection: some View {
        Section("Drive") {
            if let tree = store.tree {
                // The drive is the single collapsible root row — it starts closed so
                // the sidebar stays compact on first load; expanding it reveals the
                // primary folders (biggest first) and the "System & other" remainder.
                let root = SidebarNode(
                    kind: .folder(tree.rootID), tree: tree, path: "",
                    otherBytes: store.unscannedVolumeBytes)
                OutlineGroup([root], children: \.children) { node in
                    if let nodeID = node.nodeID {
                        let isRoot = nodeID == tree.rootID
                        treeRow(
                            name: node.name(rootName: store.rootDisplayName), bytes: node.bytes,
                            icon: isRoot ? driveIcon : "folder", bold: isRoot
                        )
                        .tag(SidebarItem.node(nodeID))
                    } else {
                        treeRow(
                            name: node.name(rootName: ""), bytes: node.bytes, icon: "gearshape", dimmed: true
                        )
                        .selectionDisabled(true)
                        .help(
                            "Space used by the sealed System volume, VM, snapshots and caches Foldscale doesn't scan"
                        )
                    }
                }
            } else if store.isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning \(store.rootDisplayName)…").foregroundStyle(.secondary)
                }
            } else {
                // No scan yet: the main pane shows the drive overview with its Scan
                // button; this row mirrors it so the sidebar isn't empty.
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

    /// A place shortcut: a selectable row, so the clicked Favorite/Volume stays
    /// highlighted while the drive tree above stays exactly as you left it. The
    /// window resolves it: a folder inside the loaded scan just gets focused
    /// (instantly, with a quiet refresh); one outside the scan starts a new scan.
    private func placeRow(_ url: URL, icon: String, label: String? = nil) -> some View {
        Label(label ?? displayName(url), systemImage: icon)
            .tag(SidebarItem.place(url))
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
