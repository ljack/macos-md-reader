# AGENTS.md — working on MD Reader as an AI agent

Read this before touching the repo. It is the contract between humans and agents for this project.

## What this is

Native macOS Markdown viewer. AppKit + WebKit, Swift 5 language mode, no SwiftUI, no storyboards.
Rendering: cmark-gfm (swift-cmark `gfm` branch) → HTML → `WKWebView`. See README "How it works".

## Commands you will use

| Task | Command | Notes |
|---|---|---|
| Regenerate Xcode project | `make gen` | `project.yml` is the source of truth. Never edit `MDReader.xcodeproj` (it's gitignored). |
| Build (Debug) | `make build` | Output filtered to errors/warnings + result. |
| Unit tests | `make test` | XCTest target `MDReaderTests`, `@testable import MDReader`. |
| Launch smoke test | `make smoke` | Opens `Samples/demo.md`, checks the process stays alive, quits it. |
| Full local CI | `make ci` | build + test + smoke. This is what `pre-push` runs. |
| Install to /Applications | `make install` | Release config, Developer ID signed, not notarized. |
| Bump version | `make bump V=0.2.0` | Semver only; commits `project.yml`. Requires clean tree. |
| Release | `make release` | Clean tree required. Signs, notarizes, staples, creates GitHub release `vX.Y.Z` at HEAD, updates cask sha in `Casks/` and in the tap `ljack/homebrew-tap`. Needs keychain profile `md-reader-notary`. |
| Enable git hooks | `make hooks` | Sets `core.hooksPath=.githooks`. |

Raw `xcodebuild` if you need it:

```bash
xcodebuild -scheme MDReader -configuration Debug -derivedDataPath build/DerivedData build
xcodebuild -scheme MDReader -configuration Debug -derivedDataPath build/DerivedData test
```

## Definition of done for a change

1. `make ci` is green.
2. New logic in `MarkdownRenderer`, `FrontMatter`, `RecentFilesStore`, `WindowActions`, `BuildInfo`, `LinkPolicy` or anything else without UI has a unit test in `MDReaderTests/`.
   Anything touching `HTMLTemplate`, `PreviewWebView`, `DocumentResourceHandler`, `LinkPolicy` or the WebKit delegates is security-relevant: keep `WebViewHardeningTests` and `LinkPolicyTests` green, open `Samples/hostile.md`, and update `SECURITY.md` if a promise changes.
3. UI changes were launched and looked at (screenshot or accessibility inspection), not just compiled.
4. Commit message: imperative subject ≤ 72 chars, body explains why. Conventional prefixes not required.
5. Nothing under `build/`, `.claude/` or `*.xcodeproj` is committed (`pre-commit` blocks it).

## Verifying the running app (no human at the keyboard)

Accessibility scripting works on this machine for menus and windows:

```bash
open -a "build/DerivedData/Build/Products/Debug/MD Reader.app" "$PWD/Samples/demo.md"
osascript -e 'tell application "System Events" to tell process "MD Reader" to click menu item "Merge All Windows" of menu "Window" of menu bar 1'
osascript -e 'tell application "System Events" to tell process "MD Reader" to get name of menu items of menu "File" of menu bar 1'
```

Screenshots: `screencapture -x -l <windowID>` where the window ID comes from `CGWindowListCopyWindowInfo` (see `Scripts/` history, or capture a region with `-R x,y,w,h`). Windows may open on a secondary display with negative y; move them first with System Events.

Status bar menu is `menu bar item 1 of menu bar 2` of the process.

## Provenance: which source built this binary?

Every build runs `Scripts/stamp-build.sh` as a post-build phase and writes into `Info.plist`:

- `CFBundleVersion` = `git rev-list --count HEAD` (monotonic build number)
- `GitCommit` = short SHA, suffixed `-dirty` if the tree had uncommitted tracked changes
- `GitBranch`, `BuildDate` (UTC)

Surfaces: **About MD Reader** (commit is a link to GitHub), **Copy Build Info** in the app menu, and the feedback sheet's context footer. `Scripts/release.sh` refuses dirty trees, tags the exact commit via `gh release create --target`, and puts the commit and the zip's sha256 in the release notes. The cask pins that sha256. Chain: cask sha → release asset → tag → commit → source.

To check an installed copy:

```bash
/usr/libexec/PlistBuddy -c "Print :GitCommit" "/Applications/MD Reader.app/Contents/Info.plist"
```

## Security model (short)

The document is hostile input. Four layers, all with tests: cmark `tagfilter` plus the app's own `neutraliseStructuralTags` (`<link>`, `<meta>`, `<base>`, `<object>`, `<embed>`, `<applet>`); a per-load CSP nonce in `HTMLTemplate` (no document scripts, no fetch, no frames, no forms, no `file:`); the page is loaded with an `mdres:///<dir>/` base and `DocumentResourceHandler` (`PreviewWebView.swift`) serves only image/media/font files to the web process, which has no file access of its own; and `LinkPolicy` deciding what a click may open (web/mail → default handler, `.md` → new document, images/PDF/text → their app, anything launchable by UTType, exec bit or the `launchableExtensions` deny list → only revealed in Finder; non-click navigations dropped, `window.open` included). Remote-off has two layers: CSP and `RemoteContentBlocker` (WKContentRuleList). Documents over 64 MB are refused (`MarkdownDocument.maxDocumentBytes`). `PreviewViewController.actionHandler` / `onPageLoaded` exist for `PreviewIntegrationTests`; keep them. Do not add `allowFileAccessFromFileURLs`, `allowUniversalAccessFromFileURLs`, `file:` to the CSP, `'unsafe-inline'` for scripts, or an `NSWorkspace.open` that bypasses `LinkPolicy`. Note the WebContent sandbox: a `file:` base URL only ever worked for the temp dir, which is why the tests load images from `~/Library/Caches` and the build dir too. Full write-up: `SECURITY.md`.

## Dependencies

- `swift-cmark` is pinned by `revision:` in `project.yml`. To bump: look at the `gfm` branch, set the new SHA and its date in the comment, `make ci`, and mention the date in the commit body. Dependabot cannot see it (no `Package.swift`).
- GitHub Actions in `.github/workflows` are SHA-pinned with a `# vX.Y.Z` comment; Dependabot updates them weekly.
- `highlight.min.js` is vendored; update by replacing the file and noting the version in the commit.

## Gotchas learned the hard way

- **Same bundle id, multiple copies.** Launch Services picks any registered copy of `fi.jarkkolietolahti.MDReader`, including ones in `build/DerivedData`. `Scripts/build.sh` deletes the DerivedData copy after each Release build, and `Scripts/smoke.sh` unregisters the copy it launched and re-registers `/Applications/MD Reader.app`. If Finder opens the wrong copy: `lsregister -f "/Applications/MD Reader.app"`.
- **AppKit auto-injects menu items.** File ▸ Open Recent, and once tabs exist: Close Window / Close Tab / Close Other Tabs / Close All (⌥-alternate). Don't add duplicates; name yours differently (we use "Close All Windows").
- **Open Recent cap** is `NSRecentDocumentsLimit`, registered to 100 in `AppDelegate`.
- **Product name has a space** ("MD Reader"). Module name is `MDReader`. Test target needs explicit `TEST_HOST`.
- **User script sandboxing is off** (`ENABLE_USER_SCRIPT_SANDBOXING: NO`) so the stamp script can write the plist.
- **Keychain writes and public-repo creation** may be blocked for agents by policy. Ask the human to run those commands with `! cmd` in the Claude Code prompt.
- **Notarization credentials** live in the keychain under profile `md-reader-notary`. Never print them.
- **macOS `make` is 3.81**: no `.SHELLFLAGS`; recipes use `set -o pipefail;` inline.

## Where things live

```
MDReader/Sources/      app code (one type per file)
MDReader/Resources/    preview.css / preview.js / highlight.js, Assets.xcassets
MDReaderTests/         XCTest
Samples/demo.md        rendering fixture used by tests and smoke
Casks/md-reader.rb     Homebrew cask, mirrored to ljack/homebrew-tap by release.sh
Scripts/               build.sh, release.sh, stamp-build.sh, smoke.sh, bump.sh, gen-icon.swift, xcfilter.sh
.githooks/             pre-commit (hygiene), pre-push (make ci)
```

## Roadmap hints

TOC sidebar (inject from headings in `preview.js`, host in an `NSSplitViewController`), Mermaid (bundle mermaid.min.js, render `pre code.language-mermaid`), source/rendered split, Quick Look extension (separate target, sandboxed; renderer must stay UI-free so it can be shared).
