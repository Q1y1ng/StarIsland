# StarIsland 开发日志

> 一款纯离线、隐私优先的个人时间记录系统。
> 核心概念：**Time Slice**——每一条记录都是一个瞬间的「证据」，而非日记内容。
>
> 技术栈：SwiftUI + SwiftData (iOS 17+)
> 架构：MVVM + 单文件单职责
> 设计原则：Apple 系统原生主题，无自定义颜色/字体，无第三方库

---

## Phase 1 — 基础框架

**目标：** 搭建 App 骨架，实现最基本的时间流记录 CRUD。

### 新增文件

| 文件 | 职责 |
|---|---|
| `StarIslandApp.swift` | App 入口，挂载 `modelContainer(for: Record.self)` |
| `Models/Record.swift` | SwiftData 模型：`id`, `timestamp`, `text`, `mood(String?)`, `locationName(String?)` |
| `Views/TimelineView.swift` | 主界面：`NavigationStack` + `@Query` 倒序加载，`NavigationLink` → Detail |
| `Views/AddRecordView.swift` | 模态 sheet：`TextEditor` + 8 个 emoji mood + 保存/取消 |
| `Views/RecordDetailView.swift` | 详情页（基本占位） |
| `ViewModels/RecordViewModel.swift` | 空 ViewModel 桩，预留搜索/导出 |
| `Services/SyncService.swift` | `SyncService` 协议 + `LocalSyncService` 空实现 |

### 关键设计决策

- 使用 `ScrollView` + `LazyVStack` 而非 `List`（后期转换为自定义时间流布局）
- SwiftData 直接写入，不经过 ViewModel（Phase 1 保持简单）
- 强调色仅允许 `+` 按钮

### 项目结构

```
StarIsland/
├── StarIslandApp.swift
├── Models/
│   └── Record.swift
├── Views/
│   ├── TimelineView.swift
│   ├── AddRecordView.swift
│   └── RecordDetailView.swift
├── ViewModels/
│   └── RecordViewModel.swift
└── Services/
    └── SyncService.swift
```

---

## Phase 1.5 — 架构重构

**目标：** 为长期可维护性重构目录结构，自定义 Timeline UI。

### 变更概览

- **目录重组：** 新增 `Components/`, `Theme/`, `Utils/`, `Extensions/`
- **自定义 Timeline：** 抛弃 List 卡片样式，改为垂直时间线（圆点 + 连接线）
- **中央化日期格式化：** `DateFormatterManager` 单例 + `Date+Extension`
- **Record 模型扩展：** 预留 7 个可选字段

### 新增文件

| 文件 | 职责 |
|---|---|
| `Components/TimelineCell.swift` | 时间线单行：左侧指示器（圆点+线）+ 右侧内容（时间/地点/mood/正文/图片占位） |
| `Components/EmptyStateView.swift` | 空状态：🌌 + "StarIsland" + "记录下属于这一秒的故事。" |
| `Theme/AppTheme.swift` | 设计 Token 中心：`Spacing`, `CornerRadius`, `Timeline`, `AnimationDuration` |
| `Utils/DateFormatterManager.swift` | 单例：`fullDateTime`, `timeOnly`, `dayTitle`, `weekday` 四个懒加载 Formatter |
| `Extensions/Date+Extension.swift` | Date 计算属性桥接 FormatterManager |

### 修改文件

| 文件 | 变更 |
|---|---|
| `Models/Record.swift` | 新增 `createdAt`, `updatedAt`, `imagePaths`, `latitude`, `longitude`, `weather`, `tags` |
| `Views/TimelineView.swift` | 切换为 `ScrollView` + `LazyVStack` + `TimelineCell` |
| `Views/AddRecordView.swift` | 集成 `@FocusState`，自动弹出键盘 |
| `Views/RecordDetailView.swift` | 完整布局：日期大标题 + 元数据 + 正文 + 图片预留区 |
| `Services/LocationService.swift` | 新增 `currentLocationName(completion:)` 桩 |

### 时间线视觉设计

```
●          23:57:13  📍家  😊
│
│          日落很美，天空从橙色渐变成紫色。
│
│          [图片占位]

●          12:43:08  📍学校  😐
```

### 项目结构

