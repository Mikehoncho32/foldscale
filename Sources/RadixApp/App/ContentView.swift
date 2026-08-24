import AppKit
import RadixCore
import SwiftUI

/// The main window: a toolbar (open / rescan / scanning indicator), the Finder-style
/// outline (once a scan finishes), and the footer. Scanning is non-modal — the tree
/// area shows a live count while the background scan runs (handoff §4, rule 8).
struct ContentView: View {
    @State private var store = ScanStore()
    @State private var bridge = OutlineBridge()
    @State private var sidebar: SidebarItem? = .folder

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
        .navigationTitle(store.rootURL?.lastPathComponent ?? "Radix")
        .toolbar { toolbar }
        .onChange(of: sidebar) { _, _ in store.selection = [] }
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
        if store.tree == nil {
            placeholder
        } else if let sidebar, sidebar.isSmartList {
            SmartListView(store: store, item: sidebar)
        } else {
            FileOutlineView(store: store, generation: store.generation, bridge: bridge)
        }
    }

    @ViewBuilder private var placeholder: some View {
        VStack(spacing: 14) {
            Image(systemName: store.isScanning ? "magnifyingglass" : "internaldrive")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
            switch store.phase {
            case .scanning:
                Text("Scanning…").font(.title3)
                if let progress = store.progress {
                    Text(
                        "\(DisplayFormat.itemCount(Int64(progress.nodesScanned))) items · "
                            + DisplayFormat.bytes(progress.bytesScanned)
                    )
                    .foregroundStyle(.secondary)
                }
                ProgressView().controlSize(.small)
            case .failed(let message):
                Text("Couldn't scan that folder").font(.title3)
                Text(message).font(.footnote).foregroundStyle(.tertiary)
            case .idle, .done:
                Text("Open a folder to see what's using space").font(.title3)
                Button("Open Folder…") { openFolder() }
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
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
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(store.rootURL == nil || store.isScanning)
            if store.isScanning {
                ProgressView().controlSize(.small)
            }
        }
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
