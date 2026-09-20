import XCTest
@testable import MDReader

final class TeerminalTmuxTests: XCTestCase {
    func testParsesListKeepsRunningOnly() {
        let json = """
        [{"id":"11B5222B-7AE1-4989-B053-791E8770CE55","name":"teerminal-11b5222b","pid":14696,"status":"running","clients":2,"title":"macos-md-reader-4f","workspace":"/Users/j/_dev/macos-md-reader"},
         {"id":"0ce58f0b-95e2-47bd-b1f6-66f3e873b225","name":"teerminal-0ce58f0b","pid":42160,"status":"stopped","clients":1,"title":"External","workspace":"/Users/j/_dev/teerminal"},
         {"id":"aaaaaaaa-0000-0000-0000-000000000000","name":"x","pid":1,"status":"running","clients":0,"title":"no dir","workspace":""}]
        """
        let s = TeerminalTmux.parseList(Data(json.utf8))
        // The third row has no workspace; pid 1 (launchd) cwd is "/" and is only used when readable.
        XCTAssertTrue(s.contains { $0.id == "11b5222b-7ae1-4989-b053-791e8770ce55" && $0.host == .tmux && $0.isActive && $0.directory == "/Users/j/_dev/macos-md-reader" })
        XCTAssertFalse(s.contains { $0.id.hasPrefix("0ce58f0b") })
        XCTAssertEqual(TeerminalTmux.parseList(Data("nope".utf8)), [])
    }

    func testParsesRegistry() {
        let json = """
        [{"attached":true,"createdAt":"2026-09-16T05:16:13Z","id":"0CE58F0B-95E2-47BD-B1F6-66F3E873B225","presetSlug":"sh","title":"External — sysi6","workspaceDir":"/Users/j/_dev/teerminal","workspaceID":"W","workspaceName":"teerminal"}]
        """
        let s = TeerminalTmux.parseRegistry(Data(json.utf8))
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].id, "0ce58f0b-95e2-47bd-b1f6-66f3e873b225")
        XCTAssertEqual(s[0].directory, "/Users/j/_dev/teerminal")
        XCTAssertTrue(s[0].isActive)
    }

    func testDeduplicationPrefersAppEntryAndDropsViewerTabs() {
        let app = AgentSession(host: .teerminal, id: "ABC-1", directory: "/r", title: "", lastActivity: nil, isActive: false)
        let tmuxSame = AgentSession(host: .tmux, id: "abc-1", directory: "/r", title: "", lastActivity: nil, isActive: false)
        let tmuxOther = AgentSession(host: .tmux, id: "def-2", directory: "/r", title: "", lastActivity: nil, isActive: false)
        let viewer = AgentSession(host: .iterm2, id: "t1", directory: "/r", title: "", lastActivity: nil, isActive: false, viewsTmuxSession: "def-2")
        let plainTab = AgentSession(host: .iterm2, id: "t2", directory: "/r", title: "", lastActivity: nil, isActive: false)
        let out = AgentSession.deduplicated([app, tmuxSame, tmuxOther, viewer, plainTab])
        XCTAssertEqual(out.map(\.id), ["ABC-1", "def-2", "t2"])
    }

    func testCommandLinesAreQuoted() {
        let run = TeerminalTmux.runCommand(directory: "/Users/j/My Docs", command: "codex --resume")
        XCTAssertTrue(run.hasSuffix("tmux run --cwd '/Users/j/My Docs' -- codex --resume"), run)
        XCTAssertTrue(TeerminalTmux.runCommand(directory: "/r", command: "  ").hasSuffix("-- $SHELL"))
        XCTAssertTrue(TeerminalTmux.attachCommand("11b5222b").hasSuffix("tmux attach '11b5222b'"))
        XCTAssertEqual(TeerminalTmux.sessionName("ABC"), "teerminal-abc")
    }

    func testTmuxClientArgumentsYieldSessionID() {
        let teerminalStyle = ["/opt/homebrew/bin/tmux", "-S", "/x/server.sock", "-f", "/x/teerminal.conf", "-u",
                              "attach-session", "-f", "ignore-size", "-t", "=teerminal-A8FCB979-E502-4DDA-9053-17B8373A2B2B"]
        XCTAssertEqual(TerminalScripting.tmuxSessionID(fromArguments: teerminalStyle), "a8fcb979-e502-4dda-9053-17b8373a2b2b")
        XCTAssertEqual(TerminalScripting.tmuxSessionID(fromArguments: ["tmux", "attach", "-t", "teerminal-abc"]), "abc")
        XCTAssertNil(TerminalScripting.tmuxSessionID(fromArguments: ["zsh", "-l"]))
        XCTAssertNil(TerminalScripting.tmuxSessionID(fromArguments: ["tmux", "attach", "-t", "other"]))
    }

    func testProcessArgumentsOfSelfAreReadable() {
        let args = TerminalScripting.arguments(ofPID: getpid())
        XCTAssertFalse(args.isEmpty)
        XCTAssertNotNil(TerminalScripting.workingDirectory(ofPID: getpid()))
    }
}
