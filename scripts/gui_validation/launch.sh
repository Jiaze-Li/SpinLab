#!/bin/zsh
# Start ONE isolated test instance in the background and write a run record that binds
# bundle path, fixture, pid and process start time. Takes the single-controller lock so
# two agents never drive/stop each other's test instance.
# Usage: launch.sh <SpinLabGUITest.app> <fixture-dir> <run.json>   (prints the pid)
set -euo pipefail
[[ $# -eq 3 ]] || { echo "usage: $0 <app> <fixture-dir> <run.json>" >&2; exit 2; }
APP="${1:A}"; FX="${2:A}"; RUN="${3:A}"
LOCK="$HOME/Library/Caches/spinlab-gui-validation.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "refuse: GUI lock exists ($(cat "$LOCK/run" 2>/dev/null || echo 'owner unknown')). Never reclaimed automatically; if you have confirmed no GUI run is active, remove it yourself: rm -rf '$LOCK'" >&2; exit 1
fi
print -r -- "$RUN" > "$LOCK/run"
fail() { rm -rf "$LOCK"; echo "$1" >&2; exit 1; }
[[ -x "$APP/Contents/MacOS/SpinLabGUITest" ]] || fail "no test bundle at $APP"
for r in config library; do [[ -f "$FX/$r/.spinlab-isolated-test-root" ]] || fail "fixture marker missing: $FX/$r"; done
cua-driver permissions status --json | python3 -I -c 'import json,sys;d=json.load(sys.stdin);sys.exit(0 if d.get("accessibility") and d.get("screen_recording") else 1)' || fail "Cua permissions missing"
PREF="$HOME/Library/Preferences/com.spinlab.guitest.plist"
PREF_PRE=false; [[ -e "$PREF" ]] && PREF_PRE=true
ARGS=$(APP="$APP" FX="$FX" python3 -I -c 'import json,os;print(json.dumps({"name":os.environ["APP"],"creates_new_application_instance":True,"additional_arguments":["--spinlab-isolated-config",os.environ["FX"]+"/config","--spinlab-isolated-library",os.environ["FX"]+"/library"]}))')
PID=$(cua-driver call launch_app "$ARGS" | python3 -I -c 'import json,sys;print(json.load(sys.stdin)["pid"])') || fail "launch failed"
START=$(ps -o lstart= -p "$PID" | sed 's/^ *//')
[[ -n "$START" ]] || fail "pid $PID not running after launch"
PID="$PID" START="$START" APP="$APP" FX="$FX" PREF_PRE="$PREF_PRE" python3 -I -c 'import json,os;e=os.environ;print(json.dumps({"pid":int(e["PID"]),"start":e["START"],"app":e["APP"],"fixture":e["FX"],"prefs_preexisting":e["PREF_PRE"]=="true"},indent=1))' > "$RUN"
echo "$PID"
