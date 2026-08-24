import RadixCore
import SwiftUI

/// A flat, ranked results list for a smart list (Large files / Old and big). These
/// are bounded (top-N / filtered), so a plain SwiftUI `List` is fine here — the
/// virtualized outline (ADR-0002) is only needed for the full tree.
struct SmartListView: View {
    let store: ScanStore
    let item: SidebarItem

    var body: some View {
        if let tree = store.tree {
            let ids = results(in: tree)
            if ids.isEmpty {
                emptyState
            } else {
                List(ids, id: \.self, selection: selectionBinding) { id in
                    row(tree, id).contextMenu { rowMenu(id) }
                }
            }
        } else {
            emptyState
        }
    }

    private var selectionBinding: Binding<Set<FileTree.NodeID>> {
        Binding(get: { store.selection }, set: { store.selection = $0 })
    }

    private func results(in tree: FileTree) -> [FileTree.NodeID] {
        switch item {
        case .oldAndBig:
            let cutoff =
                Calendar.current.date(byAdding: .month, value: -6, to: Date())
                ?? Date(timeIntervalSinceNow: -15_552_000)
            return SmartLists.oldAndBig(in: tree, olderThan: cutoff)
        default:
            return SmartLists.largeFiles(in: tree)
        }
    }

    private func row(_ tree: FileTree, _ id: FileTree.NodeID) -> some View {
        HStack(spacing: 8) {
            Image(systemName: tree.flags(of: id).contains(.directory) ? "folder.fill" : "doc")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(tree.name(of: id)).lineLimit(1)
                Text(store.url(for: id)?.deletingLastPathComponent().path ?? "")
                    .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            Text(DisplayFormat.bytes(tree.totalAllocatedSize(of: id)))
                .monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func rowMenu(_ id: FileTree.NodeID) -> some View {
        Button("Reveal in Finder") {
            if let url = store.url(for: id) { FileActions.reveal([url]) }
        }
        Button("Get Info") { store.infoNode = id }
        Divider()
        Button("Move to Trash", role: .destructive) {
            store.selection = [id]
            store.isConfirmingTrash = true
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: item.systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(emptyMessage).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        switch item {
        case .oldAndBig: return "No files over 1 GB older than 6 months"
        case .largeFiles: return "No files to rank yet"
        case .folder: return ""
        }
    }
}
