import AppKit
import RadixCore
import SwiftUI

/// The main window: sidebar (drive tree, smart lists, places), a toolbar (open /
/// refresh / updating indicator), the drive overview or the Finder-style outline,
/// and the footer. Scanning is non-modal; background refreshes keep the current
/// view and preserve the user's place (handoff §4, rule 8).
struct ContentView: View {
    @State private var store = ScanStore()
    @State private var bridge = OutlineBridge()
    @State private var sidebar: SidebarItem?

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store, selection: $sidebar)
        } detail: {
            detail
        }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            if store.shouldSuggestFDA {
                FDABanner(store: store)
                Divider()
            }
            detailContent
            Divider()
            FooterView(store: store, bridge: bridge)
        }
        .frame(minWidth: 640, minHeight: 480)
        .navigationTitle(store.rootDisplayName)
        .toolbar { toolbar }
        .onChange(of: sidebar) { old, new in
            switch new {
            case .node(let id):
                store.setFocus(id)
            case .place(let url):
                // Inside the loaded scan → just focus it; outside → scan it as a new root.
                if let node = store.node(for: url) {
                    store.setFocus(node)
                } else {
                    store.openFolder(url)
                }
            case .largeFiles, .oldAndBig, nil:
                break
            }
            if old?.isSmartList != new?.isSmartList { store.selection = [] }
        }
        .onChange(of: store.generation) { _, _ in
            // A swap/splice re-resolved the focus by path; keep the sidebar in step.
            if case .node(let current) = sidebar, current != store.focusedNode {
                sidebar = .node(store.focusedNode)
            }
        }
        .onChange(of: store.scanSession, initial: true) { _, _ in
            // First look: land on the home folder — the Mac's "main folders" view,
            // where nearly all reclaimable space lives — when it's inside the scan.
            guard let tree = store.tree else { return }
            let home = FileManager.default.homeDirectoryForCurrentUser
            sidebar = store.node(for: home) != nil ? .place(home) : .node(tree.rootID)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            store.flushPersist()
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            store.openFolder(resolveDirectory(url))
            return true
        }
        .onAppear {
            store.refreshFDA()
            // Dev/CI hook: auto-scan a folder from the environment so the app can be
            // driven headlessly (screenshots, smoke tests) without the open panel.
            if let path = ProcessInfo.processInfo.environment["RADIX_SCAN_PATH"] {
                store.openFolder(URL(fileURLWithPath: path))
            } else {
                store.loadCachedScan()
                if store.tree != nil, store.autoRefreshOnLaunch { store.refresh() }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { store.isConfirmingTrash }, set: { store.isConfirmingTrash = $0 })
        ) {
            TrashConfirmView(store: store)
        }
        .sheet(
            isPresented: Binding(
                get: { store.infoNode != nil }, set: { if !$0 { store.infoNode = nil } })
        ) {
            if let node = store.infoNode {
                GetInfoView(store: store, node: node)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { store.isShowingFDAOnboarding }, set: { store.isShowingFDAOnboarding = $0 })
        ) {
            FDAOnboardingView(store: store)
        }
    }

    @ViewBuilder private var detailContent: some View {
        if store.tree != nil {
            if let sidebar, sidebar.isSmartList {
                SmartListView(store: store, item: sidebar)
            } else {
                // The drive overview is pinned on top no matter where you click; the
                // path and that section's breakdown live beneath it.
                let focus = store.focusedNode
                DriveOverviewHeader(store: store)
                Divider()
                BreadcrumbView(store: store, focus: focus) { sidebar = .node($0) }
                Divider()
                FileOutlineView(
                    store: store, generation: store.generation, focus: focus, bridge: bridge,
                    onOpenDirectory: { sidebar = .node($0) })
            }
        } else {
            placeholder
        }
    }

    @ViewBuilder private var placeholder: some View {
        switch store.phase {
        case .scanning:
            VStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Scanning \(store.rootDisplayName)…").font(.title3)
                if let progress = store.progress {
                    Text(
                        "\(DisplayFormat.itemCount(Int64(progress.nodesScanned))) items · "
                            + DisplayFormat.bytes(progress.bytesScanned)
                    )
                    .foregroundStyle(.secondary)
                }
                ProgressView().controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        case .failed(let message):
            VStack(spacing: 10) {
                Text("Couldn't scan that folder").font(.title3)
                Text(message).font(.footnote).foregroundStyle(.tertiary)
                Button("Choose a Folder…") { openFolder() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        case .idle, .done:
            DriveOverviewView(store: store)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                openFolder()
            } label: {
                Label("Open", systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: .command)
            Button {
                store.rescan()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(store.rootURL == nil || store.isScanning || store.isRefreshing)
            if store.isScanning || store.isRefreshing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    if store.isRefreshing {
                        Text(updatingText).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var updatingText: String {
        if let progress = store.refreshProgress {
            return "Updating… \(DisplayFormat.itemCount(Int64(progress.nodesScanned))) items"
        }
        return "Updating…"
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url {
            store.openFolder(url)
        }
    }

    private func resolveDirectory(_ url: URL) -> URL {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue ? url : url.deletingLastPathComponent()
    }
}

#Preview {
    ContentView()
}
