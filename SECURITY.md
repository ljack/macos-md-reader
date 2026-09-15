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
2. read any file other than resources referenced *relative to the document* (images, media);
3. navigate the preview to a remote site or submit data anywhere;
4. exfiltrate document content or local files over the network;
5. crash the app in a way that is more than a denial of service of one window.

**Out of scope.** Physical access, a compromised macOS account, malicious builds not from the
signed and notarized release, remote images/media that reveal the user's IP address to the
image host (see "Accepted risks"), and content that merely *looks* misleading.

## How the promises are kept

| Layer | Mechanism | Where |
|---|---|---|
| Rendering | cmark-gfm with the GFM `tagfilter` extension: `<script>`, `<style>`, `<iframe>`, `<object>`, `<embed>`, `<textarea>`, `<title>`, `<xmp>`, `<noembed>`, `<noframes>`, `<plaintext>` are escaped, matching GitHub. Other raw HTML is kept (`CMARK_OPT_UNSAFE`) for fidelity. | `MDReader/Sources/MarkdownRenderer.swift` |
| Page policy | A `Content-Security-Policy` on every page: `default-src 'none'`; scripts only with a per-load random nonce (so document HTML, event handlers and `javascript:` URLs never execute); `connect-src 'none'` (no fetch/XHR); no frames, objects, workers, forms or `<base>` changes. Images/media may load from `file:`, `data:` and, only while View ▸ Load Remote Images is on, `http(s):`. | `MDReader/Sources/HTMLTemplate.swift` |
| WebKit | Default `WKWebViewConfiguration`: no `allowFileAccessFromFileURLs`, no `allowUniversalAccessFromFileURLs`. Relative images work because the page's base URL is the document directory. | `MDReader/Sources/LinkPolicy.swift` (`PreviewWebView`) |
| Navigation | Every navigation goes through `LinkPolicy`. Only user clicks act. `http(s)`/`mailto` open in the default handler; other Markdown files open as new documents; images, PDFs, text and folders open in their app; anything launchable (apps, scripts, `.command`, `.webloc`, archives, disk images, symlinks, executable bit) is only revealed in Finder. Meta refresh, form posts and unknown URL schemes are dropped. | `MDReader/Sources/LinkPolicy.swift`, `PreviewViewController.swift` |
| Process | Hardened Runtime, Developer ID signed, notarized and stapled. Build provenance (commit, branch, date) stamped into `Info.plist` and shown in About; the release notes and Homebrew cask pin the zip's SHA-256. | `project.yml`, `Scripts/release.sh`, `Scripts/stamp-build.sh` |
| Network | The app makes exactly one kind of outbound request itself: `POST https://api.github.com/repos/ljack/macos-md-reader/issues` from the feedback sheet, only when the user presses Send and only with a token the user pasted. No telemetry, no update checks. | `MDReader/Sources/GitHubFeedback.swift` |
| Secrets | The optional GitHub token lives in the login Keychain (`kSecClassGenericPassword`), never in defaults or logs. Recommended scope: fine-grained token, Issues: write, this repo only. | `MDReader/Sources/GitHubFeedback.swift` (`TokenStore`) |

Regression tests: `MDReaderTests/WebViewHardeningTests.swift` loads hostile HTML into a real
`WKWebView` and checks scripts do not run, `fetch` of a local file fails, frames are blocked and
relative images still load. `MDReaderTests/LinkPolicyTests.swift` covers the navigation rules.
`Samples/hostile.md` is the manual version.

## Accepted risks (known, by design)

- **Remote images reveal your IP (default on).** A document with
  `![](https://tracker.example/pixel.png)` makes the preview fetch it, like a browser would.
  GitHub avoids this with a proxy; a local app cannot. Turn off **View ▸ Load Remote Images**
  and the CSP drops `http:`/`https:` from `img-src`/`media-src`: the app then never contacts a
  server because of a document.
- **No App Sandbox.** The app runs with the user's normal file permissions (needed for
  live-reload of arbitrary paths, "Open in Terminal/Editor", set-as-default handler and
  relative resources next to the document). The WebContent process is still WebKit-sandboxed.
- **Text files are opened as Markdown.** `.txt` is registered as an alternate type, so a hostile
  `.txt` is rendered under the same rules as `.md`. Same protections apply.
- **Clicking a link to a local image/PDF/text file opens it in its default app.** That app's
  handling of the file is its own responsibility.

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
- `make ci` (build, unit tests including the hardening tests, launch smoke test) runs in the
  `pre-push` hook and in GitHub Actions.
