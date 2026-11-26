# sourced: verify_run <run.json> -> sets PID RUN_APP RUN_FX RUN_ALIVE RUN_PREF_PRE.
# Refuses unless pid, process start time and command line all match this run's record.
verify_run() {
  eval "$(python3 -I -c 'import json,shlex,sys
d=json.load(open(sys.argv[1]))
for k,v in (("PID",d["pid"]),("RUN_APP",d["app"]),("RUN_FX",d["fixture"]),("RUN_START",d["start"]),("RUN_PREF_PRE","1" if d["prefs_preexisting"] else "0")): print(f"{k}={shlex.quote(str(v))}")' "$1")" || { echo "bad run record: $1" >&2; return 1; }
  RUN_ALIVE=0
  ps -o pid= -p "$PID" >/dev/null 2>&1 || return 0
  RUN_ALIVE=1
  local NOW CMD; NOW=$(ps -o lstart= -p "$PID" | sed 's/^ *//'); CMD=$(ps -ww -o command= -p "$PID")
  [[ "$NOW" == "$RUN_START" ]] || { echo "refuse: pid $PID start time differs from run record (pid reused?)" >&2; return 1; }
  [[ "$CMD" == "$RUN_APP/Contents/MacOS/SpinLabGUITest --spinlab-isolated-config $RUN_FX/config --spinlab-isolated-library $RUN_FX/library"* ]] \
    || { echo "refuse: pid $PID command line does not match this run's bundle/fixture" >&2; return 1; }
}
