cask "md-reader" do
  version "0.1.0"
  sha256 "cd83dbeda07a5a82396711566cdfeb307cc0af446e0927e95f7faa09f7fb0b51"

  url "https://github.com/ljack/homebrew-tap/releases/download/md-reader-v#{version}/MD-Reader-#{version}.zip"
  name "MD Reader"
  desc "Fast native Markdown viewer for macOS"
  homepage "https://github.com/ljack/homebrew-tap"

  depends_on macos: ">= :sonoma"

  app "MD Reader.app"

  zap trash: [
    "~/Library/Preferences/fi.jarkkolietolahti.MDReader.plist",
    "~/Library/Saved Application State/fi.jarkkolietolahti.MDReader.savedState",
    "~/Library/WebKit/fi.jarkkolietolahti.MDReader",
  ]

  caveats do
    <<~EOS
      MD Reader is ad-hoc signed (no Apple Developer ID). To skip the Gatekeeper
      warning on first launch, install with:
        brew install --cask --no-quarantine ljack/tap/md-reader
      Otherwise right-click the app in /Applications and choose Open once.
    EOS
  end
end
