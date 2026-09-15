import Foundation
import Security
import WebKit

enum HTMLTemplate {
    private static let css = load("preview", "css")
    private static let js = load("preview", "js")
    private static let hljs = load("highlight.min", "js")
    private static let hljsLight = load("github.min", "css")
    private static let hljsDark = load("github-dark.min", "css")

    static func warmUp() {
        _ = css; _ = js; _ = hljs; _ = hljsLight; _ = hljsDark
    }

    /// Content Security Policy for the preview page. The rendered Markdown is untrusted:
    /// it may carry raw HTML (`CMARK_OPT_UNSAFE`, like GitHub). Only the app's own scripts run
    /// (nonce), nothing may fetch/XHR, frame, embed, submit forms or change the base URL.
    /// Images and media may load through the app's `mdres:` resource handler (relative paths next
    /// to the document; the web process has no `file:` access) and, when `allowRemote`
    /// (View ▸ Load Remote Images), from http(s) so badges and hosted images work. Remote loads
    /// reveal the reader's IP address to the image host. See SECURITY.md.
    static func contentSecurityPolicy(nonce: String, allowRemote: Bool = RemoteContent.isEnabled) -> String {
        let local = "\(PreviewWebView.scheme): data: blob:"
        let sources = allowRemote ? local + " https: http:" : local
        return [
            "default-src 'none'",
            "script-src 'nonce-\(nonce)'",
            "style-src 'unsafe-inline'",
            "img-src \(sources)",
            "media-src \(sources)",
            "font-src \(PreviewWebView.scheme): data:",
            "connect-src 'none'",
            "object-src 'none'",
            "frame-src 'none'",
            "child-src 'none'",
            "worker-src 'none'",
            "base-uri 'none'",
            "form-action 'none'",
        ].joined(separator: "; ")
    }

    /// 128-bit random nonce, base64. New one per page load so document content can never guess it.
    static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = bytes.map { _ in UInt8.random(in: 0...255) }
        }
        return Data(bytes).base64EncodedString()
    }

    static func page(body: String, nonce: String = makeNonce(), allowRemote: Bool = RemoteContent.isEnabled) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy(nonce: nonce, allowRemote: allowRemote))">
        <meta name="color-scheme" content="light dark">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style>
        <style>
        @media (prefers-color-scheme: light) { \(hljsLight) }
        @media (prefers-color-scheme: dark) { \(hljsDark) }
        </style>
        </head>
        <body>
        <article id="content" class="markdown-body">\(body)</article>
        <script nonce="\(nonce)">\(hljs)</script>
        <script nonce="\(nonce)">\(js)</script>
        </body>
        </html>
        """
    }

    private static func load(_ name: String, _ ext: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }
}

// MARK: - Remote content preference

/// View ▸ Load Remote Images. On by default. Off makes the CSP refuse http(s) images and media,
/// so a document cannot make the app contact any server.
enum RemoteContent {
    static let changed = Notification.Name("MDReader.remoteContentChanged")
    private static let key = "loadRemoteImages"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    static func toggle() { isEnabled.toggle() }
}

/// Second, independent layer for "Load Remote Images: off": a WebKit content rule list that
/// blocks every http(s)/ws(s) load in the web view, whatever kind of element asked for it
/// (including `<link rel=preconnect>`-style hints the CSP does not govern). Compiled once at
/// launch; `apply` attaches or detaches it before each page load.
enum RemoteContentBlocker {
    static let ready = Notification.Name("MDReader.remoteContentBlockerReady")
    static let identifier = "MDReader.block-remote-v1"
    // WebKit's rule regex dialect has no alternation, so one rule per scheme.
    static let rules = """
    [{"trigger": {"url-filter": "^http://"},  "action": {"type": "block"}},
     {"trigger": {"url-filter": "^https://"}, "action": {"type": "block"}},
     {"trigger": {"url-filter": "^ws://"},    "action": {"type": "block"}},
     {"trigger": {"url-filter": "^wss://"},   "action": {"type": "block"}}]
    """
    private(set) static var ruleList: WKContentRuleList?

    static func compile(completion: ((WKContentRuleList?) -> Void)? = nil) {
        if let ruleList { completion?(ruleList); return }
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules) { list, error in
            if let error { NSLog("RemoteContentBlocker: compile failed: %@", String(describing: error)) }
            ruleList = list
            completion?(list)
            if list != nil { NotificationCenter.default.post(name: ready, object: nil) }
        }
    }

    /// Attach the block list when remote content is off, detach otherwise.
    static func apply(to webView: WKWebView, remoteEnabled: Bool = RemoteContent.isEnabled) {
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        if !remoteEnabled, let ruleList { controller.add(ruleList) }
    }
}
