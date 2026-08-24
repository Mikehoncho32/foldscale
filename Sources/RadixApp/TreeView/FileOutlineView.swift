import AppKit
import RadixCore
import SwiftUI

/// A Finder-style `NSOutlineView` (wrapped for SwiftUI) that renders a `FileTree`
/// with parent-relative size bars, size-sort by default, and column re-sorting.
/// `NSOutlineView` recycles row views, so it stays at 60 fps with tens of
/// thousands of visible rows where SwiftUI `Table` does not (see ADR-0002).
struct FileOutlineView: NSViewRepresentable {
    let store: ScanStore
    let generation: Int

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.allowsMultipleSelection = true
        outline.rowSizeStyle = .default
        outline.indentationPerLevel = 14
        outline.usesAlternatingRowBackgroundColors = false
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator

        for spec in Self.columns {
            let column = NSTableColumn(identifier: .init(spec.id))
            column.title = spec.title
            column.width = spec.width
            column.minWidth = spec.minWidth
            column.sortDescriptorPrototype = NSSortDescriptor(key: spec.sortKey, ascending: spec.ascending)
            outline.addTableColumn(column)
        }
        outline.outlineTableColumn = outline.tableColumn(withIdentifier: .init("name"))
        outline.sortDescriptors = [NSSortDescriptor(key: "size", ascending: false)]

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        context.coordinator.outlineView = outline
        context.coordinator.apply(tree: store.tree, generation: generation)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.apply(tree: store.tree, generation: generation)
    }

    private struct ColumnSpec {
        let id: String
        let title: String
        let width: CGFloat
        let minWidth: CGFloat
        let sortKey: String
        let ascending: Bool
    }

    private static let columns: [ColumnSpec] = [
        ColumnSpec(id: "name", title: "Name", width: 320, minWidth: 180, sortKey: "name", ascending: true),
        ColumnSpec(id: "size", title: "Size", width: 190, minWidth: 140, sortKey: "size", ascending: false),
        ColumnSpec(id: "items", title: "Items", width: 92, minWidth: 70, sortKey: "items", ascending: false),
        ColumnSpec(
            id: "modified", title: "Modified", width: 110, minWidth: 90, sortKey: "modified",
            ascending: false),
    ]

    /// Data source + delegate. Holds the tree and a per-id identity/sorted-children
    /// cache; rebuilt on each new scan generation.
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        weak var outlineView: NSOutlineView?
        private let store: ScanStore
        private var tree: FileTree?
        private var generation = -1
        private var sortKey: SortKey = .size
        private var ascending = false
        private var nodeCache: [FileTree.NodeID: OutlineNode] = [:]
        private var childCache: [FileTree.NodeID: [FileTree.NodeID]] = [:]

        init(store: ScanStore) { self.store = store }

        func apply(tree: FileTree?, generation: Int) {
            guard generation != self.generation else { return }
            self.generation = generation
            self.tree = tree
            nodeCache.removeAll()
            childCache.removeAll()
            outlineView?.reloadData()
        }

        private func node(_ id: FileTree.NodeID) -> OutlineNode {
            if let cached = nodeCache[id] { return cached }
            let made = OutlineNode(id: id)
            nodeCache[id] = made
            return made
        }

        private func sortedChildren(of id: FileTree.NodeID) -> [FileTree.NodeID] {
            if let cached = childCache[id] { return cached }
            let kids = tree?.childrenSorted(of: id, by: sortKey, ascending: ascending) ?? []
            childCache[id] = kids
            return kids
        }

        private func parentRelativeFraction(of id: FileTree.NodeID) -> CGFloat {
            guard let tree else { return 0 }
            let parent = tree.parent(of: id)
            let denominator = tree.totalAllocatedSize(of: parent == FileTree.none ? id : parent)
            guard denominator > 0 else { return 0 }
            return CGFloat(Double(tree.totalAllocatedSize(of: id)) / Double(denominator))
        }

        // MARK: NSOutlineViewDataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let tree else { return 0 }
            let parent = (item as? OutlineNode)?.id ?? tree.rootID
            return sortedChildren(of: parent).count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            let parent = (item as? OutlineNode)?.id ?? tree?.rootID ?? FileTree.none
            return node(sortedChildren(of: parent)[index])
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let tree, let outlineNode = item as? OutlineNode else { return false }
            return tree.flags(of: outlineNode.id).contains(.directory)
                && tree.childCount(of: outlineNode.id) > 0
        }

        func outlineView(
            _ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
        ) {
            guard let descriptor = outlineView.sortDescriptors.first, let key = descriptor.key else {
                return
            }
            sortKey = Self.sortKey(for: key)
            ascending = descriptor.ascending
            childCache.removeAll()
            outlineView.reloadData()
        }

        // MARK: NSOutlineViewDelegate

        func outlineView(
            _ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any
        ) -> NSView? {
            guard let tree, let outlineNode = item as? OutlineNode, let column = tableColumn else {
                return nil
            }
            let id = outlineNode.id
            switch column.identifier.rawValue {
            case "name":
                let cell = reuse(outlineView, NameCellView.reuseIdentifier) { NameCellView() }
                cell.configure(
                    name: tree.name(of: id),
                    isDirectory: tree.flags(of: id).contains(.directory),
                    isDataless: tree.flags(of: id).contains(.dataless))
                return cell
            case "size":
                let cell = reuse(outlineView, SizeBarView.reuseIdentifier) { SizeBarView() }
                cell.fraction = parentRelativeFraction(of: id)
                cell.text = DisplayFormat.bytes(tree.totalAllocatedSize(of: id))
                return cell
            case "items":
                let count = tree.itemCount(of: id)
                return textCell(
                    outlineView, id: "items", text: count > 0 ? DisplayFormat.itemCount(count) : "—")
            case "modified":
                return textCell(
                    outlineView, id: "modified",
                    text: DisplayFormat.relativeModified(epochSeconds: tree.modificationTime(of: id)))
            default:
                return nil
            }
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView else { return }
            let ids = outlineView.selectedRowIndexes.compactMap {
                (outlineView.item(atRow: $0) as? OutlineNode)?.id
            }
            store.selection = Set(ids)
        }

        // MARK: Helpers

        private static func sortKey(for columnKey: String) -> SortKey {
            switch columnKey {
            case "name": return .name
            case "items": return .items
            case "modified": return .modified
            default: return .size
            }
        }

        private func reuse<View: NSView>(
            _ outlineView: NSOutlineView, _ identifier: NSUserInterfaceItemIdentifier,
            make: () -> View
        ) -> View {
            if let existing = outlineView.makeView(withIdentifier: identifier, owner: self) as? View {
                return existing
            }
            let view = make()
            view.identifier = identifier
            return view
        }

        private func textCell(_ outlineView: NSOutlineView, id: String, text: String) -> NSView {
            let identifier = NSUserInterfaceItemIdentifier("text.\(id)")
            let field: NSTextField
            if let existing = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
                field = existing
            } else {
                field = NSTextField(labelWithString: "")
                field.identifier = identifier
                field.font = .systemFont(ofSize: 12)
                field.textColor = .secondaryLabelColor
                field.lineBreakMode = .byTruncatingTail
            }
            field.stringValue = text
            return field
        }
    }
}
