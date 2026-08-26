# Changelog

All notable changes to Foldscale are recorded here, newest first. The top released section becomes
the GitHub release notes and the in-app update notes (`Scripts/release.sh`), so write it before
releasing. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- **Five more lists in the sidebar.** *App leftovers* (Clean Up): support data, containers and
  group containers left behind by apps that aren't installed anymore — review first, nothing is
  pre-ticked. *Phone backups*: iPhone and iPad backups by device name and date, archived copies
  marked. *Virtual machines*: Parallels, VMware Fusion, UTM, VirtualBox and Tart machines, plus the
  disks behind Docker, OrbStack, Lima and colima (with where to shrink them). *Media libraries*:
  Photos, Music, TV, Podcasts, Books, iMovie, Lightroom and friends — informational, with where to
  remove items. *Cloud files*: iCloud Drive, Dropbox, Google Drive, OneDrive and Box — what's on
  this Mac versus online-only, per account. Empty lists stay hidden.
- **What grew** (What's Here): folders that got at least 500 MB bigger since an earlier scan,
  grouped by last week / last month / longer, with the growth and the date it's measured from.
  Foldscale now keeps a small size history (`size-history.plist`, a few MB at most, thinned to
  90 days) next to its scan cache; the list appears once you've used the app on two different days.

## [1.3.0] - 2026-08-26

### Added
- **Auto-updates.** Foldscale can now keep itself current: on its second launch it asks whether to
  check foldscale.com once a day, and **Foldscale → Check for Updates…** works at any time. The
  check sends no identifiers; updates are verified with both Apple's Developer ID and an EdDSA key
  built into the app. Versions before 1.3.0 have no updater — download once more or `brew upgrade`.
- Settings: "Check for updates automatically" and "Download and install updates automatically".

### Changed
- The "no network" wording on the website, in the README and in the Full Disk Access sheet now
  describes the one optional request the app makes.

## [1.2.0] - 2026-08-26

**Radix is now Foldscale.** Same app, new name — an unrelated Mac disk analyzer already used
"Radix", so we renamed rather than share it.

### Changed
- App, modules, bundle id (`io.github.mikehoncho32.foldscale`), Homebrew cask (`foldscale`) and
  website (foldscale.com) renamed. The v1.1.0 release stays available under its old name.
- Sidebar is wider by default, so list labels like "Videos & recordings · 16 GB" no longer truncate.
- Free-up space section headers show the safety badge once instead of twice.

### Upgrading from Radix 1.1
- Drag Foldscale to Applications and delete the old Radix.app. macOS treats the renamed app as new,
  so grant **Full Disk Access** once more.
- Your last scan and the "refresh on launch" setting carry over automatically; the old
  `~/Library/Application Support/Radix` folder is adopted on first launch.
- Homebrew: `brew uninstall --cask radix-finder && brew install --cask mikehoncho32/foldscale/foldscale`.

## [1.1.0] - 2026-08-26

First **signed and notarized** release: download, drag to Applications, double-click.

### Added
- **Drive tree in the sidebar** — the drive at the top, expandable folder by folder with GB on every
  row; click any folder to open it in the main area.
- **Always current** — the last scan opens instantly and refreshes in the background; the folder you
  click is re-checked on the spot; the cache saves as you go.
- **Drive overview** (used · system & other · free) pinned above whatever you're looking at; first
  launch shows your drives with one-click Scan.
- **Task-oriented lists** replace "Large files / Old and big": Downloads, Caches & Trash, Developer
  junk (Clean Up) and Apps & games, Big projects, Videos & recordings (What's Here) — each with a
  safety badge and a GB total; empty ones hide.
- **Free up space** — say how much you need (5–100 GB); the safest candidates are pre-ticked to
  cover it, you adjust, one confirmation. Nothing risky is ever pre-ticked.
- Launches on your home folder; ⓘ explains used / free / purgeable; Settings (⌘,) to turn
  background refresh off.

## [1.0.0] - 2026-08-24

First release (as Radix, unsigned).

### Added
- Finder-style outline with parent-relative size bars and sticky size sort.
- Move to Trash with confirmation and reclaimed-space total, protected-path safety, live re-totaling.
- Quick Look · Reveal in Finder · Copy Path · Get Info.
- Full Disk Access onboarding; cloud-aware — never materializes online-only files.
- Smart lists (Large files, Old and big); sidebar Favorites + Volumes.
- Remembers the last scan and reloads it instantly.

[Unreleased]: https://github.com/Mikehoncho32/foldscale/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/Mikehoncho32/foldscale/releases/tag/v1.3.0
[1.2.0]: https://github.com/Mikehoncho32/foldscale/releases/tag/v1.2.0
[1.1.0]: https://github.com/Mikehoncho32/foldscale/releases/tag/v1.1.0
[1.0.0]: https://github.com/Mikehoncho32/foldscale/releases/tag/v1.0.0
