# JettyNotepad Architecture v1.0

> Date: 2026-04-05
> Status: Design (pre-implementation)

---

## 1. Architecture Decision Records

### ADR-001: Swift + AppKit

**Decision:** Swift + AppKit (not SwiftUI, not Tauri, not Electron)

**Rationale:**
- `NSTabbedWindow` 免费提供标签拖出为独立窗口能力（SwiftUI 至今不支持）
- `NSDocument` 架构天然支持自动保存、版本管理、会话恢复
- `NSTextView` 提供完整的文本编辑能力（拼写检查、Undo/Redo、属性字符串）
- 启动时间 ~200ms、内存 ~15-30MB、包体 ~2-5MB — 符合"轻量"定位
- CotEditor（7.8K stars）验证了这条技术路径的可行性
- SwiftUI 可用于偏好设置面板等次要 UI（通过 `NSHostingView` 嵌入）

**最低部署目标:** macOS 13 (Ventura) — 覆盖 ~95% 活跃 Mac

---

### ADR-002: NSTextView + TextKit 1

**Decision:** NSTextView + TextKit 1 编辑器引擎

**Rationale:**
- 通过子类化 `NSTextStorage`，在 `processEditing()` 中解析 Markdown 语法并应用 `NSAttributedString` 属性，实现类 Typora 的内联渲染
- `NSUndoManager` 集成：可自定义 undo 分组、设置 100 步上限、hook 编辑操作用于快照创建
- `textStorage(_:didProcessEditing:range:changeInLength:)` 代理方法在每次变更时触发，提供精确 delta 用于快照
- 内置 `NSSpellChecker` 集成（红色下划线、建议替换、自动更正）
- TextKit 2 待 macOS 稳定后在 v2+ 迁移（CotEditor 曾尝试迁移但因渲染 bug 回退）

---

### ADR-003: SQLite 作为 .jnt 格式

**Decision:** `.jnt` 文件是一个 SQLite 数据库

**备选方案对比:**

| 方案 | 写入性能 | 崩溃安全 | 可调试性 | Quick Look | 选择 |
|------|---------|---------|---------|------------|------|
| **SQLite** | INSERT（增量） | WAL 模式原子写 | `sqlite3 file.jnt` | QL 扩展 ~50 行 | **选用** |
| ZIP Bundle | 全量重写 | 需 temp+rename | 改名 .zip 即可查看 | 内嵌 Preview.txt | 备选 |
| 自定义二进制 | 可优化 | 需自建 | 无 | 需 QL 扩展 | 否决 |
| JSON | 全量重写 | 无原子性 | 极好 | 纯文本 | 否决 |

**关键理由:**
- 自动保存频率高（每分钟 + 失焦 + 空闲），SQLite INSERT 比 ZIP 全量重写效率高一个量级
- WAL 模式：崩溃时不丢失数据，读写不互相阻塞
- `PRAGMA integrity_check` 提供内建完整性检查
- `PRAGMA user_version` 支持无痛 schema 迁移
- macOS 系统自带 SQLite — 无需打包
- Apple 自家应用（Photos、Mail、Messages）全部使用 SQLite 做文档存储

---

### ADR-004: diff-match-patch 差异算法

**Decision:** 使用 diff-match-patch（字符级），而非 Myers（行级）

**Rationale:**
- JettyNotepad 面向散文/笔记，不是代码 — 修一个错别字不应生成整行 diff
- 对比 Myers 行级：空间节省 20-30%，100 个快照累积可观
- diff-match-patch 专为人类文本设计（Google Docs 同款），内置语义清理
- 5ms 内完成 50KB 文档对比，patch 应用 < 1ms
- Swift 社区有可用移植（~1500 行，基于 Google 公开规范）

**存储策略:** 反向 diff 链。当前内容完整存储，每个快照存从新到旧的反向 diff。读取当前文档无需任何 diff 处理。

---

## 2. .jnt 文件格式（SQLite Schema）

### 2.1 Schema 定义

