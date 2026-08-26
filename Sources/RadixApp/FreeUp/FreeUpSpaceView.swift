import RadixCore
import SwiftUI

/// The goal flow: "I need X GB" → a ranked checklist of what can go, safest first,
/// pre-ticked to cover the target → one Move to Trash confirmation. Candidates come
/// from the smart lists, so everything here is already classified and explained.
struct FreeUpSpaceView: View {
    let store: ScanStore

    @State private var target: Int64 = FreeUpPlanner.quickTargets[1]  // 10 GB
    @State private var checked: Set<FileTree.NodeID> = []
    @State private var includeReviewFirst = false
    @State private var userAdjusted = false

    var body: some View {
        if let tree = store.tree, store.smartListsAreCurrent {
            let suggestions = FreeUpPlanner.suggestions(from: store.smartLists, in: tree)
            let reclaim = FreeUpPlanner.reclaimTotal(of: checked, in: tree)
            VStack(spacing: 0) {
                header(tree: tree, reclaim: reclaim, suggestions: suggestions)
                Divider()
                if suggestions.isEmpty {
                    emptyState
                } else {
                    list(suggestions, tree)
                }
                Divider()
                actionBar(reclaim: reclaim, tree: tree)
            }
            .onAppear { autoPick(suggestions, tree) }
            .onChange(of: store.generation) { _, _ in
                checked = checked.filter { tree.isLive($0) }
                if !userAdjusted { autoPick(suggestions, tree) }
            }
            .onChange(of: target) { _, _ in
                userAdjusted = false
                autoPick(suggestions, tree)
            }
            .onChange(of: includeReviewFirst) { _, _ in
                userAdjusted = false
                autoPick(suggestions, tree)
            }
        } else {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Looking through your scan…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Header

    private func header(tree: FileTree, reclaim: Int64, suggestions: [SpaceSuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Free up space", systemImage: "sparkles").font(.title3.weight(.semibold))
                Spacer()
                if let volume = store.volume {
                    Text("\(DisplayFormat.bytes(volume.availableCapacity)) free now").foregroundStyle(
                        .secondary)
                }
            }
            HStack(spacing: 10) {
                Text("I need").foregroundStyle(.secondary)
                Picker("Target", selection: $target) {
                    ForEach(FreeUpPlanner.quickTargets, id: \.self) { bytes in
                        Text(DisplayFormat.bytes(bytes)).tag(bytes)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)
                Spacer()
                Toggle("Also pick items marked Review first", isOn: $includeReviewFirst)
                    .toggleStyle(.checkbox)
                    .font(.callout)
            }
            VStack(alignment: .leading, spacing: 4) {
                CapacityBar(segments: [
                    (
                        reclaim >= target ? Color.green.opacity(0.8) : Color.accentColor.opacity(0.75),
                        Double(min(reclaim, target))
                    ),
                    (Color.secondary.opacity(0.12), Double(max(0, target - reclaim))),
                ])
                .frame(height: 10)
                HStack {
                    Text(progressText(reclaim: reclaim)).font(.callout).monospacedDigit()
                    Spacer()
                    if let hint = safeCoverageHint(suggestions, tree: tree, reclaim: reclaim) {
                        Text(hint).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func progressText(reclaim: Int64) -> String {
        if reclaim >= target {
            return "You'll reclaim \(DisplayFormat.bytes(reclaim)) — target reached ✓"
        }
        return "You'll reclaim \(DisplayFormat.bytes(reclaim)) of \(DisplayFormat.bytes(target))"
    }

    /// When the safe items alone can't reach the target, say so and point at the toggle.
    private func safeCoverageHint(_ suggestions: [SpaceSuggestion], tree: FileTree, reclaim: Int64) -> String?
    {
        guard reclaim < target, !includeReviewFirst else { return nil }
        let safe = Set(suggestions.filter { $0.safety == .safeToTrash }.map(\.node))
        let safeTotal = FreeUpPlanner.reclaimTotal(of: safe, in: tree)
        guard safeTotal < target else { return nil }
        return "Safe items cover \(DisplayFormat.bytes(safeTotal)) — include Review first items to go further"
    }

    // MARK: - List

    private func list(_ suggestions: [SpaceSuggestion], _ tree: FileTree) -> some View {
        List {
            ForEach([SmartListSafety.safeToTrash, .reviewFirst], id: \.self) { safety in
                let rows = suggestions.filter { $0.safety == safety }
                if !rows.isEmpty {
                    Section {
                        ForEach(rows) { suggestion in
                            row(suggestion, tree)
                        }
                    } header: {
                        HStack(spacing: 8) {
                            Text(safety == .safeToTrash ? "Safe to remove" : "Review first")
                            SafetyBadge(safety: safety)
                        }
                    }
                }
            }
        }
    }

    private func row(_ suggestion: SpaceSuggestion, _ tree: FileTree) -> some View {
        let isDirectory = tree.flags(of: suggestion.node).contains(.directory)
        let name = tree.name(of: suggestion.node)
        let covered = FreeUpPlanner.hasAncestor(of: suggestion.node, in: checked, tree: tree)
        return Toggle(isOn: binding(for: suggestion.node)) {
            HStack(spacing: 8) {
                Image(systemName: name.hasSuffix(".app") ? "app.fill" : (isDirectory ? "folder.fill" : "doc"))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(location(of: suggestion.node)).lineLimit(1)
                        Text("·")
                        Text(suggestion.source.title)
                        if let note = suggestion.note {
                            Text("·")
                            Text(note).lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(DisplayFormat.bytes(suggestion.bytes))
                    .monospacedDigit()
                    .foregroundStyle(covered ? .tertiary : .secondary)
                    .help(covered ? "Already covered by a folder you ticked" : "")
            }
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 2)
    }

    private func binding(for node: FileTree.NodeID) -> Binding<Bool> {
        Binding(
            get: { checked.contains(node) },
            set: { isOn in
                userAdjusted = true
                if isOn { checked.insert(node) } else { checked.remove(node) }
            })
    }

    /// "~/Downloads" — the parent folder, home-relative.
    private func location(of node: FileTree.NodeID) -> String {
        guard let parent = store.url(for: node)?.deletingLastPathComponent().path else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if parent == home { return "~" }
        return parent.hasPrefix(home + "/") ? "~" + parent.dropFirst(home.count) : parent
    }

    // MARK: - Action bar

    private func actionBar(reclaim: Int64, tree: FileTree) -> some View {
        HStack(spacing: 12) {
            if let trash = trashBytes(tree) {
                Label(
                    "Plus \(DisplayFormat.bytes(trash)) sitting in your Trash — empty it in Finder",
                    systemImage: "trash"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Untick all") {
                userAdjusted = true
                checked = []
            }
            .disabled(checked.isEmpty)
            Button {
                store.selection = checked.filter { tree.isLive($0) }
                store.isConfirmingTrash = true
            } label: {
                Label(
                    "Move \(checked.count) item\(checked.count == 1 ? "" : "s") to Trash"
                        + " (\(DisplayFormat.bytes(reclaim)))",
                    systemImage: "trash")
            }
            .tint(.red)
            .keyboardShortcut(.defaultAction)
            .disabled(checked.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func trashBytes(_ tree: FileTree) -> Int64? {
        guard let entry = store.smartLists[.cachesAndTrash]?.entries(in: "Trash").first,
            tree.isLive(entry.node)
        else { return nil }
        return tree.totalAllocatedSize(of: entry.node)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text("Nothing obvious to clear — nice and tidy").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Auto pick

    private func autoPick(_ suggestions: [SpaceSuggestion], _ tree: FileTree) {
        checked = FreeUpPlanner.greedySelection(
            target: target, from: suggestions, in: tree, includeReviewFirst: includeReviewFirst)
    }
}
