#!/usr/bin/env bash
# SpinLab — Stop hook: build on source change
#
# Triggered by Claude Code Stop event (once per conversation turn).
# Guards: change detection → dedup lock → timestamped log → background build + notification.

set -euo pipefail

PROJECT='/Users/jack/Downloads/scripts/Codex SpinLab/SpinLab-4.0'
PIDFILE=/tmp/spinlab_build.pid
LOGDIR=/tmp/spinlab_build_logs

cd "$PROJECT" || exit 0

# -- 1. Change detection: paths that affect the built product --
# Sources/SpinLabApp/   → app source
# Package.swift / .resolved → dependency changes
# scripts/build_desktop_app.sh → build script itself
if ! git status --porcelain \
    Sources/SpinLabApp/ \
    Package.swift \
    Package.resolved \
    scripts/build_desktop_app.sh \
  | grep -q .; then
  exit 0
fi

# -- 2. Dedup: skip if a build is already running --
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  exit 0
fi

# -- 3. Timestamped log (keep 7 days) --
mkdir -p "$LOGDIR"
LOG="$LOGDIR/build_$(date +%Y%m%d_%H%M%S).log"
find "$LOGDIR" -name "build_*.log" -mtime +7 -delete 2>/dev/null || true

# -- 4. Background build + notification --
nohup bash -c "
  echo \$\$ > '$PIDFILE'
  cd '$PROJECT' && ./scripts/build_desktop_app.sh debug \
    && osascript -e 'display notification \"Build 完成，可以测试\" with title \"SpinLab\" sound name \"Glass\"' \
    || osascript -e 'display notification \"Build 失败，见 $LOG\" with title \"SpinLab\" sound name \"Basso\"'
  rm -f '$PIDFILE'
" > "$LOG" 2>&1 &

exit 0
