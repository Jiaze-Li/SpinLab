#!/usr/bin/env bash
# Installs the architecture coverage pre-commit hook.
# Safe to run multiple times — uses a sentinel to avoid duplicate installation.

set -euo pipefail

HOOK_PATH="$(git rev-parse --git-path hooks/pre-commit 2>/dev/null || true)"

if [[ -z "$HOOK_PATH" ]]; then
    echo "[spinlab] Error: not inside a git repository."
    exit 1
fi

SENTINEL_START="# spinlab-architecture-coverage:start"
SENTINEL_END="# spinlab-architecture-coverage:end"

HOOK_BLOCK="${SENTINEL_START}
./scripts/verify_architecture_code_coverage.sh
${SENTINEL_END}"

if [[ -f "$HOOK_PATH" ]]; then
    if grep -qF "$SENTINEL_START" "$HOOK_PATH"; then
        echo "[spinlab] Architecture coverage hook already installed at $HOOK_PATH."
        exit 0
    fi
    # Append to existing hook
    printf '\n%s\n' "$HOOK_BLOCK" >> "$HOOK_PATH"
    echo "[spinlab] Architecture coverage hook appended to existing pre-commit at $HOOK_PATH."
else
    # Create new hook
    printf '#!/bin/sh\n%s\n' "$HOOK_BLOCK" > "$HOOK_PATH"
    chmod +x "$HOOK_PATH"
    echo "[spinlab] Architecture coverage hook installed at $HOOK_PATH."
fi
