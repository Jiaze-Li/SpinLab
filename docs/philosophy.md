# Development Philosophy

Status: active
Owner: Jack (product owner) — AI supplements, Jack confirms

This document captures Jack's development philosophy, habits, and preferences.
It is not a rule file (those live in CLAUDE.md and specs/).
It helps AI assistants understand *how Jack thinks* so they can collaborate more effectively.

---

## Interaction Philosophy

- Information density over decoration. UI is a research tool, not a consumer product.
- Minimal clicks. If a workflow step can be eliminated without losing safety, eliminate it.
- No silent behavior. If the system makes a decision, the user must be able to see why.
- Parsed metadata is always a suggestion. User confirmation is the only authority.
- **What you see is what the app is set to.** Every rule — including rarely-changed ones — must be visible and editable in the UI. No silent configuration outside the UI. (Established v5.1.5.)

## Data Philosophy

- Raw data is immutable. All transformations are traceable.
- Internal archive is the canonical source of truth, not external files.
- Sample is the anchor for all experimental knowledge.
- Domain model is the contract. Features build on the model, not around it.

## Architecture Philosophy

- First-principles reasoning. No redundant, decorative, or non-functional code.
- Long-term maintainability over short-term convenience.
- Extension-based growth. New workflows enter through extension modules, not core changes.
- Reject complexity that serves hypothetical future needs.
- Three similar lines of code is better than a premature abstraction.

## Collaboration Philosophy

> Canonical collaboration rules (role definition, execution gate, adversarial protocol, workload balancing) live in the global `~/.claude/CLAUDE.md`. This section documents SpinLab-specific context and the full rationale.

### Role Definition
- Jack is the **product owner** — he sets direction, makes product decisions, and judges UX/aesthetics. He is not a technical supervisor.
- AI agents (Claude + Codex) hold **technical execution authority** — they independently design, implement, and review all code-level decisions.
- This delegation requires a strict dual-AI adversarial mechanism as the quality guarantee (see Cross-Review Protocol below).

### Interaction Boundaries

**Ask Jack (product-level):**
- Feature behavior ("what should happen when the user clicks X?")
- Direction and priority trade-offs ("support A or B first?")
- UI layout and aesthetics ("panel placement, visual style")
- Product logic ambiguity ("when data conflicts, which source wins?")

**AI resolves internally (technical-level):**
- Which files to change, what code to write, what variables/protocols to add
- Architecture decisions, module boundaries, refactor strategies
- Technical debt cleanup approach and sequencing
- Implementation path selection when product outcome is equivalent
- All code-level review findings and fixes

**When AI cannot converge on a technical decision:** translate the disagreement into product-level impact (e.g., "方案 A 启动快但占内存多，方案 B 反过来") and ask Jack to choose on the product axis. Never surface code-level details.

### Execution Gate (需求确认门禁)
- The gate is at **requirement confirmation**, not plan approval.
- If Jack's intent is clear → AI proceeds directly to design, adversarial review, execution, and cross-review. No technical plan is presented for approval.
- If Jack's intent is ambiguous → AI confirms in functional language ("你是要实现 XX 效果吗？"), then proceeds upon confirmation.
- The gate protects against AI acting prematurely during exploratory discussion. It does NOT require Jack to review or approve technical plans.
- AI must not present technical implementation details (files, code, variables) for Jack to approve — that is the dual-AI adversarial protocol's job.

### General Rules
- AI should use functional language (what the user sees, what happens) in design discussions, not code-level terms. Do NOT report file names, class names, variable names, or implementation details to Jack unless he specifically asks.
- Default: responses in Chinese, terse, no trailing summaries. User's explicit per-session format requests take precedence.

## Cross-Review Protocol (Claude ↔ Codex)

Because technical execution authority is delegated to AI without human code review, the dual-AI adversarial mechanism is the **sole quality gate**. Every rule below exists to prevent single-AI regression, hallucination, and confirmation bias.