```sql
-- 文档当前状态（始终只有 1 行）
CREATE TABLE document (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    content TEXT NOT NULL,                    -- 当前文本（UTF-8）
    cursor_position INTEGER DEFAULT 0,
    scroll_position REAL DEFAULT 0.0,
    created_at TEXT NOT NULL,                 -- ISO 8601
    modified_at TEXT NOT NULL,                -- ISO 8601
    original_line_ending TEXT DEFAULT 'LF'    -- LF / CRLF / CR
);

-- 历史快照（最多 100 个）
CREATE TABLE snapshots (
    seq INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,                  -- ISO 8601
    snapshot_type TEXT NOT NULL,              -- manualSave / autoSave / sessionBoundary / forkPoint
    edit_summary TEXT,                        -- type / paste / delete / replace / mixed
    diff_data BLOB NOT NULL,                 -- diff-match-patch 压缩反向 diff
    content_length_before INTEGER,
    content_length_after INTEGER
);

-- 元数据键值对
CREATE TABLE metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- 来源链：子文件记录
CREATE TABLE children (
    child_uuid TEXT PRIMARY KEY,
    child_path TEXT,                          -- 最后已知路径（提示，非权威）
    fork_timestamp TEXT NOT NULL,
    fork_snapshot_seq INTEGER
);

-- 快照上限触发器
CREATE TRIGGER limit_snapshots AFTER INSERT ON snapshots
BEGIN
    DELETE FROM snapshots
    WHERE seq IN (
        SELECT seq FROM snapshots
        ORDER BY seq ASC
        LIMIT max(0, (SELECT count(*) FROM snapshots) - 100)
    );
END;
```

### 2.2 metadata 表预定义 key

| key | 值示例 | 说明 |
|-----|--------|------|
| `format_version` | `"1"` | 格式版本号 |
| `file_uuid` | `"550e8400-..."` | 全局唯一，创建后不变 |
| `display_name` | `"会议纪要 Q2"` | 自动从首行生成 |
| `display_name_source` | `"firstLine"` / `"userSet"` | 名称来源 |
| `parent_uuid` | `"339a2e00-..."` / `null` | 父文件 UUID |
| `parent_path` | `"/Users/.../v1.jnt"` | 父文件最后已知路径 |
| `parent_snapshot_seq` | `"42"` | 从父文件哪个快照分叉 |
| `parent_fork_timestamp` | `"2026-04-05T..."` | 分叉时间 |
| `companion_original_path` | `"/Users/.../notes.txt"` | 外来文件原始路径 |
| `companion_original_format` | `"txt"` / `"md"` | 外来文件格式 |

### 2.3 文件大小估算

| 场景 | 文档大小 | 快照数 | .jnt 文件大小 |
|------|---------|--------|--------------|
| 典型笔记 | 10 KB | 100 | ~100-200 KB |
| 长文草稿 | 50 KB | 100 | ~300-500 KB |
| 配置文件 | 2 KB | 50 | ~30-50 KB |

### 2.4 Quick Look 与 Spotlight 集成

- **Quick Look 扩展:** 打开 SQLite → `SELECT content FROM document WHERE id = 1` → 渲染为纯文本
- **Spotlight Importer:** 同样查询 content，提供全文索引
- **UTI 声明:** `com.jettymarquis.jettynotepad.jnt`，conforming to `public.data`, `public.content`

### 2.5 优雅降级

| 损坏场景 | 恢复策略 |
|---------|---------|
| SQLite 完全无法打开 | 尝试 SQLite 恢复模式；失败则报错 |
| document 表完好，其余损坏 | 打开文档内容，无历史，生成新 UUID |
| snapshots 表部分损坏 | 显示可用快照，标记损坏的为不可用 |
| metadata 表损坏 | 重新生成元数据，丢失来源链 |
| children 表损坏 | 丢失子文件追踪，不影响文档编辑 |

---

## 3. 核心模块架构

