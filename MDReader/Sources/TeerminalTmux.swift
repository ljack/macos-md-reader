import Foundation

/// Teerminal's persistent sessions: harness processes kept alive in Teerminal's private tmux server,
/// listed and attached through `teerminalctl tmux …` (see ~/.agents/TEERMINAL.md). They outlive the
/// Teerminal app, so they are inventoried here directly rather than through the app's manifest.
enum TeerminalTmux {
    /// Where `teerminalctl` is looked for; Finder-launched apps do not see the user's shell PATH.
    static var candidatePaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/teerminalctl", "/opt/homebrew/bin/teerminalctl", "/usr/local/bin/teerminalctl"]
    }

    static var controlPath: String? {
        candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isAvailable: Bool { controlPath != nil }

    static var registryURL: URL { TeerminalManifest.supportDirectory.appendingPathComponent("tmux-sessions.json") }

    // MARK: Inventory

    /// Live sessions: `teerminalctl tmux list --json` when the CLI is present (knows which panes are
    /// dead), else the app-written registry, which lists sessions without liveness.
    static func liveSessions() -> [AgentSession] {
        if let ctl = controlPath, let out = run(ctl, ["tmux", "list", "--json"], timeout: 6) {
            return parseList(out)
        }
        guard let data = try? Data(contentsOf: registryURL) else { return [] }
        return parseRegistry(data)
    }

    static func parseList(_ data: Data) -> [AgentSession] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let id = row["id"] as? String, (row["status"] as? String) == "running" else { return nil }
            var dir = (row["workspace"] as? String) ?? ""
            if dir.isEmpty, let pid = row["pid"] as? Int, let cwd = TerminalScripting.workingDirectory(ofPID: pid_t(pid)) {
                dir = cwd
            }
            guard !dir.isEmpty else { return nil }
            let clients = row["clients"] as? Int ?? 0
            return AgentSession(host: .tmux, id: id.lowercased(), directory: dir,
                                title: row["title"] as? String ?? "", lastActivity: nil, isActive: clients > 0)
        }
    }

    static func parseRegistry(_ data: Data) -> [AgentSession] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let id = row["id"] as? String, let dir = row["workspaceDir"] as? String, !dir.isEmpty else { return nil }
            return AgentSession(host: .tmux, id: id.lowercased(), directory: dir,
                                title: row["title"] as? String ?? "", lastActivity: nil,
                                isActive: (row["attached"] as? Bool) ?? false)
        }
    }

    /// tmux session name for a Teerminal session id, as seen in `tmux attach` client argv.
    static func sessionName(_ id: String) -> String { "teerminal-\(id.lowercased())" }

    // MARK: Command lines (run inside a terminal window, so they stay interactive)

    static func attachCommand(_ id: String) -> String {
        "\(TerminalScripting.shellQuoted(controlPath ?? "teerminalctl")) tmux attach \(TerminalScripting.shellQuoted(id))"
    }

    /// `teerminalctl tmux run --cwd <dir> -- <command>`; `command` is the user's own shell text.
    static func runCommand(directory: String, command: String) -> String {
        let harness = command.trimmingCharacters(in: .whitespaces)
        return "\(TerminalScripting.shellQuoted(controlPath ?? "teerminalctl")) tmux run --cwd \(TerminalScripting.shellQuoted(directory)) -- \(harness.isEmpty ? "$SHELL" : harness)"
    }

    // MARK: Helpers

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = DispatchTime.now() + timeout
        let group = DispatchGroup()
        group.enter()
        var data = Data()
        DispatchQueue.global().async {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if group.wait(timeout: deadline) == .timedOut {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}
