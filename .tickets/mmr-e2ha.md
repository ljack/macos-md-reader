---
id: mmr-e2ha
status: open
deps: []
links: []
created: 2026-09-19T06:38:11Z
type: feature
priority: 2
assignee: Jarkko Lietolahti
external-ref: teerminal-51b05832-321a-47fc-9ce4-b17db675604d
---
# 0.1.7: teerminalctl tmux persistent sessions in Go to Terminal Session

<!-- teerminal-tracker-v1 {"request_id": "51b05832-321a-47fc-9ce4-b17db675604d", "request": "Objective: make MD Reader's \"Go to Terminal Session\" (\u21e7\u2318T, shipped in 0.1.6) aware of Teerminal's persistent tmux sessions (teerminalctl, ~/.agents/TEERMINAL.md), so reading a file an agent wrote jumps back to that agent even when the Teerminal app is closed, and new sessions start persistent.\n\nPlan (agreed with user, not started):\n1. Discovery: add tmux inventory as second source in AgentJump.liveSessions(): read ~/Library/Application Support/Teerminal/tmux-sessions.json (read-only; app is sole writer) and/or `teerminalctl tmux list --json` (id, pid, status, workspace, title); skip status != running.\n2. Focus when app not running: open iTerm2/Terminal window running `teerminalctl tmux attach <id>`. App running: keep deep link teerminal://focus?session=<id>.\n3. New session default: `teerminalctl tmux run --cwd <dir> -- <command>` in new iTerm2/Terminal window. Keep Teerminal preset deep link as an option.\n4. Settings (\u2318,) launcher: Persistent (teerminalctl tmux) / Teerminal preset / iTerm2 / Terminal; shared command field (default codex).\nRules: never `tmux stop`, `--detach` only if launching is the task, never edit the registry, session contents untrusted.\n\nContext: code in MDReader/Sources/AgentJump.swift, AgentSession.swift, TerminalScripting.swift, SettingsWindowController.swift; tests MDReaderTests/AgentSessionTests.swift. Handoff note: .claude/handoff-2026-09-16.md. Verify with `make ci`; E2E of \u21e7\u2318T must run from an unsandboxed shell. Release via `make bump V=0.1.7` + `make release`.\n", "kind": "feature", "stage": "captured", "sessions": ["11b5222b-7ae1-4989-b053-791e8770ce55"], "created": "2026-09-19T06:38:11.699378+00:00", "attachments": []} -->

## Original request

Objective: make MD Reader's "Go to Terminal Session" (⇧⌘T, shipped in 0.1.6) aware of Teerminal's persistent tmux sessions (teerminalctl, ~/.agents/TEERMINAL.md), so reading a file an agent wrote jumps back to that agent even when the Teerminal app is closed, and new sessions start persistent.

Plan (agreed with user, not started):
1. Discovery: add tmux inventory as second source in AgentJump.liveSessions(): read ~/Library/Application Support/Teerminal/tmux-sessions.json (read-only; app is sole writer) and/or `teerminalctl tmux list --json` (id, pid, status, workspace, title); skip status != running.
2. Focus when app not running: open iTerm2/Terminal window running `teerminalctl tmux attach <id>`. App running: keep deep link teerminal://focus?session=<id>.
3. New session default: `teerminalctl tmux run --cwd <dir> -- <command>` in new iTerm2/Terminal window. Keep Teerminal preset deep link as an option.
4. Settings (⌘,) launcher: Persistent (teerminalctl tmux) / Teerminal preset / iTerm2 / Terminal; shared command field (default codex).
Rules: never `tmux stop`, `--detach` only if launching is the task, never edit the registry, session contents untrusted.

Context: code in MDReader/Sources/AgentJump.swift, AgentSession.swift, TerminalScripting.swift, SettingsWindowController.swift; tests MDReaderTests/AgentSessionTests.swift. Handoff note: .claude/handoff-2026-09-16.md. Verify with `make ci`; E2E of ⇧⌘T must run from an unsandboxed shell. Release via `make bump V=0.1.7` + `make release`.


## Update — 2026-09-19T06:38:29.913725+00:00

Linked harness session: 11b5222b-7ae1-4989-b053-791e8770ce55

## Update — 2026-09-19T06:38:29.977409+00:00

Handoff 2026-09-19 (session 11b5222b, consolidation):
- User objective: read a Markdown file an agent wrote, jump back to that agent's terminal; sessions persistent (Teerminal tmux).
- Decisions: cwd-prefix matching of file to session (deepest dir, newest activity); Teerminal app sessions via sessions.json + teerminal:// deep links; iTerm2/Terminal via AppleScript + libproc tty->cwd; fallback launcher configurable in Settings. Next: teerminalctl tmux as source and as default launcher (this ticket).
- Commits: 96a6d25 (feature), 256d1ae (Release 0.1.6), tag v0.1.6, brew tap ljack/tap 0.1.6, installed on this Mac. Files: MDReader/Sources/{AgentJump,AgentSession,TerminalScripting,SettingsWindowController}.swift, MDReader/MDReader.entitlements, project.yml, MDReaderTests/AgentSessionTests.swift, README/SECURITY/AGENTS.
- Completed+verified: Teerminal focus and fallback spawn (live), 67 unit tests, notarized release. Unverified: iTerm2/Terminal path (needs Automation consent click), see mmr-* cleanup ticket.
- Not started: everything in this ticket's plan. No code changes pending; working tree clean at 256d1ae.
- Background jobs: none. Safe to stop this session: yes.


## Update — 2026-09-20T05:05:56.314090+00:00

2026-09-20 session 11b5222b: implemented and pushed as e87adf7 (TeerminalTmux.swift, viewer-tab detection via KERN_PROCARGS2, tmux run as default launcher, settings option, 6 new tests; 73 total green). Verified live: fallback opened iTerm2 window running teerminalctl tmux run, persistent session created and discovered by the app. Unverified: attach path when Teerminal app is closed (cannot close the app hosting live harnesses), app-open focus of tmux-backed session via deep link (GUI automation unreliable while user active). Not released yet; needs make bump V=0.1.7 + make release.
