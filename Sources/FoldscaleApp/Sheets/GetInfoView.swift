import FoldscaleCore
import SwiftUI

/// A lightweight Get Info sheet (handoff §4). Unlike the outline, it surfaces the
/// logical size alongside the allocated (on-disk) size — the one place logical size
/// is shown (§4, rule 3).
struct GetInfoView: View {
    let store: ScanStore
    let node: FileTree.NodeID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let tree = store.tree {
                HStack(spacing: 8) {
                    Image(systemName: tree.flags(of: node).contains(.directory) ? "folder.fill" : "doc.fill")
                        .foregroundStyle(.secondary)
                    Text(tree.name(of: node)).font(.headline).lineLimit(1)
                }
                Divider()
                row("Kind", kind(tree))
                row("On disk (allocated)", DisplayFormat.bytes(tree.totalAllocatedSize(of: node)))
                row("Logical size", DisplayFormat.bytes(tree.logicalSize(of: node)))
                if tree.flags(of: node).contains(.directory) {
                    row("Items", DisplayFormat.itemCount(tree.itemCount(of: node)))
                }
                row(
                    "Modified",
                    DisplayFormat.relativeModified(epochSeconds: tree.modificationTime(of: node)))
                if let path = store.url(for: node)?.path {
                    row("Where", path, mono: true)
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func kind(_ tree: FileTree) -> String {
        let flags = tree.flags(of: node)
        if flags.contains(.dataless) { return "Cloud placeholder" }
        if flags.contains(.symlink) { return "Symbolic link" }
        return flags.contains(.directory) ? "Folder" : "File"
    }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(value)
                .font(mono ? .system(.callout, design: .monospaced) : .callout)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
