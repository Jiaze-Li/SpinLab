#!/bin/zsh
# Run a cua run_script flow against ONE verified test pid (single session, bounded).
# Usage: run_flow.sh <pid> <flow.js>   (the pid's command line must be a SpinLabGUITest
# launched with isolated flags; anything else is refused.)
set -euo pipefail
[[ $# -eq 2 ]] || { echo "usage: $0 <pid> <flow.js>" >&2; exit 2; }
PID="$1"; FLOW="$2"
[[ "$PID" =~ '^[0-9]+$' ]] || { echo "bad pid" >&2; exit 2; }
CMD=$(ps -o command= -p "$PID" 2>/dev/null) || { echo "refuse: pid $PID not running" >&2; exit 1; }
[[ "$CMD" == *"/SpinLabGUITest.app/Contents/MacOS/SpinLabGUITest "*"--spinlab-isolated-config "*"--spinlab-isolated-library "* ]] \
  || { echo "refuse: pid $PID is not an isolated SpinLabGUITest instance" >&2; exit 1; }
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