```
StarIsland/
├── Models/        → Record.swift
├── Views/         → TimelineView, AddRecordView, RecordDetailView
├── Components/    → TimelineCell, EmptyStateView  ← NEW
├── Theme/         → AppTheme                       ← NEW
├── Utils/         → DateFormatterManager           ← NEW
├── Extensions/    → Date+Extension                 ← NEW
├── Services/      → SyncService, LocationService
└── ViewModels/    → RecordViewModel
```

---

## Phase 2 — Capture System

**目标：** 打造 App 核心——3 秒快速记录系统。图片、Mood 枚举、定位、Quick Capture、日期分组。

### 新增文件

| 文件 | 职责 |
|---|---|
| `Models/Mood.swift` | `Mood` 枚举：`.happy/.neutral/.sad/.tired/.excited`，提供 `emoji`/`title`/`symbol`/`color` |
| `Components/ImageGridView.swift` | 自适应图片网格（1 大/2 并列/3 上1下2/4 2×2/5-9 自动3列），点击进入 PhotoViewer |
| `Components/PhotoViewer.swift` | 全屏图片浏览器：`TabView` 分页滑动 + 捏合缩放 |
| `Components/MoodSelectorView.swift` | 横向 Mood 选择器：8 个 emoji 按钮，`interactiveSpring` 动画 |
| `Components/DaySectionHeader.swift` | 日期分组头部：悬浮日期 + 时间线延续 + section 分割线 |
| `Components/ImagePicker.swift` | `CameraPicker` (UIImagePickerController) + `ImagePickerView` (PhotosPicker) |
| `Services/ImageStorageService.swift` | 图片磁盘管理：`Application Support/images/`，UUID 文件名，save/url/delete |

### 修改文件

| 文件 | 变更 |
|---|---|
| `Models/Record.swift` | `mood: String?` → `Mood?` **Breaking Change** |
| `Views/TimelineView.swift` | 日期分组：`groupedRecords` + `DaySectionHeader` |
| `Views/AddRecordView.swift` | Quick Capture 自动聚焦 + 相机/相册按钮 + `MoodSelectorView` + 定位异步写入 |
| `Views/RecordDetailView.swift` | Mood 显示改为 emoji+title + `ImageGridView` 替代占位 |
| `Components/TimelineCell.swift` | Mood 改为 `mood.emoji` + `ImageGridView` 替代占位，最多预览 4 张 |
| `Theme/AppTheme.swift` | 新增 `photoSpacing`, `sectionSpacing`, `image` cornerRadius |
| `Services/LocationService.swift` | 正式实现：`CoreLocation` + `CLGeocoder` 反向地理编码，async/await |
| `StarIslandApp.swift` | `init` 中确保 images 目录存在 |

### Phase 2 关键指标

- **Quick Capture 目标：** 3 秒完成（打开→输入→保存→退出）
- **图片系统：** 拍照/相册多选，最大 9 张，UUID 文件名，不入库 UIImage
- **定位：** fire-and-forget，不阻塞保存
- **日期分组：** 按日历日分组，时间线连续不间断

### 新增 Info.plist 要求

| Key | 描述 |
|---|---|
| `NSCameraUsageDescription` | StarIsland 需要使用相机来记录瞬间。 |
| `NSPhotoLibraryUsageDescription` | StarIsland 需要访问相册来添加图片。 |
| `NSLocationWhenInUseUsageDescription` | StarIsland 使用位置来标记记录的地点。 |

---

## Phase 2.5 — 体验打磨

**目标：** 不新增复杂功能，专注体验、动画、搜索、删除保护。

### 新增文件

| 文件 | 职责 | 行数 |
|---|---|---|
| `Components/HomeHeaderView.swift` | 首页大标题："今天 / 2026年06月24日 星期三 / 3 条记录" | 59 |
| `Components/SearchBarView.swift` | 搜索框：放大镜 + 占位符 + 清除按钮 | 54 |
| `Views/SearchView.swift` | 搜索页面：`@Query` + `SearchService` 内存过滤，TimelineCell 结果 | 106 |
| `Services/SearchService.swift` | 搜索服务：AND 分词，文字/地点/Mood 三维匹配 | 60 |
| `Services/ImageCacheService.swift` | 图片缓存：`NSCache` (100张/50MB)，异步加载 | 67 |

### 修改文件

