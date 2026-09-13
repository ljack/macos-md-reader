import AppKit
import WebKit

/// Floating find field over the web view. ⌘F shows it, Esc hides, ⏎ / ⇧⏎ step through matches.
final class FindBar: NSVisualEffectView, NSSearchFieldDelegate {
    private unowned let webView: WKWebView
    private let field = NSSearchField()
    private let statusLabel = NSTextField(labelWithString: "")

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.18)
            s.shadowBlurRadius = 12
            s.shadowOffset = NSSize(width: 0, height: -3)
            return s
        }()

        field.placeholderString = "Find"
        field.delegate = self
        field.target = self
        field.action = #selector(fieldAction(_:))
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.controlSize = .regular
        field.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let prev = NSButton(image: NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Previous")!,
                            target: self, action: #selector(prevAction))
        let next = NSButton(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next")!,
                            target: self, action: #selector(nextAction))
        let done = NSButton(title: "Done", target: self, action: #selector(hide))
        for b in [prev, next, done] {
            b.bezelStyle = .accessoryBarAction
            b.controlSize = .small
            b.translatesAutoresizingMaskIntoConstraints = false
        }

        let stack = NSStackView(views: [field, statusLabel, prev, next, done])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            field.widthAnchor.constraint(equalToConstant: 220),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Show / hide

    func show() {
        isHidden = false
        window?.makeFirstResponder(field)
        field.selectText(nil)
    }

    @objc func hide() {
        isHidden = true
        statusLabel.stringValue = ""
        window?.makeFirstResponder(webView)
    }

    // MARK: Find

    func find(backwards: Bool) {
        if isHidden { show(); return }
        let query = field.stringValue
        guard !query.isEmpty else { statusLabel.stringValue = ""; return }
        let config = WKFindConfiguration()
        config.backwards = backwards
        config.caseSensitive = false
        config.wraps = true
        webView.find(query, configuration: config) { [weak self] result in
            self?.statusLabel.stringValue = result.matchFound ? "" : "Not found"
        }
    }

    @objc private func fieldAction(_ sender: Any?) {
        find(backwards: NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false)
    }

    @objc private func prevAction() { find(backwards: true) }
    @objc private func nextAction() { find(backwards: false) }

    // MARK: NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        if field.stringValue.isEmpty {
            statusLabel.stringValue = ""
        } else {
            find(backwards: false)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            hide()
            return true
        }
        return false
    }
}
