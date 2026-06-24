# StarIsland Test Plan

> 测试计划与执行记录。
>
> T1 — Build Pipeline Validation

---

## T1: Build Pipeline Validation

| 项目 | 内容 |
|---|---|
| **测试 ID** | T1 |
| **名称** | Build Pipeline Validation |
| **目标** | 验证 GitHub Actions 能稳定构建 StarIsland 并产出可安装 IPA |
| **类型** | CI/CD 集成测试 |
| **优先级** | 🔴 P0 (阻塞) |
| **负责人** | DevOps |
| **开始日期** | 2026-06-24 |

---

### 测试项

| # | 测试项 | 预期 | 检查方法 |
|---|--------|------|----------|
| 1 | `project.yml` XcodeGen 生成 | StarIsland.xcodeproj 生成成功 | `xcodegen generate` |
| 2 | `xcodebuild clean build` (Debug, 无签名) | Build Succeeded | CI log |
| 3 | build.log 生成并上传 | Artifact 可下载 | GitHub Actions Artifacts |
| 4 | diagnostic.log 生成 | Swift 文件数、资源数正确 | CI log |
| 5 | `xcodebuild archive` (Release, 需签名) | Archive Succeeded | CI log (仅 workflow_dispatch) |
| 6 | IPA export | StarIsland.ipa 生成 | CI artifact |
| 7 | IPA 上传 | StarIsland-IPA artifact 保留 30 天 | GitHub Actions Artifacts |
| 8 | push 触发 | Build Verification job 运行 | GitHub Actions |
| 9 | pull_request 触发 | Build Verification job 运行 | GitHub Actions |
| 10 | workflow_dispatch 触发 | 全部 job 运行 | GitHub Actions |

---

### 执行记录

| 日期 | 测试 | 提交 | 结果 | 备注 |
|------|------|------|------|------|
| 2026-06-24 | T1-1 | — | ⏳ 待执行 | 首次 push 后验证 |

---

### 环境

- **CI Runner:** `macos-latest` (macOS 15.x, Xcode 16.x)
- **iOS Target:** 17.0
- **Device:** iPhone 12 Pro (真机 AltStore 安装)
- **构建工具:** XcodeGen + xcodebuild

### 通过标准

- [ ] Build Verification: ✅ Build Succeeded
- [ ] Diagnostic: ✅ 全部 required files 存在
- [ ] Archive (if configured): ✅ Archive Succeeded
- [ ] IPA (if configured): ✅ .ipa 文件生成
- [ ] Artifact: ✅ build.log / diagnostic.log / IPA 可下载

---

## 后续测试

| ID | 名称 | 计划 |
|----|------|------|
| T2 | Data Integrity | IntegrityService 验证 |
| T3 | Backup & Restore | 导出 ZIP → 删除数据 → 导入恢复 |
| T4 | Recycle Bin | 删除 → 恢复 → 永久删除 → 30天清理 |
| T5 | Theme & Icon | 浅色/深色切换, App 图标切换 |
| T6 | Performance | 10k records, 60fps 验证 |
