import Foundation
import RadixCore

// A tiny benchmark driver for the ADR-0001 node-layout fork. It scans a path with
// either the struct-of-arrays or the class-per-node layout and prints scan time,
// node/byte totals, and a 50k-child sort time. Peak RSS is measured externally by
// wrapping this in `/usr/bin/time -l` (see Scripts/bench.sh).

func die(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func seconds(since start: DispatchTime) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else { die("usage: radix-bench <soa|class> <path>", code: 2) }
let layout = arguments[1]
let url = URL(fileURLWithPath: arguments[2])

do {
    switch layout {
    case "soa":
        let scanStart = DispatchTime.now()
        let tree = try Scanner.scan(at: url, options: ScanOptions(exclusions: .none))
        let scanSeconds = seconds(since: scanStart)

        // Find the widest directory, then time sorting its children by size.
        var widest = tree.rootID
        var widestChildren = 0
        var node: FileTree.NodeID = 0
        while node < FileTree.NodeID(tree.count) {
            let children = tree.childCount(of: node)
            if children > widestChildren {
                widestChildren = children
                widest = node
            }
            node += 1
        }
        let sortStart = DispatchTime.now()
        let sorted = tree.childrenSortedBySize(of: widest)
        let sortMilliseconds = seconds(since: sortStart) * 1000

        print(
            "layout=soa nodes=\(tree.count) items=\(tree.itemCount(of: tree.rootID)) "
                + "bytes=\(tree.totalAllocatedSize(of: tree.rootID)) "
                + "scan_s=\(String(format: "%.2f", scanSeconds)) "
                + "widest_children=\(widestChildren) sorted=\(sorted.count) "
                + "sort_ms=\(String(format: "%.2f", sortMilliseconds))"
        )

    case "class":
        let scanStart = DispatchTime.now()
        let root = try Scanner.scanClassTree(at: url, options: ScanOptions(exclusions: .none))
        let scanSeconds = seconds(since: scanStart)
        let nodes = (root?.itemCount ?? 0) + 1
        print(
            "layout=class nodes=\(nodes) bytes=\(root?.totalSize ?? 0) "
                + "scan_s=\(String(format: "%.2f", scanSeconds))"
        )

    case "cache":
        let tree = try Scanner.scan(at: url, options: ScanOptions(exclusions: .none))
        let snapshot = ScanSnapshot(rootPath: url.path, savedAt: Date(), tree: tree)

        let plistEncoder = PropertyListEncoder()
        plistEncoder.outputFormat = .binary
        let binary = try plistEncoder.encode(snapshot)
        let binaryLoadStart = DispatchTime.now()
        _ = try PropertyListDecoder().decode(ScanSnapshot.self, from: binary)
        let binaryLoadMs = seconds(since: binaryLoadStart) * 1000

        let json = try JSONEncoder().encode(snapshot)
        let jsonLoadStart = DispatchTime.now()
        _ = try JSONDecoder().decode(ScanSnapshot.self, from: json)
        let jsonLoadMs = seconds(since: jsonLoadStart) * 1000

        let compressed = try (binary as NSData).compressed(using: .lzfse) as Data
        let lzfseLoadStart = DispatchTime.now()
        let decompressed = try (compressed as NSData).decompressed(using: .lzfse) as Data
        _ = try PropertyListDecoder().decode(ScanSnapshot.self, from: decompressed)
        let lzfseLoadMs = seconds(since: lzfseLoadStart) * 1000

        print(
            "cache nodes=\(tree.count) "
                + "binary_bytes=\(binary.count) binary_load_ms=\(String(format: "%.0f", binaryLoadMs)) "
                + "json_bytes=\(json.count) json_load_ms=\(String(format: "%.0f", jsonLoadMs)) "
                + "lzfse_bytes=\(compressed.count) lzfse_load_ms=\(String(format: "%.0f", lzfseLoadMs))")

    default:
        die("unknown layout '\(layout)' (expected soa, class, or cache)", code: 2)
    }
} catch {
    die("scan failed: \(error)", code: 1)
}
