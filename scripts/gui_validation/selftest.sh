#!/bin/zsh
# Run the isolated self-test (headless, exits 0 with a JSON report).
# Usage: selftest.sh <SpinLabGUITest.app> <fixture-dir>
set -euo pipefail
[[ $# -eq 2 ]] || { echo "usage: $0 <app> <fixture-dir>" >&2; exit 2; }
timeout() { perl -e 'alarm shift; exec @ARGV' "$@"; }
timeout 60 "$1/Contents/MacOS/SpinLabGUITest" --spinlab-isolated-config "$2/config" \
  --spinlab-isolated-library "$2/library" --spinlab-isolated-selftest
