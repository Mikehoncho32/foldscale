import RadixCore
import SwiftUI

/// The always-present footer: current selection total on the left, volume space on
/// the right, including the APFS purgeable figure that explains why Radix's free
/// number can differ from Finder's (handoff §4, rule 6 · §5.11).
struct FooterView: View {
    let store: ScanStore

    var body: some View {
        HStack(spacing: 8) {
            Text(leftText)
            Spacer()
            if let volume = store.volume {
                Text(volumeText(volume))
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