| 文件 | 变更 |
|---|---|
| `Models/Record.swift` | 新增 `isTrashed: Bool` + `trashedAt: Date?` |
| `Views/TimelineView.swift` | 1. `@Query` 过滤 `!isTrashed`；2. `HomeHeaderView` 替代导航大标题；3. Hero 动画 `@Namespace` + 全屏覆盖；4. 插入动画追踪；5. 搜索工具栏按钮 |
| `Views/RecordDetailView.swift` | 软删除：工具栏垃圾桶 + `.alert` 确认 → `isTrashed = true` → dismiss |
| `Components/TimelineCell.swift` | 新增 `isNew` 参数 → 插入动画（dot 扩散 + 内容淡入）；新增 hero 参数转发 |
| `Components/ImageGridView.swift` | 新增 `heroNamespace/heroFilename/onTapImage`；`matchedGeometryEffectIfAvailable`；接入 `ImageCacheService` |
| `Components/PhotoViewer.swift` | 新增 `namespace/heroFilename/onDismiss`；当前图片使用 `matchedGeometryEffect(isSource: false)` |
| `Theme/AppTheme.swift` | 新增 `AnimationDuration.insert/hero/delete`；`Search.barHeight`；`CornerRadius.searchBar`；`Spacing.headerSpacing` |

### Phase 2.5 关键特性

#### 首页 Header 重构
```
之前:       ┌─ 时间轴 ─┐
之后:       🔍               +
            │ 今天           │
            │ 2026年06月24日 │
            │ 3 条记录       │
```
- 移除 `navigationTitle`，`toolbarBackground(.hidden)`
- 大字体 Apple Journal 风格，跟随 ScrollView 自然滚动

#### Hero 图片动画
- `@Namespace` 从 TimelineView → TimelineCell → ImageGridView → PhotoViewer 贯穿
- `matchedGeometryEffect` 实现平滑放大/缩回
- 全屏覆盖隐藏导航栏和状态栏

#### 插入动画
- 仅 Quick Capture 返回后触发（追踪 `newRecordID`）
- 圆点 `scaleEffect(0.5→1)` + 内容 `opacity(0.6→1)` + `scaleEffect(0.97→1)`
- `interactiveSpring(response: 0.3, dampingFraction: 0.8)`

#### 搜索系统
```
用户输入: "晚霞 学校 😊"
→ 分词: ["晚霞", "学校", "😊"]
→ 匹配: text CONTAINS "晚霞" OR location CONTAINS "学校" OR mood.emoji == "😊"
→ 结果: TimelineCell 展示
```

#### 软删除
- `Record.isTrashed = true`, `Record.trashedAt = Date()`
- Timeline `@Query` 使用 `#Predicate { !$0.isTrashed }` 自动过滤
- Detail 页工具栏删除 + 确认弹窗
- 未来可扩展回收站恢复功能

---

## 项目现状

### 统计

| 指标 | Phase 1 | Phase 1.5 | Phase 2 | Phase 2.5 | 当前 |
|---|---|---|---|---|---|
| **Swift 文件数** | 6 | 13 | 20 | 25 | **25** |
| **总代码行数** | ~200 | ~800 | ~1850 | ~2315 | **2,315** |
| **Components** | 0 | 2 | 7 | 9 | **9** |
| **Services** | 1 | 2 | 4 | 6 | **6** |
| **Models** | 1 | 1 | 2 | 2 | **2** |

### 完整文件树（25 文件 / 2,315 行）

