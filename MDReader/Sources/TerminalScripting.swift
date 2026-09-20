import AppKit
import Darwin

/// iTerm2 and Terminal.app sessions via Apple Events: each tab's tty is asked over AppleScript and
/// the working directory is read from the processes on that tty with libproc, so no shell
/// integration is needed. Needs the `com.apple.security.automation.apple-events` entitlement and
/// the user's one-time Automation consent per app; when consent is missing the lists are empty.
enum TerminalScripting {
    static let iTermBundleID = "com.googlecode.iterm2"
    static let terminalBundleID = "com.apple.Terminal"

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    // MARK: Enumerate

    /// Rows of "<id>\t<tty>" from the app, one per session/tab.
    static func iTermSessions() -> [AgentSession] {
        guard isRunning(iTermBundleID) else { return [] }
        let script = """
        set out to ""
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set out to out & (unique id of s) & tab & (tty of s) & tab & (name of s) & linefeed
                    end repeat
                end repeat
            end repeat
        end tell
        return out
        """
        return sessions(host: .iterm2, fromRows: run(script))
    }

    static func terminalSessions() -> [AgentSession] {
        guard isRunning(terminalBundleID) else { return [] }
        let script = """
        set out to ""
        tell application "Terminal"
            repeat with w in windows
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    set out to out & (id of w) & "/" & i & tab & (tty of t) & tab & (custom title of t) & linefeed
                end repeat
            end repeat
        end tell
        return out
        """
        return sessions(host: .terminal, fromRows: run(script))
    }

    static func sessions(host: AgentSession.Host, fromRows rows: String) -> [AgentSession] {
        rows.split(separator: "\n").flatMap { line -> [AgentSession] in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else { return [] }
            let title = parts.count > 2 ? parts[2] : ""
            let viewer = attachedTmuxSession(onTTY: parts[1])
            return workingDirectories(onTTY: parts[1]).map {
                AgentSession(host: host, id: parts[0], directory: $0, title: title, lastActivity: nil,
                             isActive: false, viewsTmuxSession: viewer)
            }
        }
    }

    // MARK: Focus / open

    static func focus(_ session: AgentSession) -> Bool {
        switch session.host {
        case .iterm2:
            return run("""
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if unique id of s is "\(escaped(session.id))" then
                                tell s to select
                                tell t to select
                                tell w to select
                                activate
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return ""
            """) == "ok"
        case .terminal:
            let parts = session.id.split(separator: "/")
            guard parts.count == 2 else { return false }
            return run("""
            tell application "Terminal"
                set w to window id \(parts[0])
                set selected tab of w to tab \(parts[1]) of w
                set frontmost of w to true
                activate
                return "ok"
            end tell
            """) == "ok"
        case .teerminal, .tmux:
            return false
        }
    }

    static func openNew(host: AgentSession.Host, directory: String, command: String) -> Bool {
        openWindow(host: host, running: "cd \(shellQuoted(directory))" + (command.isEmpty ? "" : " && \(command)"))
    }

    /// The terminal app used for windows MD Reader opens itself (tmux attach / run): iTerm2 when installed.
    static var preferredTerminal: AgentSession.Host {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: iTermBundleID) != nil ? .iterm2 : .terminal
    }

    /// Focus the iTerm2 / Terminal tab that is attached to tmux session `id`, if there is one.
    static func focusViewer(ofTmuxSession id: String) -> Bool {
        let all = iTermSessions() + terminalSessions()
        guard let tab = all.first(where: { $0.viewsTmuxSession == id.lowercased() }) else { return false }
        return focus(tab)
    }

    static func openWindow(host: AgentSession.Host, running shellLine: String) -> Bool {
        switch host {
        case .iterm2:
            return run("""
            tell application "iTerm2"
                set w to (create window with default profile)
                tell current session of w to write text "\(escaped(shellLine))"
                activate
                return "ok"
            end tell
            """) == "ok"
        case .terminal:
            return run("""
            tell application "Terminal"
                do script "\(escaped(shellLine))"
                activate
                return "ok"
            end tell
            """) == "ok"
        case .teerminal, .tmux:
            return false
        }
    }

    // MARK: Helpers

    static func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func shellQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private(set) static var lastError: String?

    @discardableResult
    static func run(_ source: String) -> String {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            lastError = error[NSAppleScript.errorMessage] as? String
            return ""
        }
        lastError = nil
        return result?.stringValue ?? ""
    }

    /// `/dev/ttysNNN` of the controlling terminal of `pid`, or nil when it has none.
    static func ttyPath(ofPID pid: pid_t) -> String? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.e_tdev != 0, info.e_tdev != UInt32.max,
              let name = devname(dev_t(bitPattern: info.e_tdev), mode_t(S_IFCHR)) else { return nil }
        return "/dev/" + String(cString: name)
    }

    /// Current directory of one process (libproc), nil when it cannot be read.
    static func workingDirectory(ofPID pid: pid_t) -> String? {
        var vnode = proc_vnodepathinfo()
        let vsize = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnode, vsize) == vsize else { return nil }
        let path = withUnsafePointer(to: &vnode.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return path.isEmpty ? nil : path
    }

    /// argv of a process via sysctl KERN_PROCARGS2 (same-user processes only).
    static func arguments(ofPID pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
        let argc = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        var fields = buffer[MemoryLayout<Int32>.size..<size].split(separator: 0, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        guard !fields.isEmpty else { return [] }
        fields.removeFirst()                      // executable path
        fields = Array(fields.drop { $0.isEmpty }) // padding after it
        return Array(fields.prefix(argc))
    }

    /// PIDs whose controlling terminal is `tty`.
    static func pids(onTTY tty: String) -> [pid_t] {
        var st = stat()
        guard stat(tty, &st) == 0 else { return [] }
        let dev = UInt32(bitPattern: st.st_rdev)
        var count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return pids.prefix(Int(count)).filter { pid in
            guard pid > 0 else { return false }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size && info.e_tdev == dev
        }
    }

    /// The Teerminal tmux session id a `tmux attach` client on `tty` is viewing, if any.
    static func attachedTmuxSession(onTTY tty: String) -> String? {
        for pid in pids(onTTY: tty) {
            if let id = tmuxSessionID(fromArguments: arguments(ofPID: pid)) { return id }
        }
        return nil
    }

    /// `tmux … attach-session -t =teerminal-<uuid>` (Teerminal) or `tmux attach -t teerminal-<uuid>` → uuid.
    static func tmuxSessionID(fromArguments args: [String]) -> String? {
        guard let first = args.first, (first as NSString).lastPathComponent == "tmux" else { return nil }
        for arg in args {
            let name = arg.hasPrefix("=") ? String(arg.dropFirst()) : arg
            if name.hasPrefix("teerminal-") { return String(name.dropFirst("teerminal-".count)).lowercased() }
        }
        return nil
    }

    /// Working directories of every process whose controlling terminal is `tty`, deepest path first.
    static func workingDirectories(onTTY tty: String) -> [String] {
        var st = stat()
        guard stat(tty, &st) == 0 else { return [] }
        let dev = UInt32(bitPattern: st.st_rdev)
        var count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var dirs = Set<String>()
        for pid in pids.prefix(Int(count)) where pid > 0 {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.e_tdev == dev else { continue }
            var vnode = proc_vnodepathinfo()
            let vsize = Int32(MemoryLayout<proc_vnodepathinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnode, vsize) == vsize else { continue }
            let path = withUnsafePointer(to: &vnode.pvi_cdir.vip_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            if !path.isEmpty { dirs.insert(path) }
        }
        return dirs.sorted { $0.count > $1.count }
    }
}
