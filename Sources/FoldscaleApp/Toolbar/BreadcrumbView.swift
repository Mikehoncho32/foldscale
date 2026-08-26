import FoldscaleCore
import SwiftUI

/// The clickable path bar above the outline (handoff §4): root › … › focused
/// folder. Clicking a crumb re-focuses the main pane on that ancestor.
struct BreadcrumbView: View {
    let store: ScanStore
    let focus: FileTree.NodeID
    let onSelect: (FileTree.NodeID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(crumbs.enumerated()), id: \.element) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        onSelect(node)
                    } label: {
                        Text(label(for: node))
                            .fontWeight(node == focus ? .semibold : .regular)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(node == focus ? .primary : .secondary)
                    .disabled(node == focus)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .font(.callout)
    }

    /// Ancestors from the root down to `focus`.
    private var crumbs: [FileTree.NodeID] {
        guard let tree = store.tree else { return [] }
        var path: [FileTree.NodeID] = []
        var current = focus
        while current != FileTree.none {
            path.append(current)
            current = tree.parent(of: current)
        }
        return path.reversed()
    }

    private func label(for node: FileTree.NodeID) -> String {
        guard let tree = store.tree else { return "" }
        return node == tree.rootID ? store.rootDisplayName : tree.name(of: node)
    }
}
