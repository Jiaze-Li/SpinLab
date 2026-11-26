#!/bin/zsh
# Create an empty synthetic isolated fixture (config + library roots with the
# marker required by docs/architecture/ISOLATED_LAUNCH.md).
# Usage: prepare_fixture.sh <fixture-dir>   (must not exist or be empty)
set -euo pipefail
[[ $# -eq 1 ]] || { echo "usage: $0 <fixture-dir>" >&2; exit 2; }
D="$1"
if [[ -e "$D" && -n "$(ls -A "$D" 2>/dev/null)" ]]; then echo "refuse: $D not empty" >&2; exit 1; fi
mkdir -p "$D/config" "$D/library"
for r in config library; do print -rn -- "spinlab-isolated-test-root-v1" > "$D/$r/.spinlab-isolated-test-root"; done
echo "$D"
