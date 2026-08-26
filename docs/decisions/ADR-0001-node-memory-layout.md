# ADR-0001: File-node memory layout — struct-of-arrays

- **Status:** Accepted
- **Date:** 2026-08-24

## Context

The scanner must hold a whole-disk tree in memory — up to ~1–2M nodes — while
staying responsive. Handoff §7 sets hard targets: **< 150 MB RSS for a 1M-node
tree** and **sorting a 50k-child directory by size in < 16 ms**, and asks us to
benchmark two layouts and record the result:

1. **Class-per-node** — a reference tree (`ClassFileNode` with a `children` array).
   Ergonomic, natural recursion, but one heap object + ARC + a child array per node.
2. **Struct-of-arrays (SoA)** — parallel arrays (`parent`, `firstChild`,
   `nextSibling`, sizes, flags, …) indexed by an `Int32` node id, with all names
   packed into one shared UTF-8 buffer referenced by `(offset, length)`.

Both are implemented behind the `TreeBuilder` protocol so one walk drives either
(`FileTreeBuilder` vs `ClassTreeBuilder`), and `foldscale-bench` measures them on the
same fixture.

## Decision

**Use the struct-of-arrays layout (`FileTree`) as the shipping tree**, built with
**capacity reservation** via a fast `readdir`-only pre-count.

The pre-count matters: the first measurement showed naive SoA *losing*, because
appending to 12 parallel arrays without reserving capacity leaves ~2× geometric
growth overhead. Reserving exact capacity removes that overhead and the SoA wins
clearly.

## Results

Environment: Apple Silicon (arm64), macOS 26.5, Swift 6.3.3 **release** build,
warm cache. Fixture: ~1.06M nodes (empty files, so byte totals are 0 — this
benchmark isolates *structure* memory and scan speed; size correctness is covered
separately by the `du`-parity unit tests).

| Layout | Peak RSS | vs 150 MB target | Scan (1.06M) | Sort 50k children |
|---|---|---|---|---|
| **SoA + capacity reserve** | **82.1 MiB** (86,048,768 B) | ✅ 45% under | 18.9 s | **0.14 ms** |
| Class-per-node | 119.6 MiB (125,386,752 B) | ✅ under | 19.0 s | — |
| SoA, *no* reserve (rejected) | 150.0 MiB (157,319,168 B) | ❌ over | 15.4 s | 0.22 ms |

All targets met by SoA + reserve: **82 MiB < 150 MB**, **0.14 ms ≪ 16 ms**, and
**18.9 s ≪ 60 s** for > 1M nodes.

## Consequences

- **Accepted:** index-based traversal (no reference identity, no ARC) is less
  ergonomic than pointers, but the accessor API (`children(of:)`, `path(of:)`,
  `totalAllocatedSize(of:)`) hides it, and the value-type tree is trivially
  `Sendable` and cheap to serialize for the scan cache (ADR-0003, Milestone 5).
- **Accepted:** a `readdir`-only pre-count pass costs ~15–20% scan time (both
  layouts pay it here) in exchange for meeting the memory target; it also warms the
  cache for the real pass. A future single-pass chunked allocator could remove it.
- The class layout is kept only as the benchmark baseline (`Scanner.scanClassTree`).
- The margin (82 vs 150 MB) leaves headroom for real filenames and 2M-node disks,
  where SoA's shared name buffer scales better than per-node `String`s.
