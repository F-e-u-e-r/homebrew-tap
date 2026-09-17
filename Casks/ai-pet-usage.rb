cask "ai-pet-usage" do
  version "0.2.0"
  sha256 "509b13c3694ddc94fb01f8d5b6a39a3daddea105258e61b9c19c5a1947f0a6c1"

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
    "~/Library/LaunchAgents/dev.aipetusage.app.report.plist",
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
