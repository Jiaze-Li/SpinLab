#!/bin/zsh
# End of a GUI run: stop ONLY the verified test pid, remove its own prefs plist,
# re-fingerprint production data by content and fail if anything changed.
# Usage: finish.sh <pid> <prod_before.txt>
set -uo pipefail
[[ $# -eq 2 ]] || { echo "usage: $0 <pid> <prod_before.txt>" >&2; exit 2; }
PID="$1"; BEFORE="$2"; HERE=$(cd "$(dirname "$0")" && pwd)
CMD=$(ps -o command= -p "$PID" 2>/dev/null || true)
if [[ -n "$CMD" ]]; then
  [[ "$CMD" == *"/SpinLabGUITest.app/Contents/MacOS/SpinLabGUITest "*"--spinlab-isolated-config "* ]] \
    || { echo "refuse: pid $PID is not an isolated SpinLabGUITest instance; not killing" >&2; exit 1; }
  kill "$PID"; for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$PID" 2>/dev/null || break; sleep 0.5; done
  kill -0 "$PID" 2>/dev/null && { echo "FAIL: pid $PID still running" >&2; exit 1; }
fi
rm -f "$HOME/Library/Preferences/com.spinlab.guitest.plist"
AFTER="${BEFORE:r}_after.txt"
"$HERE/prod_fingerprint.sh" > "$AFTER"
if diff -q "$BEFORE" "$AFTER" >/dev/null; then echo "PASS: production content hashes unchanged ($(grep -vc '^##' "$AFTER") files)"; else echo "FAIL: production data changed:"; diff "$BEFORE" "$AFTER" | head -20; exit 1; fi
