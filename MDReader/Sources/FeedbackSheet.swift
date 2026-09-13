import AppKit

/// Sheet for filing a bug / feedback / idea as a GitHub issue.
final class FeedbackSheet: NSWindowController {
    private let kindControl = NSSegmentedControl()
    private let titleField = NSTextField()
    private let bodyView = NSTextView()
    private let contextCheckbox = NSButton(checkboxWithTitle: "Include app version and document name", target: nil, action: nil)
    private let tokenField = NSSecureTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let submitButton = NSButton(title: "Submit", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private let documentURL: URL?

    init(documentURL: URL?, initialKind: FeedbackKind = .feedback) {
        self.documentURL = documentURL
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
                            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        panel.title = "Send Feedback"
        super.init(window: panel)
        buildUI()
        kindControl.selectedSegment = initialKind.rawValue
        kindChanged()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        kindControl.segmentStyle = .texturedRounded
        kindControl.trackingMode = .selectOne
        kindControl.segmentCount = FeedbackKind.allCases.count
        for kind in FeedbackKind.allCases {
            kindControl.setLabel(kind.title, forSegment: kind.rawValue)
            kindControl.setImage(NSImage(systemSymbolName: kind.symbol, accessibilityDescription: kind.title), forSegment: kind.rawValue)
            kindControl.setImageScaling(.scaleProportionallyDown, forSegment: kind.rawValue)
        }
        kindControl.target = self
        kindControl.action = #selector(kindChanged)

        titleField.placeholderString = "Title"
        titleField.font = .systemFont(ofSize: 14)
        titleField.delegate = self

        bodyView.font = .systemFont(ofSize: 13)
        bodyView.isRichText = false
        bodyView.isAutomaticQuoteSubstitutionEnabled = false
        bodyView.allowsUndo = true
        bodyView.textContainerInset = NSSize(width: 6, height: 8)
        let scroll = NSScrollView()
        scroll.documentView = bodyView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        bodyView.autoresizingMask = [.width]
        bodyView.minSize = NSSize(width: 0, height: 0)
        bodyView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        bodyView.isVerticallyResizable = true
        bodyView.textContainer?.widthTracksTextView = true

        contextCheckbox.state = .on

        tokenField.placeholderString = "GitHub token (optional — without it, opens in browser)"
        tokenField.stringValue = TokenStore.load() ?? ""
        tokenField.font = .systemFont(ofSize: 12)
        let tokenHelp = NSButton(title: "", target: self, action: #selector(openTokenHelp))
        tokenHelp.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "Token help")
        tokenHelp.bezelStyle = .helpButton
        tokenHelp.isBordered = false
        tokenHelp.toolTip = "Create a fine-grained token with Issues: Read and write for \(GitHubFeedback.owner)/\(GitHubFeedback.repo)"
        let tokenRow = NSStackView(views: [tokenField, tokenHelp])
        tokenRow.orientation = .horizontal
        tokenRow.spacing = 6

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.lineBreakMode = .byTruncatingMiddle

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancel.keyEquivalent = "\u{1b}"
        submitButton.target = self
        submitButton.action = #selector(submit(_:))
        submitButton.keyEquivalent = "\r"
        submitButton.bezelStyle = .rounded
        cancel.bezelStyle = .rounded

        let buttons = NSStackView(views: [statusLabel, spinner, cancel, submitButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let repoLabel = NSTextField(labelWithString: "Files an issue in github.com/\(GitHubFeedback.owner)/\(GitHubFeedback.repo)")
        repoLabel.textColor = .secondaryLabelColor
        repoLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let stack = NSStackView(views: [kindControl, titleField, scroll, contextCheckbox, tokenRow, repoLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            titleField.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            scroll.widthAnchor.constraint(equalTo: titleField.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
            tokenRow.widthAnchor.constraint(equalTo: titleField.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: titleField.widthAnchor),
        ])
        window?.initialFirstResponder = titleField
        updateSubmitState()
    }

    private var kind: FeedbackKind { FeedbackKind(rawValue: kindControl.selectedSegment) ?? .feedback }

    @objc private func kindChanged() {
        switch kind {
        case .bug:
            titleField.placeholderString = "What went wrong?"
            bodyView.string = bodyView.string.isEmpty ? "Steps to reproduce:\n1. \n\nExpected:\n\nActual:\n" : bodyView.string
        case .feedback:
            titleField.placeholderString = "Feedback in one line"
        case .idea:
            titleField.placeholderString = "Feature idea"
        }
        submitButton.title = "File \(kind.title)"
    }

    private func updateSubmitState() {
        submitButton.isEnabled = !titleField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @objc private func openTokenHelp() {
        NSWorkspace.shared.open(URL(string: "https://github.com/settings/personal-access-tokens/new")!)
    }

    // MARK: Actions

    @objc private func cancel(_ sender: Any?) {
        window?.sheetParent?.endSheet(window!, returnCode: .cancel)
    }

    @objc private func submit(_ sender: Any?) {
        TokenStore.save(tokenField.stringValue)
        let report = FeedbackReport(kind: kind,
                                    title: titleField.stringValue.trimmingCharacters(in: .whitespaces),
                                    body: bodyView.string,
                                    includeContext: contextCheckbox.state == .on,
                                    documentURL: documentURL)
        setBusy(true)
        GitHubFeedback.submit(report) { [weak self] result in
            guard let self else { return }
            self.setBusy(false)
            switch result {
            case .success(.created(let url)):
                self.statusLabel.stringValue = "Filed: \(url.lastPathComponent)"
                self.window?.sheetParent?.endSheet(self.window!, returnCode: .OK)
                let alert = NSAlert()
                alert.messageText = "\(self.kind.title) filed"
                alert.informativeText = url.absoluteString
                alert.addButton(withTitle: "Open on GitHub")
                alert.addButton(withTitle: "Done")
                if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
            case .success(.openedInBrowser):
                self.window?.sheetParent?.endSheet(self.window!, returnCode: .OK)
            case .failure(let error):
                self.statusLabel.stringValue = error.localizedDescription
                self.statusLabel.textColor = .systemRed
            }
        }
    }

    private func setBusy(_ busy: Bool) {
        submitButton.isEnabled = !busy
        if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }
}

extension FeedbackSheet: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) { updateSubmitState() }
}
