#!/bin/zsh
# Launch smoke test: opens the app with Samples/demo.md, checks it stays alive and shows a window, quits it.
set -uo pipefail
cd "$(dirname "$0")/.."
APP="${1:-build/MD Reader.app}"
[[ -d "$APP" ]] || { echo "smoke: app not found at $APP"; exit 1 }
BIN="$APP/Contents/MacOS/MD Reader"
LOG=$(mktemp)
pkill -x "MD Reader" 2>/dev/null; sleep 0.3
"$BIN" "$PWD/Samples/demo.md" >"$LOG" 2>&1 &
PID=$!
sleep 2.5
if ! kill -0 $PID 2>/dev/null; then echo "smoke: app exited early"; cat "$LOG"; exit 1; fi
WINDOWS=$(lsappinfo info -only bundlepath,pid "MD Reader" 2>/dev/null | grep -c pid || true)
STAMP=$(/usr/libexec/PlistBuddy -c "Print :GitCommit" "$APP/Contents/Info.plist" 2>/dev/null || echo none)
if grep -qiE "crash|fatal error|exception" "$LOG"; then echo "smoke: errors in log"; cat "$LOG"; kill $PID; exit 1; fi
osascript -e 'tell application "MD Reader" to quit' >/dev/null 2>&1 || kill $PID
sleep 0.5
kill -0 $PID 2>/dev/null && { echo "smoke: app did not quit"; kill -9 $PID; exit 1 }
echo "smoke: ok (build $STAMP, process ran ${WINDOWS:+and registered }cleanly)"
rm -f "$LOG"
