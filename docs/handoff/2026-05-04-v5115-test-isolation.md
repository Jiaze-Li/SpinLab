# v5.1.15 测试隔离 + 配置安全网（handoff）

**版本**: 5.1.15 收尾补丁
**生成**: 2026-05-04
**状态**: 待消费

---

## 1. 背景

v5.1.15 round-3 引入的 `V5115LibraryFeatureStoreCharacterizationTests` 没做文件系统隔离：

- 测试直接调真实 `LibraryFeatureStore.updateLibraryRoot(to: URL(fileURLWithPath: "/new/root"))` → `LibrarySettingsStore.save()` → 写真实 `~/Library/Application Support/SpinLab/library_settings.json`
- `swift test` 把用户原 OneDrive Library Root 覆盖成 `/new/root`，造成生产配置被测试副作用污染

事故已手工恢复。本 handoff 修根因 + 加安全网，并把规则写入 CLAUDE.md（已在前序 commit 完成）。

双 AI 评审：Claude 出方案 → Codex 评审 (`adopt-with-fixes` + 5 条 must-fix) → 整合定稿。

---

## 2. 修改点

### 2.1 `LibrarySettingsStore` 双 init（替代 optional fallback）

`Sources/SpinLabApp/Library/LibrarySettingsStore.swift`

```swift
final class LibrarySettingsStore {
    private let fileManager = FileManager.default
    private let logger = AppLogger.shared
    let settingsURL: URL  // 暴露给测试做隔离断言（read-only, public)
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// 生产路径：Application Support/SpinLab/library_settings.json
    convenience init() {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
        let spinLabURL = appSupportURL.appending(path: "SpinLab", directoryHint: .isDirectory)
        let url = spinLabURL.appending(path: "library_settings.json")
        self.init(settingsURL: url)
    }

    /// 测试 / 自定义路径：必须显式传 URL，禁止 nil
    init(settingsURL: URL) {
        self.settingsURL = settingsURL

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        try? fileManager.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
    // load / save 见下方
}
```

**为什么不用 `init(URL?)` optional**：测试 fixture 若意外传 nil 会静默回真实 Application Support，安全网失效。两个独立 init 让"测试入口"在编译期可识别。

### 2.2 `save()` 写 `.backup` 安全网（显式 do/catch，不静默吞错）

```swift
func save(_ settings: LibrarySettings) {
    let data: Data
    do {
        data = try encoder.encode(settings)
    } catch {
        logger.error(.library, "Failed to encode library settings", metadata: [
            "reason": error.localizedDescription
        ])
        return
    }

    // 写入前备份现有版本（污染恢复语义：保留覆盖前的最近一份）
    if fileManager.fileExists(atPath: settingsURL.path) {
        let backupURL = settingsURL.appendingPathExtension("backup")
        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: settingsURL, to: backupURL)
        } catch {
            // 备份失败不中止 save — 用户主动动作不该因安全网建立失败被打断；
            // 但必须 log，让事后排查能看到"这次 save 没有 backup"
            logger.warning(.library, "Failed to write settings backup before save (safety net unavailable for this write)", metadata: [
                "backupPath": backupURL.path,
                "reason": error.localizedDescription
            ])
        }
    }

    do {
        try data.write(to: settingsURL, options: .atomic)
    } catch {
        logger.error(.library, "Failed to persist library settings", metadata: [
            "path": settingsURL.path,
            "reason": error.localizedDescription
        ])
    }
}
```

**.backup 时机**：写在 save 之前。污染恢复需要的是"被覆盖前的用户配置"，不是写完后的污染值。

**单档 backup（不滚动）**：本场景污染源是测试，根因修好后不再连续覆盖；上时间戳滚动会引入清理策略和数据保留边界，超出本次 scope。

### 2.3 `load()` 加 rootPath 存在性 warning

```swift
func load() -> LibrarySettings {
    guard fileManager.fileExists(atPath: settingsURL.path) else { return .default }
    let data: Data
    do { data = try Data(contentsOf: settingsURL) }
    catch {
        logger.error(.library, "Failed to read library settings", metadata: [...])
        return .default
    }
    do {
        let settings = try decoder.decode(LibrarySettings.self, from: data)
        if let rootPath = settings.rootPath, !rootPath.isEmpty,
           !fileManager.fileExists(atPath: rootPath) {
            logger.warning(.library, "Library rootPath does not exist on disk", metadata: [
                "rootPath": rootPath
            ])
        }
        return settings
    } catch {
        logger.error(.library, "Failed to decode library settings (corrupt file, using defaults)", metadata: [...])
        return .default
    }
}
```

**只 log 不改 UI**：路径不存在可能是外接盘没挂、云盘离线、迁移中等合法状态，不应自动改 UI 或 fallback。诊断价值即可。

### 2.4 测试隔离 — `withIsolatedFeatureStore` closure helper

`Tests/SpinLabAppTests/V5115LibraryFeatureStoreCharacterizationTests.swift`

删除现有 `private func makeStore() -> LibraryFeatureStore`，替换为 closure-based helper：

```swift
/// 创建隔离 fixture：tempDir + 注入 settingsURL 的 LibrarySettingsStore，
/// closure 退出时自动清理 tempDir。目录创建失败直接 throw（不静默 try?）。
@MainActor
private func withIsolatedFeatureStore<T>(
    _ body: (LibraryFeatureStore, _ settingsURL: URL) throws -> T
) throws -> T {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("V5115FeatureStore-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let settingsURL = tempDir.appendingPathComponent("library_settings.json")
    let store = LibraryFeatureStore(
        librarySettingsStore: LibrarySettingsStore(settingsURL: settingsURL),
        libraryStore: LibraryStore(),
        libraryLogger: LibraryLogger(),
        libraryDiffEngine: LibraryDiffEngine(),
        librarySampleEditService: LibrarySampleEditService()
    )
    return try body(store, settingsURL)
}
```

