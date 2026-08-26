# ADR-0006: Size history — a thinned ledger of directory sizes beside the scan cache

- **Status:** Accepted
- **Date:** 2026-08-26

## Context

"What grew" answers the question people actually ask when a disk fills up — *what changed?* —
which needs sizes from an earlier day. The scan cache (ADR-0003) keeps exactly one snapshot and
is overwritten on every save; retaining whole trees (tens of MB each) for weeks is out of the
question, and a full per-node diff would be slow and mostly noise (every leaf that changed by a
few bytes).

## Decision

- A separate, small file: `~/Library/Application Support/Foldscale/size-history.plist`, a binary
  property list of `SizeHistory { formatVersion, rootPath, snapshots }`, one history per scan root.
  It lives in `FoldscaleCore/Persistence` next to `ScanCache` and reuses its directory (and its
  test override), so tests never touch the real file.
- A **snapshot** is `[rootRelativePath: bytes]` for directories down to depth 5 that are at least
  50 MB, capped at the 3 000 largest. A child never outweighs its parent, so pruning below the
  floor loses nothing that could later show up as growth ≥ 500 MB.
- **Thinning** on every record: one snapshot per calendar day; everything from the last 14 days,
  then one per ≥ 6 days, nothing older than 90 days. Worst case ≈ 18–25 snapshots × 3 000 entries,
  a few MB.
- Recording happens on the existing debounced persist path (after `ScanCache.save`, on the persist
  queue), never in demo mode. Today's snapshot is never a baseline, so recording never triggers a
  recompute.
- **What grew** compares the current tree (captured with the same rules) against three baselines —
  a week ago (or the oldest earlier day while the history is young), a month ago, and the oldest
  snapshot — puts each directory into the first window where it grew ≥ 500 MB, and drops an
  ancestor when a listed descendant explains ≥ 80 % of its growth. Rows rank by growth
  (`SmartListEntry.sortBytes`), so the sidebar total is total growth. The list is informational.

Rejected: keeping previous `last-scan.foldscalecache` files (tens of MB each, and diffing whole
trees); storing history inside the scan cache (would bump ADR-0003's format for a feature that
must survive cache resets); FSEvents-based change tracking (answers "what is changing now", not
"what grew since last week", and is a separate decision).

## Consequences

- The list is empty until the app has been used on two different days; the sidebar hides it
  until then.
- Folders below 50 MB or deeper than five levels never appear on their own; their growth shows on
  the nearest recorded ancestor.
- A change of scan root starts a fresh history (`rootPath` mismatch), as does a format bump.
- Users who reset the cache keep their history; deleting `size-history.plist` resets it. The
  Homebrew cask's `zap` covers the whole folder.