```
┌─────────────────────────────────────────────────────────────┐
│                     App Shell (AppKit)                       │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ WindowManager │  │  TabManager  │  │ SessionRestorer  │  │
│  │  NSTabbedWin  │  │  标签状态颜色 │  │ NSWindowRestore  │  │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘  │
│         │                  │                    │             │
│  ┌──────▼──────────────────▼────────────────────▼──────────┐ │
│  │              DocumentController                         │ │
│  │  NSDocumentController — 文件打开/新建/最近文件           │ │
│  └──────────────────────┬──────────────────────────────────┘ │
│                          │                                    │
│  ┌───────────────────────▼────────────────────────────────┐  │
│  │               JNTDocument (NSDocument)                  │  │
│  │                                                         │  │
│  │  ┌─────────────┐ ┌────────────┐ ┌───────────────────┐  │  │
│  │  │ EditorEngine│ │SnapshotMgr │ │ SourceChainMgr    │  │  │
│  │  │ NSTextView  │ │ diff-match │ │ 代际/分支追溯      │  │  │
│  │  │ +TextStorage│ │ -patch     │ │                    │  │  │
│  │  └──────┬──────┘ └─────┬──────┘ └────────┬──────────┘  │  │
│  │         │               │                 │             │  │
│  │  ┌──────▼───────────────▼─────────────────▼──────────┐  │  │
│  │  │            JNTFileStore (SQLite)                    │  │  │
│  │  │  读写 .jnt 文件 / 原子事务 / WAL 模式              │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  │                                                         │  │
│  │  ┌──────────────────┐  ┌──────────────────────────┐    │  │
│  │  │  AutoSaveManager │  │  ExternalFileManager     │    │  │
│  │  │  定时/失焦/空闲  │  │  双格式保存 / companion  │    │  │
│  │  └──────────────────┘  └──────────────────────────┘    │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                  HistoryFolderManager                   │  │
│  │  ~/Documents/JettyNote/ — registry / companions /      │  │
│  │  orphans / cleanup                                     │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────┐  ┌─────────────────────────────────┐  │
│  │  MarkdownParser  │  │  HistoryViewController          │  │
│  │  语法→属性字符串 │  │  时间线/分支树/快照浏览/diff    │  │
│  └──────────────────┘  └─────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 3.1 模块职责

| 模块 | 职责 | 关键类/协议 |
|------|------|------------|
| **WindowManager** | 窗口/标签管理、拖出标签 | `NSWindowController`, `NSTabbedWindow` |
| **TabManager** | 标签状态颜色（黄/绿/蓝）、标签排序 | `NSTabViewItem` 子类 |
| **SessionRestorer** | 启动时恢复上次会话 | `NSWindowRestoration` 协议 |
| **DocumentController** | 文件打开/新建/最近文件/文件类型注册 | `NSDocumentController` 子类 |
| **JNTDocument** | 核心文档模型，协调各子模块 | `NSDocument` 子类 |
| **EditorEngine** | 文本编辑、Undo/Redo、Markdown 渲染 | `NSTextView` + `JNTTextStorage` |
| **SnapshotManager** | 快照创建/聚合/淘汰/重建 | diff-match-patch 引擎 |
| **SourceChainManager** | 父子关系管理、分支检测、mid-tree 提示 | 读写 metadata/children 表 |
| **JNTFileStore** | SQLite 读写层、原子事务、降级恢复 | FMDB 或 swift-sqlite |
| **AutoSaveManager** | 定时保存、失焦保存、空闲检测 | `NSDocument` autosave + 自定义 |
| **ExternalFileManager** | 外来文件双格式保存、companion 管理 | 协调 JNTFileStore + 原格式写入 |
| **HistoryFolderManager** | JettyNote 文件夹结构、registry、清理 | 文件系统操作 |
| **MarkdownParser** | Markdown 语法解析→`NSAttributedString` | `NSTextStorage` 子类 |
| **HistoryViewController** | 历史浏览 UI、分支树可视化、diff 视图 | 独立面板 |

### 3.2 模块依赖关系

```
WindowManager ──→ TabManager
       │
       ▼
DocumentController ──→ JNTDocument
                           │
                    ┌──────┼──────────────────────┐
                    ▼      ▼                       ▼
              EditorEngine SnapshotManager    SourceChainManager
                    │      │                       │
                    └──────┼───────────────────────┘
                           ▼
                      JNTFileStore ←── AutoSaveManager
                           │
                           ▼
                  ExternalFileManager ──→ HistoryFolderManager
```

---

## 4. Save / Save As 状态机

### 4.1 Save (Cmd+S / Auto-save)

```
用户触发 Save
    │
    ▼
当前文件是 .jnt？────No────→ 保存原格式到原路径
    │                              │
   Yes                     更新/创建 companion .jnt
    │                              │
    ▼                              ▼
内容有变化？────No────→ 仅更新 modified_at → 完成
    │
   Yes
    │
    ▼
计算反向 diff（当前内容 → 上次保存内容）
    │
    ▼
创建快照记录（INSERT INTO snapshots）
    │
    ▼
快照数 > 100？──Yes──→ 智能淘汰（见 4.3）
    │
    ▼
更新 document 表（content, modified_at, cursor, scroll）
    │
    ▼
SQLite COMMIT（原子性保证）
    │
    ▼
更新标签颜色：黄→绿
```

**不变量:** Save 不改 UUID、不改路径、不建立新代际关系、不清空 Undo/Redo。

### 4.2 Save As

```
用户触发 Save As → 选择新路径+格式
    │
    ▼
在父文件中：创建 forkPoint 快照
    │
    ▼
生成新 UUID
    │
    ▼
创建新 .jnt 文件：
  - document 表: 当前内容
  - snapshots 表: 仅 1 条 forkPoint（空 diff，seq=0）
  - metadata: 新 UUID, parent_uuid, parent_path, parent_snapshot_seq
  - children: 空
    │
    ▼
