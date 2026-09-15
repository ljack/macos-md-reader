# Security policy

MD Reader is a native macOS viewer for Markdown files. Its whole job is to open files you did
not write, so the document is treated as hostile input. This page says what the app promises,
what it does not, and how to report a hole.

## Reporting a vulnerability

Please do **not** open a public issue for security problems.

- Preferred: GitHub private vulnerability reporting →
  <https://github.com/ljack/macos-md-reader/security/advisories/new>
- Fallback: email `jarkko.lietolahti@gmail.com` with subject `MD Reader security`.

You will get an acknowledgement within 7 days and a fix or a decision within 30 days for
confirmed issues. Credit is given in the release notes unless you prefer otherwise. There is
no bug bounty.

## Supported versions

Only the latest release on the [releases page](https://github.com/ljack/macos-md-reader/releases)
receives fixes. Homebrew users: `brew upgrade --cask md-reader`.

## Threat model

**Assets.** Everything else on the user's disk and account. The app itself holds one secret:
an optional GitHub personal access token for the feedback sheet, stored in the login Keychain.

**Attacker.** Whoever wrote or modified a `.md` file the user opens (email attachment, cloned
repo, download). They control the full Markdown, including raw HTML, links and image paths.
They may also control web servers the document points at.

**Promises.** A malicious document must not be able to

1. run code, in the app or through another app, without a deliberate user action;
2. read any file other than image, media and font files it references (relative paths next to the document, or absolute);
3. navigate the preview to a remote site or submit data anywhere;
4. exfiltrate document content or local files over the network;
5. crash the app in a way that is more than a denial of service of one window.

**Out of scope.** Physical access, a compromised macOS account, malicious builds not from the
signed and notarized release, remote images/media that reveal the user's IP address to the
image host (see "Accepted risks"), and content that merely *looks* misleading.

## How the promises are kept

| Layer | Mechanism | Where |
|---|---|---|
| Rendering | cmark-gfm with the GFM `tagfilter` extension escapes `<script>`, `<style>`, `<iframe>`, `<textarea>`, `<title>`, `<xmp>`, `<noembed>`, `<noframes>`, `<plaintext>`, matching GitHub. The app additionally escapes `<link>`, `<meta>`, `<base>`, `<object>`, `<embed>` and `<applet>` (`neutraliseStructuralTags`) so the page never even asks for a preconnect, refresh, base change or plug-in. Other raw HTML is kept (`CMARK_OPT_UNSAFE`) for fidelity. Neither filter is an HTML sanitizer; the CSP is the boundary. Documents larger than 64 MB are refused before parsing, because cmark aborts the process on allocation failure instead of returning an error. | `MDReader/Sources/MarkdownRenderer.swift`, `MarkdownDocument.swift` |
| Page policy | A `Content-Security-Policy` on every page: `default-src 'none'`; scripts only with a per-load random nonce (so document HTML, event handlers and `javascript:` URLs never execute); `connect-src 'none'` (no fetch/XHR); no frames, objects, workers, forms or `<base>` changes. Images/media may load from `mdres:` (the app's resource handler), `data:` and, only while View ▸ Load Remote Images is on, `http(s):`; never from `file:`. | `MDReader/Sources/HTMLTemplate.swift` |
| WebKit | The web content process has **no `file:` access at all**. The page is loaded with an `mdres:///<document directory>/` base URL and every relative image, video, audio or font goes through `DocumentResourceHandler`, a `WKURLSchemeHandler` in the app process. It decides by extension (image, audiovisual content, font), opens the file once with `O_NOFOLLOW` (the last path component may not be a symlink; ancestors may), validates the open descriptor with `fstat` (regular file, size) and reads from that descriptor, so the bytes served are the bytes checked. Whole responses are capped at 64 MB; larger files are served only via `Range` in 16 MB chunks; files over 4 GB never. Stopped tasks are dropped before any read. Text, scripts, directories and unknown types are a 404 to the page. No `allowFileAccessFromFileURLs`, no `allowUniversalAccessFromFileURLs`. | `MDReader/Sources/PreviewWebView.swift` |
| Navigation | Every navigation, including `target=_blank` and `window.open`, goes through `LinkPolicy` with the real WebKit navigation type. Only link activations act. `http(s)`/`mailto` open in the default handler; other Markdown files open as new documents; images, PDFs, text and folders open in their app; anything launchable is only revealed in Finder: by UTType (apps, scripts, bundles, packages, internet locations, archives, disk images, aliases, symlinks), by executable bit, and by an explicit extension deny list for types that merely *conform* to text/XML but launch or install something (`.jnlp`, `.mobileconfig`, `.terminal`, `.url`, `.inetloc`, `.workflow`, `.shortcut`, certificates, …). Meta refresh, form posts and unknown URL schemes are dropped. | `MDReader/Sources/LinkPolicy.swift`, `PreviewViewController.swift` |
| Process | Hardened Runtime, Developer ID signed, notarized and stapled. Build provenance (commit, branch, date) stamped into `Info.plist` and shown in About; the stamp is `-dirty` if tracked files changed *or* untracked files sit in a compiled directory. `release.sh` refuses dirty or untracked inputs, refuses `SKIP_NOTARIZE` with `--publish`, runs `make ci` first, and fails closed if the tag already exists (no asset replacement). The release notes and Homebrew cask pin the zip's SHA-256. | `project.yml`, `Scripts/release.sh`, `Scripts/stamp-build.sh` |
| Remote content | **View ▸ Load Remote Images** off removes `http(s):` from the CSP *and* attaches a WebKit content rule list that blocks every `http`, `https`, `ws`, `wss` load in the web view, whatever element asked for it. Two independent layers, both tested. | `MDReader/Sources/HTMLTemplate.swift` (`RemoteContentBlocker`) |
| Network | The app makes exactly one kind of outbound request itself: `POST https://api.github.com/repos/ljack/macos-md-reader/issues` from the feedback sheet, only when the user presses Send and only with a token the user pasted. No telemetry, no update checks. | `MDReader/Sources/GitHubFeedback.swift` |
| Secrets | The optional GitHub token lives in the login Keychain (`kSecClassGenericPassword`), never in defaults or logs. Keychain errors are surfaced, not swallowed: a locked or denied Keychain fails the submission instead of silently falling back to the browser, and a failed write never deletes the old token (`SecItemUpdate`). Recommended scope: fine-grained token, Issues: write, this repo only. | `MDReader/Sources/GitHubFeedback.swift` (`TokenStore`) |

Regression tests: `MDReaderTests/PreviewIntegrationTests.swift` runs hostile Markdown through the
real renderer, document and `PreviewViewController` (its web view, delegates and `LinkPolicy`) with
the side effects recorded, and checks nothing happens without a click, a click acts exactly once,
and `window.open` is not a click. `WebViewHardeningTests.swift` checks the CSP, the resource handler
(no `file:`, no non-image files, no symlinked final component, relative and `../` images from
ordinary user directories) and the remote block list. `LinkPolicyTests.swift` and
`MarkdownRendererTests.swift` cover the navigation rules and the tag filters. `Samples/hostile.md`
is the manual version.

## Accepted risks (known, by design)

- **Remote images reveal your IP (default on).** A document with
  `![](https://tracker.example/pixel.png)` makes the preview fetch it, like a browser would.
  GitHub avoids this with a proxy; a local app cannot. Turn off **View ▸ Load Remote Images**
  and the CSP drops `http:`/`https:` from `img-src`/`media-src`: the app then never contacts a
  server because of a document.
- **Very large or pathological documents are a denial of service of the app**, not of the
  system: the 64 MB cap stops cmark's abort-on-allocation-failure, but rendering still runs in
  the app process, so a document engineered for worst-case parsing can hang or crash the whole
  app rather than one window. Moving rendering to a separate process is future work.
- **No App Sandbox.** The app runs with the user's normal file permissions (needed for
  live-reload of arbitrary paths, "Open in Terminal/Editor", set-as-default handler and
  relative resources next to the document). The WebContent process is still WebKit-sandboxed.
- **"Go to Terminal Session" talks to other apps.** It reads Teerminal's session manifest, sends
  Apple Events to iTerm2 / Terminal (entitlement `com.apple.security.automation.apple-events`,
  user consent via TCC) and can start a shell command or agent preset the user configured in
  Settings. It is a menu action only: nothing in a document can trigger it, and the document
  content never reaches the command line, only the document's directory does (shell-quoted).
- **Text files are opened as Markdown.** `.txt` is registered as an alternate type, so a hostile
  `.txt` is rendered under the same rules as `.md`. Same protections apply.
- **Clicking a link to a local image/PDF/text file opens it in its default app.** That app's
  handling of the file is its own responsibility.
- **Any image/media/font file on disk can be displayed** by a document that knows its path
  (`![](/Users/me/Pictures/x.jpg)`). It is shown to the user who already owns the file and
  cannot be sent anywhere (no script, no fetch, no forms). Content types outside image, media
  and font are never served.

## Dependencies

- [swift-cmark](https://github.com/swiftlang/swift-cmark) (`gfm` branch), pinned to an exact
  revision in `project.yml`. Updated by hand, with the revision's date in the commit message.
- [highlight.js](https://highlightjs.org) vendored as `MDReader/Resources/highlight.min.js`; it
  runs under the nonce but never evaluates document text as code.
- GitHub Actions in `.github/workflows` are pinned by commit SHA and updated by Dependabot.

## Automated checks

- [CodeQL](https://github.com/ljack/macos-md-reader/security/code-scanning) (Swift,
  `security-extended` queries) on every push and weekly.
- [OpenSSF Scorecard](https://securityscorecards.dev/viewer/?uri=github.com/ljack/macos-md-reader)
  weekly.
- GitHub secret scanning with push protection, Dependabot security updates.
- `make ci` (build, unit tests including the hardening and integration tests, launch smoke
  test) runs in the `pre-push` hook and before every `--publish` release. GitHub Actions runs
  the build and the unit tests; the launch smoke test is local only.
