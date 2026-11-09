# GitRadar — macOS 原生全平台本地 Git 仓库全景管理工具

**GitRadar** 是一款基于 **Swift + SwiftUI** 原生开发的 macOS 桌面应用，专为解决「本机不同目录下散落大量 Git 项目、难以统一查看状态和批量操作」而设计。

它不仅支持 **GitHub**，还全面支持 **GitLab、Gitee、Bitbucket、Codeberg / Gitea、CNB / Coding、企业自建 Git 以及纯本地 Git 仓库**。

---

## ✨ 核心功能

1. **跨目录递归扫描与自定义虚拟分组**
   - 支持添加多个本地根目录（如 `~/AI`、`~/Projects`、`~/Work`）或直接拖拽文件夹进入窗口，自动递归扫描所有 `.git` 仓库（自动跳过 `node_modules`、`.build`、`Pods`、`venv`、`target` 等目录）。
   - 支持创建**虚拟分组 / 标签**（不移动硬盘上的真实目录），支持星标收藏置顶。

2. **全平台远程识别（不止 GitHub）**
   - 自动解析 `SSH` (`git@host:owner/repo.git`) 与 `HTTP/HTTPS` 远程地址。
   - 自动识别 **GitHub、GitLab、Gitee、Bitbucket、Codeberg/Gitea、CNB/Coding、自建 Git 服务** 与 **仅本地仓库**，展示专属平台徽章并支持一键打开对应的远程 Web 主页。

3. **仓库状态全景看板（卡片网格 & 紧凑表格双视图）**
   - 顶部全景 KPI 雷达指标卡：监控总数、未提交改动、待推送 (`Ahead`)、待拉取 (`Behind`)、已同步健康数，点击指标卡即可一键过滤。
   - 实时展示每个仓库的当前分支、领先/落后远程 Commit 数、暂存 (`Staged`) / 修改 (`Modified`) / 未跟踪 (`Untracked`) / `Stash` 计数、最近一次提交摘要与相对时间。

4. **快捷外部工具联动**
   - 自动检测本机已安装的 IDE / 编辑器（如 **Antigravity、VS Code、Cursor、Zed、PyCharm、GoLand、IntelliJ IDEA、Android Studio、Xcode** 等）与终端工具（**Warp、iTerm2、Termora、系统 Terminal**）。
   - 一键在首选 IDE、终端、Finder 或浏览器中打开目标仓库。

5. **内置快捷 Git 操作与彩色 Diff 预览**
   - 支持单仓与批量 **Fetch All**、**Pull (`--rebase` 可选)**、**Push**。
   - 支持快速切换本地分支、基于当前分支新建分支 (`git checkout -b`)。
   - 右侧详情面板内置 **变更文件列表 + 语法高亮 Unified Diff 预览**、**一键 Stage All & Commit (+ Push)**、**最近 20 条 Commit 历史查看** 以及 **多 Remote 管理**。

---

## 🚀 编译与打包

```bash
# 1. 开发调试运行
swift run

# 2. 一键构建 Release 版 GitRadar.app 与 DMG 安装包
chmod +x scripts/build_app.sh
./scripts/build_app.sh

# 3. 安装到 /Applications 并启动
cp -R dist/GitRadar.app /Applications/
open /Applications/GitRadar.app
```