```
StarIsland/
├── StarIslandApp.swift                      (17行)
│
├── Models/
│   ├── Record.swift                         (77行)  — isTrashed/trashedAt
│   └── Mood.swift                           (59行)  — enum 5 cases
│
├── Views/
│   ├── TimelineView.swift                   (223行) — 日期分组 + Hero + @Namespace
│   ├── AddRecordView.swift                  (242行) — Quick Capture + 图片 + Mood
│   ├── RecordDetailView.swift               (161行) — 软删除
│   └── SearchView.swift                     (106行) — @Query + SearchService
│
├── Components/
│   ├── TimelineCell.swift                   (155行) — isNew 动画 + Hero 转发
│   ├── EmptyStateView.swift                 (34行)
│   ├── ImageGridView.swift                  (200行) — 7种布局 + Hero + Cache
│   ├── PhotoViewer.swift                    (180行) — 分页 + 缩放 + Hero
│   ├── ImagePicker.swift                    (88行)  — Camera + PhotosPicker
│   ├── MoodSelectorView.swift               (60行)
│   ├── DaySectionHeader.swift               (53行)
│   ├── HomeHeaderView.swift                 (59行)  — Journal 风格大标题
│   └── SearchBarView.swift                  (54行)
│
├── Theme/
│   └── AppTheme.swift                       (88行)  — 设计 Token
│
├── Utils/
│   └── DateFormatterManager.swift           (65行)  — 4 Formatters 单例
│
├── Extensions/
│   └── Date+Extension.swift                 (25行)  — 4 计算属性
│
├── Services/
│   ├── SyncService.swift                    (35行)  — 协议 + 空实现
│   ├── LocationService.swift                (105行) — CoreLocation async/await
│   ├── ImageStorageService.swift            (57行)  — 磁盘 I/O
│   ├── SearchService.swift                  (60行)  — 三维搜索
│   └── ImageCacheService.swift              (67行)  — NSCache 100张
│
└── ViewModels/
    └── RecordViewModel.swift                (45行)  — 遗留/批量操作预留
```

### 架构规则（持续强制）

- ✅ `ScrollView` + `LazyVStack`，禁止 `List`
- ✅ 无第三方库
- ✅ 无自定义颜色/字体（全部 Apple System）
- ✅ 仅 `+` 按钮可使用强调色
- ✅ 单文件单职责
- ✅ 无卡片阴影/渐变
- ✅ 日期格式化全部走 `DateFormatterManager`
- ✅ 图片异步加载，不阻塞主线程
- ✅ 禁止 Cloud / AI / Social / Maps

---

## Phase 3 — Archive System

**目标：** GitHub Contribution Graph 风格热力图，Tab 系统重构，Stats 统计页。

### 新增文件

| 文件 | 职责 | 行数 |
|---|---|---|
| `Services/CalendarService.swift` | 全年日期生成、记录数统计、连续天数计算 | ~120 |
| `Services/StatsService.swift` | 全量统计计算：记录数/图片数/连续/平均/最常 | ~100 |
| `Components/ContributionGridView.swift` | GitHub 风格热力图组件：横向周排列，4 级透明度 | ~150 |
| `Components/YearPickerView.swift` | 左右箭头年份切换，`interactiveSpring` 动画 | ~55 |
| `Components/StatsCardView.swift` | Apple Health 风格统计卡片 | ~60 |
| `Views/ArchiveView.swift` | 年视图页面：Header + YearPicker + ContributionGrid + Legend | ~200 |
| `Views/ArchiveDayDetailView.swift` | 某一天的记录列表 + "在时间线中查看" 按钮 | ~150 |
| `Views/StatsView.swift` | 统计页面：9 项卡片，Apple Health 风格 | ~130 |
| `Views/ContentView.swift` | 根 TabView，4 Tab 切换 + scrollToDate 跨 Tab 联动 | ~70 |

### 修改文件

| 文件 | 变更 |
|---|---|
| `StarIslandApp.swift` | `TimelineView()` → `ContentView()` |
| `Views/TimelineView.swift` | `ScrollViewReader` + `scrollToDate`/`selectedTab` 绑定；搜索按钮切 Tab；DaySectionHeader 高亮联动 |
| `Views/SearchView.swift` | 移除 `@Environment(\.dismiss)`，适配独立 Tab |
| `Components/DaySectionHeader.swift` | 新增 `isHighlighted: Bool` 参数（黄色脉冲背景） |
| `Theme/AppTheme.swift` | 新增 `Heatmap` 结构体（cellSize/cellSpacing）+ `statsCard` 圆角 |

### 关键架构决策

#### Tab 系统
```
TabView (4 tabs)
├── Timeline ←── Archive (scroll-to-date via ScrollViewReader)
├── Archive
├── Search
└── Stats
```

每个 Tab 拥有独立 `NavigationStack`。跨 Tab 通信通过 ContentView 的 `@State` 绑定传递。

#### Contribution Grid 热力图
```
Columns: 周 (横向, ~53 列)
Rows:    星期 (纵向, 一~日, 7 行)
Colour:  Color.primary.opacity()
  0条    →  0.05
  1~2条  →  0.15
  3~5条  →  0.30
  6条以上 →  0.55
```

