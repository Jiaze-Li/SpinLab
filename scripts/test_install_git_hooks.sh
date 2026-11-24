#!/usr/bin/env bash
# Isolated real-Git regression tests; never change the developer's installed hook.
set -euo pipefail
SOURCE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
REPO="$ROOT/repo"
WORKTREE="$ROOT/linked"
mkdir -p "$REPO" "$ROOT/runtime-tmp"
export TMPDIR="$ROOT/runtime-tmp"
# Isolate fixture Git settings from the developer or runner.
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
cd "$REPO"
git init -q -b main
git config user.name "SpinLab hook test"
git config user.email "hook-test@example.invalid"
git config commit.gpgsign false
mkdir -p scripts Sources/SpinLabApp/Features/Workbench docs/architecture/workbench
cp "$SOURCE_ROOT/scripts/install_git_hooks.sh" "$SOURCE_ROOT/scripts/verify_architecture_code_coverage.sh" scripts/
src=Sources/SpinLabApp/Features/Workbench
map=docs/architecture/workbench/SHELL_BLOCKS.md
printf 'let existing = 1\n' > "$src/Existing.swift"
printf '# Workbench\n\n## Code Map\n- %s/Existing.swift — fixture\n' "$src" | sed 's|- Sources/|- \`Sources/|; s|.swift —|.swift\` —|' > "$map"
git add .
git commit -qm fixture
hook="$(git rev-parse --git-path hooks/pre-commit)"
installer="$REPO/scripts/install_git_hooks.sh"
expect_failure() {
    if "$@"; then
        echo "Expected failure: $*" >&2
        exit 1
    fi
}

# Fresh install, read-only --check, idempotent reinstall.
expect_failure bash "$installer" --check
test ! -e "$hook"
bash "$installer"
bash "$installer" --check
cp "$hook" "$ROOT/current-hook"
bash "$installer"
cmp "$ROOT/current-hook" "$hook"

# The older managed block must be replaced, while other hook code is untouched.
cat > "$hook" <<'OLD'
#!/bin/sh
# foreign hook prefix
printf 'foreign hook ran\n'
# spinlab-architecture-coverage:start
mkdir -p tmp
echo old >> tmp/architecture-coverage-hook.log
# spinlab-architecture-coverage:end
# foreign hook suffix
:
OLD
chmod 750 "$hook"
cp "$hook" "$ROOT/old-hook"
expect_failure bash "$installer" --check
cmp "$ROOT/old-hook" "$hook"
bash "$installer"
bash "$installer" --check
test "$(grep -c '^# spinlab-architecture-coverage:start$' "$hook")" -eq 1
test "$(grep -c '^# spinlab-architecture-coverage:end$' "$hook")" -eq 1
grep -Fxq '# foreign hook prefix' "$hook"
grep -Fxq '# foreign hook suffix' "$hook"
grep -Fxq "printf 'foreign hook ran\\n'" "$hook"
if grep -Fq 'architecture-coverage-hook.log' "$hook"; then exit 1; fi
python3 - "$hook" <<'PY'
import os, stat, sys
assert stat.S_IMODE(os.stat(sys.argv[1]).st_mode) == 0o750
PY
cp "$hook" "$ROOT/upgraded-hook"
bash "$installer"
cmp "$ROOT/upgraded-hook" "$hook"

# A linked worktree uses the same installed hook. An unstaged documentation
# edit cannot make a staged Swift addition pass. Once both are staged, it passes.
git worktree add -qb feature "$WORKTREE"
cd "$WORKTREE"
bash scripts/install_git_hooks.sh --check
printf 'let added = 2\n' > "$src/Added.swift"
git add "$src/Added.swift"
printf -- '- \x60%s/Added.swift\x60 — fixture\n' "$src" >> "$map"
expect_failure git commit -qm 'missing staged Code Map'
test ! -e tmp
test -z "$(find "$TMPDIR" -mindepth 1 -print -quit)"
git add "$map"
git commit -qm 'staged Swift and Code Map'
test ! -e tmp
test -z "$(find "$TMPDIR" -mindepth 1 -print -quit)"
# A normal modification of an existing file is not a structural change.
printf 'let added = 3\n' > "$src/Added.swift"
git add "$src/Added.swift"
git commit -qm 'ordinary source modification'
test ! -e tmp

# Malformed markers or foreign non-shell hooks are never overwritten.
cd "$REPO"
printf '%s\n' '# spinlab-architecture-coverage:start' >> "$hook"
cp "$hook" "$ROOT/malformed"
expect_failure bash "$installer"
cmp "$ROOT/malformed" "$hook"
printf '#!/usr/bin/env python3\nprint("foreign")\n' > "$hook"
cp "$hook" "$ROOT/foreign"
expect_failure bash "$installer"
cmp "$ROOT/foreign" "$hook"
rm "$hook"
ln -s "$ROOT/foreign" "$hook"
expect_failure bash "$installer"
test -L "$hook"
printf '#!/usr/bin/env python3\nprint("foreign")\n' | cmp - "$ROOT/foreign"

echo "PASS: install, stale upgrade, foreign hook preservation, linked-worktree staged validation, no residue, refusal cases"
