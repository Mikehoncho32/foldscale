# HANDOFF — "Tidy" (working name): a Finder-native disk space analyzer for macOS

> **For Claude Code:** Read this whole file, then enter **plan mode** and produce a plan before writing any code. Once the plan is approved, initialize the GitHub repo (§10) and start on Milestone 0. This is going to be an open-source project — write code and docs as if strangers will read them from day one.

---

## 1. One-line pitch

Finder, but every folder shows how much space it's eating, everything is sorted biggest-first at every level, and you can send stuff to the Trash right from the list. A disk analyzer for people who don't want a nerd tool.

## 2. Why this exists — the competitive landscape (researched Aug 2026)

Every existing open-source macOS analyzer leads with a chart and treats the file list as secondary. None of them look or behave like Finder. That gap is the whole product.

| Tool | Type | Primary view | Why it's not this project |
|------|------|--------------|---------------------------|
| **MacDirStat** (github.com/phalladar/MacDirStat) | OSS, SwiftUI, `fts` scanner | Treemap + tree pane, WinDirStat layout | Chart-first. Same WinDirStat aesthetic we're moving away from. **Required reading** — steal their scanner approach, they already benchmarked `fts` vs `FileManager`. |
| **OpenDisk** (opendisk.app) | OSS, MIT | Sunburst (DaisyDisk clone) | Chart-first, requires macOS 26 |
| **StorageScope** (rasputinkaiser.github.io/StorageScope) | OSS, sandboxed | Ranked lists + duplicate finder + cleanup planner | Not a directory browser; more of a cleanup wizard. Good reference for the review-before-trash flow. |
| **DiskPilot** | OSS, MIT, cross-platform | Chart | Cross-platform = not native |
| **GrandPerspective** | OSS, GPL, maintained | Treemap only | No list view at all |
| **OmniDiskSweeper** | Free, closed | Column view sorted by size | Closest UX ancestor. Dated, no size bars, no progressive scan, no smart lists. **Beat this.** |
| **DuckDisk** | Commercial, closed | Dense table-first | Nearest to our concept, but paid and closed-source |
| **DaisyDisk** | Commercial | Sunburst | Best-in-class FDA onboarding; copy that flow, not the chart |

**Positioning statement for the README:** "No treemap by default. It looks like Finder because you already know how to use Finder."

## 3. Product decisions (already made — don't re-litigate)

**Standalone native macOS app in Swift/SwiftUI.**

- Not a Finder extension: `FinderSync` extensions can only add badges, toolbar buttons, and context-menu items. They cannot render custom views. We'll ship a Finder Quick Action ("Analyze with Tidy") as an *entry point* in v1.1, not as the product.
- Not Electron/Tauri: the entire value prop is "feels like Finder." Native gives us `NSOutlineView`, Quick Look, drag & drop, sidebar vibrancy, system Trash, and Full Disk Access prompting for free. Windows/Linux are explicit non-goals.

**Stack:**
- Swift 5.10+, SwiftUI with AppKit interop where SwiftUI is weak (expect `NSOutlineView` via `NSViewRepresentable` for the main tree — SwiftUI `Table`/`OutlineGroup` will likely not hit perf targets at 1M+ nodes; benchmark first, see §7)
- macOS 14 (Sonoma) minimum
- Swift Package Manager only, no CocoaPods
- `xcodegen` (project.yml checked in, .xcodeproj gitignored) so CLI builds via `xcodebuild` work in CI
- Scanner is a separate SPM target `TidyCore` with **zero UI dependencies** — Foundation only, fully unit-tested
- Sandbox **off** for v1. A disk analyzer needs real filesystem access; Full Disk Access handles permissions. Document this in the README. Distribution is direct download (DMG, notarized) + Homebrew cask, not App Store.
- License: MIT

## 4. UX spec — "Finder, but it knows about size"

A rendered mockup of this layout was approved. Match it.

