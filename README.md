# GitRadar — macOS 原生全平台本地 Git 仓库全景管理工具

**GitRadar** 是一款基于 **Swift + SwiftUI** 原生开发的 macOS 桌面应用，专为解决「本机不同目录下散落大量 Git 项目、难以统一查看状态和批量操作」而设计。

它不仅支持 **GitHub**，还全面支持 **GitLab、Gitee、Bitbucket、Codeberg / Gitea、CNB / Coding、企业自建 Git 以及纯本地 Git 仓库**。

---

## ✨ 核心功能

1. **跨目录递归扫描与自定义虚拟分组**
   - 支持添加多个本地根目录（如 `~/AI`、`~/Projects`、`~/Work`）或直接拖拽文件夹进入窗口，自动递归扫描所有 `.git` 仓库（自动跳过 `node_modules`、`.build`、`Pods`、`venv`、`target` 等目录）。
   - 支持创建**虚拟分组 / 标签**（不移动硬盘上的真实目录），支持星标收藏置顶。

2. **全平台远程识别与完整仓库地址展示**
   - 自动解析 `SSH` (`git@host:owner/repo.git`) 与 `HTTP/HTTPS` 远程地址。
   - 自动识别 **GitHub、GitLab、Gitee、Bitbucket、Codeberg/Gitea、CNB/Coding、自建 Git 服务** 与 **仅本地仓库**，在项目卡片右下角直观展示完整仓库地址，并支持一键打开对应的 **Finder 目录** 或 **远程 Web 主页**。

3. **多级项目真实图标获取与技术栈识别**
   - 自动扫描仓库本地图标（`AppIcon`、`logo/`、`public/`、`favicon` 及 `README` 引用图标）。
   - 自动拉取并本地缓存远程仓库组织/作者官方头像（如 GitHub / GitLab Owner Avatar）。
   - 对无图片纯本地项目自动检测技术栈（`Swift`、`Python`、`TypeScript`、`Node.js`、`Rust`、`Go`、`AI Skill` 等），生成差异化的双字母专属徽标与技术栈角标。

4. **克制专业的桌面视觉 + 右侧栏 README 简介预览**
   - 借鉴 **Linear / Fork / GitHub Desktop** 的石墨灰与岩石蓝配色体系，顶部提供紧凑型分段状态过滤条（全部、未提交改动、待推送、待拉取、已同步）。
   - 点击任意项目后，右侧详情栏上方 **≥ 2/5 高度区域直接展示该项目的 README 简介摘要**（支持一键展开全文；无 README 的项目自动留空），下方提供**工作区变更列表**、**最近提交历史**与**远程/分支管理**。

5. **安全第一：一键 Git 操作「三次风险确认」机制**
   - 支持顶部批量 **Fetch / Pull**，以及右侧详情栏右上角的单仓 **Fetch / Pull / Push**、**本地分支切换/新建**、**快捷提交**与**单文件放弃修改**。
   - 所有一键 Git 操作均内置 **三步递进风险确认弹窗**（核对目标与命令 → 评估冲突/覆盖风险 → 最终执行授权），确认三次后才真正执行底层 Git 命令。

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
