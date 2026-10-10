cask "ai-pet-usage" do
  version "0.1.0-beta.2"
  sha256 "5f35904adff5eb6c8f06278f3d69c57ae70aa6e4ccf3ce33ecfd78d15e563e6f"

  url "https://github.com/F-e-u-e-r/ai-pet-usage/releases/download/v#{version}/AI-Pet-Usage-v#{version}-arm64.zip",
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
