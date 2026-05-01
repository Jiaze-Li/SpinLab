#!/usr/bin/env bash
# Architecture Code Map coverage verifier.
#
# Usage:
#   ./scripts/verify_architecture_code_coverage.sh              # --check-only (default)
#   ./scripts/verify_architecture_code_coverage.sh --write-index
#   ./scripts/verify_architecture_code_coverage.sh --no-format-check  # debug only
#
# Exit 0  = unmapped == 0 && missing == 0 && format_violations == 0
# Exit 1  = any issue found

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH_DIR="$REPO_ROOT/docs/architecture"
INDEX_FILE="$ARCH_DIR/INDEX.md"
SOURCES_DIR="$REPO_ROOT/Sources"

# ─── parse flags ─────────────────────────────────────────────────────────────
MODE="check-only"
FORMAT_CHECK=1
for arg in "$@"; do
    case "$arg" in
        --check-only)      MODE="check-only" ;;
        --write-index)     MODE="write-index" ;;
        --no-format-check) FORMAT_CHECK=0 ;;
    esac
done

# ─── tmp workspace ────────────────────────────────────────────────────────────
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RAW_FILE="$TMP_DIR/raw.txt"
MAPPED_ALL="$TMP_DIR/mapped_all.txt"
MAPPED_FILE="$TMP_DIR/mapped.txt"
ACTUAL_FILE="$TMP_DIR/actual.txt"
FORMAT_FILE="$TMP_DIR/format.txt"
DUP_FILE="$TMP_DIR/dup.txt"
UNMAPPED_FILE="$TMP_DIR/unmapped.txt"
MISSING_FILE="$TMP_DIR/missing.txt"
touch "$RAW_FILE" "$MAPPED_ALL" "$MAPPED_FILE" "$ACTUAL_FILE" \
      "$FORMAT_FILE" "$DUP_FILE" "$UNMAPPED_FILE" "$MISSING_FILE"

# ─── step 1: extract Code Map entries from architecture docs ─────────────────
# Outputs:
#   PATH:<swift-path>              — each registered path (may repeat across docs)
#   FORMAT:<file>:<lineno>:<line>  — lines failing strict format

# U+2014 em dash literal
EM_DASH="—"

find "$ARCH_DIR" -name '*.md' -type f | grep -v 'REGION_MAP\.md' | sort | while read -r f; do
    awk -v file="$f" -v format_check="$FORMAT_CHECK" -v em_dash="—" '
    /^## Code Map/ { in_map=1; in_fence=0; next }
    in_map && /^## /  { in_map=0; in_fence=0; next }
    in_map && /^```/ { in_fence = !in_fence; next }
    in_map && !in_fence {
        line = $0
        if (!(line ~ /`Sources\/[^`]+\.swift`/)) next

        # Extract all backtick-quoted swift paths on this line
        tmp = line
        while (match(tmp, /`Sources\/[^`]+\.swift`/)) {
            path = substr(tmp, RSTART+1, RLENGTH-2)
            print "PATH:" path
            tmp = substr(tmp, RSTART + RLENGTH)
        }

        # Format check: strict top-level bullet with em dash
        # Pattern: ^- `Sources/[^`]+.swift` [em_dash] [non-space].+$
        if (format_check) {
            if (!(line ~ ("^- `Sources/[^`]+\\.swift` " em_dash " [^ \t].+"))) {
                print "FORMAT:" file ":" NR ":" line
            }
        }
    }
    ' "$f"
done > "$RAW_FILE"

# Extract paths
grep '^PATH:' "$RAW_FILE" | sed 's/^PATH://' | sort > "$MAPPED_ALL"
sort -u "$MAPPED_ALL" > "$MAPPED_FILE"

# Dup detection (warning, not failure)
sort "$MAPPED_ALL" | uniq -d > "$DUP_FILE" || true

# Format violations
grep '^FORMAT:' "$RAW_FILE" | sed 's/^FORMAT://' > "$FORMAT_FILE" || true

# ─── step 2: actual Sources swift files ──────────────────────────────────────
find "$SOURCES_DIR" -name '*.swift' -type f | sed "s|$REPO_ROOT/||" | sort > "$ACTUAL_FILE"

# ─── step 3: set differences ─────────────────────────────────────────────────
comm -23 "$ACTUAL_FILE" "$MAPPED_FILE" > "$UNMAPPED_FILE" || true
comm -13 "$ACTUAL_FILE" "$MAPPED_FILE" > "$MISSING_FILE"  || true

# ─── step 4: counts ──────────────────────────────────────────────────────────
mapped_count="$(wc -l < "$MAPPED_FILE" | tr -d '[:space:]')"
actual_count="$(wc -l < "$ACTUAL_FILE" | tr -d '[:space:]')"
unmapped_count="$(wc -l < "$UNMAPPED_FILE" | tr -d '[:space:]')"
missing_count="$(wc -l < "$MISSING_FILE" | tr -d '[:space:]')"
format_count="$(wc -l < "$FORMAT_FILE" | tr -d '[:space:]')"
dup_count="$(wc -l < "$DUP_FILE" | tr -d '[:space:]')"

# ─── step 5: INDEX check / write-back ────────────────────────────────────────
index_exit=0
if [[ "$MODE" == "check-only" ]]; then
    current_index="$(grep -m1 'Code coverage' "$INDEX_FILE" 2>/dev/null \
        | grep -oE '[0-9]+/[0-9]+' | head -1 || true)"
    expected_index="${mapped_count}/${actual_count}"
    if [[ "${current_index:-}" != "$expected_index" ]]; then
        echo "[architecture-coverage][stale-index] index=${current_index:-not found} actual=${expected_index}"
        index_exit=1
    fi
elif [[ "$MODE" == "write-index" ]]; then
    today="$(date +%Y-%m-%d)"
    _tmp_idx=$(mktemp)
    sed "s|Code coverage\*\*: [0-9]*/[0-9]* source files mapped\. Last verified: [0-9-]*|Code coverage**: ${mapped_count}/${actual_count} source files mapped. Last verified: ${today}|" "$INDEX_FILE" > "$_tmp_idx" && mv "$_tmp_idx" "$INDEX_FILE"
    unset _tmp_idx
    echo "[architecture-coverage][index-updated] ${mapped_count}/${actual_count} @ ${today}"
fi

# ─── helpers: candidate region / layer hints ─────────────────────────────────
get_region() {
    local path="$1"
    if   echo "$path" | grep -qE 'SpinLabApp/Import/Rules/|SpinLabApp/Features/RulesPanel/'; then
        echo "inbox (rules authoring)"
    elif echo "$path" | grep -qE 'SpinLabApp/Import/|SpinLabApp/Features/Inbox/'; then
        echo "inbox"
    elif echo "$path" | grep -qE 'SpinLabApp/Library/|SpinLabApp/Features/Library/'; then
        echo "library"
    elif echo "$path" | grep -qE 'SpinLabApp/Features/Workbench/|SpinLabApp/Workflow/|SpinLabApp/UseCases/|SpinLabApp/Workbench/'; then
        echo "workbench"
    else
        echo "cross-cutting (check manually)"
    fi
}

get_layers() {
    local region="$1"
    local dir
    case "$region" in
        "inbox (rules authoring)") dir="$ARCH_DIR/inbox" ;;
        inbox)                     dir="$ARCH_DIR/inbox" ;;
        library)                   dir="$ARCH_DIR/library" ;;
        workbench)                 dir="$ARCH_DIR/workbench" ;;
        *) echo "(see docs/architecture/)"; return ;;
    esac
    find "$dir" -name '*.md' -not -name 'INDEX.md' | xargs -n1 basename | sort \
        | tr '\n' '|' | sed 's/|$//' | sed 's/|/ | /g'
}

