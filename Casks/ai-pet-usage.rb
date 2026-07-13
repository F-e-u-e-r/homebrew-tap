cask "ai-pet-usage" do
  version "0.1.2"
  sha256 "a64757be9a6d207d418ab3b7d1cd69cd7887b3fcaf5f5ff7f285621ed8f0c77a"

  url "https://github.com/F-e-u-e-r/ai-pet-usage/releases/download/alpha-v#{version}/AI-Pet-Usage-alpha-v#{version}-arm64.zip",
      verified: "github.com/F-e-u-e-r/ai-pet-usage/"
  name "AI Pet Usage"
  desc "Menu bar pet that reacts to AI usage"
  homepage "https://github.com/F-e-u-e-r/ai-pet-usage"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "AI Pet Usage.app"

  uninstall launchctl: "dev.aipetusage.app.report",
            quit:      "dev.aipetusage.app"

  zap trash: [
    "~/Library/Application Support/AIPetUsage",
    "~/Library/Preferences/dev.aipetusage.app.plist",
  ]

  caveats <<~EOS
    AI Pet Usage is ad-hoc signed and not notarized, so macOS blocks its first
    launch. After trying to open it once, open System Settings then Privacy &
    Security and choose "Open Anyway" (only if you trust this release):
    https://support.apple.com/102445

    Apple Silicon only. Intel Macs: build from source (see the project README).
  EOS
end
