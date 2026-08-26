# r/macapps draft (screenshot post: site/img/home-light.png)

**Title:** Foldscale — a free, open-source disk analyzer that looks like Finder (every folder shows its size, biggest first)

**Body:**

I got tired of treemaps, so I built the disk analyzer I actually wanted: a Finder-like window where every folder shows how much space it's eating, sorted biggest-first at every level, with a size bar on each row that's relative to its parent folder.

- "Free up space": pick how many GB you need, it pre-ticks the safest stuff (old installers, caches, node_modules/DerivedData…), you adjust, one confirmation.
- Task lists with safety badges: Downloads, Caches & Trash, Developer junk, Apps & games, Big projects, Videos & recordings.
- Trash only — never a permanent delete. Never opens your files. No telemetry (one optional daily update check).
- macOS 14+, Apple silicon + Intel, notarized. `brew install --cask mikehoncho32/foldscale/foldscale` or the DMG from https://foldscale.com. MIT, source on GitHub.

Happy to hear what's missing from the lists on your Mac — phone backups, VMs, cloud folders and "what grew since last week" are next.

---

# r/swift (optional, engineering angle)

**Title:** How I made a SwiftUI/AppKit disk analyzer scan ~1M files/s: readdir+fstatat instead of fts, struct-of-arrays tree, NSOutlineView

Short write-up pointing at the ADRs in `docs/decisions/` (node memory layout, tree-view backend, cache format, traversal API) and the benchmark script.
