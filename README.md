# GitRadar — macOS 原生全平台本地 Git 仓库全景管理工具

![Version](https://img.shields.io/badge/version-v0.2.0-blue)
![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-lightgrey)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

**GitRadar** 是一款基于 **Swift 6 + SwiftUI + AppKit** 原生开发的 macOS 桌面应用，专为解决「本机不同目录下散落大量 Git 项目、难以统一查看状态和批量同步管理」而设计。

它不仅支持 **GitHub**，还全面支持 **GitLab、Gitee、Bitbucket、Codeberg / Gitea、CNB / Coding、企业自建 Git 以及纯本地 Git 仓库**，所有扫描、配置与缓存均在本地离线完成，零云端数据上传。

---

## ✨ 核心功能

1. **跨目录递归扫描与自定义虚拟分组**
   - 支持添加多个本地根目录（如 `~/AI`、`~/Projects`、`~/Developer`）或直接拖拽文件夹进入窗口，自动递归扫描所有 `.git` 仓库（自动跳过 `node_modules`、`.build`、`Pods`、`venv`、`target` 等构建与依赖目录）。
   - 支持创建**虚拟分组 / 标签**（不移动硬盘上的真实目录），支持星标收藏置顶。

2. **全平台远程识别与 IDE 快捷打开**
   - 自动解析 `SSH` (`git@host:owner/repo.git`) 与 `HTTP/HTTPS` 远程地址。
   - 自动识别 **GitHub、GitLab、Gitee、Bitbucket、Codeberg/Gitea、CNB/Coding、自建 Git 服务** 与 **仅本地仓库**。
   - 仓库卡片右下角单行自适应展示完整仓库地址（超长自动尾部省略，悬停提示完整地址），底部支持一键打开 **Finder** 或 **远程主页**；右键菜单支持一键在 **VS Code**、**Antigravity IDE** 中直接打开项目。

3. **域名 / 组织 / 仓库级过滤与屏蔽管理**
   - 支持按**远程域名**（如自建 Gitea / GitLab 实例）、**远程组织 (Owner / Org)**、**指定仓库**或**路径关键字**一键过滤屏蔽，被过滤的仓库不在主看板中显示。
   - 采用清晰的**「未过滤 / 已过滤」双表视图**，支持随时查看已配置规则命中情况或一键恢复已隐藏仓库。

4. **多级项目真实图标获取与技术栈识别**
   - 自动扫描仓库本地图标（`AppIcon`、`logo/`、`public/`、`favicon` 及 `README` 引用图标）。
   - 自动拉取并本地缓存远程仓库组织/作者官方头像（如 GitHub / GitLab Owner Avatar）。
   - 对无图片纯本地项目自动检测技术栈（`Swift`、`Python`、`TypeScript`、`Node.js`、`Rust`、`Go`、`AI Skill` 等），生成差异化的双字母专属徽标。

5. **克制专业的桌面视觉 + 右侧栏 README 简介预览**
   - 借鉴 **Linear / Fork / GitHub Desktop** 的石墨灰与岩石蓝配色体系。
   - 点击任意项目后，右侧详情栏上方 **≥ 2/5 高度区域直接展示该项目的 README 简介摘要**（支持一键展开全文；无 README 的项目自动留空），下方提供**工作区变更列表**、**最近提交历史**与**远程/分支管理**。

6. **分级安全确认机制（单仓一键确认 + 批量三步确认）**
   - **单项目操作**（右侧详情栏右上角的单仓 `Fetch`、`Pull`、`Push`、本地分支切换、提交、放弃单文件修改）：采用 **1 步快捷确认弹窗**，兼顾安全与高频操作效率。
   - **批量高风险操作**（顶部 `批量 Fetch`、`一键批量 Pull`）：内置 **3 步递进式风险确认弹窗**（核对目标与命令 → 评估冲突/覆盖风险 → 最终执行授权），防止误操作污染多仓库工作区。

7. **统一顶部 Tab「偏好设置」中心**
   - 集中管理 `扫描目录`、`过滤管理`、`分组管理`、`Git 与缓存`、`执行日志` 与 `关于我们（版本信息）` 六大模块。

---

## 📥 下载安装与首次打开说明（未公证签名必读）

由于本项目为纯开源免费项目，采用本地 Ad-hoc 签名打包，暂未购买 Apple Developer ID 商业证书进行苹果公证（Notarization）。

当您从 Release 页面下载 `.dmg` 安装包并将 `GitRadar.app` 拖入 `/Applications`（应用程序）后，首次打开若提示 **「“GitRadar”已损坏，无法打开」** 或 **「无法验证开发者」**，请在终端执行以下 `xattr` 命令移除 macOS 隔离属性即可正常打开：

```bash
sudo xattr -rd com.apple.quarantine /Applications/GitRadar.app
```

执行完成后即可直接启动：

```bash
open /Applications/GitRadar.app
```

---

## 🚀 源码编译与打包

```bash
# 1. 开发调试运行
swift run

# 2. 一键构建 Release 版 GitRadar.app 与 DMG 安装镜像（自动读取 VERSION 文件）
chmod +x scripts/build_app.sh
./scripts/build_app.sh

# 3. 安装到 /Applications 并启动
cp -R dist/GitRadar.app /Applications/
open /Applications/GitRadar.app
```

---

## 📦 版本管理

- 当前发布版本：[`v0.2.0`](VERSION)
- 版本变更记录：详见 [`CHANGELOG.md`](CHANGELOG.md)

---

## 📄 开源协议 (License)

本项目基于 **[MIT License](LICENSE)** 开源协议发布。您可以自由地使用、复制、修改、合并、发布和分发本软件。
