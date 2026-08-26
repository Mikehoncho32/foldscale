import Foundation

// MARK: - Virtual machines

extension SmartListQuery {
    static let vmMinimumBytes: Int64 = 100_000_000
    static let vmGroup = "Virtual machines"
    static let containersGroup = "Containers"

    /// Folders that hold VM documents (`.pvm`, `.vmwarevm`, `.utm`), by tool.
    static let vmDocumentFolders = [
        "Parallels", "Documents/Parallels", "Virtual Machines.localized",
        "Library/Containers/com.utmapp.UTM/Data/Documents",
    ]

    /// Folders whose plain sub-folders are each one machine.
    static let vmMachineFolders = [
        (path: "VirtualBox VMs", tool: "VirtualBox"), (path: ".tart/vms", tool: "Tart"),
    ]

    /// Engine-managed data: trashing it breaks the tool, so it's informational with a
    /// pointer to where the tool itself frees space.
    static let containerEngines: [(path: String, note: String)] = [
        (
            "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw",
            "Docker Desktop disk · shrink it in Docker Desktop › Settings › Resources"
        ),
        (".orbstack", "OrbStack data · manage from OrbStack"),
        ("Library/Group Containers/HUAQ24HBR6.dev.orbstack", "OrbStack data · manage from OrbStack"),
        (".colima", "colima data · `colima delete`"),
    ]

    /// VM documents from Parallels, VMware Fusion, UTM, VirtualBox and Tart (review
    /// first — they're yours to delete), plus the disks behind Docker, OrbStack, Lima
    /// and colima (informational — managed by the tool).
    mutating func virtualMachines() -> ([SmartListEntry], [String]) {
        var seen = Set<FileTree.NodeID>()
        var entries: [SmartListEntry] = []
        entries += vmDocumentEntries(seen: &seen)
        entries += vmMachineEntries(seen: &seen)
        entries += containerEngineEntries(seen: &seen)
        entries += limaEntries(seen: &seen)
        entries += relocatedVMEntries(seen: &seen)
        return (entries, [Self.vmGroup, Self.containersGroup])
    }

    /// `.pvm` / `.vmwarevm` / `.utm` bundles in the folders their tools use.
    private func vmDocumentEntries(seen: inout Set<FileTree.NodeID>) -> [SmartListEntry] {
        var entries: [SmartListEntry] = []
        for folder in Self.vmDocumentFolders {
            guard let root = node(at: home(folder)) else { continue }
            tree.forEachChild(of: root) { child in
                if let entry = vmDocumentEntry(child, seen: &seen) { entries.append(entry) }
            }
        }
        return entries
    }

    /// VirtualBox and Tart keep one plain folder per machine, plus Tart's image cache.
    private func vmMachineEntries(seen: inout Set<FileTree.NodeID>) -> [SmartListEntry] {
        var entries: [SmartListEntry] = []
        for folder in Self.vmMachineFolders {
            guard let root = node(at: home(folder.path)) else { continue }
            tree.forEachChild(of: root) { child in
                guard tree.isDirectory(child), isBigEnough(child), seen.insert(child).inserted else { return }
                entries.append(
                    SmartListEntry(
                        node: child, group: Self.vmGroup, note: "\(folder.tool) · used \(age(of: child))",
                        safety: .reviewFirst))
            }
        }
        if let cache = node(at: home(".tart/cache")), isBigEnough(cache), seen.insert(cache).inserted {
            entries.append(
                SmartListEntry(
                    node: cache, group: Self.vmGroup, note: "Downloaded images; Tart re-pulls them",
                    safety: .reviewFirst))
        }
        return entries
    }

    private func containerEngineEntries(seen: inout Set<FileTree.NodeID>) -> [SmartListEntry] {
        var entries: [SmartListEntry] = []
        for engine in Self.containerEngines {
            guard let node = node(at: home(engine.path)), isBigEnough(node), seen.insert(node).inserted
            else { continue }
            entries.append(
                SmartListEntry(
                    node: node, group: Self.containersGroup, note: engine.note, safety: .informational))
        }
        return entries
    }

    /// `~/.lima/<instance>` (its `_*` folders are config, not machines).
    private func limaEntries(seen: inout Set<FileTree.NodeID>) -> [SmartListEntry] {
        var entries: [SmartListEntry] = []
        guard let lima = node(at: home(".lima")) else { return entries }
        tree.forEachChild(of: lima) { instance in
            let name = tree.name(of: instance)
            guard tree.isDirectory(instance), !name.hasPrefix("_"), isBigEnough(instance),
                seen.insert(instance).inserted
            else { return }
            entries.append(
                SmartListEntry(
                    node: instance, group: Self.containersGroup,
                    note: "Lima instance · `limactl delete \(name)`", safety: .informational))
        }
        return entries
    }

    /// VM documents people moved elsewhere in their home folder (not Library, not
    /// dot-folders), a few levels down.
    private func relocatedVMEntries(seen: inout Set<FileTree.NodeID>) -> [SmartListEntry] {
        var entries: [SmartListEntry] = []
        guard let homeNode = node(at: context.homePath) else { return entries }
        tree.forEachChild(of: homeNode) { child in
            let name = tree.name(of: child)
            guard tree.isDirectory(child), name != "Library", !name.hasPrefix(".") else { return }
            if let entry = vmDocumentEntry(child, seen: &seen) { entries.append(entry) }
            walk(child, maxDepth: 2) { nested in
                if let entry = vmDocumentEntry(nested, seen: &seen) { entries.append(entry) }
            }
        }
        return entries
    }

    private func isBigEnough(_ node: FileTree.NodeID) -> Bool {
        tree.totalAllocatedSize(of: node) >= Self.vmMinimumBytes
    }

    /// A `.pvm` / `.vmwarevm` / `.utm` bundle as a review-first row, once.
    private func vmDocumentEntry(
        _ node: FileTree.NodeID, seen: inout Set<FileTree.NodeID>
    ) -> SmartListEntry? {
        guard tree.isDirectory(node), let tool = Self.vmTool(for: tree.nameUTF8(of: node)),
            isBigEnough(node), seen.insert(node).inserted
        else { return nil }
        return SmartListEntry(
            node: node, group: Self.vmGroup, note: "\(tool) · used \(age(of: node))", safety: .reviewFirst)
    }

    private static func vmTool(for name: ArraySlice<UInt8>) -> String? {
        if SmartListBytes.hasSuffix(name, SmartListBytes.vmBundleSuffixes[0]) { return "Parallels" }
        if SmartListBytes.hasSuffix(name, SmartListBytes.vmBundleSuffixes[1]) { return "VMware Fusion" }
        if SmartListBytes.hasSuffix(name, SmartListBytes.vmBundleSuffixes[2]) { return "UTM" }
        return nil
    }
}
