# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，并采用 [语义化版本 (Semantic Versioning)](https://semver.org/lang/zh-CN/) 进行版本管理。

## [0.2.0] - 2026-11-09

### Added
- **域名 / 组织 / 仓库级过滤与屏蔽管理**：
  - 支持一键屏蔽自建 Gitea / GitLab 域名、远程组织（Owner/Org）、单个仓库或自定义路径关键字。
  - 采用「未过滤 / 已过滤」双表视图设计，支持随时查看命中规则、一键过滤或恢复已隐藏仓库。
- **统一顶部 Tab「偏好设置」中心**：
  - 整合 `扫描目录`、`过滤管理`、`分组管理`、`Git 与缓存`、`执行日志` 与 `关于我们` 六大模块。
  - 采用卡片式对齐表格（Card-Table）设计，消除文字折行与列表错位。
- **右键菜单 IDE 快捷打开能力**：
  - 在仓库卡片及表格行右键菜单中新增「在 VS Code 中打开」与「在 Antigravity IDE 中打开」（优先匹配 `/Applications/Antigravity IDE.app`）。
- **开源协议与版本管理体系**：
  - 新增 `LICENSE`（MIT 开源协议）、`VERSION` 单一版本源与 `CHANGELOG.md`。

### Changed
- **分级安全确认机制**：
  - 单项目 Git 操作（单仓 `Fetch`、`Pull`、`Push`、切换分支、提交、放弃单文件修改）简化为 **1 步快捷确认**。
  - 批量高风险 Git 操作（`批量 Fetch`、`一键批量 Pull`）保留 **3 步递进式风险确认**。
- **主看板与卡片布局细节优化**：
  - 移除中间主视图左上角与侧边栏重复的状态胶囊按钮，改为展示当前选中视图图标、标题与仓库数量徽章，修复焦点常驻问题。
  - 修复卡片模式下超长远程 URL 撑高卡片的问题，改为单行尾部自动截断（悬停可查看完整 URL）。

---

## [0.1.0] - 2026-11-09

### Added
- **GitRadar 首个原生版本发布**：
  - 基于 Swift 6 + SwiftUI + AppKit 构建 macOS 原生多目录 Git 仓库全景管理工具。
  - 支持跨目录递归扫描 `.git` 仓库、拖拽文件夹添加与自定义虚拟分组。
  - 支持 GitHub、GitLab、Gitee、Bitbucket、Codeberg/Gitea、CNB/Coding、自建 Git 与纯本地仓库识别。
  - 支持多级项目真实图标扫描、远程组织头像缓存与技术栈双字母徽标生成。
  - 支持右侧详情栏 ≥ 2/5 高度 README 简介预览、工作区改动查看、提交历史与远程分支管理。
