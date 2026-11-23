# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，并采用 [语义化版本 (Semantic Versioning)](https://semver.org/lang/zh-CN/) 进行版本管理。

## [0.3.0] - 2026-11-23

### Added
- **GitHub 仓库排行榜（四大核心榜单）**：
  - 新增 **Trending 趋势热榜**（支持今日 / 本周 / 本月飙升，优先解析官方 Trending 页面并附带 Search API 兜底回退）。
  - 新增 **新晋黑马榜**（筛选近 7 / 30 / 90 天内新创建且 Star 增长最快的项目，自动计算新建天数与日均 Star 增速）。
  - 新增 **AI / Agent 专题榜**（聚合 `LLM / Agent / MCP / Skill` 领域的近期新秀、近期活跃与殿堂总榜）。
  - 新增 **全站 Star 总榜**（支持按全部语言或 Python、TypeScript、Rust、Go、Swift 等 11 种主流语言筛选 Top 殿堂级项目）。
  - 排行榜卡片与详情面板深度打通本地状态：自动标记「本机已克隆」与「已收藏 (@account)」，支持一键 Clone 或直接在 Finder / VS Code / Antigravity IDE 中打开。
- **远程 GitHub Star 仓库多账号追踪与管理**：
  - 支持同时添加、编辑多个 GitHub 账号并配置 Personal Access Token（内置一键在线测试 Token 有效性与配额余量）。
  - 自动分页拉取账号下全部 Star 仓库，提供「全部远程 Star」、「近期版本更新」、「本机已克隆」与按单账号筛选视图。
  - 支持设置「默认 Clone 目录」（配置后点击「一键 Clone」直接静默克隆至目标目录并自动纳入本地仓库监控）。
  - 右侧详情面板支持按需拉取远程项目的中文/英文 `README.md` 全文预览与最新 GitHub Release 版本说明。

### Changed
- **构建脚本跨架构增强**：
  - `scripts/build_app.sh` 新增 macOS Universal Binary (`arm64 + x86_64`) 编译支持与 CommandLineTools SDK 兼容处理。

---

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