更新父文件 children 表：INSERT 子文件记录
    │
    ▼
目标格式非 .jnt？──Yes──→ 同时写入目标格式文件
    │
    ▼
SQLite COMMIT 两个文件（先父后子）
    │
    ▼
切换活跃文档到新文件
    │
    ▼
更新 registry.json
```

### 4.3 快照智能淘汰

当快照数达到 100 时，按优先级淘汰：

1. **合并相邻自动快照:** 2 分钟内的相邻 `autoSave` 合并（compose diff）
2. **稀释旧自动快照:** >7 天的 `autoSave` 稀释至每小时一个
3. **稀释更旧快照:** >30 天的 `autoSave` 稀释至每天一个
4. **永不淘汰:** `manualSave`、`forkPoint`（除非占比超 80%，此时对 `sessionBoundary` 做时间稀释）

淘汰时合并 diff：删除快照 N，将其 diff 与快照 N+1 的 diff 合成，保持链完整。

> **MVP 实现现状（2026，三轮红队评审后）：** 上述"智能淘汰 + 类型保护"**未实现**。
> MVP 阶段淘汰为纯 FIFO（`limit_snapshots` 触发器按 `seq` 删最旧，不区分
> `snapshot_type`），`manualSave`/`forkPoint` 超过 100 条快照后**同样会被淘汰**。
> 原因：反向 diff 链是相邻快照间的增量链，按类型跳过删除会在链中间打洞——被
> "保护"的快照反而无法重建（`patchApply` 会因上下文不匹配而报错）。真正的类型
> 保护必须先做本节描述的 diff 合并（删除快照 N 时把它的 diff 并入相邻快照），
> 这是一项实质性新功能，列为 Phase 2.5，不在 MVP 完整化范围内。

## 5. 分支与代际追溯系统

### 5.1 数据模型

```
                    ┌──────────────┐
                    │  初稿.jnt    │
                    │  UUID: AAA   │
                    │  children:   │
                    │   [BBB, CCC] │
                    └──┬────┬──────┘
                       │    │
            ┌──────────▼┐  ┌▼──────────┐
            │ 修订版.jnt │  │ 变体.jnt  │
            │ UUID: BBB  │  │ UUID: CCC │
            │ parent:AAA │  │ parent:AAA│
            │ fork@seq42 │  │ fork@seq67│
            │ children:  │  │ children: │
            │  [DDD]     │  │  []       │
            └──┬─────────┘  └───────────┘
               │
         ┌─────▼──────┐
         │ 终稿.jnt   │
         │ UUID: DDD  │
         │ parent:BBB │
         │ children:[]│
         └────────────┘
