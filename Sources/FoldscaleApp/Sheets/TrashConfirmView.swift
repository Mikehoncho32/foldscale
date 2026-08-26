import FoldscaleCore
import SwiftUI

/// The required confirmation before any trash action (handoff §6): lists what will
/// go — biggest first, with where it lives and its size — and the space reclaimed
/// (nested items counted once). The destructive button is danger-tinted and is
/// **not** the default button, so Return can't trash anything by accident.
struct TrashConfirmView: View {
    let store: ScanStore
    @Environment(\.dismiss) private var dismiss

    /// Outermost selected items, biggest first (a folder covers its contents).
    private var nodes: [FileTree.NodeID] {
        guard let tree = store.tree else { return [] }
        return FreeUpPlanner.outermost(of: store.selection, in: tree)
            .sorted { tree.totalAllocatedSize(of: $0) > tree.totalAllocatedSize(of: $1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Move \(nodes.count) item\(nodes.count == 1 ? "" : "s") to the Trash?")
                .font(.headline)

            if let tree = store.tree {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(nodes, id: \.self) { node in
                            HStack(spacing: 8) {
                                Image(systemName: iconName(tree, node)).foregroundStyle(.secondary).frame(
                                    width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(tree.name(of: node)).lineLimit(1)
                                    Text(location(of: node)).font(.caption).foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(DisplayFormat.bytes(tree.totalAllocatedSize(of: node)))
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                    .font(.callout)
                }
                .frame(maxHeight: 220)
            }

            Text("You'll reclaim \(DisplayFormat.bytes(store.selectionReclaimBytes)).")
                .foregroundStyle(.secondary)

            if store.selectionHasProtected {
                Label("Protected system items will be skipped.", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .keyboardShortcut(.defaultAction)
                Button("Move to Trash") { confirm() }
                    .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func iconName(_ tree: FileTree, _ node: FileTree.NodeID) -> String {
        tree.flags(of: node).contains(.directory) ? "folder" : "doc"
    }

    /// "~/Downloads" — the parent folder, home-relative.
    private func location(of node: FileTree.NodeID) -> String {
        guard let parent = store.url(for: node)?.deletingLastPathComponent().path else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if parent == home { return "~" }
        return parent.hasPrefix(home + "/") ? "~" + parent.dropFirst(home.count) : parent
    }

    private func confirm() {
        let selected = store.selection
        Task {
            await store.trash(selected)
            dismiss()
        }
    }
}
