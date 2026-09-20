import AppKit
import os

/// "Go to Terminal Session": bring the terminal that is working in the document's directory to
/// the front, or start one there the way the user configured it.
enum AgentJump {
    static let log = Logger(subsystem: "fi.jarkkolietolahti.MDReader", category: "AgentJump")

    enum Keys {
        static let launcher = "agentLauncher"      // AgentSession.Host raw value
        static let preset = "agentTeerminalPreset" // Teerminal preset slug
        static let command = "agentCommand"        // harness command: tmux run / iTerm2 / Terminal
    }

    static var teerminalInstalled: Bool {
        NSWorkspace.shared.urlForApplication(toOpen: URL(string: "teerminal://focus")!) != nil
    }

    static var launcher: AgentSession.Host {
        get {
            if let raw = UserDefaults.standard.string(forKey: Keys.launcher), let host = AgentSession.Host(rawValue: raw) {
                return host
            }
            if TeerminalTmux.isAvailable { return .tmux }
            if teerminalInstalled { return .teerminal }
            return MarkdownDocument.iTermURL != nil ? .iterm2 : .terminal
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.launcher) }
    }

    static var preset: String {
        get { UserDefaults.standard.string(forKey: Keys.preset) ?? "codex" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.preset) }
    }

    static var command: String {
        get { UserDefaults.standard.string(forKey: Keys.command) ?? "codex" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.command) }
    }

    /// Every live session from every host that can be asked, Teerminal first (cheapest, no consent).
    static func liveSessions() -> [AgentSession] {
        AgentSession.deduplicated(TeerminalManifest.liveSessions() + TeerminalTmux.liveSessions()
            + TerminalScripting.iTermSessions() + TerminalScripting.terminalSessions())
    }

    /// Runs off the main thread (Apple Events and /proc walks can take a moment), then focuses or opens.
    static func go(to fileURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        let path = fileURL.path
        let dir = fileURL.deletingLastPathComponent().path
        DispatchQueue.global(qos: .userInitiated).async {
            let sessions = liveSessions()
            log.notice("go: \(path, privacy: .public) candidates \(sessions.map { "\($0.host.rawValue):\($0.id.prefix(8))@\($0.directory)" }.joined(separator: ", "), privacy: .public)")
            if let scriptError = TerminalScripting.lastError { log.error("apple events: \(scriptError, privacy: .public)") }
            let result: Result<String, Error>
            if let hit = AgentSession.best(for: path, among: sessions) {
                log.notice("focus \(hit.host.rawValue, privacy: .public) \(hit.id, privacy: .public)")
                result = focus(hit) ? .success("Switched to \(hit.title.isEmpty ? hit.host.displayName : hit.title)")
                    : .failure(failure("Could not focus the \(hit.host.displayName) session.", TerminalScripting.lastError))
            } else {
                log.notice("no session for \(dir, privacy: .public); opening via \(launcher.rawValue, privacy: .public)")
                result = open(directory: dir)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func focus(_ session: AgentSession) -> Bool {
        switch session.host {
        case .teerminal:
            guard let url = TeerminalManifest.focusURL(sessionID: session.id) else { return false }
            return NSWorkspace.shared.open(url)
        case .iterm2, .terminal:
            return TerminalScripting.focus(session)
        case .tmux:
            // A tab already viewing it wins; otherwise attach a fresh view in a new terminal window.
            if TerminalScripting.focusViewer(ofTmuxSession: session.id) { return true }
            return TerminalScripting.openWindow(host: TerminalScripting.preferredTerminal,
                                                running: TeerminalTmux.attachCommand(session.id))
        }
    }

    static func open(directory: String) -> Result<String, Error> {
        let host = launcher
        switch host {
        case .tmux:
            guard TeerminalTmux.isAvailable else {
                return .failure(failure("teerminalctl was not found.", "Looked in " + TeerminalTmux.candidatePaths.joined(separator: ", ")))
            }
            let terminal = TerminalScripting.preferredTerminal
            let ok = TerminalScripting.openWindow(host: terminal, running: TeerminalTmux.runCommand(directory: directory, command: command))
            return ok ? .success("Started persistent \(command.isEmpty ? "shell" : command) in \(terminal.displayName)")
                : .failure(failure("\(terminal.displayName) did not open a session.", TerminalScripting.lastError))
        case .teerminal:
            guard teerminalInstalled else { return .failure(failure("Teerminal is not installed.", nil)) }
            guard let url = TeerminalManifest.openURL(directory: directory, preset: preset),
                  NSWorkspace.shared.open(url) else { return .failure(failure("Teerminal did not open.", nil)) }
            return .success("Opened \(preset.isEmpty ? "a session" : preset) in Teerminal")
        case .iterm2, .terminal:
            let ok = TerminalScripting.openNew(host: host, directory: directory, command: command)
            return ok ? .success("Opened \(command.isEmpty ? "a shell" : command) in \(host.displayName)")
                : .failure(failure("\(host.displayName) did not open a session.", TerminalScripting.lastError))
        }
    }

    private static func failure(_ message: String, _ detail: String?) -> NSError {
        var info: [String: Any] = [NSLocalizedDescriptionKey: message]
        if let detail, !detail.isEmpty {
            info[NSLocalizedRecoverySuggestionErrorKey] = detail
        } else {
            info[NSLocalizedRecoverySuggestionErrorKey] =
                "Choose how new sessions open in MD Reader ▸ Settings…. Apple Events to iTerm2 and Terminal need Automation permission in System Settings ▸ Privacy & Security."
        }
        return NSError(domain: "MDReader.AgentJump", code: 1, userInfo: info)
    }
}
