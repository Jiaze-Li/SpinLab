# SpinLab documentation

This page is a **navigation index**, not a new contract or progress board. Read the smallest useful set of current documents. Historical designs do not override current task requirements.

## Start from the work you are doing

| Work | Read first | Then, as needed |
|---|---|---|
| New Sample-centred feature | [Execution entry](architecture/spinlab/execution/README.md) → [SKELETON](architecture/spinlab/execution/SKELETON.md) → relevant brief | [Library](architecture/library/INDEX.md) and [Inbox](architecture/inbox/INDEX.md) architecture, actual code |
| Existing bug / refactor | [Architecture index](architecture/INDEX.md) → owning region | [Feature invariants](features.md), relevant specs, code and tests |
| Workbench / plots | [Workbench index](architecture/workbench/INDEX.md) | [UI rules](../specs/04_UI_RULES.md), [plot rules](../specs/05_PLOT_RULES.md), [controls](../specs/06_WORKBENCH_CONTROLS_UI.md) |
| Inbox / archive behavior | [Product rules](../specs/01_PRODUCT_RULES.md), [Inbox index](architecture/inbox/INDEX.md) | [Library index](architecture/library/INDEX.md), [data-rule entry](../specs/02_DATA_RULES.md) |
| Agent engineering / tests | [AGENTS.md](../AGENTS.md) | [Test strategy](architecture/TESTING_STRATEGY.md) and owning module |
| Web variants and export | [Ecosystem boundaries](ecosystem.md) | [Web Library](web_library.md), [design notes](WebLibraryDesignPrinciples.md) |

## One maintained owner per subject

| Subject | Source of truth | Scope |
|---|---|---|
| Approved new Sample-centred data model and safeguards | [SKELETON.md](architecture/spinlab/execution/SKELETON.md) | Target for new work; not proof of current implementation |
| Sample task requirements, order and dependencies | [Execution README / briefs](architecture/spinlab/execution/README.md) | One brief per task; task progress is elsewhere |
| Task progress | [V5_ROADMAP.md](V5_ROADMAP.md) | 5.6.x for Sample-centred work; no parallel task board |
| Technical-debt lifecycle | `docs/TASK_BOARD.md` (shared symlink) | Only the shared task board tracks debt state |
| Current implemented architecture | [Architecture index](architecture/INDEX.md) and region documents | Verify against actual Swift when touching code |
| UI and figures | [specs](../specs/) | Global UI, plot typography and Workbench controls have separate owners |
| Common Agent rules | [AGENTS.md](../AGENTS.md) | [CLAUDE.md](../CLAUDE.md) is a compatibility pointer |
| Scientific research and past design rationale | [Historical design index](architecture/spinlab/README.md) | Reference, not an implementation mandate |

## History and handoffs

[D1–D6, G0/G1 and new database designs](architecture/spinlab/README.md) document earlier decisions and review evidence. D2/D4/D5 preserve scientific examples and important domain reasoning, but are not automatically binding on current implementation. The G1-01 supplemental designs v0.1–v0.4 are retired.

History also exists under `docs/archive/`, `docs/handoff/archive/`, and area-specific history folders. Use [handoff rules](handoff/README.md) for short-lived cross-agent context; prefer PR discussion to a permanent file for each review comment.

`docs/history` and `docs/TASK_BOARD.md` are symlinks to the sibling `SpinLab-shared` directory in the intended local multi-worktree layout. They may not resolve in GitHub or an ordinary clone. Do not replace them with local copies or infer an empty task board after a failed read.

Further references: [developer philosophy](philosophy.md), [feature status](features.md), and [V5 roadmap](V5_ROADMAP.md).
