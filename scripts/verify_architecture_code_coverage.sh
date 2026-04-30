#!/usr/bin/env bash
# Verifies Code Map file paths in docs/architecture/**/*.md are valid and
# the numerator in docs/architecture/INDEX.md is in sync.
#
# Exit 0 = all checks pass. Exit 1 = any check failed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH_DIR="$REPO_ROOT/docs/architecture"
INDEX_FILE="$ARCH_DIR/INDEX.md"
SOURCES_DIR="$REPO_ROOT/Sources"
EXPECTED_TOTAL=218

# ---- extract Code Map paths from architecture docs ----
# Scans each .md (excluding REGION_MAP.md).
# Only lines inside ## Code Map sections (stops at next ## heading).
# Fenced code blocks inside Code Map are skipped.
# Extracts backtick-quoted strings that start with Sources/ and end with .swift.

extract_paths() {
    find "$ARCH_DIR" -name '*.md' -type f | grep -v 'REGION_MAP\.md' | while read -r f; do
        awk '
        /^## Code Map/ { in_map=1; in_fence=0; next }
        in_map && /^## /  { in_map=0; in_fence=0; next }
        in_map && /^```/ { in_fence = !in_fence; next }
        in_map && !in_fence {
            line = $0
            while (match(line, /`Sources\/[^`]+\.swift`/)) {
                path = substr(line, RSTART+1, RLENGTH-2)
                print path
                line = substr(line, RSTART + RLENGTH)
            }
        }
        ' "$f"
    done
}

all_paths="$(extract_paths)"

# Unique paths
if [[ -z "$all_paths" ]]; then
    unique_paths=""
    mapped_count=0
else
    unique_paths="$(echo "$all_paths" | sort -u | grep -v '^$' || true)"
    if [[ -z "$unique_paths" ]]; then
        mapped_count=0
    else
        mapped_count="$(echo "$unique_paths" | wc -l | tr -d '[:space:]')"
    fi
fi

# Duplicate references (warning only)
if [[ -n "$all_paths" ]]; then
    dup_paths="$(echo "$all_paths" | sort | uniq -d | grep -v '^$' || true)"
else
    dup_paths=""
fi

# ---- check denominator ----
actual_total="$(find "$SOURCES_DIR" -name '*.swift' -type f | wc -l | tr -d '[:space:]')"

# ---- read INDEX numerator ----
index_numerator="$(grep -m1 'Code coverage' "$INDEX_FILE" 2>/dev/null \
    | grep -oE '[0-9]+/' | head -1 | tr -d '/' || true)"

# ---- report ----
exit_code=0

# Warnings: duplicate references
if [[ -n "$dup_paths" ]]; then
    while IFS= read -r dup; do
        [[ -z "$dup" ]] && continue
        echo "[architecture-coverage][warning] Duplicate reference: $dup"
    done <<< "$dup_paths"
fi

# Errors: missing files
if [[ -n "$unique_paths" ]]; then
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        if [[ ! -f "$REPO_ROOT/$path" ]]; then
            echo "[architecture-coverage][error] Missing mapped file: $path"
            exit_code=1
        fi
    done <<< "$unique_paths"
fi

# Error: denominator mismatch
if [[ "$actual_total" -ne "$EXPECTED_TOTAL" ]]; then
    echo "[architecture-coverage][error] Sources Swift total changed: expected=$EXPECTED_TOTAL actual=$actual_total — update EXPECTED_TOTAL and INDEX"
    exit_code=1
fi

# Error: numerator mismatch
if [[ "${index_numerator:-}" != "$mapped_count" ]]; then
    echo "[architecture-coverage][error] INDEX coverage numerator mismatch: index=${index_numerator:-not found} actual=$mapped_count"
    exit_code=1
fi

if [[ $exit_code -eq 0 ]]; then
    echo "[architecture-coverage] mapped=$mapped_count total=$actual_total"
    echo "[architecture-coverage] index=\"$mapped_count/$actual_total source files mapped\""
    echo "[architecture-coverage] PASS"
fi

exit $exit_code
