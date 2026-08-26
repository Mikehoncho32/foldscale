# ADR-0003: Scan-cache format — LZFSE-compressed binary property list

- **Status:** Accepted
- **Date:** 2026-08-24

## Context

Foldscale persists the last scan so a relaunch shows results without a rescan (handoff
§5, item 10), stored in Application Support (§11 decision — survives cache purges).
The tree is a struct-of-arrays (`FileTree`, ADR-0001). Handoff §7 asks us to pick a
format by benchmark, target **load < 2 s for 1M nodes**, comparing SQLite vs flat
binary vs Codable + compression.

Because `FileTree` is already parallel arrays of trivial values, the natural
encoding is one **raw-bytes `Data` blob per array** (a `memcpy`, no per-element
work). `FileTree`'s `Codable` conformance does exactly that; the only question is
the envelope and whether to compress.

## Decision

Persist as a **binary property list of the raw-array blobs, LZFSE-compressed**
(`ScanCache`).

SQLite is rejected: it shines for incremental/partial queries, but Foldscale reloads
the *whole* tree at once, where a single flat blob is simpler, dependency-free, and
faster. JSON is rejected: base64-ing the blobs inflates size and load time.

## Results

Environment: Apple Silicon, macOS 26.5, Swift 6.3.3 release, 1,060,102 nodes.

| Format | On-disk size | Load time | vs 2 s target |
|---|---|---|---|
| Binary plist (blobs) | 62.4 MiB | 8 ms | ✅ |
| **Binary plist + LZFSE** | **5.8 MiB** | **41 ms** | ✅ |
| JSON (naive Codable) | 99.4 MiB | 311 ms | ✅ but 17× larger, 7× slower |

LZFSE is ~10× smaller than uncompressed for +33 ms — and load stays **~50× under**
the 2 s target. (This fixture is empty files with repetitive names, so it compresses
unusually well; real trees compress less, but LZFSE still shrinks the cache
materially at negligible load cost.)

## Consequences

- A disk-analysis tool shouldn't itself hog disk; **5.8 MiB beats 62 MiB** for the
  cache, and 41 ms is imperceptible on relaunch.
- No third-party dependency (LZFSE + property lists are in the SDK).
- The format is a raw memory image of the arrays, so it is **version-fragile**: a
  layout change must bump a format version / invalidate old caches. `load()` already
  fails soft (returns `nil`) on any decode error, forcing a fresh scan.
- Native-endian and machine-local by design (the cache never travels between Macs).
