#!/usr/bin/env bash
# UI rules guard (specs/04_UI_RULES.md): no new numeric spacing or small text in Features.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 -I "$ROOT_DIR/scripts/ui_rules_check.py" "$@"
