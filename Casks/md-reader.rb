cask "md-reader" do
  version "0.1.0"
  sha256 "cd83dbeda07a5a82396711566cdfeb307cc0af446e0927e95f7faa09f7fb0b51"

  url "https://github.com/ljack/macos-md-reader/releases/download/v#{version}/MD-Reader-#{version}.zip"
  name "MD Reader"
  desc "Fast native Markdown viewer for macOS"
  homepage "https://github.com/ljack/macos-md-reader"

  depends_on macos: ">= :sonoma"

  app "MD Reader.app"

  zap trash: [
    "~/Library/Preferences/fi.jarkkolietolahti.MDReader.plist",
    "~/Library/Saved Application State/fi.jarkkolietolahti.MDReader.savedState",
    "~/Library/WebKit/fi.jarkkolietolahti.MDReader",
  ]

end
