# F-e-u-e-r/homebrew-tap

Homebrew tap for [AI Pet Usage](https://github.com/F-e-u-e-r/ai-pet-usage) — a
macOS menu-bar desktop pet that reacts to your AI usage.

```bash
brew install --cask F-e-u-e-r/tap/ai-pet-usage
```

- **Apple Silicon only.** Intel Macs: build from source (see the project README).
- The app is **ad-hoc signed and not notarized**, so macOS blocks the first
  launch. After trying to open it once, go to **System Settings → Privacy &
  Security → Open Anyway** (only if you trust the release). Homebrew does not
  remove this one-time approval — only Developer ID notarization would.

Update: `brew upgrade --cask ai-pet-usage` · Uninstall: `brew uninstall --cask ai-pet-usage`

## Maintainer: cutting a release + updating this cask

The app's in-app updater reads GitHub Releases directly, so a fresh release can be
ahead of `brew upgrade` until this cask is bumped. Release tags follow the canonical
grammar in the app repo's [`docs/release/VERSIONING.md`](https://github.com/F-e-u-e-r/ai-pet-usage/blob/main/docs/release/VERSIONING.md)
(`vX.Y.Z-alpha.N`, `vX.Y.Z-beta.N`, `vX.Y.Z-rc.N`, `vX.Y.Z`). Tags are immutable, so a
mistaken tag burns that version number. Publish in this order:

1. In the app repo, **annotate** the release tag with the changelog as its message —
   bullet lines only, **no `## What's new` heading** (the release workflow adds that
   heading; a duplicate would truncate the in-app "What's new").
   e.g. `git tag -a v0.1.0-beta.1 -m "- Fixed X" -m "- Added Y" && git push origin v0.1.0-beta.1`
2. The `release-app` workflow publishes the GitHub Release with the arm64 zip.
3. Update this cask: **Actions → bump-cask → Run workflow** to refresh `version`,
   `sha256` and `url` immediately (otherwise it auto-bumps within ~6h). The cask tracks the
   highest canonical **beta / rc / stable** release by version order; alpha releases and the
   retired `alpha-v*` tags are never selected.
4. `brew style Casks/ai-pet-usage.rb`, then smoke-test `brew install --cask F-e-u-e-r/tap/ai-pet-usage`.

`bash scripts/test-bump.sh` tests the selector, the asset and digest extraction, the cask rewrite, the download
check and the whole bump (`scripts/bump-cask.sh`, end-to-end against a stubbed `gh` / `curl` and a throwaway git
repository). It needs `jq`, `ruby` and `git`.

Installs from the retired `alpha-v*` line move to the canonical line with
`brew upgrade --cask ai-pet-usage` (Homebrew treats any cask version change as an upgrade),
or with `brew reinstall --cask ai-pet-usage`.
