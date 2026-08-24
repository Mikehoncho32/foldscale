import SwiftUI

/// The sidebar (handoff §4): quick places (Favorites, mounted Volumes), the smart
/// lists, and the current location. Favorites/Volumes are one-click scans; the
/// smart lists and Folder are selectable views of the current scan.
struct SidebarView: View {
    let store: ScanStore
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Favorites") {
                ForEach(favorites, id: \.self) { url in
                    placeRow(url, icon: favoriteIcon(url))
                }
            }

            Section("Smart Lists") {
                Label(SidebarItem.largeFiles.title, systemImage: SidebarItem.largeFiles.systemImage)
                    .tag(SidebarItem.largeFiles)
                Label(SidebarItem.oldAndBig.title, systemImage: SidebarItem.oldAndBig.systemImage)
                    .tag(SidebarItem.oldAndBig)
            }

            if !volumes.isEmpty {
                Section("Volumes") {
                    ForEach(volumes, id: \.self) { url in
                        placeRow(url, icon: "externaldrive", label: volumeName(url))
                    }
                }
            }

            if let root = store.rootURL {
                Section("Location") {
                    Label(root.lastPathComponent, systemImage: "folder").tag(SidebarItem.folder)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }

    private func placeRow(_ url: URL, icon: String, label: String? = nil) -> some View {
        Button {
            store.openFolder(url)
            selection = .folder
        } label: {
            Label(label ?? displayName(url), systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Places

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
