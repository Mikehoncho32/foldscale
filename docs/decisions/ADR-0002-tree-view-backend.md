# ADR-0002: Tree-view backend — NSOutlineView, not SwiftUI Table

- **Status:** Accepted
- **Date:** 2026-08-24

## Context

The main view is a Finder-style tree that must stay at 60 fps with tens of
thousands of visible/expandable rows, custom size-bar cells, and live updates
(handoff §7). The two candidates:

1. **SwiftUI `Table` + `OutlineGroup`** — pure SwiftUI, least code.
2. **`NSOutlineView`** wrapped in `NSViewRepresentable` — AppKit, more glue.

## Decision

**Use `NSOutlineView`** (see `FileOutlineView`).

The deciding factor is **row virtualization**. `NSOutlineView` realizes and
recycles only the row views currently on screen (plus a small buffer) — the same
mechanism Finder and Xcode's navigator use — so per-frame work is bounded by the
number of *visible* rows (~30), independent of tree size. Our implementation
leans on this via `makeView(withIdentifier:)` reuse for every cell.

SwiftUI `Table`/`OutlineGroup`, by contrast, materializes all rows up front and
re-diffs them on updates; the community documents visible jitter beyond ~2,000
rows and a scroll-performance regression on macOS 15.5 that remains unresolved.
For a disk tool where a single directory can hold 50k+ entries, that is
disqualifying.

## Results / evidence

- **Architectural guarantee:** with row recycling, frame cost is O(visible rows),
  not O(total rows) — the property that makes 50k-row directories scroll smoothly.
- **Prior art:** first-party apps (Finder, Xcode) use `NSOutlineView` for exactly
  this shape of data.
- **Research:** Apple Developer Forums (macOS 15.5 Table scroll regression); Swift
  community reports of SwiftUI list/table jitter past ~2k rows and full-row
  initialization.
- **Verified here:** the app builds and scans real folders correctly (the in-app
  `/bin` scan matches `du` exactly). A precise 50k-row *frame-time* capture was not
  automatable in this environment (Instruments + Screen Recording aren't available
  to the headless runner); the recycling model above is the basis for the fps
  claim, and interactive scroll smoothness is a manual check when running the app.

## Consequences

- **Accepted:** an `NSViewRepresentable` + coordinator (data source/delegate) is
  more code than SwiftUI `Table`, and value-type `FileTree` nodes are bridged to
  `NSOutlineView`'s object-identity model via a small cached `OutlineNode` wrapper.
- Size-sort is applied in the data source and is global, so it stays sticky at
  every depth (handoff §4, rule 2).
- Column re-sorting uses the native header `sortDescriptors`.
- Revisit only if a future SwiftUI release ships true row virtualization for
  hierarchical data.
