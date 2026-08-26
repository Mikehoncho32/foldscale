# Releasing Foldscale

One command, from `main`, on the signing Mac:

```sh
CODE_SIGN_IDENTITY="Developer ID Application: MARK RIVERA GOERSCH (55XVDTTXCV)" Scripts/release.sh 1.3.0
```

## Before you run it
- Write the release notes under `## [Unreleased]` in `CHANGELOG.md` and merge them. They become the
  GitHub release body and the in-app update notes.
- Signing identity in the login keychain, notarization credentials stored once as
  `xcrun notarytool store-credentials radix-notary`, `gh auth login` done, `brew install xcodegen`.
- The Sparkle private key must be in the login keychain (`generate_keys -p` prints the public half;
  it must equal `SUPublicEDKey` in `project.yml`). Restore from the backup with `generate_keys -f`.

## What the script does, in order
1. **preflight** — clean `main`, tools present, tag unused, `[Unreleased]` non-empty.
2. **branch** `release/<v>`, **bump** (`Scripts/set-version.sh`: project.yml, site fallbacks; promotes
   the CHANGELOG section).
3. **build** — `Scripts/build-dmg.sh`: build, re-sign Sparkle inside-out, sign, notarize, staple, DMG.
4. **draft-release** — uploads the DMG to a *draft* GitHub release (not yet public).
5. **appcast** — `Scripts/appcast.sh` signs the DMG with the EdDSA key and prepends the item;
   `Scripts/check-version.sh` asserts everything agrees.
6. **pr** — one PR with project.yml, site, appcast, CHANGELOG; waits for checks; squash-merges.
7. **publish** — flips the draft to public, targeting the merged commit (creates the tag); the
   enclosure URL goes live seconds before Pages deploys the feed.
8. **pages** — waits for the deploy and for foldscale.com/appcast.xml to show the version.
9. **homebrew** — `update.sh <v>` in the tap repo (sha256 bump) and pushes.

## When something fails
- Notarization: nothing has been pushed yet. `xcrun notarytool log <id> --keychain-profile radix-notary`,
  fix, rerun the same command — finished steps notice they're done; `--force` replaces the appcast item.
- "does not include a secure timestamp" from notarytool, or `no trusted timestamp on … after 5
  attempts` in the log: Apple's timestamp server was flaky. Every signature is retried five times
  automatically; if it still fails, wait a few minutes and rerun the same command.
- Between merge and publish: Pages refuses to deploy a feed whose enclosure isn't live, so nothing
  breaks; rerun with `--from publish`.
- Abandon a merged release: `gh release delete v<v> --yes` (still a draft), revert the release commit,
  `gh workflow run pages.yml`.
- Testing the update flow without a release: build locally, `Scripts/appcast.sh <v> <dmg> --out
  /tmp/feed/appcast.xml --url http://localhost:8000/Foldscale-<v>.dmg`, serve `/tmp/feed` with
  `python3 -m http.server 8000`, launch with `FOLDSCALE_APPCAST_URL=http://localhost:8000/appcast.xml`.
