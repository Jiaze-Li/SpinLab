#!/bin/zsh
# End of a GUI run: stop ONLY this run's verified test process (pid + start time + bundle +
# fixture must match the run record), remove the test prefs plist only if this run created it,
# release the GUI lock, then re-fingerprint production data by content and fail on any change
# or any unreadable file.
# Usage: finish.sh <run.json> <prod_before.txt>
set -uo pipefail
[[ $# -eq 2 ]] || { echo "usage: $0 <run.json> <prod_before.txt>" >&2; exit 2; }
HERE="${0:A:h}"; . "$HERE/_verify_run.sh"; BEFORE="$2"; RUN="${1:A}"
verify_run "$RUN" || exit 1
LOCK="$HOME/Library/Caches/spinlab-gui-validation.lock"
if [[ $RUN_ALIVE == 1 ]]; then
  kill "$PID"; for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$PID" 2>/dev/null || break; sleep 0.5; done
  kill -0 "$PID" 2>/dev/null && { echo "FAIL: pid $PID still running (lock kept)" >&2; exit 1; }
fi
[[ $RUN_PREF_PRE == 0 ]] && rm -f "$HOME/Library/Preferences/com.spinlab.guitest.plist"
[[ "$(cat "$LOCK/run" 2>/dev/null)" == "$RUN" ]] && rm -rf "$LOCK"
AFTER="${BEFORE:r}_after.txt"
"$HERE/prod_fingerprint.sh" > "$AFTER" || { echo "FAIL: production fingerprint after run could not be established"; exit 1; }
if diff -q "$BEFORE" "$AFTER" >/dev/null; then echo "PASS: production content hashes unchanged ($(grep -c '^[0-9a-f]\{64\}  ' "$AFTER") hashed files)"; else echo "FAIL: production data changed:"; diff "$BEFORE" "$AFTER" | head -20; exit 1; fi