### Window layout
```
┌──────────────┬────────────────────────────────────────────────────────────┐
│ ● ● ●  [◀ ▶]  Macintosh HD › Users › jordan          [⟳ Rescan] [Filter] [🔍] │
├──────────────┼────────────────────────────────────────────────────────────┤
│ Favorites    │  Name                          Size ▼        Items   Modified │
│  jordan   ●  │  ▾ 📁 Library          ████████░░░  142.3 GB  812,404   Today  │
│  Downloads   │      ▸ 📁 Caches       ██████░░░░░   68.1 GB  402,118   Today  │
│  Desktop     │      ▸ 📁 Developer    ████░░░░░░░   44.6 GB  291,700   3d ago │ ← selected
│  Documents   │      ▸ 📁 App Support  ██░░░░░░░░░   19.8 GB  108,220   Yest.  │
│              │  ▸ 📁 Movies           █████░░░░░░   88.1 GB      214   Mar 2  │
│ Volumes      │  ▸ 📁 Downloads        █░░░░░░░░░░   21.7 GB    1,932   Today  │
│  Macintosh HD│    📁 Pictures ☁ iCloud ░░░░░░░░░░░    8.9 GB   14,006   Today  │
│  Backup SSD  │    📁 Documents        ░░░░░░░░░░░    3.2 GB    6,410   Aug 20 │
│              │                                                            │
│ Smart lists  │                                                            │
│  Large files │                                                            │
│  Old and big │                                                            │
│  Duplicates  │                                                            │
├──────────────┴────────────────────────────────────────────────────────────┤
│ 1 selected · 44.6 GB · 412.6 GB used of 500 GB · 88.2 GB free            │
│                          [Quick look] [Reveal in Finder] [Move to Trash]  │
└───────────────────────────────────────────────────────────────────────────┘
```

### The rules that make it work
1. **Size bar is relative to the parent, not the disk.** When you expand `Library`, the `Caches` bar means "48% of Library." This is what lets you drill down without losing scale, and it's the single thing that separates this from "Finder with a size column." Bar is a single muted accent color, no rainbow.
2. **Sort by size is the default and sticky at every depth.** Name / Items / Modified are available but size is what you land on.
3. **Show allocated size, not logical size.** Allocated is what actually frees up. Logical size goes in Get Info only.
4. **Cloud placeholders (iCloud / Dropbox online-only) show their local footprint only, with a cloud badge.** Trashing a placeholder frees nothing, so counting it lies to the user.
5. **Smart lists live in the sidebar** as places you go, not features you enable: Large files (top 200 by size across the scan), Old and big (>1 GB, not accessed in >6 months), Duplicates (v1.2, opt-in, hash-verified).
6. **Footer always shows selection total and free space.** Move to Trash is one click away but styled as a danger-tinted secondary button, never a primary.
7. **Treemap is a toolbar toggle in v1.2, never the landing view.**
8. **Progressive scan.** Tree fills in as the scan runs; sizes update live; a subtle per-folder "scanning…" indicator. Never a modal progress bar.
9. **Live re-totaling.** After trashing, every ancestor's size and bar updates instantly without a rescan.
10. **Visual tone:** system fonts, system colors, sidebar vibrancy, SF Symbols. Indistinguishable from a first-party Apple app at a glance. Dark mode from day one (free if we never hardcode colors).

### Interactions
- Disclosure triangles + keyboard nav identical to Finder list view (arrow keys, right/left to expand/collapse, `Cmd-↓` to open)
- Clickable breadcrumb path bar
- Search/filter: name, extension, min size, age
- Quick Look on space bar
- Context menu: Reveal in Finder, Open, Get Info, Copy Path, Move to Trash, Exclude from scan
- Multi-select → Move to Trash → **confirmation sheet** listing items and "You'll reclaim 44.6 GB"
- Drag a folder onto the window to scan it; `Cmd-O` to pick; sidebar volumes are one-click scans
- Column (Miller) view as an alternate view mode — v1.1

## 5. Feature scope

### v1.0 — must ship
1. Pick a folder or volume (sidebar, `Cmd-O`, drag-drop)
2. Fast recursive scan with progressive UI; handles ~2M files without freezing
3. Outline view per §4 with size bars, item counts, modified date, sort
4. Quick Look, Reveal in Finder, Copy Path, Get Info
5. Multi-select → Move to Trash with confirmation + reclaimed-space summary
6. Live size recalculation after trash
7. Full Disk Access detection + onboarding that deep-links to System Settings
8. Exclusions: skip `/System`, `/private/var/vm`, Time Machine local snapshots; handle cloud placeholders
9. Smart lists: Large files, Old and big
10. Persist last scan so relaunch doesn't force a rescan
11. Footer stats incl. APFS purgeable space explanation

