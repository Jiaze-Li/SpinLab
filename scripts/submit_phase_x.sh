#!/usr/bin/env bash
# Phase X submission helper for Workbench changes.
#
# Usage:
#   ./scripts/submit_phase_x.sh "short description"
#
# Behavior:
#   - detects staged and unstaged Workbench Swift changes
#   - adds missing Workbench Code Map entries to docs/architecture/workbench/SHELL_BLOCKS.md
#   - refreshes architecture coverage index
#   - stages updated docs and sources
#   - commits with: "Phase X: <description>"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKBENCH_DIR="$REPO_ROOT/Sources/SpinLabApp/Features/Workbench"
WORKBENCH_DOC="$REPO_ROOT/docs/architecture/workbench/SHELL_BLOCKS.md"
INDEX_FILE="$REPO_ROOT/docs/architecture/INDEX.md"
VERIFY="$REPO_ROOT/scripts/verify_architecture_code_coverage.sh"

if [[ $# -lt 1 ]]; then
    echo "usage: $0 \"<description>\""
    exit 1
fi

DESC="$*"
if [[ -z "${DESC// }" ]]; then
    echo "[phase-x] description is required"
    exit 1
fi

if ! git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[phase-x] not inside a git repository"
    exit 1
fi

WORKBENCH_FILES=()
while IFS= read -r rel; do
    [[ -n "$rel" ]] && WORKBENCH_FILES+=("$rel")
done < <(
    {
        git -C "$REPO_ROOT" diff --name-only --cached --diff-filter=ACMR -- "$WORKBENCH_DIR"
        git -C "$REPO_ROOT" diff --name-only --diff-filter=ACMR -- "$WORKBENCH_DIR"
        git -C "$REPO_ROOT" ls-files --others --exclude-standard -- "$WORKBENCH_DIR"
    } | sort -u
)

if [[ "${#WORKBENCH_FILES[@]}" -eq 0 ]]; then
    echo "[phase-x] no Workbench Swift changes detected"
    exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

existing_map="$tmp_dir/existing_map.txt"
touch "$existing_map"

awk '
BEGIN { in_map=0; in_fence=0 }
/^## Code Map/ { in_map=1; next }
in_map && /^## / { in_map=0; next }
in_map && /^```/ { in_fence=!in_fence; next }
in_map && !in_fence {
    if (match($0, /`Sources\/[^`]+\.swift`/)) {
        path = substr($0, RSTART+1, RLENGTH-2)
        print path
    }
}
' "$WORKBENCH_DOC" | sort -u > "$existing_map"

describe_file() {
    local rel="$1"
    local base="${rel##*/}"
    local stem="${base%.swift}"
    local label="${stem//_/ }"
    label="${label//+/ }"
    case "$base" in
        *WorkspaceShell.swift) echo "composes the shared Workbench shell layout" ;;
        *WorkspaceProvider.swift) echo "provides the Workbench workspace slot contract" ;;
        *WorkspaceRegistry.swift) echo "tracks available Workbench workspace registrations" ;;
        *FeatureStore.swift) echo "coordinates Workbench feature state and workflow surface" ;;
        *PlotCanvas*.swift) echo "renders the shared Workbench plot canvas" ;;
        *PlotControls*.swift) echo "coordinates shared Workbench plot controls" ;;
        *Trace*.swift) echo "presents Workbench trace output for the current run" ;;
        *Status*.swift) echo "presents the shared Workbench status surface" ;;
        *Warning*.swift) echo "presents Workbench warnings and diagnostics" ;;
        *Save*.swift) echo "coordinates save-to-library presentation for Workbench" ;;
        *Pack*.swift) echo "coordinates pack restore and pack presentation for Workbench" ;;
        *UseCase.swift) echo "implements a Workbench workflow use case" ;;
        *) echo "supports Workbench shell composition for ${label}" ;;
    esac
}

append_missing_entries() {
    local doc="$1"
    local tmp_doc="$2"
    awk -v new_entries_file="$3" '
        BEGIN {
            while ((getline line < new_entries_file) > 0) {
                entries[++count] = line
            }
            close(new_entries_file)
            in_map=0
            inserted=0
        }
        /^## Code Map/ {
            print
            in_map=1
            next
        }
        in_map && /^## / {
            if (!inserted) {
                for (i = 1; i <= count; i++) print entries[i]
                inserted=1
            }
            in_map=0
            print
            next
        }
        {
            print
        }
        END {
            if (in_map && !inserted) {
                for (i = 1; i <= count; i++) print entries[i]
            }
        }
    ' "$doc" > "$tmp_doc"
}

missing_entries="$tmp_dir/missing_entries.txt"
touch "$missing_entries"

for rel in "${WORKBENCH_FILES[@]}"; do
    if [[ "$rel" != *.swift ]]; then
        continue
    fi
    if ! grep -qxF "$rel" "$existing_map"; then
        desc="$(describe_file "$rel")"
        printf -- '- `%s` — %s\n' "$rel" "$desc" >> "$missing_entries"
    fi
done

if [[ -s "$missing_entries" ]]; then
    sort "$missing_entries" > "$tmp_dir/missing_entries.sorted"
    append_missing_entries "$WORKBENCH_DOC" "$tmp_dir/SHELL_BLOCKS.md" "$tmp_dir/missing_entries.sorted"
    mv "$tmp_dir/SHELL_BLOCKS.md" "$WORKBENCH_DOC"
fi

"$VERIFY" --write-index --no-format-check

git -C "$REPO_ROOT" add -A -- \
    "$WORKBENCH_DOC" \
    "$INDEX_FILE" \
    "$WORKBENCH_DIR"

if [[ -z "$(git -C "$REPO_ROOT" diff --cached --name-only)" ]]; then
    echo "[phase-x] nothing staged after refresh"
    exit 0
fi

git -C "$REPO_ROOT" commit -m "Phase X: ${DESC}"
