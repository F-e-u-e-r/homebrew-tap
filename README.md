# F-e-u-e-r/homebrew-tap

Homebrew tap for [AI Pet Usage](https://github.com/F-e-u-e-r/ai-pet-usage) — a
macOS menu-bar desktop pet that reacts to your AI usage.

```bash
brew install --cask F-e-u-e-r/tap/ai-pet-usage
```

- **Apple Silicon only.** Intel Macs: build from source (see the project README).
- The alpha is **ad-hoc signed and not notarized**, so macOS blocks the first
  launch. After trying to open it once, go to **System Settings → Privacy &
  Security → Open Anyway** (only if you trust the release). Homebrew does not
  remove this one-time approval — only Developer ID notarization would.

Update: `brew upgrade --cask ai-pet-usage` · Uninstall: `brew uninstall --cask ai-pet-usage`

## Maintainer: cutting a release + updating this cask

The app's in-app updater reads GitHub Releases directly, so a fresh release can be
ahead of `brew upgrade` until this cask is bumped. Publish in this order:

1. In the app repo, **annotate** the release tag with the changelog as its message —
   bullet lines only, **no `## What's new` heading** (the release workflow adds that
   heading; a duplicate would truncate the in-app "What's new").
   e.g. `git tag -a alpha-v0.1.3 -m "- Fixed X" -m "- Added Y" && git push origin alpha-v0.1.3`
2. The `release-app` workflow publishes the GitHub Release with the arm64 zip.
3. Update this cask: **Actions → bump-cask → Run workflow** to refresh `version` +
   `sha256` immediately (otherwise it auto-bumps within ~6h).
4. `brew style Casks/ai-pet-usage.rb`, then smoke-test `brew install --cask F-e-u-e-r/tap/ai-pet-usage`.
