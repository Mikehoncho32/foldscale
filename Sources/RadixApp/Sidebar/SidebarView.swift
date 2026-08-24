import SwiftUI

/// The sidebar (handoff §4): the current location and the smart lists. Favorites
/// and Volumes join it in Milestone 6.
struct SidebarView: View {
    let store: ScanStore
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Location") {
                Label(store.rootURL?.lastPathComponent ?? "No folder", systemImage: "folder")
                    .tag(SidebarItem.folder)
            }
            Section("Smart Lists") {
                Label(SidebarItem.largeFiles.title, systemImage: SidebarItem.largeFiles.systemImage)
                    .tag(SidebarItem.largeFiles)
                Label(SidebarItem.oldAndBig.title, systemImage: SidebarItem.oldAndBig.systemImage)
                    .tag(SidebarItem.oldAndBig)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 190)
    }
}