### v1.1
- Column (Miller) view
- Finder Quick Action extension ("Analyze with Tidy")
- Homebrew cask, Sparkle auto-updates

### v1.2
- Treemap toggle
- Duplicates smart list (same-size candidates → SHA-256 verify, bounded)
- Scan diffing: "what grew since last scan"

### Non-goals (v1)
Windows/Linux · permanent delete · automatic/"magic" cache cleaning · cloud contents not downloaded · iOS · App Store

## 6. Architecture

```
Tidy/
├── project.yml                # xcodegen
├── Package.swift
├── Sources/
│   ├── TidyCore/              # Foundation only. No UI. Fully tested.
│   │   ├── Scanner/           # fts-based walker, size aggregation, cancellation, batching
│   │   ├── Model/             # FileNode tree — layout decided by benchmark (§7)
│   │   ├── Exclusions/        # Path rules, cloud-placeholder detection, protected paths
│   │   ├── SmartLists/        # Large files, old & big — queries over the tree
│   │   ├── Persistence/       # Scan cache (format TBD in plan)
│   │   └── Actions/           # trashItem, reveal, copyPath — thin NSWorkspace/FileManager wrappers
│   └── TidyApp/               # SwiftUI + AppKit interop
│       ├── App/               # @main, window scene, menu commands, FDA check
│       ├── Sidebar/
│       ├── TreeView/          # NSOutlineView wrapper, size-bar cell, live updates
│       ├── Toolbar/           # Nav, breadcrumb, rescan, filter, search
│       ├── Footer/            # Stats + action bar
│       ├── Sheets/            # Trash confirmation, FDA onboarding, Get Info
│       └── ViewModels/        # @Observable stores bridging Core → UI
├── Tests/TidyCoreTests/       # Fixture trees under tmp; correctness + perf
├── Scripts/                   # build.sh, make-fixture-tree.sh, bench.sh, notarize.sh
└── docs/
    ├── HANDOFF.md             # this file
    └── decisions/             # ADR-000x-*.md for every benchmarked fork
```