#### 跨 Tab 滚动联动
1. Archive 点击日期 → 设置 `scrollToDate` + `selectedTab = .timeline`
2. TimelineView `onChange(of: scrollToDate)` → `ScrollViewReader.scrollTo(date)`
3. DaySectionHeader 短暂高亮（`isHighlighted` 2 秒脉冲）
4. `scrollToDate = nil` 消费事件

#### Stats 统计
- 使用 `StatsService.compute(context:)` 一次性计算
- `AppStats` 结构体：recordCount, photoCount, longestStreak, averagePerDay, topLocation, topMood
- 所有统计异步计算，不阻塞主线程

### Heatmap 颜色方案
```swift
case 0:     return .primary.opacity(0.05)
case 1, 2:  return .primary.opacity(0.15)
case 3...5: return .primary.opacity(0.30)
default:    return .primary.opacity(0.55)
```

---

## Phase 3.5 — Memory Map

**目标：** 通过 Apple Maps 地点聚合回顾人生轨迹。

### 新增文件

| 文件 | 职责 | 行数 |
|---|---|---|
| `Models/MemoryLocation.swift` | 聚合地点模型：名称/坐标/记录数/首末日期 | ~45 |
| `Services/MapService.swift` | 地点聚合、坐标聚类、Haversine 距离、TimeFilter、足迹坐标 | ~160 |
| `Views/MapView.swift` | Apple Maps 地图视图：Pin 注解、Segmented Picker 时间过滤、足迹 Polyline 覆盖层 | ~215 |
| `Views/LocationDetailView.swift` | 地点详情：Mini 地图 + 该地点全部 TimelineCell 记录 | ~130 |
| `Views/FootprintView.swift` | 人生轨迹 Polyline 全屏视图：最近 30 天坐标线 + 起点/终点标记 | ~165 |

### 修改文件

| 文件 | 变更 |
|---|---|
| `Views/ContentView.swift` | 新增 `.map` Tab；`AppTab` 扩展为 5 值；新增 `focusLocation` 跨 Tab 状态 |
| `Views/SearchView.swift` | 新增 `selectedTab`/`focusLocation` 绑定；地点匹配时显示"在地图上查看"入口 |
| `Views/StatsView.swift` | 新增 4 张卡片：总地点数 / 最常地点 / 最近地点 / 最远距离 |
| `Services/StatsService.swift` | `AppStats` 扩展 `totalLocations` / `farthestDistanceKm` / `latestLocation`；新增 `compute(from:)` 复用 |

### 关键架构决策

#### Tab 系统升级（5 Tab）
```
TabView (5 tabs)
├── Timeline ←── Archive (scroll-to-date)
├── Archive
├── Map       ←── Search (focusLocation)
│   ├── MKMapView + Annotation pins
│   ├── TimeFilter segmented picker
│   ├── Footprint polyline overlay
│   └── ⇢ LocationDetailView (sheet)
├── Search
│   ├── Record results → TimelineCell
│   └── Location results → Map tab
└── Stats
```

#### MemoryLocation 聚合
```swift
// MapService.aggregateLocations(from:timeFilter:)
// 1. TimeFilter 过滤记录
// 2. Dictionary(grouping: by locationName)
// 3. 每组平均坐标 (lat/lng)
// 4. 排序: recordCount 降序
```

#### 地点搜索联动
```
Search 输入 "学校"
  → 匹配 locations: ["学校"]
  → 显示 "📍 学校  在地图上查看"
  → 点击:
      focusLocation = "学校"
      selectedTab = .map
  → MapView onAppear:
      position = region(centered on 学校)
      showingDetail = true (LocationDetailView sheet)
```

#### Footprint 足迹模式
- `MapService.footprintCoordinates(from:)` — 最近 30 天，chronological order
- In‑map: `MapPolyline` with `.primary.opacity(0.35)`, lineWidth 1.5
- Full‑screen: `FootprintView` with start/end markers
- Toggle from MapView bottom button or toolbar icon

#### MapKit 技术选型
- iOS 17+ `Map` + `Annotation` (非 MKMapView UIViewRepresentable)
- `MapPolyline` 用于足迹路径
- `MapCameraPosition` 用于搜索定位缩放
- `MapCompass` + `MapScaleView` 系统控件
- `.mapStyle(.standard)` — 仅 Apple Maps 标准样式

