#!/usr/bin/env python3
"""Controls Contract checker (specs/06_WORKBENCH_CONTROLS_UI.md, invariants I2/I3/I4b + bypass).

Works on the compiler's parse tree (`swiftc -dump-parse`), so comments and string
literals never produce identifier matches. Usage:

    controls_contract_ast.py --root <dir containing Swift sources>

Exit 0 = clean, 1 = violations (printed as `VIOLATION <rule> <file>: <detail>`), 2 = tool error.
"""
import argparse, concurrent.futures, os, re, subprocess, sys

COMMON_PLOT_COMPONENTS = {
    "WorkbenchCommonControls", "CartesianXYPlotControls", "DualAxisPlotControls", "HeatmapPlotControls",
}
# Removed in the migration: the three independent assemblers. Declaring or using any of them
# again is a violation (there is no allow-list).
LEGACY_COMPONENTS = {
    "WorkbenchStandardPlotControls", "WorkbenchPlotControlsPanel",
    "DualAxisPlotControlsPanel", "HeatmapPlotControlsPanel",
}
SPECIFIC_MARKERS = {
    "WorkbenchLeafInput", "WorkbenchSpecificGroup", "WorkbenchSpecificBuilder",
    "WorkbenchSpecificContent", "WorkbenchSpecificRow", "WorkbenchSpecificInput",
}
COMMON_LITERALS = {"Show Title", "Plot title", "Title size", "Transparent"}
# Shared UI directories: they must never reference a concrete workflow, store or app state.
SHARED_DIRS = ("/ControlsSurface/", "/PlotSystem/Controls/")
SHARED_FORBIDDEN_EXTRA = {"workflowID", "SpinLabAppState", "WorkbenchWorkflowKind", "WorkbenchFeatureStore"}


def dump(path):
    out = subprocess.run(["swiftc", "-dump-parse", path], capture_output=True, text=True)
    return out.stdout + out.stderr


class Facts:
    def __init__(self, path, text):
        self.path = path
        self.base = os.path.basename(path)
        self.idents = set(re.findall(r'(?:\bname|\bid|\bfield|\blabel)="([^"]+)"', text))
        self.decls = set(re.findall(r'\((?:struct|class|enum|protocol|actor)_decl[^\n]*? "([A-Za-z0-9_]+)"', text))
        self.literals = set(re.findall(r'string_literal_expr[^\n]*? value="([^"]*)"', text))
        # The parse dump omits inheritance clauses, so read each declaration header at the
        # position the parse tree reports (comments stripped) to learn its conformances.
        self.idents |= declaration_conformances(path, text)
        for m in re.finditer(r'argument_list labels="([^"]*)"', text):
            for lab in m.group(1).split(":"):
                if lab:
                    self.idents.add(lab)


def declaration_conformances(path, text):
    try:
        lines = open(path, encoding="utf-8").read().split("\n")
    except OSError:
        return set()
    found = set()
    for m in re.finditer(r'\((?:struct|class|enum|protocol|actor|extension)_decl[^\n]*?range=\[[^:\]]*:(\d+):(\d+)', text):
        line, col = int(m.group(1)) - 1, int(m.group(2)) - 1
        if line >= len(lines):
            continue
        chunk = lines[line][col:] + "\n" + "\n".join(lines[line + 1:line + 6])
        chunk = re.sub(r'/\*.*?\*/', '', chunk, flags=re.S)
        chunk = re.sub(r'//[^\n]*', '', chunk)
        header = chunk.split("{", 1)[0]
        if ":" in header:
            header = header.split(":", 1)[1]
            header = header.split(" where ", 1)[0]
            for part in re.findall(r'[A-Za-z_][A-Za-z0-9_\.]*', header):
                found.add(part.split(".")[-1])
    return found


