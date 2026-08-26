# ADR-0004: Directory traversal — `readdir`/`fstatat`, not `fts(3)`

- **Status:** Accepted
- **Date:** 2026-08-24

## Context

The handoff (§6) suggested starting the scanner from BSD `fts(3)` with
`FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV`, citing MacDirStat as the validation that
`fts` beats `FileManager.enumerator`. Two things surfaced during Milestone 1:

1. **MacDirStat itself no longer uses `fts`.** Its current scanner uses
   `opendir`/`readdir` + `fstatat(…, AT_SYMLINK_NOFOLLOW)`, closing each directory
   handle before recursing. The "`fts` is faster than `FileManager`" comparison was
   never "`fts` vs `readdir`."
2. **`fts` has real friction in Swift:** `fts_name` is a C flexible-array member
   that imports awkwardly, and `FTS_XDEV`'s device-boundary semantics interact
   subtly with firmlinks and synthetic `/System/Volumes` mounts (flagged in the plan).

The handoff also explicitly delegated these engineering calls ("give me numbers and
your recommendation… flag anything wrong").

## Decision

Traverse with **`opendir` / `readdir` / `fstatat`**, single-threaded depth-first,
closing each directory before descending (bounding open file descriptors).

- `fstatat(dirfd, name, &st, AT_SYMLINK_NOFOLLOW)` gives metadata without building
  full paths per file and without following symlinks (the `FTS_PHYSICAL` equivalent).
- The cross-volume boundary is handled explicitly via an allowed-device set
  (`ScanOptions.stayOnStartVolume`, `VolumePolicy`) rather than `FTS_XDEV`, so the
  policy is visible and testable. A scan rooted at `/` also admits the Data volume's
  device, so firmlinked user folders (`/Users`, `/Applications`, `/Library`) are
  included even on macOS releases where they report a different `st_dev` than `/`.
  Validated on-device (macOS 26.5): those paths share `/`'s device here, so the
  allowance is a no-op today and a safety net elsewhere.
- Directory inodes are deduped by `(st_dev, st_ino)` (guarding against firmlink/cycle
  double-visits); hard-linked files are deduped the same way.

**Metadata-only guarantee:** the walker calls `lstat`/`fstatat` but never `open`s or
reads file contents, so scanning a cloud-backed (`SF_DATALESS`) folder cannot trigger
a download. This is the safety-critical property from the plan's §2.2.

## Consequences

- **Accepted:** single-threaded for now. `readdir`+`fstatat` scans ~1.06M nodes in
  ~19 s warm (ADR-0001) — well under the 60 s target — so parallelism (per-subtree
  `TaskGroup`, as MacDirStat does) is deferred; it complicates SoA index assignment
  and isn't needed to hit the target. Revisit if larger disks demand it.
- **Accepted:** deviates from the handoff's `fts` suggestion. The walk is isolated in
  `DirectoryWalker`, so switching to `fts` later is contained.
- Names are read from `dirent.d_name` via `withUnsafeBytes`, avoiding the `fts_name`
  flexible-array idiom entirely.

## Addendum (2026-08-25): subtree refresh

`ScanOptions.volumePolicyRoot` lets a subtree scan (used for click-to-refresh) reuse the
full scan's allowed-device set, so refreshing `/usr` keeps the firmlinked `/usr/local`.
`ScanOptions.capacityHint` skips the `readdir` pre-count when a previous count is known.
A subtree scan starts with an empty hard-link `seen` set, so a link first seen outside the
subtree is counted again inside it until the next full refresh — accepted drift.
