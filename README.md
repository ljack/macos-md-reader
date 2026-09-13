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

## Features

- Menu bar icon: last 100 opened Markdown files, ⌥-click to reveal in Finder; open current document's folder in Finder, Terminal or iTerm2. Toggle with **Show in Menu Bar**.
- Feedback button (toolbar / Help menu): file a Bug, Feedback or Idea as a GitHub issue in this repo. With a GitHub token (stored in Keychain) it posts via the API; without one it opens a prefilled new-issue page.
- Live reload, ⌘F find, zoom, print, Open With, dark mode.

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
  StatusItemController.swift menu bar icon + recents menu
  RecentFilesStore.swift     last-100 list in UserDefaults
  GitHubFeedback.swift       issue API / browser fallback, Keychain token
  FeedbackSheet.swift        Bug / Feedback / Idea sheet
MDReader/Resources/
  preview.css / preview.js   theme + heading anchors, copy buttons, highlight
  highlight.min.js, github*.css   highlight.js 11.11.1
```
