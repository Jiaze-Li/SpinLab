#!/usr/bin/env bash
# Install or update only SpinLab's managed architecture-coverage pre-commit block.
# Requires python3 (standard library only), like the other SpinLab dev tooling.
# Usage: ./scripts/install_git_hooks.sh [--check]
# --check: exit 0 only when the current managed block is installed and executable.
set -euo pipefail

case "$#:$*" in
    0:) MODE=install ;;
    1:--check) MODE=check ;;
    *) echo "Usage: $0 [--check]" >&2; exit 2 ;;
esac
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"
HOOK_PATH="$(git rev-parse --git-path hooks/pre-commit)"

# The hook is shared by linked worktrees. Use the staged snapshot rather than
# working-tree files, so an unstaged Code Map edit cannot satisfy the check.
# Do not write logs or temporary files into the worktree.
HOOK_BLOCK=$(cat << 'HOOKEOF'
# spinlab-architecture-coverage:start
_spinlab_diff_rc=0
git diff --cached --quiet --find-renames --find-copies --diff-filter=ACDR -- ':(glob)Sources/**/*.swift' || _spinlab_diff_rc=$?
if [ "$_spinlab_diff_rc" -eq 1 ]; then
    if ! (
        _spinlab_snapshot=$(mktemp -d) || exit 1
        trap 'rm -rf "$_spinlab_snapshot"' 0
        trap 'exit 1' HUP INT TERM
        git checkout-index --prefix="$_spinlab_snapshot/" -af || exit 1
        cd "$_spinlab_snapshot" || exit 1
        if [ "${1:-}" = "--force-refresh" ]; then
            bash scripts/verify_architecture_code_coverage.sh --force-refresh --no-format-check
        else
            bash scripts/verify_architecture_code_coverage.sh --no-format-check
        fi
    ); then
        echo "[pre-commit] Workbench Code Map coverage check failed; update and stage the Code Map before committing." >&2
        exit 1
    fi
elif [ "$_spinlab_diff_rc" -ne 0 ]; then
    echo "[pre-commit] Could not inspect staged changes for architecture coverage." >&2
    exit 1
fi
unset _spinlab_diff_rc
# spinlab-architecture-coverage:end
HOOKEOF
)

# Replace the complete marked block, never the rest of the hook. Refuse
# malformed/duplicate markers, non-shell hooks and symlinks rather than guessing.
# Write atomically beside the hook and retain its existing permission bits.
python3 - "$HOOK_PATH" "$MODE" "$HOOK_BLOCK" <<'PYEOF'
import os
import pathlib
import re
import stat
import sys
import tempfile

path = pathlib.Path(sys.argv[1])
mode = sys.argv[2]
block = sys.argv[3].encode() + b"\n"
start = b"# spinlab-architecture-coverage:start"
end = b"# spinlab-architecture-coverage:end"


def refuse(reason):
    print(f"[spinlab] {reason}: {path}", file=sys.stderr)
    sys.exit(1)


try:
    before = path.lstat()
except FileNotFoundError:
    before = None

if before is not None and not stat.S_ISREG(before.st_mode):
    refuse("Refusing non-regular pre-commit hook")

old = path.read_bytes() if before is not None else b""
lines = old.splitlines(keepends=True)
starts = [i for i, line in enumerate(lines) if line.rstrip(b"\r\n") == start]
ends = [i for i, line in enumerate(lines) if line.rstrip(b"\r\n") == end]

if starts or ends:
    if len(starts) != 1 or len(ends) != 1 or starts[0] >= ends[0]:
        refuse("Malformed or duplicate SpinLab hook markers; no changes made")
    new = b"".join(lines[:starts[0]]) + block + b"".join(lines[ends[0]+1:])
else:
    prefix = old if old else b"#!/bin/sh\n"
    if not prefix.endswith(b"\n"):
        prefix += b"\n"
    new = prefix + b"\n" + block

# Existing scripts may contain other tools' hooks. Only append shell code to
# a recognizable shell interpreter; do not rewrite another language's hook.
if old:
    shebang = lines[0].rstrip(b"\r\n")
    if not re.fullmatch(rb"#![ \t]*(?:/[^ \t]*/(?:sh|bash|dash|ksh|zsh)|/usr/bin/env[ \t]+(?:sh|bash|dash|ksh|zsh))(?:[ \t]+[^\r\n]*)?", shebang):
        refuse("Existing pre-commit is not a recognized shell script")

executable = before is not None and bool(before.st_mode & stat.S_IXUSR)
if old == new and executable:
    print(f"[spinlab] Architecture coverage hook is current at {path}.")
    sys.exit(0)
if mode == "check":
    refuse("Architecture coverage hook is missing or outdated; run installer")

path.parent.mkdir(parents=True, exist_ok=True)
fd, temp_name = tempfile.mkstemp(prefix=".spinlab-pre-commit-", dir=path.parent)
try:
    with os.fdopen(fd, "wb") as out:
        out.write(new)
        out.flush()
        os.fchmod(out.fileno(), (stat.S_IMODE(before.st_mode) if before else 0o755) | stat.S_IXUSR)
    # Do not clobber a hook another installer changed while preparing this update.
    try:
        current = path.lstat()
    except FileNotFoundError:
        current = None
    if (before is None) != (current is None) or (
        before is not None and (
            not stat.S_ISREG(current.st_mode)
            or (current.st_dev, current.st_ino, current.st_mode) != (before.st_dev, before.st_ino, before.st_mode)
            or path.read_bytes() != old
        )
    ):
        refuse("Pre-commit changed during installation; retry after inspection")
    os.replace(temp_name, path)
finally:
    if os.path.exists(temp_name):
        os.unlink(temp_name)

print(f"[spinlab] Architecture coverage hook {'updated' if starts else 'installed'} at {path}.")
PYEOF
