# 🌌 StarIsland

> **一个完全本地优先的个人时间档案系统。**
>
> 每一条记录都是一个瞬间的「证据」—— time slice。
>
> 纯离线 · 隐私优先 · 无广告 · 无社交 · 无 AI

---

## 特性

| 功能 | 说明 |
|---|---|
| 📜 **Timeline** | 时间线流，每条记录附带时间、地点、心情、照片 |
| 🗂️ **Archive** | 年 / 月 / 日三级归档，贡献热力图 |
| 🗺️ **Map** | 记录的地理足迹，按位置聚合 |
| 🔍 **Search** | 全文搜索，支持地点和心情 |
| 📊 **Stats** | 年度统计，情绪分布，位置排名 |
| 💾 **Backup** | ZIP 格式导出/导入，支持自动每日备份 |
| 🗑️ **Recycle Bin** | 30 天回收站，可恢复/永久删除 |
| 🌓 **Theme** | 浅色 / 深色 / 跟随系统 |
| 🎨 **App Icon** | 默认 / Deep Space / White 三款图标 |

## 设计原则

- **Apple 原生** — 纯 SwiftUI + SwiftData，无自定义渲染
- **零第三方依赖** — 全部 Apple 系统框架，无 CocoaPods / SPM 第三方包
- **单文件单职责** — 每个 Swift 文件一个类型，View < 400 行
- **隐私优先** — 所有数据存储在本地，不上传云端
- **iPhone 优先** — 针对 iPhone 12 Pro 优化，保持 60fps

## 技术栈

- **语言：** Swift 5.9+
- **UI 框架：** SwiftUI (iOS 17+)
- **持久化：** SwiftData
- **地图：** MapKit
- **定位：** CoreLocation
- **后台任务：** BGTaskScheduler
- **压缩：** Compression (系统框架)
- **最低部署目标：** iOS 17.0
- **目标设备：** iPhone (仅竖屏)

## 安装

### AltStore / SideStore

1. 从 [Releases](https://github.com/your-org/StarIsland/releases) 下载 `.ipa`
2. 通过 AltStore 或 SideStore 侧载安装

### 手动构建

```bash
# 1. 安装 XcodeGen
brew install xcodegen

# 2. 生成 Xcode 项目
xcodegen generate

# 3. 用 Xcode 打开 StarIsland.xcodeproj
open StarIsland.xcodeproj

# 4. 选择 iPhone 12 Pro 模拟器或真机运行
```

## 分支策略

```
main        ← 正式发布
release/*   ← RC / 候选版本
develop     ← 日常开发
```

## 项目结构

```
StarIsland/
├── StarIslandApp.swift          # App 入口
├── Info.plist                   # 应用配置
├── Assets.xcassets/             # 资源目录（图标、颜色）
├── Models/                      # SwiftData 模型
│   ├── Record.swift
│   ├── Mood.swift
│   ├── MemoryLocation.swift
│   └── BackupMetadata.swift
├── Views/                       # 视图
│   ├── ContentView.swift
│   ├── TimelineView.swift
│   ├── AddRecordView.swift
│   ├── RecordDetailView.swift
│   ├── SearchView.swift
│   ├── ArchiveView.swift
│   ├── ArchiveDayDetailView.swift
│   ├── StatsView.swift
│   ├── MapView.swift
│   ├── LocationDetailView.swift
│   ├── FootprintView.swift
│   ├── SettingsView.swift
│   ├── RecycleBinView.swift
│   ├── DataHealthView.swift
│   └── DebugView.swift          (DEBUG only)
├── Components/                  # 可复用组件
│   ├── TimelineCell.swift
│   ├── DaySectionHeader.swift
│   ├── ImageGridView.swift
│   ├── PhotoViewer.swift
│   ├── HomeHeaderView.swift
│   ├── SearchBarView.swift
│   ├── EmptyStateView.swift
│   ├── MoodSelectorView.swift
│   ├── ImagePicker.swift
│   ├── ContributionGridView.swift
│   ├── YearPickerView.swift
│   └── StatsCardView.swift
├── Services/                    # 服务层
│   ├── CalendarService.swift
│   ├── StatsService.swift
│   ├── MapService.swift
│   ├── SyncService.swift
│   ├── LocationService.swift
│   ├── ImageStorageService.swift
│   ├── ImageCacheService.swift
│   ├── SearchService.swift
│   ├── BackupService.swift
│   ├── AutoBackupManager.swift
│   └── IntegrityService.swift
├── Theme/
│   └── AppTheme.swift           # 设计 Token
├── Utils/
│   ├── DateFormatterManager.swift
│   ├── SettingsStorage.swift
│   └── ZipHelper.swift
├── ViewModels/
│   └── RecordViewModel.swift
└── Extensions/
    └── Date+Extension.swift
```

## 未来方向

| 功能 | 优先级 | 计划 |
|---|---|---|
| Timeline 筛选 | 🟢 高 | v1.1 |
| iCloud 纯备份 | 🟢 高 | v1.2 |
| Widget | 🟡 中 | v1.x |
| iPad 自适应布局 | 🟡 中 | v1.x |
| Map 足迹聚类 | 🟡 中 | v1.x |
| JSON/CSV 导出 | 🔵 低 | v1.x |
| 标签管理 | 🔵 低 | v1.x |
| Memory AI | ⚫ 最低 | v2.0 |

## 许可

MIT License © 2026 StarIsland

---

*在星空岛上，记录属于这一秒的故事。*
