#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_root="$(cd "$script_dir/.." && pwd)"
web_repo="$source_root/../SpinLab-Web-Library"
export_output_dir="$web_repo/public"
library_root="/Users/jack/Downloads/data"

log() {
    printf '[publish-web] %s\n' "$1"
}

if [[ ! -d "$web_repo" ]]; then
    log "Missing web library repo: $web_repo"
    exit 1
fi

if [[ ! -d "$web_repo/.git" ]]; then
    log "Web library repo is not a git repository: $web_repo"
    exit 1
fi

log "Exporting static library snapshot..."
python3 "$source_root/scripts/export_static_library.py" \
    --library-root "$library_root" \
    --output-dir "$export_output_dir"

log "Validating web library snapshot..."
python3 "$source_root/scripts/validate_web_library.py" \
    --output-dir "$export_output_dir"

log "Checking web snapshot changes..."
change_check_status=0
if python3 "$source_root/scripts/check_web_library_changes.py" \
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
