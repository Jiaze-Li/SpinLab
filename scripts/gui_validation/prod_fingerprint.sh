#!/bin/zsh
# Fail-closed CONTENT fingerprint (sha256 per file) of everything the isolated-launch
# contract protects (docs/architecture/ISOLATED_LAUNCH.md, IsolatedLaunch.swift):
# Application Support {SpinLab, com.spinlab.app}, the prefs plist, the production app
# executable, and every absolute "*Path" named by either real library_settings.json
# (Library Root, registry, backup, vault, web repo...). Exit 1 and say why when the set
# of locations cannot be established or any file cannot be fully read. Missing locations
# are recorded as "(absent)" so a later appearance shows in the diff. Dataless cloud
# files are recorded by size/mtime only (reading them would download them).
exec python3 -I - <<'PY'
import hashlib, json, os, stat, sys
home = os.path.expanduser("~")
sup = os.path.join(home, "Library", "Application Support")
roots, errors = [], []
settings = [os.path.join(sup, d, "library_settings.json") for d in ("SpinLab", "com.spinlab.app")]
roots += [os.path.join(sup, "SpinLab"), os.path.join(sup, "com.spinlab.app"),
          os.path.join(home, "Library/Preferences/com.spinlab.app.plist"),
          "/Applications/SpinLab.app/Contents/MacOS"]
for f in settings:
    if not os.path.lexists(f): continue
    if not os.path.exists(f): errors.append(f"settings link unresolvable: {f}"); continue
    try:
        d = json.load(open(f, "rb"))
        assert isinstance(d, dict)
    except Exception as e:
        errors.append(f"settings unreadable: {f}: {e}"); continue
    for k, v in d.items():
        if k.endswith("BookmarkData") and v is not None:
            errors.append(f"bookmark in {f}: {k} cannot be resolved here")
        if k.endswith("Path") and isinstance(v, str) and v:
            if not v.startswith("/"): errors.append(f"relative path in settings: {k}")
            else: roots.append(v)
def hashfile(p):
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""): h.update(chunk)
    return h.hexdigest()
lines = []
for r in sorted(set(roots)):
    lines.append(f"## {r}")
    if not os.path.lexists(r): lines.append("(absent)"); continue
    if os.path.islink(r):
        if not os.path.exists(r): errors.append(f"dangling link root: {r}"); continue
        real = os.path.realpath(r); lines.append(f"root-link  {real}"); r = real
    def onerr(e): errors.append(f"cannot read {e.filename}: {e.strerror}")
    files = [r] if not os.path.isdir(r) else []
    if not files:
        for dp, dn, fn in os.walk(r, onerror=onerr):
            files += [os.path.join(dp, n) for n in fn]
    for p in sorted(files):
        try:
            st = os.lstat(p)
            if stat.S_ISLNK(st.st_mode): lines.append(f"link  {os.readlink(p)}  {p}")
            elif getattr(st, "st_flags", 0) & 0x40000000: lines.append(f"dataless  {st.st_size}|{int(st.st_mtime)}  {p}")
            elif stat.S_ISREG(st.st_mode): lines.append(f"{hashfile(p)}  {p}")
            else: errors.append(f"unsupported file type: {p}")
        except OSError as e:
            errors.append(f"cannot read {p}: {e.strerror}")
if errors:
    print("FINGERPRINT FAILED (fail-closed):", *errors[:20], sep="\n  ", file=sys.stderr); sys.exit(1)
print("\n".join(lines))
PY
