#!/usr/bin/env python3
"""UI rules guard (specs/04_UI_RULES.md): ratchet on spacing literals, small text, and CJK UI strings.

Scans Sources/SpinLabApp/Features/**/*.swift (and LibraryResultService.swift when scanning the real repo) for
  numeric-spacing   numeric literals in .padding(N), .padding(.edge, N) and spacing: N (0 is allowed)
  small-text        .font(.caption), .font(.caption2), .font(.footnote), .font(.subheadline)
  cjk-ui-literal    string literals containing CJK characters in UI views / user-facing error descriptions
  disclosure-group  direct DisclosureGroup(...) calls or manual chevron.down/chevron.right toggles (use CollapsibleSectionHeader)
and compares per-file counts with scripts/ui_rules_baseline.json. Existing violations are
recorded there; a count may only go down. A file missing from the baseline has baseline 0.

--base-baseline FILE is the baseline as it is on the target branch. The per-rule totals of the
baseline file must not exceed it (when the rule exists in the base baseline), so a PR cannot pass
by raising the baseline (renames and moves keep the totals, so they are fine).

Usage: ui_rules_check.py [--root DIR] [--baseline FILE] [--base-baseline FILE] [--update-baseline]
Exit 0 = ok, 1 = new violations, 2 = tool error.
"""
import argparse, json, os, re, sys

RULES = {
    "numeric-spacing": re.compile(
        r"\.padding\(\s*(?:\.\w+\s*,\s*)?[1-9]\d*(?:\.\d+)?\s*\)"
        r"|\bspacing:\s*[1-9]\d*(?:\.\d+)?"
    ),
    "small-text": re.compile(r"\.font\(\s*\.(?:caption2?|footnote|subheadline)\b"),
    "cjk-ui-literal": re.compile(
        r'"""(?:\\.|[^\\])*?[\u4e00-\u9fff]+(?:\\.|[^\\])*?"""'
        r'|"(?:\\.|[^"\\\n])*?[\u4e00-\u9fff]+(?:\\.|[^"\\\n])*?"',
        re.S,
    ),
    "disclosure-group": re.compile(
        r"\bDisclosureGroup\s*\("
        r'|"chevron\.down"[^\n]*"chevron\.right"|"chevron\.right"[^\n]*"chevron\.down"'
    ),
}


# Tokens in priority order: string literals are matched first so a "//" inside one is not a comment.
_TOKEN = re.compile(r'"""(?:\\.|[^\\])*?"""|"(?:\\.|[^"\\\n])*"|/\*.*?\*/|//[^\n]*', re.S)


def strip_comments(text):
    def repl(m):
        tok = m.group(0)
        if tok.startswith("/*"):
            return "\n" * tok.count("\n")
        if tok.startswith("//"):
            return ""
        return tok  # string literal: keep as is
    return _TOKEN.sub(repl, text)


def scan_file(path):
    with open(path, encoding="utf-8") as fh:
        body = strip_comments(fh.read())
    per_rule = {r: len(rx.findall(body)) for r, rx in RULES.items()}
    return {r: n for r, n in per_rule.items() if n}


def scan(root, extra_files=()):
    counts = {}
    for dirpath, _, files in os.walk(root):
        for name in files:
            if not name.endswith(".swift"):
                continue
            path = os.path.join(dirpath, name)
            per_rule = scan_file(path)
            if per_rule:
                counts[os.path.relpath(path, root)] = per_rule
    for key, path in extra_files:
        if os.path.isfile(path):
            per_rule = scan_file(path)
            if per_rule:
                counts[key] = per_rule
    return counts


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.dirname(here)
    default_root = os.path.join(repo, "Sources/SpinLabApp/Features")
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=default_root)
    ap.add_argument("--baseline", default=os.path.join(here, "ui_rules_baseline.json"))
    ap.add_argument("--base-baseline", help="baseline from the target branch; the baseline may not exceed it")
    ap.add_argument("--update-baseline", action="store_true")
    args = ap.parse_args()
    if not os.path.isdir(args.root):
        print(f"tool error: {args.root} is not a directory", file=sys.stderr)
        return 2

    extra_files = []
    if os.path.abspath(args.root) == os.path.abspath(default_root):
        extra_files.append((
            "../Library/LibraryResultService.swift",
            os.path.join(repo, "Sources/SpinLabApp/Library/LibraryResultService.swift"),
        ))

    current = scan(args.root, extra_files)
    if args.update_baseline:
        with open(args.baseline, "w", encoding="utf-8") as fh:
            json.dump(current, fh, indent=2, sort_keys=True, ensure_ascii=False)
            fh.write("\n")
        print(f"baseline written: {sum(sum(v.values()) for v in current.values())} known violations "
              f"in {len(current)} files")
        return 0

    try:
        with open(args.baseline, encoding="utf-8") as fh:
            baseline = json.load(fh)
    except (OSError, ValueError) as exc:
        print(f"tool error: cannot read baseline: {exc}", file=sys.stderr)
        return 2

    if args.base_baseline:
        try:
            with open(args.base_baseline, encoding="utf-8") as fh:
                base = json.load(fh)
        except (OSError, ValueError) as exc:
            print(f"tool error: cannot read base baseline: {exc}", file=sys.stderr)
            return 2
        raised = []
        for rule in RULES:
            # A newly introduced rule key is absent from the base branch's baseline file;
            # enforce the non-increasing total check once the rule exists on the base branch.
            if not any(rule in v for v in base.values()):
                continue
            new_total = sum(v.get(rule, 0) for v in baseline.values())
            old_total = sum(v.get(rule, 0) for v in base.values())
            if new_total > old_total:
                raised.append(f"BASELINE RAISED {rule}: {old_total} on the target branch -> {new_total}")
        if raised:
            print("\n".join(raised))
            print("\nThe baseline may only go down. Fix the new violations instead of recording them.")
            return 1

    bad, improved = [], []
    for path, rules in sorted(current.items()):
        for rule, n in sorted(rules.items()):
            allowed = baseline.get(path, {}).get(rule, 0)
            if n > allowed:
                bad.append(f"VIOLATION {rule} {path}: {n} found, {allowed} allowed")
    for path, rules in sorted(baseline.items()):
        for rule, allowed in sorted(rules.items()):
            n = current.get(path, {}).get(rule, 0)
            if n < allowed:
                improved.append(f"{path} {rule}: {allowed} -> {n}")

    for line in bad:
        print(line)
    if bad:
        print("\nUse AppSpacing tokens, WorkbenchUIStyle/AppFontScale text roles, and English UI copy "
              "(specs/04_UI_RULES.md). Do not raise the baseline to make this pass.")
        return 1
    if improved:
        print("Fewer violations than the baseline; tighten it with "
              "scripts/ui_rules_check.py --update-baseline:")
        for line in improved:
            print("  " + line)
    print("ui-rules: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
