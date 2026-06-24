# StarIsland Roadmap

> 产品演进路线图。

---

## ✅ v0.1 — 原型 (Phase 1)

- [x] 基础 SwiftUI + SwiftData 骨架
- [x] Timeline 时间线流 CRUD
- [x] 添加记录（文字 + 心情）
- [x] 记录详情

## ✅ v0.5 — 丰富 (Phase 1.5 ~ 3.5)

- [x] 自定义 Timeline UI（圆点 + 连接线）
- [x] Archive 年/月/日三级归档 + 贡献热力图
- [x] Map 地理足迹聚合
- [x] Search 全文搜索（文字/地点/心情）
- [x] Stats 年度统计面板
- [x] 照片拍摄/选择与本地持久化
- [x] Footprint 视图
- [x] Design Token 统一 (`AppTheme`)

## ✅ v0.9 — 数据保护 (Phase 4)

- [x] Sync 架构预留 (SyncStatus / CloudSyncService 桩)
- [x] 备份导出/导入 (ZIP 格式)
- [x] 自动每日备份 (BGTaskScheduler)
- [x] Settings 设置页 (Form)
- [x] 统一 AppStorage 管理 (`SettingsStorage`)

## ✅ v1.0 RC — 发布候选 (Phase 4.5)

- [x] 回收站 (Recycle Bin) — 恢复/永久删除/批量操作
- [x] 主题系统 (浅色/深色/跟随系统)
- [x] App 图标 (默认 / Deep Space / White)
- [x] 数据完整性检查 (IntegrityService)
- [x] 数据健康页 (DataHealthView)
- [x] Debug 诊断页 (DEBUG only)
- [x] 统一动画常量 (`interactiveSpring`)
- [x] 统一空状态 (🌌 StarIsland)
- [x] GitHub Actions 自动构建
- [x] 文档体系 (README / CHANGELOG / LICENSE)

---

## 🗺️ v1.1 — 稳定优化

- [ ] Timeline 筛选（按心情 / 地点 / 标签）
- [ ] 标签管理（CRUD + 自动补全）
- [ ] 性能优化（大型数据集归档/地图分组渲染）
- [ ] JSON / CSV 导出
- [ ] iPad 自适应布局（基础）
- [ ] 本地化完善
- [ ] 辅助功能（Dynamic Type / VoiceOver）

## 🗺️ v1.2 — 云备份

- [ ] iCloud 纯备份（仅 ZIP 上传/恢复，无实时同步）
- [ ] iCloud 状态监控 + 冲突提示

## 🗺️ v1.x — 扩展

- [ ] iOS Widget（今日/本周快照）
- [ ] Map 足迹聚类 (MKClusterAnnotation)
- [ ] Watch app（快速记录入口）
- [ ] Core Spotlight 索引

## 🗺️ v2.0 — AI（最低优先级）

- [ ] Memory AI — 基于时间线数据的个性化回忆生成
- [ ] 智能标签推荐
- [ ] 图片文字识别 (VisionKit)

---

## 版本命名

| 版本 | 含义 |
|---|---|
| v0.x | 功能开发阶段 |
| v1.0 RC | 发布候选 |
| v1.0 | 正式版 |
| v1.x | 功能迭代 |
| v2.0 | 重大更新 |

*优先级：隐私 > 稳定 > 功能 > AI*
