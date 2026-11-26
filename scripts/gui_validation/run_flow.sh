#!/bin/zsh
# Run a cua run_script flow against this run's verified test instance (single session, bounded).
# Usage: run_flow.sh <run.json> <flow.js>   (run record from launch.sh; pid, start time,
# bundle and fixture must match and the run must hold the GUI lock.)
set -euo pipefail
[[ $# -eq 2 ]] || { echo "usage: $0 <run.json> <flow.js>" >&2; exit 2; }
. "${0:A:h}/_verify_run.sh"; FLOW="$2"
verify_run "$1" || exit 1
[[ $RUN_ALIVE == 1 ]] || { echo "refuse: test instance not running" >&2; exit 1; }
LOCKRUN=$(cat "$HOME/Library/Caches/spinlab-gui-validation.lock/run" 2>/dev/null || true)
[[ "$LOCKRUN" == "${1:A}" ]] || { echo "refuse: this run does not hold the GUI lock" >&2; exit 1; }
cua-driver permissions status --json | python3 -I -c 'import json,sys;d=json.load(sys.stdin);sys.exit(0 if d.get("accessibility") and d.get("screen_recording") else 1)' \
  || { echo "refuse: Cua permissions missing" >&2; exit 1; }
ARGS=$(PID="$PID" FLOW="$FLOW" python3 -I -c 'import json,os;print(json.dumps({"script":open(os.environ["FLOW"]).read().replace("__PID__",os.environ["PID"])}))')
RAW=$(perl -e 'alarm 180; exec @ARGV' cua-driver call run_script "$ARGS")
# drop the inline screenshot/call log; print only the script result, fail unless it says pass
print -r -- "$RAW" | python3 -I -c '
import json,sys
d=json.load(sys.stdin)
for k in ("screenshot_png_b64","calls"): d.pop(k,None)
print(json.dumps(d,indent=1,ensure_ascii=False))
r=d.get("value")
sys.exit(0 if d.get("ok") and isinstance(r,dict) and r.get("pass") is True else 1)'
