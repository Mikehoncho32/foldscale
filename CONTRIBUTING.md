# Contributing to Foldscale

Thanks for your interest! Foldscale aims to feel like a first-party Apple app, so contributions are held
to a matching bar for polish, performance, and safety.

## Ground rules

- **Be kind.** This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).
- **Safety is non-negotiable.** All deletion goes through `FileManager.trashItem` — never
  `removeItem`. A test enforces this; PRs that add `removeItem(` will fail CI.
- **`FoldscaleCore` stays UI-free.** No `import SwiftUI` / `import AppKit` in the engine (a test enforces
  this). Keep filesystem/analysis logic in `FoldscaleCore` and UI in `FoldscaleApp`.

## Getting set up

```bash
brew install xcodegen swiftlint
git clone https://github.com/Mikehoncho32/foldscale.git
cd foldscale
swift test                 # engine unit tests
xcodegen generate          # produces Foldscale.xcodeproj (gitignored)
open Foldscale.xcodeproj        # or build via xcodebuild
```

## Before you open a PR

Run the same checks CI runs:

```bash
swift test
swiftlint --strict
swift format lint --strict --recursive Sources Tests   # or `swift format --in-place` to auto-fix
xcodegen generate && xcodebuild -project Foldscale.xcodeproj -scheme FoldscaleApp -destination 'platform=macOS' build
```

## Commit & PR conventions

- **Conventional commits**: `feat:`, `fix:`, `perf:`, `docs:`, `test:`, `chore:`, `refactor:`.
- PRs are **squash-merged**; keep the PR title in conventional-commit form.
- One logical change per PR. Reference the milestone or issue it addresses.
- If you change a benchmarked decision (node layout, tree backend, cache format), update or add an
  **ADR** in `docs/decisions/` and cite the numbers in your PR description.

## Performance

Foldscale targets 1M items scanned in < 60 s, 60 fps during scan, and < 150 MB RSS for a 1M-node tree.
If your change touches the scan hot path or the tree view, include before/after numbers
(`Scripts/bench.sh`).

## Reporting bugs / requesting features

Use the issue templates. For bugs, include your macOS version, whether Full Disk Access is granted,
and the kind of volume/folder being scanned (APFS, external, cloud-backed).
