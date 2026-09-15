import AppKit
import WebKit

final class PreviewViewController: NSViewController, WKNavigationDelegate, WKUIDelegate {
    private unowned let document: MarkdownDocument
    private(set) var webView: WKWebView!
    private var findBar: FindBar!
    private var pageLoaded = false
    private var updateQueued = false

    init(document: MarkdownDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: View

    override func loadView() {
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 840),
                            configuration: PreviewWebView.makeConfiguration())
        web.navigationDelegate = self
        web.uiDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        web.allowsMagnification = true
        web.allowsBackForwardNavigationGestures = false
        web.pageZoom = Zoom.current
        web.translatesAutoresizingMaskIntoConstraints = false
        webView = web

        let container = NSView(frame: web.frame)
        container.addSubview(web)

        let bar = FindBar(webView: web)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.isHidden = true
        container.addSubview(bar)
        findBar = bar

        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            web.topAnchor.constraint(equalTo: container.topAnchor),
            web.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bar.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
        ])
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(zoomChanged), name: Zoom.changed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(remoteContentChanged), name: RemoteContent.changed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(remoteContentChanged), name: RemoteContentBlocker.ready, object: nil)
        loadFullPage()
    }

    // MARK: Rendering

    private func loadFullPage() {
        pageLoaded = false
        RemoteContentBlocker.apply(to: webView)
        let result = MarkdownRenderer.render(document.text)
        let page = HTMLTemplate.page(body: result.html)
        webView.loadHTMLString(page, baseURL: baseURL)
    }

    private func pushUpdate() {
        guard pageLoaded else { updateQueued = true; return }
        let result = MarkdownRenderer.render(document.text)
        guard let data = try? JSONSerialization.data(withJSONObject: result.html, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__md && window.__md.update(\(json));") { _, _ in }
    }

    /// Called by the document after it re-read the file.
    func contentDidChange(fullReload: Bool) {
        if fullReload { loadFullPage() } else { pushUpdate() }
    }

    // MARK: Actions (responder chain)

    @objc func reloadDocument(_ sender: Any?) {
        if !document.reloadFromDisk(force: true) { loadFullPage() }
    }

    @objc func zoomIn(_ sender: Any?) { Zoom.step(+1) }
    @objc func zoomOut(_ sender: Any?) { Zoom.step(-1) }
    @objc func actualSize(_ sender: Any?) { Zoom.reset() }

    @objc private func zoomChanged() {
        webView.pageZoom = Zoom.current
    }

    /// The CSP lives in the page head, so a policy change needs a full reload.
    @objc private func remoteContentChanged() {
        loadFullPage()
    }

    @objc func showFind(_ sender: Any?) { findBar.show() }
    @objc func findNext(_ sender: Any?) { findBar.find(backwards: false) }
    @objc func findPrevious(_ sender: Any?) { findBar.find(backwards: true) }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoaded = true
        if updateQueued { updateQueued = false; pushUpdate() }
        onPageLoaded?()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let action = LinkPolicy.action(for: url,
                                       isLinkClick: navigationAction.navigationType == .linkActivated,
                                       base: baseURL)
        if action == .allowInPage { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        perform(action)
    }

    // MARK: WKUIDelegate (target=_blank, window.open)

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Same rule as decidePolicyFor: only a real link activation may act. A programmatic
        // window.open is .other and ends up as .block.
        if let url = navigationAction.request.url {
            perform(LinkPolicy.action(for: url,
                                      isLinkClick: navigationAction.navigationType == .linkActivated,
                                      base: baseURL))
        }
        return nil
    }

    private var baseURL: URL? { PreviewWebView.baseURL(forDirectory: document.fileURL?.deletingLastPathComponent()) }

    // MARK: Test hooks

    /// Replaces the side effects of a navigation decision (integration tests record instead of opening).
    var actionHandler: ((LinkPolicy.Action) -> Void)?
    /// Called after every full page load.
    var onPageLoaded: (() -> Void)?

    private func perform(_ action: LinkPolicy.Action) {
        if let actionHandler { actionHandler(action); return }
        switch action {
        case .allowInPage, .block:
            break
        case .openMarkdown(let url):
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSAlert(error: error).runModal() }
            }
        case .openFile(let url), .openExternal(let url):
            NSWorkspace.shared.open(url)
        case .revealFile(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

// MARK: - Zoom

enum Zoom {
    static let changed = Notification.Name("MDReader.zoomChanged")
    private static let key = "pageZoom"
    private static let levels: [CGFloat] = [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    static var current: CGFloat {
        let v = UserDefaults.standard.double(forKey: key)
        return v > 0 ? CGFloat(v) : 1.0
    }

    static func step(_ direction: Int) {
        let cur = current
        let idx = levels.firstIndex(where: { abs($0 - cur) < 0.01 }) ?? 5
        let next = levels[max(0, min(levels.count - 1, idx + direction))]
        set(next)
    }

    static func reset() { set(1.0) }

    private static func set(_ value: CGFloat) {
        UserDefaults.standard.set(Double(value), forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }
}
