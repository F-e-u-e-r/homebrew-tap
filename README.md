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
