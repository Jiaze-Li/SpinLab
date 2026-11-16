#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
publish_root="${SPINLAB_PUBLISH_ROOT:-$(cd "$script_dir/.." && pwd)}"

# Both the Library to publish and the target Web Library repository are owned by SpinLab settings
# and must be passed explicitly; this script never probes sibling directories on its own.
library_root="${SPINLAB_LIBRARY_ROOT:-}"
web_repo="${SPINLAB_WEB_LIBRARY_DIR:-}"
template_dir="${SPINLAB_WEB_TEMPLATE_DIR:-}"
schema_path="${SPINLAB_NEW_SAMPLE_SCHEMA_PATH:-}"
harness_path="${SPINLAB_PAGE_CHECK_HARNESS_PATH:-}"
rules_book_dir="${SPINLAB_RULES_BOOK_DIR:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --library-root)
            library_root="${2:-}"
            shift 2
            ;;
        --web-repo)
            web_repo="${2:-}"
            shift 2
            ;;
        --template-dir)
            template_dir="${2:-}"
            shift 2
            ;;
        --schema-path)
            schema_path="${2:-}"
            shift 2
            ;;
        --harness-path)
            harness_path="${2:-}"
            shift 2
            ;;
        --rules-book-dir)
            rules_book_dir="${2:-}"
            shift 2
            ;;
        *)
            printf '[publish-web] Unknown argument: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$template_dir" ]]; then
    if [[ -d "$publish_root/WebLibraryTemplate" ]]; then
        template_dir="$publish_root/WebLibraryTemplate"
    else
        template_dir="$publish_root/Resources/WebLibraryTemplate"
    fi
fi

if [[ -z "$schema_path" ]]; then
    if [[ -f "$publish_root/config/new_sample_form_schema.json" ]]; then
        schema_path="$publish_root/config/new_sample_form_schema.json"
    else
        schema_path="$publish_root/Sources/SpinLabApp/config/new_sample_form_schema.json"
    fi
fi

if [[ -z "$harness_path" ]]; then
    harness_path="$publish_root/scripts/tests/web_library_compare_harness.js"
fi

log() {
    printf '[publish-web] %s\n' "$1"
}

if [[ -z "$library_root" ]]; then
    log "No Library given: set SPINLAB_LIBRARY_ROOT or pass --library-root (SpinLab passes its selected Library when it publishes)."
    exit 1
fi

if [[ ! -d "$library_root" ]]; then
    log "Library folder does not exist: $library_root"
    exit 1
fi

if [[ -z "$web_repo" ]]; then
    log "No web library repository given: set SPINLAB_WEB_LIBRARY_DIR or pass --web-repo (choose the Web Repository in SpinLab Publish)."
    exit 1
fi

if [[ ! -d "$web_repo" ]]; then
    log "Missing web library repo: $web_repo"
    exit 1
fi

if [[ ! -d "$web_repo/.git" ]]; then
    log "Web library repo is not a git repository: $web_repo"
    exit 1
fi

export_output_dir="$web_repo/public"

export_args=(
    --library-root "$library_root"
    --output-dir "$export_output_dir"
    --template-dir "$template_dir"
    --schema-path "$schema_path"
)
if [[ -n "$rules_book_dir" ]]; then
    export_args+=(--rules-book-dir "$rules_book_dir")
fi

log "Exporting static library snapshot..."
python3 "$publish_root/scripts/export_static_library.py" "${export_args[@]}"

log "Validating web library snapshot..."
python3 "$publish_root/scripts/validate_web_library.py" \
    --output-dir "$export_output_dir" \
    --template-dir "$template_dir"

log "Checking the exported page in a headless browser..."
page_check_status=0
python3 "$publish_root/scripts/check_web_library_page.py" \
    --output-dir "$export_output_dir" \
    --harness-path "$harness_path" || page_check_status=$?
if [[ $page_check_status -eq 3 ]]; then
    # No headless browser on this machine: reported as NOT RUN (never as a pass), publishing continues.
    log "Page check NOT RUN: no headless browser found."
elif [[ $page_check_status -ne 0 ]]; then
    log "Page check failed; nothing was committed or pushed."
    exit "$page_check_status"
fi

log "Checking web snapshot changes..."
change_check_status=0
if python3 "$publish_root/scripts/check_web_library_changes.py" \
    --repo-dir "$web_repo"; then
    exit 0
else
    change_check_status=$?
fi

if [[ $change_check_status -ne 1 ]]; then
    exit "$change_check_status"
fi

cd "$web_repo"

if ! git diff --cached --quiet -- . ':(exclude)public'; then
    log "Refusing to publish because unrelated staged changes exist in $web_repo."
    exit 1
fi

log "Publishing changes from public/..."
git add public
git commit -m "Update SpinLab web snapshot"
git push

log "Cloudflare Pages will redeploy automatically."
log "Site: https://spinlab-web-library.pages.dev"
