---
id: mmr-ix35
status: open
deps: []
links: []
created: 2026-09-19T06:38:29Z
type: task
priority: 2
assignee: Jarkko Lietolahti
external-ref: teerminal-551e728d-bf35-47ca-942f-d2d2b4b8936e
---
# Verify iTerm2 path and clean up after 0.1.6 Go to Terminal Session

<!-- teerminal-tracker-v1 {"request_id": "551e728d-bf35-47ca-942f-d2d2b4b8936e", "request": "Unverified / cleanup items left from the 0.1.6 \"Go to Terminal Session\" work (commit 96a6d25, released 256d1ae):\n- iTerm2/Terminal path never exercised end to end: first \u21e7\u2318T with iTerm2 running triggers the macOS Automation consent prompt; needs a human click, then verify tab focus and cwd matching.\n- Teerminal deep-link focus once showed \"No workspace selected\" (two dev builds of Teerminal running share the URL scheme); later runs fine; not reproducible.\n- Leftover Teerminal `sh` session \"jumptest\" spawned during testing (scratch dir); safe to close.\n- Spotlight index on this Mac is broken machine-wide (1 of 93 apps indexed); needs `sudo mdutil -E /System/Volumes/Data`. Not an MD Reader bug.\n", "kind": "task", "stage": "captured", "sessions": ["11b5222b-7ae1-4989-b053-791e8770ce55"], "created": "2026-09-19T06:38:29.847250+00:00", "attachments": []} -->

## Original request

Unverified / cleanup items left from the 0.1.6 "Go to Terminal Session" work (commit 96a6d25, released 256d1ae):
- iTerm2/Terminal path never exercised end to end: first ⇧⌘T with iTerm2 running triggers the macOS Automation consent prompt; needs a human click, then verify tab focus and cwd matching.
- Teerminal deep-link focus once showed "No workspace selected" (two dev builds of Teerminal running share the URL scheme); later runs fine; not reproducible.
- Leftover Teerminal `sh` session "jumptest" spawned during testing (scratch dir); safe to close.
- Spotlight index on this Mac is broken machine-wide (1 of 93 apps indexed); needs `sudo mdutil -E /System/Volumes/Data`. Not an MD Reader bug.


## Update — 2026-09-19T06:38:46.118352+00:00

Linked harness session: 11b5222b-7ae1-4989-b053-791e8770ce55

## Update — 2026-09-19T06:38:46.191418+00:00

Handoff 2026-09-19 (session 11b5222b): nothing executed on these items; all still pending. Safe to stop the session.