# ─── step 6: output ──────────────────────────────────────────────────────────
exit_code=0

echo "[architecture-coverage] mapped=${mapped_count} total=${actual_count} unmapped=${unmapped_count} missing=${missing_count} format_violations=${format_count} dup=${dup_count}"

# Dup warnings (non-fatal)
if [[ "$dup_count" -gt 0 ]]; then
    while IFS= read -r dup; do
        [[ -z "$dup" ]] && continue
        echo "[architecture-coverage][dup-warning] $dup"
    done < "$DUP_FILE"
fi

# Unmapped: code exists but not registered
if [[ "$unmapped_count" -gt 0 ]]; then
    exit_code=1
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        region="$(get_region "$path")"
        layers="$(get_layers "$region")"
        echo "[architecture-coverage][unmapped] $path"
        echo "  candidate region: ${region}"
        echo "  candidate layer:  ${layers}"
        printf "  next: in the target md's ## Code Map section add:\n"
        printf "    - \`%s\` — <one active sentence describing stable responsibility>\n" "$path"
    done < "$UNMAPPED_FILE"
fi

# Missing: registered in docs but code does not exist
if [[ "$missing_count" -gt 0 ]]; then
    exit_code=1
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        registered_in="$(grep -rn "$path" "$ARCH_DIR" 2>/dev/null | grep -v 'REGION_MAP' | head -1 || echo "unknown")"
        echo "[architecture-coverage][missing] $path"
        echo "  registered in: ${registered_in}"
        echo "  next: remove that line; if renamed, new path appears as [unmapped] above"
    done < "$MISSING_FILE"
fi

# Format violations
if [[ "$format_count" -gt 0 ]]; then
    exit_code=1
    while IFS= read -r violation; do
        [[ -z "$violation" ]] && continue
        # violation: file:lineno:content (content may contain colons)
        v_file="$(echo "$violation" | cut -d: -f1)"
        v_line="$(echo "$violation" | cut -d: -f2)"
        v_content="$(echo "$violation" | cut -d: -f3-)"
        echo "[architecture-coverage][format] ${v_file}:${v_line} — does not match \`- \`Sources/...swift\` — <active short sentence>\`"
        echo "  found: ${v_content}"
    done < "$FORMAT_FILE"
fi

[[ $index_exit -ne 0 ]] && exit_code=1

if [[ $exit_code -eq 0 ]]; then
    echo "[architecture-coverage] PASS"
fi

exit $exit_code
