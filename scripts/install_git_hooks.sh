#!/usr/bin/env bash
# Installs the architecture coverage pre-commit hook.
# Safe to run multiple times — uses a sentinel to avoid duplicate installation.
#
# Usage:
#   ./scripts/install_git_hooks.sh           # install hook
#   ./scripts/install_git_hooks.sh --check   # exit 0 if installed, 1 if not

set -euo pipefail

# ─── --check mode ────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--check" ]]; then
    HOOK_PATH="$(git rev-parse --git-path hooks/pre-commit 2>/dev/null || true)"
    if [[ -n "$HOOK_PATH" && -f "$HOOK_PATH" ]] && grep -qF "# spinlab-architecture-coverage:start" "$HOOK_PATH" 2>/dev/null; then
        echo "[spinlab] Architecture coverage hook is installed at $HOOK_PATH."
        exit 0
    else
        echo "[spinlab] Architecture coverage hook is NOT installed."
        exit 1
    fi
fi

# ─── install mode ─────────────────────────────────────────────────────────────
HOOK_PATH="$(git rev-parse --git-path hooks/pre-commit 2>/dev/null || true)"

if [[ -z "$HOOK_PATH" ]]; then
    echo "[spinlab] Error: not inside a git repository."
    exit 1
fi

SENTINEL_START="# spinlab-architecture-coverage:start"
SENTINEL_END="# spinlab-architecture-coverage:end"

# Full hook body: staged-filter + verify call + trigger log
HOOK_BLOCK=$(cat << 'HOOKEOF'
# spinlab-architecture-coverage:start
_staged=$(git diff --cached --name-status --find-renames --find-copies 2>/dev/null || true)
# Only trigger when staged contains Sources/**/*.swift additions, deletions, renames, or copies
_hits=$(printf '%s\n' "$_staged" | awk '
  $1 ~ /^[ADC]/ && $2 ~ /^Sources\/.+\.swift$/ { print; next }
  $1 ~ /^R/     && ($2 ~ /^Sources\/.+\.swift$/ || $3 ~ /^Sources\/.+\.swift$/) { print }
')
if [ -n "$_hits" ]; then
    _ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    _tmp_tree=$(mktemp -d)
    git checkout-index --prefix="$_tmp_tree/" -af 2>/dev/null
    (cd "$_tmp_tree" && bash scripts/verify_architecture_code_coverage.sh --check-only)
    _rc=$?
    rm -rf "$_tmp_tree"
    mkdir -p tmp
    printf '%s\trc=%d\tstaged=%s\n' "$_ts" "$_rc" "$(printf '%s\n' "$_hits" | tr '\n' ';')" >> tmp/architecture-coverage-hook.log
    unset _ts _tmp_tree
    if [ $_rc -ne 0 ]; then
        unset _staged _hits _rc
        echo "[pre-commit] Code Map と Sources が不一致です。上記の unmapped/missing 提示に従って修正後、再 commit してください。"
        echo "[pre-commit] 緊急バイパス: git commit --no-verify（既知の制限。60 日後の検証で git log から逆引き識別されます）"
        exit 1
    fi
    unset _rc
fi
unset _staged _hits
# spinlab-architecture-coverage:end
HOOKEOF
)

if [[ -f "$HOOK_PATH" ]]; then
    if grep -qF "$SENTINEL_START" "$HOOK_PATH"; then
        echo "[spinlab] Architecture coverage hook already installed at $HOOK_PATH."
        exit 0
    fi
    printf '\n%s\n' "$HOOK_BLOCK" >> "$HOOK_PATH"
    echo "[spinlab] Architecture coverage hook appended to existing pre-commit at $HOOK_PATH."
else
    printf '#!/bin/sh\n%s\n' "$HOOK_BLOCK" > "$HOOK_PATH"
    chmod +x "$HOOK_PATH"
    echo "[spinlab] Architecture coverage hook installed at $HOOK_PATH."
fi
