#!/usr/bin/env bash
# Plot Style Guard — enforces specs/05_PLOT_RULES.md on plot *text* code paths.
# Usage: scripts/check_plot_style.sh [scan_dir]   (default: Sources/SpinLabApp/Workbench)
# Scientific curves, markers, gradients and grid lines are deliberately not inspected.
# There is NO inline exemption: comments such as "plot-style:allow" do not bypass any rule.
# The only exemptions are the two registered owner files below (ALLOW_*), fixed in this script.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCAN_DIR="${1:-$ROOT_DIR/Sources/SpinLabApp/Workbench}"

# Files that own the shared entry points may use the low-level APIs.
ALLOW_FONT_API='/PlotTextPolicy\.swift$'
ALLOW_ATTR_API='/(PlotTextPolicy|MathMarkupRenderer)\.swift$'

files=()
while IFS= read -r f; do files+=("$f"); done < <(
  find "$SCAN_DIR" -name '*.swift' -not -path '*/Controls/*' -not -name 'PlotTextPolicy.swift' | sort
)
[[ ${#files[@]} -gt 0 ]] || { echo "[plot-style] no source files under $SCAN_DIR"; exit 2; }

fail=0
report() { echo "[plot-style][violation] $1"; fail=1; }

scan() { # <rule message> <ERE> [allow-path-regex]
  local msg="$1" re="$2" allow="${3:-}" hit
  for f in "${files[@]}"; do
    if [[ -n "$allow" && "$f" =~ $allow ]]; then continue; fi
    while IFS= read -r hit; do
      [[ -n "$hit" ]] && report "$msg: ${f#$ROOT_DIR/}:$hit"
    done < <(grep -nE "$re" "$f" | grep -vE '^[0-9]+:[[:space:]]*//' || true)
  done
}

scan "direct font creation (use PlotTextPolicy.font / WorkbenchChartStyle.makeTextLine)" \
  'CTFontCreate[A-Za-z]*\(|NSFont[ (.]|UIFont[ (.]|Font\.custom\(|\.systemFont\(' "$ALLOW_FONT_API"
scan "non-Arial font name literal" \
  '"[^"]*(TimesNewRoman|Times New Roman|Helvetica|Menlo|Courier|SFMono|SF Mono|Georgia|Palatino|Verdana|Calibri)[^"]*"' "$ALLOW_FONT_API"
scan "text stroke / shadow" \
  'kCTStrokeColorAttributeName|kCTStrokeWidthAttributeName|setShadow\(|NSShadow|\.strokeColor|setTextDrawingMode' ""
scan "text attributes built outside the shared factory" \
  'kCTFontAttributeName|kCTForegroundColorAttributeName|CTLineCreateWithAttributedString' "$ALLOW_ATTR_API"
scan "text color variable not PlotTextPolicy.black/white" \
  '\b(label|text|title|axisTitle|legendText)Color[[:space:]]*(:[^=]+)?=[[:space:]]*[^P[:space:]]' ""
scan "inline CGColor passed as text color" \
  '(draw(Centered|LeftAligned|RightAligned|Rotated[0-9]*|Markup)[A-Za-z0-9]*|makeTextLine|makeLine)\([^)]*[cC]olor:[[:space:]]*CGColor\(|^[[:space:]]*color:[[:space:]]*CGColor\(' ""

if [[ $fail -ne 0 ]]; then
  echo "[plot-style] FAILED — see specs/05_PLOT_RULES.md"
  exit 1
fi
echo "[plot-style] OK (${#files[@]} files scanned under ${SCAN_DIR#$ROOT_DIR/})"
