#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
pointer_file="/Users/jack/Library/Application Support/SpinLab/config/.repo_pointer.json"
expected_repo_root="/Users/jack/Downloads/scripts/Codex SpinLab/SpinLab"
expected_repository_config_dir="/Users/jack/Downloads/scripts/Codex SpinLab/SpinLab/Sources/SpinLabApp/config"

cd "$repo_root"

changed_files=()
while IFS= read -r path; do
  [[ -n "$path" ]] && changed_files+=("$path")
done < <(
  {
    git diff --name-only HEAD
    git ls-files --others --exclude-standard
  } | awk '!seen[$0]++'
)

requires_build=false
requires_publish=false
recommends_publish=false
docs_or_readme_only=true

for path in "${changed_files[@]}"; do
  case "$path" in
    Sources/SpinLabApp/*)
      requires_build=true
      docs_or_readme_only=false
      ;;
    Resources/WebLibraryTemplate/*|scripts/export_static_library.py)
      requires_publish=true
      docs_or_readme_only=false
      ;;
    scripts/publish_web_library.sh|scripts/validate_web_library.py)
      recommends_publish=true
      docs_or_readme_only=false
      ;;
    docs/*|README.md)
      ;;
    *)
      docs_or_readme_only=false
      ;;
  esac
done

if [[ ${#changed_files[@]} -eq 0 || "$docs_or_readme_only" == true ]]; then
  echo "No rebuild or publish required"
fi

if [[ "$requires_build" == true ]]; then
  echo "Required: ./scripts/build_desktop_app.sh debug"
fi

if [[ "$requires_publish" == true ]]; then
  echo "Required: ./scripts/publish_web_library.sh"
fi

if [[ "$recommends_publish" == true && "$requires_publish" == false ]]; then
  echo "Recommended: ./scripts/publish_web_library.sh"
fi

if [[ -f "$pointer_file" ]]; then
  if ! grep -Fq "\"repo_root\": \"$expected_repo_root\"" "$pointer_file" || \
     ! grep -Fq "\"repository_config_dir\": \"$expected_repository_config_dir\"" "$pointer_file"; then
    echo "Restart SpinLab.app"
  fi
fi

echo "Real app: /Applications/SpinLab.app"
echo "Desktop shortcut: ~/Desktop/SpinLab.app -> /Applications/SpinLab.app"
