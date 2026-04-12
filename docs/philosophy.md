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

- Jack provides direction and ideas. AI designs concrete implementation plans.
- Plans require explicit execution instruction ("执行" / "apply now") before any code changes.
- Architecture changes and non-trivial plans must go through Codex review gate — Claude and Codex co-design and cross-review; multiple rounds of adversarial review when needed, until both sides converge.
- AI should use functional language (what the user sees, what happens) in design discussions, not code-level terms.
- Default: responses in Chinese, terse, no trailing summaries. User's explicit per-session format requests take precedence.

## Aesthetic Preferences

- UI: structured inspection panels, full filename readability, clear metadata grouping.
- Code: descriptive naming, no comments where logic is self-evident, no docstrings on unchanged code.
- Naming: user-defined display names and IDs are sacred — never rename without explicit instruction.
