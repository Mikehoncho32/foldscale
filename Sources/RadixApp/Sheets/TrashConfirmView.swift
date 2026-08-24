import RadixCore
import SwiftUI

/// The required confirmation before any trash action (handoff §6): it lists the
/// items and the space that will be reclaimed, and notes any protected items that
/// will be skipped. The destructive button is danger-tinted, never primary-styled.
struct TrashConfirmView: View {
    let store: ScanStore
    @Environment(\.dismiss) private var dismiss

    private var nodes: [FileTree.NodeID] { Array(store.selection) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Move \(nodes.count) item\(nodes.count == 1 ? "" : "s") to the Trash?")
                .font(.headline)

            if let tree = store.tree {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(nodes.prefix(8), id: \.self) { node in
                        Label(tree.name(of: node), systemImage: iconName(tree, node))
                            .lineLimit(1)
                    }
                    if nodes.count > 8 {
                        Text("and \(nodes.count - 8) more…").foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
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
                Button("Move to Trash") { confirm() }
                    .tint(.red)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func iconName(_ tree: FileTree, _ node: FileTree.NodeID) -> String {
        tree.flags(of: node).contains(.directory) ? "folder" : "doc"
    }

    private func confirm() {
        let selected = store.selection
        Task {
            await store.trash(selected)
            dismiss()
        }
    }
}