### Core Principle: Independent Thinking (独立思考)
- `[HARD]` At every phase, each AI must think **independently**. No leading questions, no suggested focus areas, no pre-formed conclusions passed to the other side.
- `[HARD]` Information passed between AIs must be **minimal and non-directive**: raw requirements for design, file list + intent for review. Nothing more.
- `[HARD]` The purpose of two AIs is adversarial diversity of thought. Any communication pattern that causes one AI to follow the other's mental model defeats the mechanism and is forbidden.

### 1. Design Review (方案交叉审核)
- Trigger: cross-module changes, new patterns, persistence format changes, architecture rule changes.
- `[HARD]` Mode: give each side the **user's original requirement only** (not the other side's proposal). Both independently produce a proposal, then compare, challenge, and merge.
- `[HARD]` Do NOT share one side's draft with the other before the other has produced its own. This prevents framing bias.
- Mutual challenge is expected after initial proposals — the goal is design convergence through adversarial discussion.
- `[HARD]` Do not execute a plan that either side has flagged with unresolved objections. If technical disagreement cannot be resolved, translate into product impact and ask Jack.
- Purely mechanical tasks (typo fix, single confirmed bug fix, execution of an approved plan) skip this phase.

### 2. Execution (分工并行)
- Once design review converges, Claude acts as **task coordinator**: splits the approved plan into concrete subtasks and assigns them between Claude and Codex.
- Example: Claude does subtasks 1/2/3, Codex does subtasks 4/5/6 — both execute in parallel.
- Codex is a **full implementer**, not just a reviewer. Codex can write code, run commands, execute builds, and perform analysis independently.
- Each side is responsible for the code it writes. Clear ownership boundaries for cross-review traceability.
- Execution proceeds once requirement is confirmed and design review converges. No separate user approval needed for the technical plan.

### Workload Balancing (工作量分配)
- `[HARD]` Both AIs must be substantively utilized. Do not default to one AI doing all implementation while the other only reviews.
- `[DIRECTION]` Default workload split: **balanced** — roughly equal implementation effort between Claude and Codex when tasks are divisible.
- **User-adjustable parameter**: Jack may adjust the balance at any time by stating a preference (e.g., "让 Codex 多做点", "Claude 这轮多承担", "Codex 为主"). AI must respect the current setting until Jack changes it.
- Current setting: **balanced** (default).
- When tasks cannot be meaningfully split (e.g., single-file fix), the primary implementer still changes based on the current balance setting, and the other side handles review.

### 3. Acceptance Review (交叉验收)
- `[HARD]` The implementer does NOT review their own work. Claude's code → Codex reviews. Codex's code → Claude reviews.
- `[HARD]` Review brief states **only** what files changed and the intent. Do NOT list verification questions, do NOT suggest what to check, do NOT highlight areas of concern. The reviewer decides independently what to examine.
- `[HARD]` Findings → implementer fixes → reviewer re-verifies. Loop until reviewer reports no new issues. This loop cannot be skipped or shortened.
- `[HARD]` A new round is required when: reviewer found issues and implementer fixed them; the fix itself introduced new code that was not yet reviewed; or new user feedback changes the scope.
- Trigger: after each round of code changes, not after every small edit.

### 4. Single-AI Fallback (单 AI 降级)
- `[HARD]` If only one AI is available (e.g., Codex unavailable), that AI does **not** have technical autonomy. Technical plans must be described in functional language and confirmed by Jack before execution.
- Rationale: the adversarial mechanism is the precondition for technical delegation. Without it, human oversight must compensate.

### Why This Matters
- Leading questions cause confirmation bias — the reviewer follows the implementer's mental model and misses real issues.
- Independent review finds bugs the implementer's blind spots hide (validated in v5.3.2 session: Codex found Hc unit mismatch, empty label bug, and stale trace that Claude missed).
- Human oversight was relaxed specifically because this mechanism exists. Weakening it removes the only quality gate.

## Aesthetic Preferences

- UI: structured inspection panels, full filename readability, clear metadata grouping.
- Code: descriptive naming, no comments where logic is self-evident, no docstrings on unchanged code.
- Naming: user-defined display names and IDs are sacred — never rename without explicit instruction.