19 个 test case 全部改成 closure 形式。示例（case 9 updateLibraryRoot）：

```swift
@Test("updateLibraryRoot clears verification path and message")
func updateLibraryRootClearsVerificationState() throws {
    try withIsolatedFeatureStore { store, _ in
        store.libraryRootVerificationPath = "/old/path"
        store.libraryRootVerificationMessage = "Previously verified."
        store.updateLibraryRoot(to: URL(fileURLWithPath: "/new/root"))
        #expect(store.librarySettings.rootPath == "/new/root")
        #expect(store.libraryRootVerificationPath == nil)
        #expect(store.libraryRootVerificationMessage == nil)
    }
}
```

**`LibraryFeatureStoreIsolation` actor 锁**：保留（fs 隔离后理论可删，但保守起见维持现状，避免引入并发回归风险）。

### 2.5 新增持久化隔离 regression test

新增 case，验证 save 写入路径确实是 injected 的 tempDir：

```swift
@Test("save persists to injected settings URL, not real Application Support")
func saveWritesToInjectedSettingsURL() throws {
    try withIsolatedFeatureStore { store, settingsURL in
        store.updateLibraryRoot(to: URL(fileURLWithPath: "/tmp/regression-marker-\(UUID().uuidString)"))

        // 1. injected tempDir 文件存在
        #expect(FileManager.default.fileExists(atPath: settingsURL.path))

        // 2. 内容确实是刚 set 的 rootPath
        let data = try Data(contentsOf: settingsURL)
        let decoded = try JSONDecoder().decode(LibrarySettings.self, from: data)
        #expect(decoded.rootPath?.contains("regression-marker") == true)
    }
}
```

**为什么不直接断言"真实 Application Support 文件不变"**：在 swift test 里读真实路径本身违反隔离原则；这条 guard 通过反向断言（写入位置确是 injected URL）等价覆盖。

---

## 3. 验收口径

1. `swift test --filter V5115LibraryFeatureStoreCharacterization` 全 20 case 绿（19 原 case + 1 新增 regression）
2. **关键回归测试**：跑测试前后 `sha256sum ~/Library/Application\ Support/SpinLab/library_settings.json` 一字不差
3. 全套 `swift test` (360s timeout) 全绿（不带 filter）
4. 桌面 app rebuild + 启动，Library Root 仍是 OneDrive 路径
5. 手动改 `library_settings.json` 损坏成 `/nonexistent/path`，启动 app 后 `app_events.log` 含 `Library rootPath does not exist on disk` warning
6. 触发一次 Library 配置修改（如 Choose Library Root），确认 `library_settings.json.backup` 被写入

---

## 4. 风险点 & 不在范围

### 风险点

- **R1 (low)**：`.backup` 单档每次覆盖；连续两次污染会丢 backup。本场景测试隔离修好后不复发，可接受。
- **R2 (low)**：测试 `tempDir` 在 `/var/folders/...`，crash 时 defer 不执行会留残留；macOS 系统定期清理可接受。
- **R3 (low)**：`load()` warning 在 app 启动期写，需确认 `AppLogger.shared` 在 LibraryFeatureStore.init 时已初始化 — 执行时若 log 实际未落盘，改为延后到第一次 UI 渲染前发。

### 不在范围

- 抽 `LibrarySettingsStoreProtocol` 做依赖反转：超出事故修复，当前 store 行为很窄不值得抽象（Codex 同意）。
- 时间戳滚动 backup：超出 scope（Codex 同意）。
- `loadResult` enum / 自动 fallback：会越过用户确认权（Codex 同意）。
- 其他 `V5115LibraryStoreCharacterizationTests` 等已用 tempDir 的测试：本来就隔离，不动。

---

## 5. 执行顺序

1. 改 `LibrarySettingsStore.swift`（修改点 2.1 + 2.2 + 2.3）
2. 跑 `swift build` 验证编译（不动测试时其他调用点应自动通过 `LibrarySettingsStore()` convenience init）
3. 改 `V5115LibraryFeatureStoreCharacterizationTests.swift`（修改点 2.4 + 2.5）
4. 跑 `swift test --filter V5115LibraryFeatureStoreCharacterization`，全绿
5. **关键 sentinel**：先 `sha256sum ~/Library/Application\ Support/SpinLab/library_settings.json` 记一个值；再跑全套 `swift test`；再 sha256sum 比对，**hash 一致 = 隔离成功**
6. `./scripts/build_desktop_app.sh debug` rebuild
7. 启动 app，确认 Library Root 仍是 OneDrive 路径
8. commit + handoff 归档 + ROADMAP 标 [x] + history 设计思路迁移

---

## 6. Phase 状态

s1 = 方案完成（本 handoff 落盘瞬间）
s2 = 方案执行中（接手会话第一次 commit 落地翻状态）
s3 = 验收中（所有 commit 完毕 + ROADMAP `[x]` 当天）
s4 = 验收通过（Jack 给"5.1.15 验收通过"含版本号指令时整行删 + history INDEX 加一行）

---

## 7. 评审证据

- Claude 方主稿：`tmp/v5115-test-isolation-review-brief.md` §5
- Codex 评审：`tmp/v5115-test-isolation-review.md`（裁决 adopt-with-fixes，5 条 must-fix 全部并入本 handoff §2 修改点）
- 派发流水：`tmp/v5115-test-isolation-review.md-stdout.log`