### Scanner design notes
- Start from `fts(3)` (MacDirStat validated it's faster than `FileManager.enumerator`). Use `FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV`.
- Read allocated size via `st_blocks * 512`. Logical via `st_size`.
- Don't follow symlinks. Dedupe hardlinks by `(st_dev, st_ino)` so they aren't double-counted.
- Cloud placeholder detection: check `URLResourceKey.isUbiquitousItemKey` + `ubiquitousItemDownloadingStatusKey` for iCloud; for Dropbox/OneDrive, dataless files show `SF_DATALESS` in `st_flags`.
- Run the scan on a background `Task`; batch updates to the UI every ~200 ms or every 5k nodes. Never publish per-node.
- Cancellation checked at every directory boundary.
- Surface APFS purgeable space from `volumeAvailableCapacityForImportantUsageKey` so the footer can explain why Finder's number differs.

### Safety rules (non-negotiable)
- All deletion goes through `FileManager.trashItem(at:resultingItemURL:)`. **No `removeItem`. Ever.** Add a lint rule or test that greps for it.
- Confirmation sheet required for every trash action. Shows count + total allocated bytes.
- Refuse to trash anything under `/System`, `/Library`, `/usr`, `/bin`, `/sbin`, `/private`, `/Applications/Utilities`, the app's own bundle, or `~/Library/Application Support/Tidy`. Show "protected" state instead of a disabled button.
- Never auto-scan on launch unless the user previously chose a target and opted in.

## 7. Performance targets & the forks you must benchmark

Targets:
- 1M items scanned in < 60 s on Apple Silicon, SSD, warm cache
- 60 fps during scan
- < 150 MB RSS for a 1M-node tree
- Sorting a 50k-child directory by size: < 16 ms

Forks — **benchmark, decide, write an ADR in `docs/decisions/`, move on.** Don't ask me to pick between options I can't evaluate; give me numbers and your recommendation.
1. `FileNode` memory layout: class-per-node vs struct-of-arrays (parallel arrays: size, parentIndex, firstChild, nameOffset into a shared string buffer). Measure RSS at 1M nodes.
2. Tree view: SwiftUI `Table` + `OutlineGroup` vs `NSOutlineView` wrapper. Measure frame time with 50k visible rows and live updates every 200 ms.
3. Scan cache format: SQLite vs flat binary vs `Codable` + compression. Measure load time for 1M nodes; target < 2 s.

## 8. Milestones

| # | Milestone | Done when |
|---|-----------|-----------|
| 0 | Repo + skeleton | Public repo on GitHub, MIT license, README with positioning, `Package.swift`, xcodegen project, empty app launches, CI runs `swift test` on PRs |
| 1 | Scanner core | `TidyCore` scans fixture tree, aggregates allocated sizes correctly, hardlink dedupe works, tests green, `Scripts/bench.sh` exists, ADR-0001 (node layout) written |
| 2 | Outline view | Tree renders per §4 with parent-relative size bars, size sort, progressive updates during scan, ADR-0002 (tree view) written |
| 3 | Actions | Quick Look, Reveal, Copy Path, Get Info, Move to Trash w/ confirmation sheet, live re-total |
| 4 | Permissions + exclusions | FDA onboarding, protected paths, cloud placeholders badged and correctly sized |
| 5 | Smart lists + persistence | Large files, Old and big, scan cache, ADR-0003 (cache format) |
| 6 | v1.0 polish + release | Sidebar volumes/favorites, footer stats, app icon, notarized DMG, GitHub Release, tag `v1.0.0` |

## 9. Open-source hygiene (this is going public)

- README: positioning statement, one screenshot, install (DMG now, `brew install --cask` in v1.1), FDA explanation, "why no sandbox," contributing link
- `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, issue templates (bug / feature), PR template
- `docs/decisions/` ADRs so contributors understand why things are the way they are
- Conventional commits; squash-merge PRs; `main` protected after milestone 0
- CI: `macos-latest`, `swift build` + `swift test` on every PR; `swiftlint` and `swift-format` checks
- Every public type in `TidyCore` gets a doc comment

## 10. Instructions for Claude Code

1. **Enter plan mode.** Produce a plan covering: repo bootstrap, xcodegen project shape, the three benchmark forks in §7 and how you'll run them, milestone 0 and 1 task lists. Flag anything in this doc you think is wrong or underspecified.
2. **After plan approval, bootstrap with `gh`:**
   ```bash
   gh repo create tidy --public --description "Finder-native disk space analyzer for macOS. No treemap by default." --clone
   cd tidy
   # .gitignore (Swift/Xcode/xcodegen), LICENSE (MIT), README stub w/ positioning, CONTRIBUTING.md
   # copy this file to docs/HANDOFF.md
   git add -A && git commit -m "chore: initial scaffold" && git push -u origin main
   ```
   Then enable branch protection on `main` and open a PR per milestone.
3. Set up GitHub Actions CI before writing scanner code.
4. Write `Scripts/make-fixture-tree.sh` (generates a deterministic tree with known sizes, hardlinks, symlinks, and a fake dataless file) **before** the scanner, so tests exist from the first real commit.
5. Enforce `TidyCore` has no `import SwiftUI` / `import AppKit` with a test that fails if it does.
6. Read MacDirStat's `Sources/MacDirStat/Scanning/` before writing ours. Don't copy — it's a different license posture and we want SoA layout — but learn from it.
7. For every fork in §7: benchmark, decide, write the ADR, and mention the result in the PR description.

## 11. Open questions (answer in the plan, or ask if blocking)

- App name. "Tidy" is a placeholder; check GitHub, Homebrew cask names, and the Mac App Store for collisions. Alternatives welcome.
- Min macOS: 14 is the assumption. If `@Observable` or anything we need requires 15, say so.
- Scan cache location: `~/Library/Application Support/Tidy` (survives cache purges) vs `~/Library/Caches/Tidy`. Leaning App Support.
- Menu-bar mini mode showing free space — v1.2 probably, but cheap to leave a hook for.
- Should "Old and big" use `st_atime` (unreliable, often disabled) or `st_mtime`? Investigate what's actually populated on APFS with default mount options.
