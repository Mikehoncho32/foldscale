import Foundation

/// The column a directory's children are ordered by. Size is the default and is
/// sticky at every depth (handoff §4, rule 2).
public enum SortKey: Sendable, CaseIterable {
    case size
    case name
    case items
    case modified
}

extension FileTree {
    /// The children of `node`, ordered by `key`. Defaults to descending, which is
    /// what "biggest first" wants for size, items, and most-recent for modified.
    public func childrenSorted(
        of node: NodeID,
        by key: SortKey,
        ascending: Bool = false
    ) -> [NodeID] {
        let kids = children(of: node)
        let ordered: [NodeID]
        switch key {
        case .size:
            ordered = kids.sorted { totalAllocatedSize(of: $0) < totalAllocatedSize(of: $1) }
        case .items:
            ordered = kids.sorted { itemCount(of: $0) < itemCount(of: $1) }
        case .modified:
            ordered = kids.sorted { modificationTime(of: $0) < modificationTime(of: $1) }
        case .name:
            ordered = kids.sorted {
                name(of: $0).localizedStandardCompare(name(of: $1)) == .orderedAscending
            }
        }
        return ascending ? ordered : ordered.reversed()
    }
}
