cask "orbithud" do
  version "1.2.5"
  sha256 :no_check

  url "https://github.com/mojtaba-afraz/OrbitHUD/releases/download/v#{version}/OrbitHUD-macOS.dmg"
  name "OrbitHUD"
  desc "Zero-Gravity Glassmorphic Usage & Quota HUD for Google Antigravity, Claude Code, and Codex CLI"
  homepage "https://github.com/mojtaba-afraz/OrbitHUD"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "OrbitHUD.app"

  caveats <<~EOS
    OrbitHUD is ad-hoc signed (no paid Apple Developer ID certificate).
    If macOS Gatekeeper blocks first launch, install with `--no-quarantine` or run:
      xattr -dr com.apple.quarantine /Applications/OrbitHUD.app
  EOS

  zap trash: [
    "~/.gemini/antigravity-usage-widget",
    "~/Library/Preferences/com.orbithud.antigravity.plist",
  ]
end
