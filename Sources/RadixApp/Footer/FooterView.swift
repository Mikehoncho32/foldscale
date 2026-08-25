import RadixCore
import SwiftUI

/// The always-present footer: a stats line (selection / totals and freshness on the
/// left, volume space on the right, incl. the APFS purgeable figure — §4 rule 6 /
/// §5.11) and an actions line. "Move to Trash" is one click away but
/// danger-tinted (rule 6).
struct FooterView: View {
    let store: ScanStore
    let bridge: OutlineBridge

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(leftText)
                FreshnessLabel(store: store)
                Spacer()
                if let volume = store.volume {
                    Text(volumeText(volume))
                }
            }
            HStack(spacing: 8) {
                Spacer()
                Button {
                    bridge.quickLook()
                } label: {
                    Label("Quick Look", systemImage: "eye")
                }
                Button {
                    FileActions.reveal(store.urls(for: store.selection))
                } label: {
                    Label("Reveal in Finder", systemImage: "arrow.up.forward.app")
                }
                Button {
                    store.isConfirmingTrash = true
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
                .tint(.red)
            }
            .disabled(store.selection.isEmpty)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var leftText: String {
        if !store.selection.isEmpty {
            return "\(store.selection.count) selected · \(DisplayFormat.bytes(store.selectedTotalBytes))"
        }
        if let tree = store.tree {
            let items = DisplayFormat.itemCount(tree.itemCount(of: tree.rootID))
            return "\(items) items · \(DisplayFormat.bytes(tree.totalAllocatedSize(of: tree.rootID)))"
        }
        return ""
    }

    private func volumeText(_ volume: VolumeStats) -> String {
        var text =
            "\(DisplayFormat.bytes(volume.usedCapacity)) used of "
            + "\(DisplayFormat.bytes(volume.totalCapacity)) · "
            + "\(DisplayFormat.bytes(volume.availableCapacity)) free"
        if volume.purgeable > 0 {
            text += " (+ \(DisplayFormat.bytes(volume.purgeable)) purgeable)"
        }
        return text
    }
}

/// "Updated just now / 5 minutes ago / 3 days ago" for the focused folder. Ticks
/// once a minute so it stays truthful while the window sits open.
private struct FreshnessLabel: View {
    let store: ScanStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if store.isRefreshing {
                Text("· Updating…").foregroundStyle(.tertiary)
            } else if store.tree != nil, let when = store.freshness(of: store.focusedNode) {
                Text("· Updated \(Self.relative(when, now: context.date))").foregroundStyle(.tertiary)
            }
        }
    }

    private static func relative(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
