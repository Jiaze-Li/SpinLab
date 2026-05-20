# SpinLab

A native macOS research app for magnetic experiment ingestion, visualization, analysis, and archival.

## Documentation

Full documentation index lives at [`docs/README.md`](docs/README.md).

Key entry points:

| Document | Purpose |
|---|---|
| [`docs/README.md`](docs/README.md) | Documentation index (architecture / specs / history / handoff) |
| [`docs/architecture/INDEX.md`](docs/architecture/INDEX.md) | Architecture dispatch entry |
| [`docs/V5_ROADMAP.md`](docs/V5_ROADMAP.md) | Active roadmap |
| [`docs/TASK_BOARD.md`](docs/TASK_BOARD.md) | Cross-version task overview |

## Setup

**Architecture coverage hook**: after first clone, run `./scripts/install_git_hooks.sh` to install the architecture documentation coverage pre-commit check.

## Web Library Export

SpinLab-html stays code-only. The static web library lives in the separate private repo `../SpinLab-Web-Library`, and the exporter writes only into that repo's `public/` directory.

Supported export path:

```bash
python scripts/export_static_library.py \
  --library-root /Users/jack/Downloads/data \
  --output-dir ../SpinLab-Web-Library/public
```

Workflow:

1. Run the exporter from this repo.
2. Review the generated files in `../SpinLab-Web-Library/public`.
3. Manually commit and push changes from the private web repo. The exporter never runs `git commit` or `git push`.
4. Cloudflare Pages deploys from the private repo's `public/` output.
5. Cloudflare Access uses One-time PIN login. Keep the browser session for 30 days when you want the login to persist across visits.

The exporter may replace files inside `--output-dir`, but it must not delete or modify anything outside that directory.

## Agent Policy

| Document | Purpose |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) / [`AGENTS.md`](AGENTS.md) | Agent execution policy, hard gates, implementation behavior constraints (mirrored copies) |
