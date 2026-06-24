# Changelog

All notable changes to StarIsland will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0-rc] — 2026-06-24

### Added

#### Phase 4 — Sync & Backup System

- **Sync 架构预留**
  - `SyncStatus` 枚举 (idle / syncing / success / failed)
  - `CloudSyncService` 占位实现
  - Record 模型新增 `syncId` 和 `syncVersion` 字段

- **备份系统**
  - `BackupService` — ZIP 格式导出/导入
  - ZIP 实现：纯 Swift（CRC-32 lookup table + Compression 框架 deflate）
  - 备份格式：`StarIslandBackup_yyyyMMdd.zip` → `metadata.json` + `records.json` + `images/`
  - 导入去重：基于 `syncId` 的幂等合并
  - `AutoBackupManager` — BGTaskScheduler 每日自动备份
  - 备份保留策略：可配置保留数量（默认 30 个）

- **设置页**
  - Apple Settings 风格 `Form` 布局
  - 数据备份：导出/导入/自动备份开关/保留数量
  - 同步状态显示
  - 关于页面：版本号、记录/照片统计
  - `SettingsStorage` — 统一 `@AppStorage` 管理

- **工具**
  - `ZipHelper` — 纯 Swift ZIP 创建/解压
  - `BackupMetadata` — 备份元数据模型
  - `BackupDocument` — FileDocument 封装用于 `.fileExporter`

#### Phase 4.5 — v1.0 RC

- **回收站**
  - `RecycleBinView` — 滑动恢复/永久删除
  - 批量编辑模式（多选 + 批量恢复/删除）
  - 30 天自动清理提示
  - 确认警报防止误操作

- **主题系统**
  - `ThemeMode` 枚举：system / light / dark
  - `preferredColorScheme` 动态切换
  - 持久化到 `@AppStorage`

- **App 图标**
  - 三款图标：默认（Default）/ Deep Space / White
  - 通过 `UIApplication.setAlternateIconName` 切换
  - 模拟器安全保护

- **数据完整性**
  - `IntegrityService` — 后台 3 项并行检查
  - 孤立图片自动清理
  - 缺失图片检测
  - 重复 syncId 自动修复（保留最高版本）
  - `DataHealthView` — 健康状态面板

- **诊断工具**
  - `DebugView` — 仅在 DEBUG 配置下编译
  - 指标：记录数/照片数/缓存、数据库大小、内存占用、启动时间

- **动画统一**
  - `AppTheme.AnimationDuration` — spring / hero / insert / delete
  - 统一使用 `.interactiveSpring(response:dampingFraction:)`
  - 替代散落的硬编码动画值

- **空状态统一**
  - 🌌 `StarIsland` + "记录属于这一秒的故事。"
  - 统一应用于 Timeline / Search / RecycleBin

### Changed

- `EmptyStateView` 文案："记录下属于这一秒的故事。" → "记录属于这一秒的故事。"
- `SearchView` 空状态：🔍 → 🌌
- `ContentView` 底部 Tab：新增 设置 (gearshape.fill) 为第 6 个 Tab
- `SettingsView`：全面重写为 v1.0 RC 布局
- `ImageCacheService`：手动 cache count 跟踪（NSLock 线程安全）
- `StarIslandApp.swift`：启动时运行 IntegrityService + AutoBackupManager.setup()

### Fixed

- 修复 SettingsView 缺少 `.fileExporter` 导致导出崩溃的问题
- 修复 ZipHelper 使用 COMPRESSION_ZLIB（应为 COMPRESSION_DEFLATE — ZIP deflate 是 raw deflate）
- 修复 `import Compression` 位于文件底部的问题
- 修复 AutoBackupManager 后台任务需要独立 ModelContainer
- 修复 ImageCacheService.cacheCount 使用 NSCache.countLimit（错误 — 该属性是上限而非实际计数）
- 修复 `OSAllocatedUnfairLock` 需要 import os，改用 NSLock
- 修复 SettingsView 缺少 `import UniformTypeIdentifiers`
- 修复 DebugView 缺少 `import MachO`（task_info 需要）
- 修复 StatRow 为 internal 以支持 DataHealthView 复用

### Security

- 所有数据纯本地存储，无网络请求
- 备份文件无加密（纯本地文件系统保护）

---

## [0.9] — 2026-06-xx

### Added

- SyncService 协议 + CloudSyncService 桩
- Record sync 字段
- 备份导出/导入
- 自动备份
- Settings 设置页
- SettingsStorage 统一管理

---

## [0.5] — 2026-06-xx

### Added

- Archive 年/月/日三级归档
- Map 地理足迹
- Search 全文搜索
- Stats 统计面板
- Footprint 视图
- 照片拍摄/选择/持久化
- AppTheme 设计 Token

### Changed

- Timeline 自定义 UI（圆点 + 连接线）
- TimelineCell 组件化

---

## [0.1] — 2026-06-xx

### Added

- SwiftUI + SwiftData 基础框架
- Timeline 时间线流
- 记录 CRUD
- 心情选择
- RecordViewModel 桩

---

[1.0.0-rc]: https://github.com/your-org/StarIsland/releases/tag/v1.0.0-rc
[0.9]: https://github.com/your-org/StarIsland/releases/tag/v0.9
[0.5]: https://github.com/your-org/StarIsland/releases/tag/v0.5
[0.1]: https://github.com/your-org/StarIsland/releases/tag/v0.1