```

### 5.2 Mid-Tree 编辑检测

```swift
// 在 JNTDocument.makeWindowControllers() 或首次编辑时
func checkMidTreeEdit() {
    guard !children.isEmpty else { return }  // 非中间节点，无需提示
    guard !midTreeEditAcknowledged else { return }  // 本次会话已确认

    showNonModalAlert(
        title: "此文档有 \(children.count) 个后续版本",
        message: "继续在此编辑可能导致后续版本的历史引用不完整。建议另存为新版本。",
        primaryButton: "另存为新版本",     // → 触发 Save As 流程
        secondaryButton: "继续编辑"         // → 设置 midTreeEditAcknowledged = true
    )
}
```

- 每次编辑会话只提示一次
- 非模态（banner/sheet），不阻塞输入
- "另存为新版本"是主按钮样式

### 5.3 来源链断裂处理

| 场景 | 处理 |
|------|------|
| 父文件被移动 | registry 查找 UUID → 更新路径；找不到则标记 `unreachable` |
| 父文件被删除 | 来源链保留 UUID 信息，UI 显示"原始文件不可用" |
| 子文件被移动 | 同上，下次打开子文件时更新父文件的 children 路径 |
| 子文件被删除 | 父文件的 children 记录保留，UI 标记为"不可用" |

**原则:** UUID 是权威身份标识，file path 仅作提示。链断裂不影响文档编辑能力。

---

## 6. 历史文件夹结构

```
~/Documents/JettyNote/
├── registry.json              # UUID → 路径 索引
├── companions/                # 外来文件的 .jnt companion
│   ├── ab/                    # UUID 前 2 位分片
│   │   └── ab3f9c00-...jnt
│   └── cd/
│       └── cde412-...jnt
├── orphans/                   # 原始文件已删除的 companion
│   └── <UUID>.jnt
└── settings.json              # 保留策略配置
```

### 6.1 清理策略

| 维度 | 默认值 | 说明 |
|------|--------|------|
| 按容量 | 无限制 | 用户可设上限（如 500MB） |
| 按数量 | 无限制 | 用户可设上限（如 1000 个文件） |
| 单文件历史 | 手动 | 用户可清除某个文件的全部快照 |
| 一键清空 | 手动 | 清除全部历史和 companion 文件 |
| 孤儿检测 | 每周 | 原始文件不存在的 companion 移入 orphans/ |
| 孤儿清理 | 90 天 | orphans/ 中超过 90 天的自动删除 |

---

## 7. 标签状态颜色系统

| 颜色 | 状态 | 触发条件 |
|------|------|---------|
| 浅黄 | 有未保存修改 | 内容与上次保存不一致 |
| 浅绿 | 已保存 | 内容与上次保存一致 |
| 浅蓝 | 外来文件 | 打开非 .jnt 文件（尚未完全纳入历史体系） |

状态转换：
- 新建/打开 .jnt → 绿
- 打开外来文件 → 蓝
- 任何编辑 → 黄
- 保存成功 → 绿（外来文件首次保存后从蓝变绿，因为已建立 companion）

---

## 8. 自动保存触发矩阵

| 触发器 | 快照类型 | 条件 |
|--------|---------|------|
| 定时（默认 1 分钟） | `autoSave` | 内容有变化 |
| 失焦 | `autoSave` | 内容有变化 |
| 空闲 > 5 秒（编辑爆发后） | `autoSave` | 内容有变化 |
| 关闭标签 | `sessionBoundary` | 始终记录 |
| 启动恢复会话 | `sessionBoundary` | 始终记录 |
| Cmd+S | `manualSave` | 始终记录 |
| Save As | `forkPoint` | 始终记录 |

---

## 9. 会话恢复机制

利用 `NSWindowRestoration` + SQLite WAL：

1. **正常退出:** 所有标签的文档路径、光标位置、滚动位置保存到 `UserDefaults` 或 restoration state
2. **异常崩溃:** SQLite WAL 模式确保最后一次写入不丢失；下次启动时 SQLite 自动回放 WAL
3. **恢复流程:** 启动 → 读取 restoration state → 依次打开文档 → 恢复光标和滚动位置 → 检查 WAL 是否有未提交的数据

---

## 10. 外来文件双格式保存

```
用户打开 /Desktop/notes.txt
    │
    ▼
标签颜色 = 蓝
    │
    ▼
用户编辑 → 标签颜色 = 黄
    │
    ▼
用户 Cmd+S
    │
    ├──→ 写入 /Desktop/notes.txt（原格式）
    │
    └──→ 写入 ~/Documents/JettyNote/companions/<uuid-prefix>/<uuid>.jnt
         - metadata.companion_original_path = "/Desktop/notes.txt"
         - metadata.companion_original_format = "txt"
    │
    ▼
标签颜色 = 绿（已纳入历史体系）
更新 registry.json
```

---

## 11. 技术依赖

| 依赖 | 用途 | 来源 |
|------|------|------|
| SQLite | .jnt 文件存储 | macOS 系统自带 |
| diff-match-patch | 快照 diff 算法 | Swift 社区移植 / 清净室实现 |
| NSTextView / TextKit 1 | 编辑器引擎 | AppKit |
| NSDocument | 文档生命周期管理 | AppKit |
| NSTabbedWindow | 标签窗口管理 | AppKit |
| NSSpellChecker | 拼写检查 | AppKit |
| Quick Look Extension | .jnt 预览 | QL Framework |
| Spotlight Importer | .jnt 全文索引 | Core Spotlight |

---

## 12. v1.0 实现阶段建议

### Phase 1: 基础编辑器 (MVP)
- AppKit 窗口 + 标签 + NSTextView
- 新建 / 打开 / 保存 .jnt（SQLite 读写）
- 100 步 Undo/Redo
- 自动保存（定时 + 失焦）
- 会话恢复

### Phase 2: 历史与追溯
- 快照系统（diff-match-patch）
- 历史浏览界面（时间线 + diff 查看）
- Save As 代际关系
- 标签颜色状态

### Phase 3: 外来文件与分支
- 外来文件双格式保存
- 来源链管理
- 分支树可视化
- Mid-tree 编辑提示
- 历史文件夹管理与清理

### Phase 4: 增强层
- Markdown 内联渲染
- 拼写检查 + 自动更正
- Quick Look 扩展
- Spotlight Importer
- 导出为 .txt / .md

### Phase 5: AI 扩展（未来）
- Rewrite / Summarize / Write
- Core ML + Apple Neural Engine
- 本地模型接口预留
