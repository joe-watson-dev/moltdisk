# Homebrew cask for MoltDisk. This repo doubles as its own tap:
#   brew tap joe-watson-dev/moltdisk https://github.com/joe-watson-dev/moltdisk
#   brew trust joe-watson-dev/moltdisk
#   brew install --cask moltdisk
cask "moltdisk" do
  # Always the newest GitHub release; `brew upgrade --cask --greedy moltdisk` reinstalls it.
  version :latest
  sha256 :no_check

  url "https://github.com/joe-watson-dev/moltdisk/releases/latest/download/MoltDisk.zip"
  name "MoltDisk"
  desc "Mac cleaner for developers: dev caches, build folders, simulators and complete app uninstalls"
  homepage "https://moltdisk.vercel.app/"

  depends_on macos: ">= :sequoia"
  depends_on arch: :arm64

  app "MoltDisk.app"

  # MoltDisk isn't notarized by Apple yet, so macOS would block it as coming from an unidentified developer.
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/MoltDisk.app"]
  end

  zap trash: [
    "~/Library/Application Support/MoltDisk",
    "~/Library/Preferences/dev.moltdisk.MoltDisk.plist",
    "~/Library/Saved Application State/dev.moltdisk.MoltDisk.savedState",
  ]
end
