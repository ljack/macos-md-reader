cask "md-reader" do
  version "0.1.1"
  sha256 "a2765e6df6f92aa7a0932f49840ea0f7b8311191d56b4546a754abacff252079"

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
