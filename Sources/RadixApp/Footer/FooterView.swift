import RadixCore
import SwiftUI

/// The always-present footer: a stats line (selection / totals and freshness on the
/// left, volume space on the right, incl. the APFS purgeable figure — §4 rule 6 /
/// §5.11) and an actions line. "Move to Trash" is one click away but
/// danger-tinted (rule 6).
struct FooterView: View {
    let store: ScanStore
    let bridge: OutlineBridge
    @State private var isShowingSpaceInfo = false

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
                Group {
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
                Button {
                    isShowingSpaceInfo.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("What do free, purgeable and used mean?")
                .popover(isPresented: $isShowingSpaceInfo, arrowEdge: .bottom) {
                    SpaceInfoPopover(volume: store.volume)
                }
            }
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

/// Explains the footer's space figures — and why Finder's "available" number is
/// bigger: it counts purgeable space, which macOS reclaims on its own and which
/// deleting files in Radix can't touch.
private struct SpaceInfoPopover: View {
    let volume: VolumeStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About these numbers").font(.headline)
            row(
                "Used", volume.map { DisplayFormat.bytes($0.usedCapacity) },
                "Everything on the drive right now — what the list above breaks down.")
            row(
                "Free", volume.map { DisplayFormat.bytes($0.availableCapacity) },
                "Space you can write to this second.")
            row(
                "Purgeable", volume.map { DisplayFormat.bytes($0.purgeable) },
                "Counted as used today, but macOS deletes it by itself when space runs low: "
                    + "local Time Machine snapshots, photos and iCloud files that also live in the cloud, "
                    + "and caches apps have marked disposable. You can't free it by deleting files here, "
                    + "and you don't need to.")
            Text(
                "Finder's \"Available\" adds free and purgeable together, which is why its number is bigger."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 360)
    }

    private func row(_ label: String, _ value: String?, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).fontWeight(.semibold)
                if let value { Text(value).monospacedDigit().foregroundStyle(.secondary) }
            }
            Text(detail).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
