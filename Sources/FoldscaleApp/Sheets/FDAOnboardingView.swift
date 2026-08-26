import AppKit
import FoldscaleCore
import SwiftUI

/// A dismissible banner shown when a scan hit unreadable folders and Full Disk
/// Access isn't granted (handoff §5.7).
struct FDABanner: View {
    let store: ScanStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)
            Text(message)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Grant…") { store.isShowingFDAOnboarding = true }
            Button {
                store.fdaBannerDismissed = true
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    private var message: String {
        let count = store.deniedDirectories
        return "\(count) folder\(count == 1 ? "" : "s") couldn't be read. "
            + "Grant Full Disk Access for complete results."
    }
}

/// Full Disk Access onboarding (handoff §5.7): explains why it's needed, deep-links
/// to the System Settings pane, and polls until access is granted — then offers a
/// rescan. macOS provides no grant callback, hence the poll.
struct FDAOnboardingView: View {
    let store: ScanStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Full Disk Access", systemImage: "lock.shield")
                .font(.headline)

            Text(
                "Foldscale reads file sizes across your disk. macOS keeps some folders — Mail, "
                    + "Messages, Time Machine, other apps' data — behind Full Disk Access, so parts "
                    + "of a scan can come back incomplete without it. Nothing about your files leaves your Mac."
            )
            .fixedSize(horizontal: false, vertical: true)

            Text("Open the setting below, enable Foldscale in the list, then return here.")
                .foregroundStyle(.secondary)

            if store.fdaGranted {
                Label("Full Disk Access is granted.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            HStack {
                Button("Open Full Disk Access Settings") { openSettings() }
                Spacer()
                if store.fdaGranted {
                    Button("Rescan") {
                        store.rescan()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done") { dismiss() }
                }
            }
        }
        .padding(20)
        .frame(width: 470)
        .task { await pollUntilGranted() }
    }

    private func openSettings() {
        guard let url = URL(string: FullDiskAccess.settingsURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func pollUntilGranted() async {
        while !Task.isCancelled, !store.fdaGranted {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            store.refreshFDA()
        }
    }
}
