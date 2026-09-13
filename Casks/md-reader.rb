cask "md-reader" do
  version "0.1.3"
  sha256 "6ee94e0edc21c7b37c5d81dd1af0490d4860b693deb4f08aef5379a56bb26458"

  url "https://github.com/ljack/macos-md-reader/releases/download/v#{version}/MD-Reader-#{version}.zip"
  name "MD Reader"
  desc "Fast native Markdown viewer for macOS"
  homepage "https://github.com/ljack/macos-md-reader"

  depends_on macos: :sonoma

  app "MD Reader.app"

  zap trash: [
    "~/Library/Preferences/fi.jarkkolietolahti.MDReader.plist",
    "~/Library/Saved Application State/fi.jarkkolietolahti.MDReader.savedState",
    "~/Library/WebKit/fi.jarkkolietolahti.MDReader",
  ]

end
