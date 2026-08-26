import FoldscaleCore
import Foundation

/// Dev hook: `FOLDSCALE_DUMP_LISTS=1` prints every smart-list row to stderr once the
/// lists are computed, so a list can be checked against a real scan without
/// clicking through the UI (false-positive hunting for App leftovers, etc.).
enum SmartListDump {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["FOLDSCALE_DUMP_LISTS"] != nil }

    static func printIfRequested(
        _ results: [SmartListKind: SmartListResult], tree: FileTree, context: SmartListContext
    ) {
        guard isEnabled else { return }
        var lines: [String] = []
        for kind in SmartListKind.allCases {
            guard let result = results[kind] else { continue }
            lines.append(
                "== \(kind.rawValue) · \(DisplayFormat.bytes(result.displayBytes)) · \(result.entries.count) rows"
            )
            for entry in result.entries {
                let path = context.displayPath(context.absolutePath(of: entry.node, in: tree))
                lines.append(
                    [
                        kind.rawValue, entry.group, path, entry.displayName ?? "", entry.note ?? "",
                        entry.safety.label, DisplayFormat.bytes(tree.totalAllocatedSize(of: entry.node)),
                    ].joined(separator: " | "))
            }
        }
        lines.append("== FOLDSCALE_DUMP_LISTS done")
        FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    }
}
