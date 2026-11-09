# GitRadar

![Version](https://img.shields.io/badge/version-v0.2.0-blue)
![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-lightgrey)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

**macOS 原生全平台本地 Git 仓库全景管理工具。**  
基于 `Swift 6 + SwiftUI` 构建，统一扫描与管理散落在本机多个目录下的所有 Git 仓库，纯本地离线运行。

---

## 功能特性

| 模块 | 说明 |
| :--- | :--- |
| **多目录扫描** | 支持添加多个本地根目录或拖拽文件夹，自动递归发现所有 `.git` 仓库。 |
| **全平台识别** | 自动识别 GitHub、GitLab、Gitee、Bitbucket、Gitea/Codeberg、CNB/Coding、自建 Git 与纯本地仓库。 |
| **过滤与屏蔽** | 支持按远程域名（如自建 Gitea/GitLab）、组织（Owner/Org）或仓库一键隐藏，提供「未过滤 / 已过滤」双表管理。 |
| **状态与详情** | 实时展示未提交改动、领先/落后提交数、分支状态与项目 `README` 简介预览。 |
| **快捷打开** | 支持一键打开 `Finder`、远程主页，右键菜单支持在 **VS Code** 与 **Antigravity IDE** 中打开项目。 |
| **分级安全确认** | 单项目 `Fetch / Pull / Push` 一键确认；批量 `Fetch / Pull` 采用三步递进确认，防止误操作。 |

---

## 安装与运行

### 1. DMG 安装（推荐）

1. 从 Releases 下载 `GitRadar-v0.2.0.dmg`，将 `GitRadar.app` 拖入 `/Applications`（应用程序）。
2. 由于项目未购买 Apple 开发者证书公证，首次打开若提示 **「已损坏，无法打开」** 或 **「无法验证开发者」**，请在终端执行以下命令解除隔离限制：

```bash
sudo xattr -rd com.apple.quarantine /Applications/GitRadar.app
open /Applications/GitRadar.app
```

### 2. 源码编译

环境要求：`macOS 14.0+`、`Swift 6.0+`（Xcode 或 Command Line Tools）。

```bash
# 调试运行
swift run

# 打包 Release 版 GitRadar.app 与 DMG 镜像（产物位于 dist/）
./scripts/build_app.sh
```

---

## 版本与协议

- **更新日志**：[CHANGELOG.md](CHANGELOG.md)
- **开源协议**：[MIT License](LICENSE)
