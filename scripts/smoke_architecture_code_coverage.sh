#!/usr/bin/env bash
# Smoke tests for verify_architecture_code_coverage.sh.
# Each scenario uses an isolated git worktree; all worktrees cleaned on exit.
# Copies the current (uncommitted) verify script into each worktree so the
# test always exercises the live version, not an older committed version.
#
# Exit 0 = all 4 scenarios pass. Exit 1 = any failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERIFY_SRC="$REPO_ROOT/scripts/verify_architecture_code_coverage.sh"
SMOKE_BASE="$REPO_ROOT/../tmp-spinlab-smoke-$$"

# A registered swift file used as fixture (must exist and be in a Code Map)
FIXTURE_REGISTERED="Sources/SpinLabApp/App/State/InboxFeatureStore.swift"
# New paths that are definitely not registered
FIXTURE_NEW="Sources/SpinLabApp/App/SmokeTestFixture_$$.swift"
FIXTURE_RENAMED="Sources/SpinLabApp/App/SmokeTestFixture_renamed_$$.swift"

pass=0
fail=0

cleanup_worktrees() {
    for i in 1 2 3 4; do
        local wt="${SMOKE_BASE}/scenario_${i}"
        git -C "$REPO_ROOT" worktree remove --force "$wt" 2>/dev/null || true
    done
    rm -rf "$SMOKE_BASE" 2>/dev/null || true
}
trap cleanup_worktrees EXIT

mkdir -p "$SMOKE_BASE"

new_worktree() {
    local n="$1"
    local wt="${SMOKE_BASE}/scenario_${n}"
    git -C "$REPO_ROOT" worktree add --detach "$wt" HEAD >/dev/null 2>&1
    # Copy current (possibly uncommitted) verify script into the worktree
    cp "$VERIFY_SRC" "$wt/scripts/verify_architecture_code_coverage.sh"
    echo "$wt"
}

run_verify() {
    local wt="$1"
    local exit_code=0
    local output
    output="$(bash "${wt}/scripts/verify_architecture_code_coverage.sh" --no-format-check 2>&1)" || exit_code=$?
    printf '%s\n%d' "$output" "$exit_code"
}

check() {
    local n="$1"
    local desc="$2"
    local wt="$3"
    local expected_signal="$4"
    local expected_exit="$5"

    local actual_exit=0
    local output
    output="$(bash "${wt}/scripts/verify_architecture_code_coverage.sh" --no-format-check 2>&1)" || actual_exit=$?

    local signal_ok=0
    echo "$output" | grep -qE "$expected_signal" 2>/dev/null && signal_ok=1 || true

    local exit_ok=0
    [[ "$actual_exit" -eq "$expected_exit" ]] && exit_ok=1

    if [[ $signal_ok -eq 1 && $exit_ok -eq 1 ]]; then
        echo "[smoke][$n/4] PASS — $desc"
        pass=$((pass + 1))
    else
        echo "[smoke][$n/4] FAIL — $desc"
        [[ $signal_ok -eq 0 ]] && echo "  expected output matching: $expected_signal" && echo "  actual output:" && echo "$output"
        [[ $exit_ok -eq 0 ]]   && echo "  expected exit=${expected_exit} actual=${actual_exit}"
        fail=$((fail + 1))
    fi

    git -C "$REPO_ROOT" worktree remove --force "$wt" 2>/dev/null || true
}

# ─── scenario 1: new unregistered file ───────────────────────────────────────
wt1="$(new_worktree 1)"
touch "${wt1}/${FIXTURE_NEW}"
check 1 "new unregistered swift file" "$wt1" \
    '\[unmapped\].*SmokeTestFixture' 1

# ─── scenario 2: rename (old registered path → missing, new path → unmapped) ─
wt2="$(new_worktree 2)"
mv "${wt2}/${FIXTURE_REGISTERED}" "${wt2}/${FIXTURE_RENAMED}"
check 2 "rename: old path missing + new path unmapped" "$wt2" \
    '\[missing\].*InboxFeatureStore' 1

# ─── scenario 3: delete registered file ─────────────────────────────────────
wt3="$(new_worktree 3)"
rm "${wt3}/${FIXTURE_REGISTERED}"
check 3 "delete registered swift file" "$wt3" \
    '\[missing\].*InboxFeatureStore' 1

# ─── scenario 4: combined add + rename + delete → all signals in one run ─────
wt4="$(new_worktree 4)"
touch "${wt4}/${FIXTURE_NEW}"
mv "${wt4}/${FIXTURE_REGISTERED}" "${wt4}/${FIXTURE_RENAMED}"

actual_exit4=0
output4="$(bash "${wt4}/scripts/verify_architecture_code_coverage.sh" --no-format-check 2>&1)" || actual_exit4=$?

has_unmapped_new=0; has_missing_old=0; has_unmapped_renamed=0
echo "$output4" | grep -qE '\[unmapped\].*SmokeTestFixture_[0-9]+\.'   && has_unmapped_new=1     || true
echo "$output4" | grep -qE '\[missing\].*InboxFeatureStore'            && has_missing_old=1      || true
echo "$output4" | grep -qE '\[unmapped\].*SmokeTestFixture_renamed'    && has_unmapped_renamed=1 || true

if [[ $has_unmapped_new -eq 1 && $has_missing_old -eq 1 && $has_unmapped_renamed -eq 1 && $actual_exit4 -eq 1 ]]; then
    echo "[smoke][4/4] PASS — combined add+rename+delete reported all signals"
    pass=$((pass + 1))
else
    echo "[smoke][4/4] FAIL — combined add+rename+delete"
    [[ $has_unmapped_new -eq 0 ]]     && echo "  missing [unmapped] for new file"
    [[ $has_missing_old -eq 0 ]]      && echo "  missing [missing] for old registered path"
    [[ $has_unmapped_renamed -eq 0 ]] && echo "  missing [unmapped] for renamed destination"
    [[ $actual_exit4 -ne 1 ]]         && echo "  expected exit=1 actual=${actual_exit4}"
    echo "  output: $output4"
    fail=$((fail + 1))
fi
git -C "$REPO_ROOT" worktree remove --force "$wt4" 2>/dev/null || true

# ─── summary ─────────────────────────────────────────────────────────────────
echo ""
echo "[smoke] ${pass}/4 passed, ${fail}/4 failed"
[[ $fail -eq 0 ]] && exit 0 || exit 1