#### Stats 扩展
```swift
AppStats {
    // ... Phase 3 fields
    let totalLocations: Int      // 唯一地点数
    let farthestDistanceKm: Double // Haversine 最远距离
    let latestLocation: String?   // 最近访问地点
}
```

### 时间过滤 Segmented Picker
```swift
enum TimeFilter: String, CaseIterable {
    case today  // 今天
    case week   // 最近7天
    case month  // 最近30天
    case all    // 全部
}
```

### Haversine 距离计算
```swift
private static func distanceKm(from a: CLLocationCoordinate2D,
                               to b: CLLocationCoordinate2D) -> Double {
    let R = 6371.0
    let dLat = (b.latitude - a.latitude) * .pi / 180
    let dLon = (b.longitude - a.longitude) * .pi / 180
    let aVal = sin(dLat/2)*sin(dLat/2) + cos(a.latitude*.pi/180) * cos(b.latitude*.pi/180) * sin(dLon/2)*sin(dLon/2)
    let c = 2 * atan2(sqrt(aVal), sqrt(1 - aVal))
    return R * c
}
```

---

## Phase 4 — Sync & Backup System

**目标：** 数据安全、多设备同步架构、可恢复备份。

### 新增文件

| 文件 | 职责 | 行数 |
|---|---|---|
| `Models/BackupMetadata.swift` | 备份元数据（appVersion/schemaVersion）+ JSON 序列化 Record | ~70 |
| `Services/BackupService.swift` | 导出/导入/自动备份管理：ZIP 格式，syncId 去重 | ~250 |
| `Services/AutoBackupManager.swift` | BGTaskScheduler 每日凌晨备份 + 启动时检查 + 30 个保留 | ~110 |
| `Views/SettingsView.swift` | 设置页：Form 风格，同步/备份/外观/关于 Section | ~390 |
| `Utils/SettingsStorage.swift` | 统一 @AppStorage 管理，禁止 UserDefaults 散落 | ~50 |
| `Utils/ZipHelper.swift` | 纯 Swift ZIP 实现：CRC-32 + Compression 框架 deflate | ~320 |

### 修改文件

| 文件 | 变更 |
|---|---|
| `Models/Record.swift` | 新增 `syncId: UUID?` + `syncVersion: Int`（向下兼容） |
| `Services/SyncService.swift` | 新增 `SyncStatus` enum（idle/syncing/success/failed），`CloudSyncService` 占位 |
| `Views/ContentView.swift` | AppTab 扩展为 6 个 Tab + `.settings` 入口（`gearshape.fill`） |
| `StarIslandApp.swift` | `AutoBackupManager.shared.setup()` 启动时注册 |

### 关键设计

#### Tab 系统升级（6 Tab）
```
TabView (6 tabs)
├── Timeline
├── Archive
├── Map
├── Search
├── Stats
└── Settings  ← NEW
```

#### 备份格式
```
StarIslandBackup_20260624.zip
├── metadata.json    ← appVersion / exportDate / recordCount / schemaVersion
├── records.json     ← [BackupRecord]（syncId 为去重键）
└── images/          ← 原始 JPEG（UUID 文件名）
```

#### ZIP 纯 Swift 实现
- CRC-32 纯 Swift 查表法
- Deflate 通过 `Compression` 框架 `COMPRESSION_DEFLATE`
- 创建用 stored 方法（JSON + JPEG 无需二次压缩）
- 读取兼容 stored + deflated
- 零第三方依赖

#### 导入去重
```
Import ZIP → unzip → parse records.json
→ build Set<syncId> from existing records
→ for each backupRecord:
    if syncId in set → skip
    else → copy images with new UUID → insert Record → restore metadata
→ return ImportResult
```

---

## Phase 4.5 — v1.0 RC

**目标：** 发布前打磨 — 回收站、主题、App 图标、数据完整性、Debug、性能、统一体验。

### 新增文件

| 文件 | 职责 | 行数 |
|---|---|---|
| `Views/RecycleBinView.swift` | 回收站：恢复/永久删除/批量操作/30 天自动清理 | ~280 |
| `Services/IntegrityService.swift` | 后台完整性检查：孤立图片、缺失图片、syncId 自动修复 | ~170 |
| `Views/DataHealthView.swift` | 数据健康面板：完整性状态、存储统计、备份信息 | ~130 |
| `Views/DebugView.swift` | `#if DEBUG` 专属：记录数、内存、缓存、DB 大小 | ~140 |

