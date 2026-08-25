import RadixCore
import SwiftUI

/// A task-oriented smart list: a header with what it is and how safe it is to act
/// on, then grouped rows (name · where · note · size). Rows select into the footer
/// actions like the outline; informational rows can't be selected, so the Trash
/// button never targets them.
struct SmartListView: View {
    let store: ScanStore
    let kind: SmartListKind

    var body: some View {
        // Only render results computed for the tree on screen: node ids are reused
        // between trees, so stale entries could index out of range.
        if let tree = store.tree, store.smartListsAreCurrent, let result = store.smartLists[kind] {
            VStack(spacing: 0) {
                header(result)
                Divider()
                if result.isEmpty {
                    emptyState
                } else {
                    list(result, tree)
                }
            }
        } else {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Looking through your scan…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ result: SmartListResult) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: kind.systemImage).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(kind.title).font(.title3.weight(.semibold))
                    SafetyBadge(safety: kind.safety)
                }
                Text(kind.blurb).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Text(DisplayFormat.bytes(result.totalBytes))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func list(_ result: SmartListResult, _ tree: FileTree) -> some View {
        List(selection: selectionBinding) {
            ForEach(result.groups, id: \.self) { group in
                Section(group) {
                    ForEach(result.entries(in: group).filter { tree.isLive($0.node) }, id: \.node) { entry in
                        row(entry, tree)
                            .selectionDisabled(entry.safety == .informational)
                            .contextMenu { rowMenu(entry) }
                    }
                }
            }
        }
    }

    private var selectionBinding: Binding<Set<FileTree.NodeID>> {
        Binding(get: { store.selection }, set: { store.selection = $0 })
    }

    private func row(_ entry: SmartListEntry, _ tree: FileTree) -> some View {
        let isDirectory = tree.flags(of: entry.node).contains(.directory)
        let name = tree.name(of: entry.node)
        return HStack(spacing: 8) {
            Image(systemName: icon(for: name, isDirectory: isDirectory))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).lineLimit(1)
                HStack(spacing: 6) {
                    Text(location(of: entry.node)).lineLimit(1)
                    if let note = entry.note {
                        Text("·")
                        Text(note).lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(DisplayFormat.bytes(tree.totalAllocatedSize(of: entry.node) + entry.extraBytes))
                .monospacedDigit()
                .foregroundStyle(entry.safety == .informational ? .tertiary : .secondary)
        }
        .padding(.vertical, 2)
    }

    private func icon(for name: String, isDirectory: Bool) -> String {
        if name.hasSuffix(".app") { return "app.fill" }
        if name == ".Trash" { return "trash" }
        return isDirectory ? "folder.fill" : "doc"
    }

    /// "~/Downloads" — the parent folder, home-relative.
    private func location(of node: FileTree.NodeID) -> String {
        guard let parent = store.url(for: node)?.deletingLastPathComponent().path else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if parent == home { return "~" }
        return parent.hasPrefix(home + "/") ? "~" + parent.dropFirst(home.count) : parent
    }

    @ViewBuilder private func rowMenu(_ entry: SmartListEntry) -> some View {
        Button("Reveal in Finder") {
            if let url = store.url(for: entry.node) { FileActions.reveal([url]) }
        }
        Button("Get Info") { store.infoNode = entry.node }
        if entry.safety != .informational {
            Divider()
            Button("Move to Trash", role: .destructive) {
                store.selection = [entry.node]
                store.isConfirmingTrash = true
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text("Nothing here right now").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "Safe to remove" / "Review first" / "Info" pill.
struct SafetyBadge: View {
    let safety: SmartListSafety

    var body: some View {
        Text(safety.label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch safety {
        case .safeToTrash: return .green
        case .reviewFirst: return .orange
        case .informational: return .secondary
        }
    }
}