def deny_identifiers(root, facts):
    for f in facts:
        if f.base == "WorkbenchLayoutPolicyIdentifiers.swift":
            raw = open(f.path).read()
            block = re.search(r"widthMeasuring[^=]*=\s*\[(.*?)\]", raw, re.S)
            if block:
                return set(re.findall(r'"([^"]+)"', block.group(1)))
    return {"GeometryReader", "ViewThatFits", "onGeometryChange", "containerRelativeFrame", "Layout", "AnyLayout"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    args = ap.parse_args()

    files = []
    for d, _, names in os.walk(args.root):
        for n in names:
            if n.endswith(".swift"):
                files.append(os.path.join(d, n))
    if not files:
        print("controls-contract: no Swift files under", args.root)
        return 2
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        facts = [Facts(p, t) for p, t in zip(files, pool.map(dump, files))]

    deny = deny_identifiers(args.root, facts)
    violations = []

    def in_surface(f):
        return any(d in f.path.replace(os.sep, "/") for d in SHARED_DIRS)

    # Workflow-side vocabulary comes from the actual declarations, not a hand list.
    workflow_types = set()
    for f in facts:
        if "/Features/Workbench/" in f.path or "/Features/Workbench" in os.path.dirname(f.path):
            workflow_types |= {d for d in f.decls if d.endswith(("WorkspaceStore", "WorkbenchTab", "WorkspaceView"))}
    shared_forbidden = workflow_types | SHARED_FORBIDDEN_EXTRA

    for f in facts:
        # I3 — shared UI layers never reference concrete workflows/stores.
        if in_surface(f):
            hit = f.idents & shared_forbidden
            if hit:
                violations.append(("shared-depends-on-workflow", f, ", ".join(sorted(hit))))
            continue

        is_workspace_view = "WorkflowWorkspaceLeftColumn" in f.idents and "WorkflowWorkspaceLeftColumn" not in f.decls
        uses_legacy_label = "legacyPlotControls" in f.idents

        declares_workspace_view = any(d.endswith("WorkspaceView") for d in f.decls) \
            and "/Features/Workbench/" in f.path.replace(os.sep, "/") + ""
        if declares_workspace_view and not is_workspace_view:
            violations.append(("bypasses-surface", f, "a workspace view must mount through WorkflowWorkspaceLeftColumn(controls:), not build its own left column"))

        if is_workspace_view:
            # `controls:` is the only parameter of WorkflowWorkspaceLeftColumn that carries
            # controls, and its type is the descriptor, so the label proves the Surface mount.
            if "controls" not in f.idents:
                violations.append(("bypasses-surface", f, "workspace view does not mount the Controls Surface via controls:"))
            if uses_legacy_label:
                violations.append(("uses-legacy-path", f, "legacyPlotControls no longer exists"))
            hit = f.idents & (COMMON_PLOT_COMPONENTS | LEGACY_COMPONENTS)
            if hit:
                violations.append(("rebuilds-common-or-plot", f, ", ".join(sorted(hit))))
        else:
            if uses_legacy_label and "WorkflowWorkspaceLeftColumn" not in f.decls:
                violations.append(("uses-legacy-path", f, "legacyPlotControls outside a workspace view"))
            hit = f.idents & COMMON_PLOT_COMPONENTS
            if hit and "WorkflowWorkspaceLeftColumn" not in f.decls:
                violations.append(("direct-component-use", f, ", ".join(sorted(hit))))
            hit = (f.idents | f.decls) & LEGACY_COMPONENTS
            if hit:
                violations.append(("uses-legacy-component", f, ", ".join(sorted(hit))))

        # Duplicate Common implementations outside the Surface.
        lits = f.literals & COMMON_LITERALS
        if len(lits) >= 2:
            violations.append(("duplicate-common", f, ", ".join(sorted(lits))))

        # I4b — Specific/leaf code must not measure width or place groups.
        if f.idents & SPECIFIC_MARKERS:
            hit = f.idents & deny
            if hit:
                violations.append(("specific-sets-layout-policy", f, ", ".join(sorted(hit))))

    for rule, f, detail in violations:
        print(f"VIOLATION {rule} {os.path.relpath(f.path, args.root)}: {detail}")
    if violations:
        return 1
    print(f"controls-contract: OK ({len(files)} files, {len(workflow_types)} workflow types discovered)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
