import AppKit

/// MD Reader ▸ Settings… : how "Go to Terminal Session" starts a session when none is running.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private let launcher = NSPopUpButton(frame: .zero, pullsDown: false)
    private let preset = NSTextField(string: "")
    private let command = NSTextField(string: "")

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 170),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func build() {
        for host in AgentSession.Host.allCases {
            launcher.addItem(withTitle: host.displayName)
            launcher.lastItem?.representedObject = host.rawValue
        }
        launcher.target = self
        launcher.action = #selector(changed(_:))
        for field in [preset, command] {
            field.target = self
            field.action = #selector(changed(_:))
            field.delegate = self
        }
        preset.placeholderString = "codex"
        command.placeholderString = "codex"
        preset.toolTip = "Teerminal preset slug: codex, claude, claude-box, sh…"
        command.toolTip = "Run in the new iTerm2 / Terminal window after cd; empty for just a shell"

        let grid = NSGridView(views: [
            [label("Open new sessions in:"), launcher],
            [label("Teerminal preset:"), preset],
            [label("iTerm2 / Terminal command:"), command],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(wrappingLabelWithString:
            "Go to Terminal Session (⇧⌘T) first looks for a Teerminal, iTerm2 or Terminal session already working in the document's folder and brings it to the front. These settings apply when there is none.")
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        let content = window!.contentView!
        content.addSubview(grid)
        content.addSubview(hint)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            hint.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 14),
            hint.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
            hint.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            preset.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])
    }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .right
        return l
    }

    func show() {
        launcher.selectItem(at: AgentSession.Host.allCases.firstIndex(of: AgentJump.launcher) ?? 0)
        preset.stringValue = AgentJump.preset
        command.stringValue = AgentJump.command
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func changed(_ sender: Any?) { save() }

    private func save() {
        if let raw = launcher.selectedItem?.representedObject as? String, let host = AgentSession.Host(rawValue: raw) {
            AgentJump.launcher = host
        }
        AgentJump.preset = preset.stringValue.trimmingCharacters(in: .whitespaces)
        AgentJump.command = command.stringValue.trimmingCharacters(in: .whitespaces)
    }
}

extension SettingsWindowController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) { save() }
}
