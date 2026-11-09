import AppKit
import SwiftUI

struct SettingsSheetView: View {
    @ObservedObject var store: RadarStore
    @Environment(\.dismiss) private var dismiss

    @State private var newGroupName: String = ""
    @State private var newGroupIcon: String = "folder"
    @State private var newGroupColor: String = "blue"

    private let availableIcons = [
        "folder", "sparkles", "briefcase", "wrench.and.screwdriver",
        "globe", "cpu", "terminal", "cube.box", "bolt", "star"
    ]
    private let availableColors = ["blue", "purple", "orange", "green", "pink", "teal", "indigo", "red"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: 1. 顶部导航栏：标题 + 顶部 Tab 切换器 + 完成按钮
            HStack(spacing: 12) {
                Text("设置")
                    .font(.system(size: 15, weight: .bold))

                Spacer()

                // 顶部 Tab 栏
                HStack(spacing: 4) {
                    ForEach(SettingsTab.allCases) { tab in
                        let isSelected = store.selectedSettingsTab == tab
                        Button {
                            store.selectedSettingsTab = tab
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: tab.sfSymbol)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                Text(tab.rawValue)
                                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? AppTheme.elevatedSurface : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isSelected ? AppTheme.selectedBorder.opacity(0.6) : Color.clear, lineWidth: 1)
                            )
                            .foregroundStyle(isSelected ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.subtleSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.hairlineBorder, lineWidth: 1)
                )

                Spacer()

                Button("完成") {
                    store.saveConfig()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppTheme.canvasBackground)

            Divider()

            // MARK: 2. 顶部 Tab 对应的主体内容区
            Group {
                switch store.selectedSettingsTab {
                case .directories:
                    directoriesTab
                case .filter:
                    FilterRulesContentView(store: store)
                case .groups:
                    groupsTab
                case .gitAndCache:
                    gitAndCacheTab
                case .logs:
                    actionLogsTab
                case .about:
                    aboutUsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 500)
    }

    // MARK: - Tab 1: 扫描目录管理
    private var directoriesTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部操作与扫描深度配置条
            HStack(spacing: 12) {
                Button {
                    store.promptAddDirectory()
                } label: {
                    Label("添加扫描目录...", systemImage: "folder.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .controlSize(.small)

                HStack(spacing: 6) {
                    Text("常用目录快捷添加：")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    ForEach(["~/AI", "~/Projects", "~/Developer", "~/Desktop"], id: \.self) { candidate in
                        let expanded = (candidate as NSString).expandingTildeInPath
                        if FileManager.default.fileExists(atPath: expanded),
                           !store.watchedDirectories.contains(where: { $0.path == expanded }) {
                            Button("+ \(candidate)") {
                                store.addQuickDirectory(candidate)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }

                Spacer()

                Stepper(
                    "扫描深度：\(store.defaultScanDepth) 层",
                    value: $store.defaultScanDepth,
                    in: 1...8
                )
                .font(.system(size: 11.5, weight: .medium))
                .onChange(of: store.defaultScanDepth) { _, newValue in
                    for idx in store.watchedDirectories.indices {
                        store.watchedDirectories[idx].maxDepth = newValue
                    }
                    store.saveConfig()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppTheme.subtleSurface)

            Divider()

            // 表头
            HStack(spacing: 0) {
                Text("目录名称")
                    .frame(width: 140, alignment: .leading)
                Text("完整路径")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("扫描深度")
                    .frame(width: 80, alignment: .center)
                Text("仓库数量")
                    .frame(width: 80, alignment: .trailing)
                Text("操作")
                    .frame(width: 110, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(AppTheme.canvasBackground)

            Divider()

            if store.watchedDirectories.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("尚未添加本地扫描目录")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.watchedDirectories) { dir in
                        HStack(spacing: 0) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text(dir.displayName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .frame(width: 140, alignment: .leading)

                            Text(dir.path)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("\(dir.maxDepth) 层")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .center)

                            Text("\(store.countForRootDirectory(dir.path)) 个")
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .frame(width: 80, alignment: .trailing)

                            HStack(spacing: 6) {
                                Spacer()
                                Button("Finder") {
                                    ExternalLauncher.openInFinder(path: dir.path)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)

                                Button("移除") {
                                    store.removeWatchedDirectory(dir)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                            .frame(width: 110, alignment: .trailing)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Tab 3: 虚拟分组管理
    private var groupsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部新建分组栏
            HStack(spacing: 10) {
                TextField("输入新分组名称", text: $newGroupName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 180)

                HStack(spacing: 5) {
                    ForEach(availableIcons, id: \.self) { icon in
                        Button {
                            newGroupIcon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 11))
                                .frame(width: 24, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(newGroupIcon == icon ? AppTheme.elevatedSurface : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(newGroupIcon == icon ? AppTheme.selectedBorder : AppTheme.hairlineBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 6) {
                    ForEach(availableColors, id: \.self) { colorHex in
                        let dummy = RepoGroup(name: "", icon: "", colorHex: colorHex)
                        Button {
                            newGroupColor = colorHex
                        } label: {
                            Circle()
                                .fill(dummy.color)
                                .frame(width: 14, height: 14)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: newGroupColor == colorHex ? 1.5 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                Button("+ 新建分组") {
                    store.createGroup(name: newGroupName, icon: newGroupIcon, colorHex: newGroupColor)
                    newGroupName = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .controlSize(.small)
                .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppTheme.subtleSurface)

            Divider()

            // 表头
            HStack(spacing: 0) {
                Text("分组名称")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("关联仓库数")
                    .frame(width: 100, alignment: .trailing)
                Text("操作")
                    .frame(width: 80, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(AppTheme.canvasBackground)

            Divider()

            List {
                ForEach(store.groups) { group in
                    HStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(group.color)
                                .frame(width: 8, height: 8)
                            Image(systemName: group.icon)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text(group.name)
                                .font(.system(size: 12.5, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(store.countForGroup(group.id)) 个仓库")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 100, alignment: .trailing)

                        HStack {
                            Spacer()
                            Button("删除") {
                                store.deleteGroup(group)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset)
        }
    }

    // MARK: - Tab 4: Git 参数与缓存管理
    private var gitAndCacheTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 表头
            HStack(spacing: 0) {
                Text("配置项")
                    .frame(width: 180, alignment: .leading)
                Text("当前设置与说明")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("操作 / 切换")
                    .frame(width: 180, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(AppTheme.canvasBackground)

            Divider()

            List {
                settingTableRow(
                    title: "Git Pull 拉取策略",
                    subtitle: store.pullUseRebase ? "使用 git pull --rebase --autostash" : "使用默认合并 git pull"
                ) {
                    Toggle("启用 Rebase", isOn: $store.pullUseRebase)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: store.pullUseRebase) { _, _ in store.saveConfig() }
                }

                settingTableRow(
                    title: "Git Fetch 清理引用",
                    subtitle: store.fetchUsePrune ? "执行 git fetch --all --prune 自动清理已删远程分支" : "执行 git fetch --all"
                ) {
                    Toggle("启用 --prune", isOn: $store.fetchUsePrune)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: store.fetchUsePrune) { _, _ in store.saveConfig() }
                }

                settingTableRow(
                    title: "默认主看板视图",
                    subtitle: "切换主界面默认展示为卡片网格或表格列表"
                ) {
                    Picker("", selection: $store.viewMode) {
                        ForEach(DashboardViewMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 120)
                    .onChange(of: store.viewMode) { _, _ in store.saveConfig() }
                }

                settingTableRow(
                    title: "默认排序规则",
                    subtitle: store.sortOption.rawValue
                ) {
                    Picker("", selection: $store.sortOption) {
                        ForEach(RepoSortOption.allCases, id: \.self) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 155)
                    .onChange(of: store.sortOption) { _, _ in store.saveConfig() }
                }

                settingTableRow(
                    title: "项目图标与头像缓存",
                    subtitle: ProjectMetadataInspector.avatarCacheDirectory.path
                ) {
                    Button("清空缓存并重扫") {
                        store.clearAvatarCacheAndReload()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                settingTableRow(
                    title: "本地配置文件",
                    subtitle: store.configFileURL.path
                ) {
                    Button("在 Finder 中定位") {
                        ExternalLauncher.openInFinder(path: store.configFileURL.deletingLastPathComponent().path)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .listStyle(.inset)
        }
    }

    private func settingTableRow<Control: View>(
        title: String,
        subtitle: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 180, alignment: .leading)

            Text(subtitle)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                control()
            }
            .frame(width: 180, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Tab 5: Git 执行日志
    private var actionLogsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("共记录 \(store.actionLogs.count) 条 Git 操作日志")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.actionLogs.isEmpty {
                    Button("清空日志") {
                        store.clearActionLogs()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppTheme.subtleSurface)

            Divider()

            // 表头
            HStack(spacing: 0) {
                Text("状态")
                    .frame(width: 56, alignment: .leading)
                Text("时间")
                    .frame(width: 85, alignment: .leading)
                Text("仓库名称")
                    .frame(width: 130, alignment: .leading)
                Text("执行命令")
                    .frame(width: 190, alignment: .leading)
                Text("输出摘要")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(AppTheme.canvasBackground)

            Divider()

            if store.actionLogs.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text("暂无手动 Git 命令执行记录")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.actionLogs) { log in
                    HStack(spacing: 0) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(log.success ? AppTheme.statusClean : AppTheme.statusDanger)
                                .frame(width: 6, height: 6)
                            Text(log.success ? "成功" : "失败")
                                .font(.system(size: 11))
                        }
                        .frame(width: 56, alignment: .leading)

                        Text(log.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 85, alignment: .leading)

                        Text(log.repoName)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                            .frame(width: 130, alignment: .leading)

                        Text(log.command)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 190, alignment: .leading)

                        Text(log.output.isEmpty ? "—" : log.output.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button("复制输出日志") {
                            ExternalLauncher.copyToPasteboard(log.output)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Tab 6: 关于我们与版本信息
    private var aboutUsTab: some View {
        VStack(spacing: 0) {
            // 上半部分：品牌图标与版本号
            HStack(spacing: 16) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("GitRadar")
                            .font(.system(size: 20, weight: .bold))
                        Text("v0.1.0 (Build 1)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(AppTheme.subtleSurface))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.hairlineBorder, lineWidth: 1))
                    }

                    Text("macOS 原生全平台本地 Git 仓库全景管理工具")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)

                    Text("支持 GitHub · GitLab · Gitee · Bitbucket · Gitea/Codeberg · 自建 Git · 本地仓库")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(AppTheme.subtleSurface)

            Divider()

            // 表头：版本与系统环境详情表
            HStack(spacing: 0) {
                Text("项目 / 属性")
                    .frame(width: 170, alignment: .leading)
                Text("详细信息")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(AppTheme.canvasBackground)

            Divider()

            List {
                aboutRow(label: "软件名称", value: "GitRadar (com.gitradar.app)")
                aboutRow(label: "当前版本", value: "v0.1.0 (Release · Tag v0.1.0)")
                aboutRow(label: "客户端架构", value: "macOS Native (Swift 6 + SwiftUI + AppKit · Apple Silicon)")
                aboutRow(label: "系统运行环境", value: ProcessInfo.processInfo.operatingSystemVersionString)
                aboutRow(label: "当前监控统计", value: "已扫描 \(store.repositories.count) 个仓库（显示 \(store.visibleRepositories.count) 个，已过滤 \(store.excludedRepositories.count) 个）")
                aboutRow(label: "隐私与安全", value: "纯本地离线运行，所有配置与状态仅保存在本机，不上传任何仓库数据")
                aboutRow(label: "开源协议与版权", value: "MIT License · © 2026 GitRadar")
            }
            .listStyle(.inset)
        }
    }

    private func aboutRow(label: String, value: String) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 170, alignment: .leading)

            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }
}