### 修改文件

| 文件 | 变更 |
|---|---|
| `Theme/AppTheme.swift` | +`ThemeMode` 枚举（system/light/dark）+ 统一动画常量 |
| `Utils/SettingsStorage.swift` | +`resolvedThemeMode` 便捷访问器 |
| `StarIslandApp.swift` | +`preferredColorScheme` 主题 + `IntegrityService.runAll()` 后台启动 |
| `Views/SettingsView.swift` | 回收站 Section + 主题 Picker + App 图标选单 + 数据健康导航 + Debug 链接 |
| `Services/ImageCacheService.swift` | +`cacheCount` 跟踪（NSLock 线程安全） |
| `Components/EmptyStateView.swift` | 统一文案 → "记录属于这一秒的故事。" |
| `Views/SearchView.swift` | 统一空状态 → 🌌 StarIsland 风格 |

### 关键设计

#### 回收站
- `@Query` 过滤 `isTrashed == true`，按 `trashedAt` 倒序
- swipeActions：绿色恢复 / 红色永久删除（含图片清理）
- 编辑模式：批量选择 → 恢复或清空
- 底部栏："恢复全部" + "清空回收站"
- 空状态统一 🌌 风格

#### Theme 系统
```swift
enum ThemeMode: String, CaseIterable {
    case system  // 跟随系统
    case light   // 浅色
    case dark    // 深色
}
// App: .preferredColorScheme(ThemeMode(rawValue:)?.colorScheme)
```

#### App 图标
- Settings → NavigationLink → IconPickerView
- 支持：Default / Deep Space / White
- `UIApplication.shared.setAlternateIconName()`
- Simulator 安全（`#if !targetEnvironment(simulator)`）

#### IntegrityService
```
Background TaskGroup:
├── checkOrphanedImages → 删除无引用图片
├── checkMissingImages  → 统计记录引用缺失
└── fixDuplicateSyncIds → 保留 syncVersion 最高版本，删除其余
```

#### 动画统一
```swift
struct AnimationDuration {
    insertDuration: 0.30   // interactiveSpring
    heroDuration:   0.35   // interactiveSpring
    deleteDuration: 0.25   // interactiveSpring
    sectionDuration: 0.20  // interactiveSpring
    var spring: Animation  // 全 app 统一入口
}
```

#### 空状态统一
```
🌌
StarIsland
记录属于这一秒的故事。
```
Timeline / Search / Recycle Bin 全部统一风格。

---

## 项目现状

### 统计

| 指标 | Phase 1 | Phase 1.5 | Phase 2 | Phase 2.5 | Phase 3 | Phase 3.5 | Phase 4 | Phase 4.5 | **当前** |
|---|---|---|---|---|---|---|---|---|---|
| **Swift 文件数** | 6 | 13 | 20 | 25 | 34 | 39 | 45 | 49 | **49** |
| **Models** | 1 | 1 | 2 | 2 | 2 | 3 | 4 | 4 | **4** |
| **Views** | 3 | 3 | 3 | 4 | 7 | 10 | 11 | 14 | **14** |
| **Components** | 0 | 2 | 7 | 9 | 11 | 11 | 11 | 11 | **11** |
| **Services** | 1 | 2 | 4 | 6 | 8 | 9 | 11 | 12 | **12** |
| **Theme** | 0 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | **1** |
| **Utils** | 0 | 1 | 1 | 1 | 1 | 1 | 3 | 3 | **3** |

### 完整文件树（49 文件）

