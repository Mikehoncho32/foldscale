# Show HN draft

**Title (≤ 80 chars):**
Show HN: Foldscale – Finder, but every folder shows its size (macOS, open source)

**URL:** https://foldscale.com

**First comment (post this right after submitting):**

Hi HN — I built Foldscale because every Mac disk analyzer I tried led with a treemap or a sunburst and treated the actual file list as an afterthought. I wanted the opposite: a window that looks like Finder, where every folder shows its size, the biggest thing is always on top at every level, and the size bar on each row is relative to its *parent* folder so you can drill down without losing scale.

A few things I cared about:

- **Safe by construction.** Everything goes to the Trash, never a permanent delete; system folders refuse to be trashed; it never opens your files (metadata only, so iCloud placeholders don't get downloaded).
- **"Free up space"** — pick 5/10/25/50/100 GB and it pre-ticks the safest candidates (old installers, caches, build junk), you adjust, one confirmation. Nothing marked "review first" is ever pre-ticked.
- **Task lists instead of filters:** Downloads, Caches & Trash, Developer junk, App leftovers, Apps & games, Big projects, Videos & recordings, Media libraries, Phone backups, Virtual machines, Cloud files, and "What grew" since last week — each with a safety badge.
- **Always current:** the last scan opens instantly and refreshes in the background; the folder you click is re-checked on the spot.
- No telemetry; the only network request is an optional daily update check. Notarized DMG, Homebrew cask, MIT. Swift, ~1 M files/s scan.

Things I'd genuinely like feedback on: whether the parent-relative size bars read correctly at first glance, and what's missing from the task lists on *your* Mac.

Source: https://github.com/Mikehoncho32/foldscale
