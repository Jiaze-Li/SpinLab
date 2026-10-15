#!/usr/bin/env bash
# Controls Contract guard self-test: the guard must ACCEPT compliant samples and REJECT every
# deliberate violation (specs/06_WORKBENCH_CONTROLS_UI.md I4/I7). Real parse-tree scans + real
# compiler typechecks of the Specific API; no text grep decides a verdict.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$ROOT_DIR/scripts/tests/controls_contract_fixtures"
ALLOW="$ROOT_DIR/scripts/controls_contract_legacy_allowlist.txt"
fail=0

expect() { # <ok|reject> <fixture-name> <expected-rule-or-empty>
  local want="$1" name="$2" rule="${3:-}" out rc
  out="$(python3 -I "$ROOT_DIR/scripts/controls_contract_ast.py" --root "$FIX/ast/$name" --allowlist "$ALLOW" 2>&1)"; rc=$?
  if [[ "$want" == ok ]]; then
    [[ $rc -eq 0 ]] && echo "[ok]     accepted  $name" || { echo "[FAIL]   should accept $name"; echo "$out"; fail=1; }
  else
    if [[ $rc -eq 1 && ( -z "$rule" || "$out" == *"VIOLATION $rule "* ) ]]; then
      echo "[ok]     rejected  $name ($rule)"
    else
      echo "[FAIL]   should reject $name with $rule (rc=$rc)"; echo "$out"; fail=1
    fi
  fi
}

expect ok     ok_new_workflow
expect ok     ok_leaf_internal_stack
expect ok     ok_comments_and_strings_ignored
expect reject bypass_legacy_initializer   uses-legacy-path
expect reject rebuilds_plot_controls      bypasses-surface
expect reject rebuilds_plot_controls      rebuilds-common-or-plot
expect reject shared_depends_on_workflow  shared-depends-on-workflow
expect reject specific_sets_layout_policy specific-sets-layout-policy
expect reject duplicate_common            duplicate-common
expect reject own_left_column             bypasses-surface
expect reject legacy_dir_escape           uses-legacy-component

# I4a: typing of the Specific API, checked by the real Swift compiler on the self-contained
# API files (Specific content + shared layout + style tokens).
API="$ROOT_DIR/Sources/SpinLabApp"
API_FILES=(
  "$API/Workbench/Modules/PlotSystem/ControlsSurface/WorkbenchSpecificContent.swift"
  "$API/Workbench/Modules/PlotSystem/ControlsSurface/WorkbenchControlLayout.swift"
  "$API/UI/AppSpacing.swift" "$API/UI/AppFontScale.swift" "$API/UI/WorkbenchUIStyle.swift"
)
tc() { swiftc -typecheck -module-name ControlsContractProbe "${API_FILES[@]}" "$1" 2>&1; }
if out="$(tc "$FIX/typecheck/ok_typed_specific.swift")"; then echo "[ok]     compiles  ok_typed_specific"
else echo "[FAIL]   ok_typed_specific should compile"; echo "$out"; fail=1; fi
for bad in bad_arbitrary_view_as_input bad_view_as_group bad_stack_as_row bad_anyview_input; do
  if out="$(tc "$FIX/typecheck/$bad.swift")"; then echo "[FAIL]   $bad compiled but must be rejected"; fail=1
  elif [[ "$out" == *"error:"* ]]; then echo "[ok]     rejected  $bad (compiler error)"
  else echo "[FAIL]   $bad failed without a compiler diagnostic"; echo "$out"; fail=1; fi
done

# The real tree must pass with the real allow-list.
if "$ROOT_DIR/scripts/check_controls_contract.sh" >/dev/null; then echo "[ok]     real tree passes check_controls_contract.sh"
else echo "[FAIL]   real tree violates the contract"; fail=1; fi

[[ $fail -eq 0 ]] && echo "[controls-contract] self-test OK" || { echo "[controls-contract] self-test FAILED"; exit 1; }
