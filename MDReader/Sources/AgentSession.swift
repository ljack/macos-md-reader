import Foundation

/// A live terminal session that may be working in the directory of the open document.
struct AgentSession: Equatable {
    enum Host: String, CaseIterable {
        case teerminal, iterm2, terminal

        var displayName: String {
            switch self {
            case .teerminal: return "Teerminal"
            case .iterm2: return "iTerm2"
            case .terminal: return "Terminal"
            }
        }
    }

    var host: Host
    /// Teerminal session UUID, iTerm2 session unique id, or Terminal "windowID/tabIndex".
    var id: String
    var directory: String
    var title: String
    var lastActivity: Date?
    var isActive: Bool

    /// The session whose directory is the deepest ancestor of `filePath`; ties go to the most
    /// recently active, then the currently selected one. `nil` when no session contains the file.
    static func best(for filePath: String, among sessions: [AgentSession]) -> AgentSession? {
        let file = (filePath as NSString).standardizingPath
        let candidates = sessions.filter { file.hasPrefix(($0.directory as NSString).standardizingPath + "/") }
        return candidates.max { a, b in
            if a.directory.count != b.directory.count { return a.directory.count < b.directory.count }
            let ta = a.lastActivity ?? .distantPast, tb = b.lastActivity ?? .distantPast
            if ta != tb { return ta < tb }
            return !a.isActive && b.isActive
        }
    }
}

// MARK: - Teerminal manifest

/// Teerminal writes `~/Library/Application Support/Teerminal/sessions.json` on every session change
/// (see Teerminal `State/SessionManifest.swift`), so the running sessions can be read without
/// talking to the app. The file is `[]` when Teerminal has quit cleanly.
enum TeerminalManifest {
    static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["TEERMINAL_SUPPORT_DIR"] {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Teerminal")
    }

    static var manifestURL: URL { supportDirectory.appendingPathComponent("sessions.json") }

    static func liveSessions() -> [AgentSession] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        return parse(data)
    }

    static func parse(_ data: Data) -> [AgentSession] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        return rows.compactMap { row in
            guard let id = row["sessionId"] as? String, let dir = row["workspaceDir"] as? String else { return nil }
            let status = row["status"] as? String ?? ""
            guard status != "exited", status != "killed" else { return nil }
            let stamp = row["lastActivityAt"] as? String
            let date = stamp.flatMap { iso.date(from: $0) ?? isoPlain.date(from: $0) }
                ?? (row["lastActivityAt"] as? Double).map { Date(timeIntervalSinceReferenceDate: $0) }
            let preset = row["presetSlug"] as? String ?? ""
            let name = row["workspaceName"] as? String ?? (dir as NSString).lastPathComponent
            return AgentSession(host: .teerminal, id: id, directory: dir,
                                title: preset.isEmpty ? name : "\(preset) in \(name)",
                                lastActivity: date, isActive: status == "waiting")
        }
    }

    static func focusURL(sessionID: String) -> URL? {
        URL(string: "teerminal://focus?session=\(sessionID)")
    }

    static func openURL(directory: String, preset: String) -> URL? {
        var comps = URLComponents()
        comps.scheme = "teerminal"
        comps.host = "open"
        comps.queryItems = [URLQueryItem(name: "dir", value: directory)]
        if !preset.isEmpty { comps.queryItems?.append(URLQueryItem(name: "preset", value: preset)) }
        return comps.url
    }
}
