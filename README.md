<h1 align="center">Radix</h1>

<p align="center">
  <strong>A Finder-native disk space analyzer for macOS.</strong><br>
  No treemap by default. It looks like Finder because you already know how to use Finder.
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.10%2B-orange?logo=swift">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue">
  <em>&nbsp;· Status: pre-release, in active development (Milestone 0)</em>
</p>

<!-- TODO: replace with a real screenshot once the outline view lands (Milestone 2). -->
<p align="center"><em>Screenshot coming with Milestone 2.</em></p>

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
- **Smart lists** live in the sidebar as places you go: *Large files*, *Old and big*.
- **Safe by construction.** Every delete routes through the system Trash with a confirmation sheet — never a permanent delete. Protected system paths refuse to be trashed.

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel

## Install

> Radix has not shipped its first release yet. When it does, this section links a notarized DMG from
> [GitHub Releases](../../releases); a Homebrew cask follows in v1.1. Until then, build from source below.

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
| 0 | Repo + skeleton, CI, empty app launches ← **you are here** |
| 1 | Scanner core: `fts` walk, allocated-size aggregation, hardlink dedupe |
| 2 | Outline view with parent-relative size bars, size sort, progressive scan |
| 3 | Quick Look · Reveal · Copy Path · Get Info · Move to Trash (+ live re-total) |
| 4 | Full Disk Access onboarding, protected paths, cloud placeholders |
| 5 | Smart lists + scan-cache persistence |
| 6 | v1.0: sidebar, footer stats, icon, notarized DMG, release |

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) and our
[Code of Conduct](CODE_OF_CONDUCT.md). The `docs/decisions/` ADRs explain *why* things are the way
they are; please read the relevant one before proposing a change to scanner or UI internals.

## License

[MIT](LICENSE) © 2026 Radix contributors.
