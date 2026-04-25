# Tech Debt Inbox

> **角色**：未分版本段的 raw 捕获池。
>
> **流程**：
> 1. 发现新债 → 追加到 `## Inbox` 末尾，写明 code pointer / 问题 / 目标态 / 估时
> 2. Jack 拍板归入 `docs/V5_ROADMAP.md` 的某个 5.x.y 段
> 3. **同时**从本文件删除该条（避免与 ROADMAP 双账本）
>
> 已完成事件不再进本文件，统一走 `history/vX.Y.Z_*.md` 版本日志（沿用 v5.3.x / v5.5.0 的模式）。
> `TECH_DEBT_EXECUTION_LOG.md` 已 sunset，保留作为历史记录，不再追加。

---

## Inbox

### `try?` audit in LibraryStore — 剩余项

**Code:** `Sources/SpinLabApp/Library/LibraryStore.swift` — `createDirectory` 调用 + 部分 read paths

**Status:** Partial done 2026-04-05 (Round E)。`writeJSON` 已加 stderr 日志，关键写入路径有原子事务保护。

**Remaining problem:** `createDirectory` 和若干 read path 仍用 `try?` 静默吞错。失败时无日志，调试时只能从"目录莫名为空"反推。

**Target state:** 至少 stderr 落日志，可选升级为 throw + 调用方处理。

**Effort:** Low (mechanical)。
