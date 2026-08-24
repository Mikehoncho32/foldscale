<!-- PR titles use conventional commits, e.g. "feat: parent-relative size bars". PRs are squash-merged. -->

## What & why

Describe the change and the problem it solves. Link the milestone or issue.

## Checklist

- [ ] `swift test` passes
- [ ] `swiftlint --strict` and `swift format lint --strict --recursive Sources Tests` pass
- [ ] App still builds: `xcodegen generate && xcodebuild -project Radix.xcodeproj -scheme RadixApp -destination 'platform=macOS' build`
- [ ] No `removeItem(` added; deletion still routes through `FileManager.trashItem`
- [ ] `RadixCore` still free of `import SwiftUI` / `import AppKit`
- [ ] If a benchmarked decision changed, an ADR in `docs/decisions/` is added/updated with numbers
- [ ] Public `RadixCore` types have doc comments

## Performance impact (if scan hot path or tree view)

Before / after numbers from `Scripts/bench.sh`, if applicable.
