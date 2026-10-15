#!/usr/bin/env bash
# Controls Contract guard (specs/06_WORKBENCH_CONTROLS_UI.md). AST-based: the Swift compiler's
# parse tree is scanned, so comments and string literals never match.
# Usage: scripts/check_controls_contract.sh [source_root]   (default: Sources/SpinLabApp)
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT_DIR/Sources/SpinLabApp}"
exec python3 -I "$ROOT_DIR/scripts/controls_contract_ast.py" --root "$SRC"
