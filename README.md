<h1 align="center">Radix</h1>

<p align="center">
  <strong>A Finder-native disk space analyzer for macOS.</strong><br>
  No treemap by default. It looks like Finder because you already know how to use Finder.
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.10%2B-orange?logo=swift">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue">
  <em>&nbsp;· Status: v1.1 — signed and notarized releases</em>
</p>

<!-- TODO: add a screenshot of the drive view + Free up space. -->

---

## Why Radix

Every folder shows how much space it's eating, everything is sorted biggest-first at every level, and
you can send things to the Trash right from the list. A disk analyzer for people who don't want a
nerd tool.

Existing open-source analyzers lead with a chart and treat the file list as an afterthought. Radix
inverts that: a **Finder-identical list view is the product**. The size bar next to each row is
**relative to its parent folder**, so you can drill down without losing scale — the one thing that
separates this from "Finder with a size column."

- **Sort by size, sticky at every depth.** Name / Items / Modified are there too, but size is where you land.
- **Allocated size, not logical size** — what actually frees up when you delete.
- **Cloud-aware.** iCloud/Dropbox online-only placeholders show their real local footprint with a badge; Radix never silently downloads them.
- **Task-oriented lists** live in the sidebar as places you go — *Downloads*, *Caches & Trash*, *Developer junk*, *Apps & games*, *Big projects*, *Videos & recordings* — each with a safety badge.
- **Free up space.** Say how much you need; Radix pre-ticks the safest candidates to cover it, you adjust, one confirmation.
- **Always current.** The last scan opens instantly and refreshes in the background; the folder you click is re-checked on the spot.
- **Safe by construction.** Every delete routes through the system Trash with a confirmation sheet — never a permanent delete. Protected system paths refuse to be trashed.

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel

## Install

Download **`Radix-<version>.dmg`** from the [latest release](../../releases/latest), open it, and
drag **Radix** into your Applications folder, then double-click it. Releases from v1.1.0 on are
signed with a Developer ID and notarized by Apple, so there's no Gatekeeper warning.

> Running an older unsigned build (v1.0.0)? **Right-click Radix → Open** the first time.

### Full Disk Access

Radix reads file sizes across your disk, which macOS gates behind **Full Disk Access**. On first run
Radix detects whether it has been granted and, if not, walks you to
**System Settings → Privacy & Security → Full Disk Access**. Nothing leaves your machine — Radix has
no network code and no telemetry.

### Why no sandbox?

A disk analyzer needs to see the *whole* disk. The App Store sandbox fundamentally can't allow that,
so Radix ships **outside the App Store** as a notarized, hardened-runtime app and relies on
user-granted Full Disk Access (a TCC permission, not an entitlement) instead. This is a deliberate,
documented trade-off — see [`docs/decisions/`](docs/decisions).

## Build from source

```bash
# Prerequisites: Xcode 15+, and (for the app target) xcodegen — `brew install xcodegen`
git clone https://github.com/Mikehoncho32/radix.git
cd radix

# Run the engine's unit tests (Foundation-only, no Xcode UI needed):
swift test

# Generate the Xcode project and build the app:
xcodegen generate
xcodebuild -project Radix.xcodeproj -scheme RadixApp -destination 'platform=macOS' build
```

The generated `Radix.xcodeproj` is intentionally **not** checked in — `project.yml` (xcodegen) is the
source of truth so CI can build from a clean checkout.

## Architecture

Radix is split into two pieces:

- **`RadixCore`** — a Foundation-only Swift package: the recursive `fts`-based scanner, the file-node
  model, exclusion rules, smart-list queries, the scan cache, and safe file actions. **Zero UI
  dependencies** (enforced by a test), so it is fully unit-tested in isolation via `swift test`.
- **`RadixApp`** — the SwiftUI + AppKit macOS app (built via xcodegen + xcodebuild).

Performance and design forks (node memory layout, tree-view backend, cache format) are decided by
benchmark and recorded as ADRs in [`docs/decisions/`](docs/decisions).

## Roadmap

| Milestone | What |
|---|---|
| 0 | Repo + skeleton, CI, empty app launches |
| 1 | Scanner core: `fts` walk, allocated-size aggregation, hardlink dedupe |
| 2 | Outline view with parent-relative size bars, size sort, progressive scan |
| 3 | Quick Look · Reveal · Copy Path · Get Info · Move to Trash (+ live re-total) |
| 4 | Full Disk Access onboarding, protected paths, cloud placeholders |
| 5 | Smart lists + scan-cache persistence |
| 6 | v1.0: sidebar, footer stats, icon, DMG, release |
| 1.1 | Drive tree sidebar, live refresh, drive overview, task-oriented smart lists, Free up space, notarized DMG |

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) and our
[Code of Conduct](CODE_OF_CONDUCT.md). The `docs/decisions/` ADRs explain *why* things are the way
they are; please read the relevant one before proposing a change to scanner or UI internals.

## License

[MIT](LICENSE) © 2026 Radix contributors.
