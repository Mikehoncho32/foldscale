import FoldscaleCore
import SwiftUI

/// First-launch landing (WinDirStat-style): every mounted volume as a card with its
/// used / free capacity and a Scan button. The whole drive is the starting point,
/// and the user chooses when the scan starts — nothing scans unasked.
struct DriveOverviewView: View {
    let store: ScanStore

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Where is your space going?")
                    .font(.title2.weight(.semibold))
                Text("Pick a drive to scan. Foldscale shows every folder's size, biggest first.")
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
                ForEach(volumes, id: \.self) { url in
                    VolumeCard(url: url, isBoot: url.path == "/") { store.openFolder(url) }
                }
            }
            .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private var volumes: [URL] {
        let mounted =
            FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: [.volumeNameKey], options: [.skipHiddenVolumes]) ?? []
        // Boot volume first, then the rest by name.
        return mounted.sorted { lhs, rhs in
            if lhs.path == "/" { return true }
            if rhs.path == "/" { return false }
            return lhs.path < rhs.path
        }
    }
}

/// One volume: name, capacity bar, used / free figures, and the Scan button.
private struct VolumeCard: View {
    let url: URL
    let isBoot: Bool
    let scan: () -> Void

    private var stats: VolumeStats? { VolumeStats.forVolume(containing: url) }
    private var name: String {
        (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? url.lastPathComponent
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isBoot ? "internaldrive.fill" : "externaldrive.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text(name).font(.headline)
                if let stats {
                    CapacityBar(
                        segments: [
                            (Color.accentColor.opacity(0.7), Double(stats.usedCapacity)),
                            (
                                Color.secondary.opacity(0.15),
                                Double(max(0, stats.totalCapacity - stats.usedCapacity))
                            ),
                        ])
                    Text(
                        "\(DisplayFormat.bytes(stats.usedCapacity)) used · "
                            + "\(DisplayFormat.bytes(stats.availableCapacity)) free · "
                            + "\(DisplayFormat.bytes(stats.totalCapacity)) total"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: scan) {
                Label("Scan", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(isBoot ? .defaultAction : nil)
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// The "overall of the whole drive" header shown above the breakdown when the
/// root is focused: one stacked bar — scanned folders · System & other · free —
/// with the figures beneath.
struct DriveOverviewHeader: View {
    let store: ScanStore
    /// Opens the "Free up space" flow (shown as a button beside the figures).
    var onFreeUpSpace: (() -> Void)?

    var body: some View {
        if let tree = store.tree {
            let scanned = tree.totalAllocatedSize(of: tree.rootID)
            let other = store.unscannedVolumeBytes ?? 0
            let free = store.volume?.availableCapacity ?? 0
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(store.rootDisplayName).font(.title3.weight(.semibold))
                    Spacer()
                    if let volume = store.volume {
                        let used = DisplayFormat.bytes(volume.usedCapacity)
                        let total = DisplayFormat.bytes(volume.totalCapacity)
                        Text("\(used) used of \(total)").foregroundStyle(.secondary)
                    }
                    if let onFreeUpSpace {
                        Button(action: onFreeUpSpace) {
                            Label("Free Up Space…", systemImage: "sparkles")
                        }
                        .controlSize(.small)
                    }
                }
                CapacityBar(
                    segments: [
                        (Color.accentColor.opacity(0.75), Double(scanned)),
                        (Color.secondary.opacity(0.45), Double(other)),
                        (Color.secondary.opacity(0.12), Double(free)),
                    ]
                )
                .frame(height: 10)
                HStack(spacing: 16) {
                    legend(
                        color: Color.accentColor.opacity(0.75),
                        label: store.rootIsVolumeRoot ? "Scanned folders" : "This folder", bytes: scanned)
                    if store.rootIsVolumeRoot {
                        legend(color: Color.secondary.opacity(0.45), label: "System & other", bytes: other)
                        legend(color: Color.secondary.opacity(0.25), label: "Free", bytes: free)
                    }
                    Spacer()
                    Text("\(DisplayFormat.itemCount(tree.itemCount(of: tree.rootID))) items")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func legend(color: Color, label: String, bytes: Int64) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
            Text(DisplayFormat.bytes(bytes)).monospacedDigit()
        }
    }
}

/// A proportional stacked bar.
struct CapacityBar: View {
    let segments: [(Color, Double)]

    var body: some View {
        GeometryReader { geometry in
            let total = max(segments.reduce(0) { $0 + $1.1 }, 1)
            HStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Rectangle()
                        .fill(segment.0)
                        .frame(width: max(0, geometry.size.width * segment.1 / total))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
    }
}
