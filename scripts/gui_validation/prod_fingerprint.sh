#!/bin/zsh
# Read-only CONTENT fingerprint (sha256 per file) of production SpinLab data:
# Application Support (SpinLab, com.spinlab.app), prefs plists, and the real
# Library root named in library_settings.json. Diff two outputs to prove no change.
# Also records the production app bundle's executable hash.
set -uo pipefail
H() { find "$1" -type f -print0 2>/dev/null | xargs -0 shasum -a 256 2>/dev/null | sort -k2; }
S="$HOME/Library/Application Support"
for p in "$S/SpinLab" "$S/com.spinlab.app" "$HOME/Library/Preferences/com.spinlab.app.plist" "/Applications/SpinLab.app/Contents/MacOS"; do
  [[ -e $p ]] && { echo "## $p"; H "$p"; }
done
LIB=$(plutil -extract rootPath raw -o - "$S/SpinLab/library_settings.json" 2>/dev/null || true)
[[ -n $LIB && -d $LIB ]] && { echo "## $LIB"; H "$LIB"; }
exit 0
