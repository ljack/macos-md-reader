# MD Reader

Fast, native Markdown viewer for macOS. AppKit + WebKit, cmark-gfm rendering, GitHub-style theme with automatic dark mode, live reload, and Finder integration as the default `.md` opener.

## Build

Requires Xcode 26+ and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
swift Scripts/gen-icon.swift      # regenerate app icon (optional)
xcodegen generate
xcodebuild -scheme MDReader -configuration Release build
```

Or `./Scripts/build.sh` which does all of the above and copies `MD Reader.app` to `build/`.

## Install as default Markdown viewer

1. Copy `build/MD Reader.app` to `/Applications` (Launch Services registers it on first launch).
2. Launch it once. It offers to become the default viewer; you can also pick **MD Reader ▸ Make Default Markdown Viewer…** later.

## Layout

```
project.yml                  xcodegen spec (targets, Info.plist, SwiftPM deps)
MDReader/Sources/
  main.swift                 NSApplicationMain, no storyboards
  AppDelegate.swift          launch behaviour, open panel when launched empty
  MenuBuilder.swift          programmatic main menu, Open Recent, Open With
  MarkdownDocument.swift     NSDocument (read-only), live reload, print
  DocumentWindowController.swift
  PreviewViewController.swift  WKWebView host, link policy, zoom
  FindBar.swift              ⌘F overlay using WKWebView.find
  MarkdownRenderer.swift     cmark-gfm → HTML, front matter
  HTMLTemplate.swift         page shell, bundled CSS/JS
  FileWatcher.swift          kqueue file watcher (survives atomic saves)
MDReader/Resources/
  preview.css / preview.js   theme + heading anchors, copy buttons, highlight
  highlight.min.js, github*.css   highlight.js 11.11.1
```