```
StarIsland/
├── StarIslandApp.swift                      (21行)  ← Theme + Integrity
│
├── Models/                                         4
│   ├── Record.swift                         (94行)  — +syncId/syncVersion
│   ├── Mood.swift                           (59行)
│   ├── MemoryLocation.swift                 (45行)
│   └── BackupMetadata.swift                 (70行)  ← Phase 4
│
├── Views/                                           14
│   ├── ContentView.swift                    (127行) — 6 Tab (Timeline/Archive/Map/Search/Stats/Settings)
│   ├── TimelineView.swift                   (254行) — 保持滚动 + 高亮
│   ├── AddRecordView.swift                  (243行) — Quick Capture <3s
│   ├── RecordDetailView.swift               (161行) — 软删除
│   ├── SearchView.swift                     (209行) — 统一空状态
│   ├── ArchiveView.swift                    (203行) — 热力图
│   ├── ArchiveDayDetailView.swift           (~150行)
│   ├── StatsView.swift                      (~160行) — 13 项统计
│   ├── MapView.swift                        (~215行) — Apple Maps + 足迹
│   ├── LocationDetailView.swift             (~130行)
│   ├── FootprintView.swift                  (~165行)
│   ├── SettingsView.swift                   (~390行) — Theme/Bakcup/Health/About  ← Phase 4+4.5
│   ├── RecycleBinView.swift                 (~280行) ← Phase 4.5
│   ├── DataHealthView.swift                 (~130行) ← Phase 4.5
│   └── DebugView.swift                      (~140行) ← Phase 4.5 (DEBUG only)
│
├── Components/                                      11
│   ├── TimelineCell.swift                   (155行)
│   ├── DaySectionHeader.swift               (~70行)  — isHighlighted
│   ├── ImageGridView.swift                  (200行)  — Hero + Cache
│   ├── PhotoViewer.swift                    (180行)  — 分页缩放
│   ├── HomeHeaderView.swift                 (59行)
│   ├── SearchBarView.swift                  (54行)
│   ├── EmptyStateView.swift                 (34行)  — 统一 🌌
│   ├── MoodSelectorView.swift               (60行)
│   ├── ImagePicker.swift                    (88行)
│   ├── ContributionGridView.swift           (~150行) — 4 级透明度
│   ├── YearPickerView.swift                 (~55行)
│   └── StatsCardView.swift                  (~60行)
│
├── Theme/                                            1
│   └── AppTheme.swift                       (~120行) — +ThemeMode + 统一动画
│
├── Services/                                        12
│   ├── CalendarService.swift                (~120行)
│   ├── StatsService.swift                   (~160行)
│   ├── MapService.swift                     (~160行)
│   ├── SyncService.swift                    (~85行)  — +SyncStatus + CloudSyncService
│   ├── LocationService.swift                (105行)
│   ├── ImageStorageService.swift            (57行)
│   ├── ImageCacheService.swift              (~85行)  — +cacheCount
│   ├── SearchService.swift                  (60行)
│   ├── BackupService.swift                  (~250行) ← Phase 4
│   ├── AutoBackupManager.swift              (~110行) ← Phase 4
│   └── IntegrityService.swift               (~170行) ← Phase 4.5
│
├── Utils/                                            3
│   ├── DateFormatterManager.swift           (65行)
│   ├── SettingsStorage.swift                (~55行) — 统一 @AppStorage  ← Phase 4
│   └── ZipHelper.swift                      (~320行) — 纯 Swift ZIP  ← Phase 4
│
├── Extensions/
│   └── Date+Extension.swift                 (25行)
│
└── ViewModels/
    └── RecordViewModel.swift                (45行)
```

### 架构规则（持续强制）

- ✅ `ScrollView` + `LazyVStack`，禁止 `List`
- ✅ 无第三方库（仅 Apple 原生: SwiftUI, SwiftData, MapKit, CoreLocation)
- ✅ 无自定义颜色/字体（全部 Apple System）
- ✅ 仅 `+` 按钮可使用强调色
- ✅ 单文件单职责，View < 400 行
- ✅ 无卡片阴影/渐变
- ✅ 日期格式化全部走 `DateFormatterManager`
- ✅ 图片异步加载，NSCache 缓存，不阻塞主线程
- ✅ 禁止 Cloud / AI / Social（Apple Maps 除外）
- ✅ 跨 Tab 通信通过 `@Binding` + ContentView 共享状态
- ✅ 统计/聚合逻辑在 Service 层，View 中无业务计算
- ✅ 所有文件 I/O 在 async Task 后台线程
- ✅ UserDefaults 统一由 `SettingsStorage` 管理
- ✅ 启动不阻塞：IntegrityService 后台异步运行

### 未来方向（v2.0 候选）

- Timeline 筛选：按 Mood / 地点 / 日期范围
- iCloud 纯备份（非同步，仅归档）
- Widget：今日记录数量 + 快捷记录
- Watch App：抬手即记
- iPad 自适应布局（横屏 Split View）
- Map 聚类：大量 Pin 时的视觉聚合
- 导出：纯文本 / JSON 归档
- 标签系统增强：标签管理 + 标签过滤
