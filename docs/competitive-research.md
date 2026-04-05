# JettyNotepad 竞品研究报告

> 研究日期：2026-04-05

## 核心结论

**没有任何现有项目同时具备**：轻量记事本 UX + 内嵌版本历史 + 分支追溯 + 文档代际链。JNPT 占据未被覆盖的产品空间。

---

## 竞品分析

### 1. Notepads (0x7c13/Notepads)
- **Stars**: ~10K | **Tech**: C# / UWP (Windows)
- 最接近的轻量记事本美学，会话恢复做得极好
- 启动快、~3MB 体积、内置 diff viewer 和 Markdown 预览
- **缺失**: 无版本历史、无分支、无自定义格式、仅 Windows

### 2. Joplin (laurent22/joplin)
- **Stars**: ~54.2K | **Tech**: TypeScript / Electron
- 每 10 分钟自动快照、90 天默认保留、跨设备同步
- 恢复创建副本（非破坏性）
- **借鉴**: 无感自动版本化 + 可配置保留策略
- **缺失**: 线性历史无分支、重型应用（~200MB）、无代际关系

### 3. GitDoc (lostintangent/gitdoc)
- **Stars**: 326 | **Tech**: TypeScript / VS Code Extension
- 每 30 秒自动 commit、squash 合并多个版本、glob 模式选择性版本化
- **借鉴**: 核心理念最接近 — 让版本控制像 Google Docs 一样无感
- **缺失**: 依赖 VS Code + Git、非独立应用、无代际追溯

### 4. Obsidian Version Control Plugin (micmejia/obsidian-Version-Control)
- **Stars**: 新项目 | **Tech**: TypeScript / Obsidian Plugin
- "Create Deviations" = 从旧版本分支出新笔记（最接近 JNPT 分支概念）
- 手动命名快照、diff 对比、卡片/列表视图
- **借鉴**: Deviations 交互模式、命名快照、导出为 JSON
- **缺失**: 依赖 Obsidian、无父子关系追踪、无自动保存

### 5. Obsidian Edit History (antoniotejada/obsidian-edit-history)
- **Stars**: 134 | **Tech**: JavaScript / Obsidian Plugin
- diff-match-patch 压缩存储、最新版完整 + 向前 diff 链
- 日历/时间线视图、多种 diff 可视化模式
- **借鉴**: 存储架构（最省空间）、日历浏览 UX
- **缺失**: 依赖 Obsidian、无分支、历史与文档分离

### 6. CotEditor (coteditor/CotEditor)
- **Stars**: ~7.8K | **Tech**: Swift / AppKit (macOS 原生)
- macOS 原生编辑器标杆、继承 NSDocument 内置 Versions
- 17 种语言本地化、App Store 分发
- **借鉴**: macOS 原生开发规范、NSDocument 架构、沙箱/Hardened Runtime
- **缺失**: 无自定义版本历史、无分支、无自定义格式

### 7. text-versioncontrol (kindone/text-versioncontrol)
- **Stars**: 14 | **Tech**: TypeScript / npm 库
- 命名分支 + checkpoint + merge/rebase、Quill Delta JSON 格式
- **借鉴**: 最完整的文档级 Git 语义实现、Delta 格式紧凑
- **缺失**: 仅是库、无 UI、无持久化、面向协作而非单用户

### 8. AFFiNE (toeverything/AFFiNE)
- **Stars**: ~67K | **Tech**: TypeScript + Rust / Electron
- CRDT 本地优先架构（y-octo），天然保留所有变更
- **借鉴**: 市场验证（67K stars = 巨大需求）、CRDT 时间戳教训
- **缺失**: 极重型应用、版本历史尚未实现、无代际关系

### 9. NotepadEx (Air16/NotepadEx)
- **Stars**: 8 | **Tech**: C# / WinForms (Windows)
- 词边界 undo 粒度、idle 2 秒自动备份、会话恢复
- **借鉴**: 词边界触发版本 — 平衡粒度和噪音的优秀方案
- **缺失**: 历史仅在内存中（关闭即丢失）、无分支、仅 Windows

### 10. Zettlr (Zettlr/Zettlr)
- **Stars**: ~12.8K | **Tech**: TypeScript / Vue / Electron
- Textbundle 格式（内容 + 元数据打包）、30+ 导出格式
- **借鉴**: Textbundle 是 .jnt 设计的先例、CodeMirror 6 编辑器引擎
- **缺失**: 无版本历史、无分支、重型 Electron 应用

---

## 竞品能力矩阵

| 能力 | Notepads | Joplin | GitDoc | Obs-VC | Obs-EH | CotEditor | text-vc | AFFiNE | NotepadEx | Zettlr | **JNPT** |
|------|----------|--------|--------|--------|--------|-----------|---------|--------|-----------|--------|----------|
| 轻量记事本 UX | Yes | No | No | No | No | Yes | N/A | No | Yes | No | **Yes** |
| macOS 原生 | No | No | No | No | No | Yes | N/A | No | No | No | **Yes** |
| 自动保存/会话恢复 | Yes | Yes | Yes | No | Yes | Yes | N/A | Yes | Yes | Yes | **Yes** |
| 版本历史快照 | No | Yes | Yes | Yes | Yes | 有限 | Yes | 部分 | No | No | **Yes** |
| Git 式分支 | No | No | No | 部分 | No | No | Yes | No | No | No | **Yes** |
| 文档代际链 | No | No | No | No | No | No | No | No | No | No | **Yes** |
| 自定义格式内嵌历史 | No | No | No | No | No | No | No | No | No | No | **Yes** |
| 双格式保存 | No | No | No | No | No | No | No | No | No | No | **Yes** |

---

## 六大借鉴要点

1. **存储格式** — Obsidian Edit History 的 diff-match-patch + 压缩方案最优
2. **macOS 原生** — CotEditor 的 NSDocument 架构 + 系统 Versions 集成
3. **分支 UX** — Obsidian VC 的 "Deviations" 交互模式
4. **无感版本化** — Joplin 定时快照 + GitDoc 语义聚合
5. **快照粒度** — NotepadEx 词边界方案 + 时间间隔混合策略
6. **市场验证** — AFFiNE/Joplin 证明本地优先版本工具有巨大需求

## JNPT 独占优势

- 自定义格式内嵌历史（.jnt）
- 文档代际链（父子关系追踪）
- 双格式保存（原格式 + .jnt）
- 来源链元数据
- "另存为 = 新分支"的产品隐喻
