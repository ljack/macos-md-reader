cask "md-reader" do
  version "0.1.0"
  sha256 "8f4db5c0aa314439b5db92d2dccd54aa98f293857a7ab7fc2a1a3f0543031124"

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
