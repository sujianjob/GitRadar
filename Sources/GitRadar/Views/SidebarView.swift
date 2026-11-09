import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: RadarStore
    @State private var newGroupName: String = ""
    @State private var newGroupIcon: String = "folder.fill"
    @State private var newGroupColor: String = "blue"

    private let availableIcons = [
        "folder.fill", "sparkles", "briefcase.fill", "wrench.and.screwdriver.fill",
        "globe", "cpu.fill", "terminal.fill", "cube.box.fill", "bolt.fill", "star.fill"
    ]
    private let availableColors = ["blue", "purple", "orange", "green", "pink", "teal", "indigo", "red"]

    var body: some View {
        List(selection: $store.selectedFilter) {
            // MARK: 1. 智能雷达概览
            Section("状态雷达") {
                sidebarRow(
                    filter: .all,
                    title: "全部 Git 仓库",
                    icon: "dot.radiowaves.left.and.right",
                    iconColor: .blue,
                    count: store.repositories.count
                )
                sidebarRow(
                    filter: .dirty,
                    title: "未提交改动",
                    icon: "pencil.circle.fill",
                    iconColor: .orange,
                    count: store.dirtyReposCount,
                    highlightBadge: store.dirtyReposCount > 0 ? .orange : nil
                )
                sidebarRow(
                    filter: .unpushed,
                    title: "待推送 Commit",
                    icon: "arrow.up.circle.fill",
                    iconColor: .blue,
                    count: store.unpushedReposCount,
                    highlightBadge: store.unpushedReposCount > 0 ? .blue : nil
                )
                sidebarRow(
                    filter: .needsPull,
                    title: "待拉取更新",
                    icon: "arrow.down.circle.fill",
                    iconColor: .cyan,
                    count: store.behindReposCount,
                    highlightBadge: store.behindReposCount > 0 ? .cyan : nil
                )
                sidebarRow(
                    filter: .favorites,
                    title: "星标常用",
                    icon: "star.fill",
                    iconColor: .yellow,
                    count: store.favoriteReposCount
                )
            }

            // MARK: 2. 托管平台（不止 GitHub）
            Section("托管平台与远程") {
                ForEach(GitProvider.allCases) { provider in
                    let count = store.countForProvider(provider)
                    if count > 0 || provider == .github || provider == .gitlab || provider == .gitee || provider == .localOnly {
                        sidebarRow(
                            filter: .provider(provider),
                            title: provider.rawValue,
                            icon: provider.sfSymbol,
                            iconColor: provider.badgeColor,
                            count: count
                        )
                    }
                }
            }

            // MARK: 3. 自定义虚拟分组
            Section {
                ForEach(store.groups) { group in
                    sidebarRow(
                        filter: .group(group.id),
                        title: group.name,
                        icon: group.icon,
                        iconColor: group.color,
                        count: store.countForGroup(group.id)
                    )
                    .contextMenu {
                        Button(role: .destructive) {
                            store.deleteGroup(group)
                        } label: {
                            Label("删除分组「\(group.name)」", systemImage: "trash")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("虚拟分组")
                    Spacer()
                    Button {
                        store.showNewGroupSheet = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("创建自定义虚拟分组（不移动本地文件夹）")
                }
            }

            // MARK: 4. 跨目录扫描根路径
            Section {
                if store.watchedDirectories.isEmpty {
                    Text("尚未添加监控目录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.watchedDirectories) { dir in
                        sidebarRow(
                            filter: .rootDirectory(dir.path),
                            title: dir.displayName,
                            subtitle: dir.path,
                            icon: "externaldrive.fill.badge.checkmark",
                            iconColor: .indigo,
                            count: store.countForRootDirectory(dir.path)
                        )
                        .contextMenu {
                            Button {
                                ExternalLauncher.openInFinder(path: dir.path)
                            } label: {
                                Label("在 Finder 中打开", systemImage: "folder")
                            }
                            Button {
                                Task { await store.scanAndRefreshAll() }
                            } label: {
                                Label("重新扫描此目录", systemImage: "arrow.clockwise")
                            }
                            Divider()
                            Button(role: .destructive) {
                                store.removeWatchedDirectory(dir)
                            } label: {
                                Label("移除监控目录", systemImage: "trash")
                            }
                        }
                    }
                }

                Button {
                    store.promptAddDirectory()
                } label: {
                    Label("添加扫描目录 / 仓库...", systemImage: "folder.badge.plus")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            } header: {
                HStack {
                    Text("本地扫描目录")
                    Spacer()
                    Button {
                        store.promptAddDirectory()
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("添加任意目录自动扫描 Git 仓库")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 10) {
                    if store.isScanning {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在扫描仓库...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("共监控 \(store.repositories.count) 个仓库")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        store.showSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("偏好设置与操作日志")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
        .sheet(isPresented: $store.showNewGroupSheet) {
            newGroupSheet
        }
    }

    @ViewBuilder
    private func sidebarRow(
        filter: SidebarFilter,
        title: String,
        subtitle: String? = nil,
        icon: String,
        iconColor: Color,
        count: Int,
        highlightBadge: Color? = nil
    ) -> some View {
        NavigationLink(value: filter) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 4)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(highlightBadge != nil ? highlightBadge!.opacity(0.18) : Color.secondary.opacity(0.14))
                        )
                        .foregroundStyle(highlightBadge ?? .secondary)
                }
            }
        }
    }

    private var newGroupSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("创建虚拟分组")
                .font(.headline)
            Text("虚拟分组可用于按业务或主题归类不同目录下的 Git 仓库，不会移动硬盘上的真实文件夹。")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("分组名称（如：微服务集群、个人开源）", text: $newGroupName)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("选择图标")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(availableIcons, id: \.self) { icon in
                        Button {
                            newGroupIcon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 14))
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(newGroupIcon == icon ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("选择颜色")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(availableColors, id: \.self) { colorHex in
                        let groupDummy = RepoGroup(name: "", icon: "", colorHex: colorHex)
                        Button {
                            newGroupColor = colorHex
                        } label: {
                            Circle()
                                .fill(groupDummy.color)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: newGroupColor == colorHex ? 2 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Spacer()
                Button("取消") {
                    store.showNewGroupSheet = false
                }
                Button("创建分组") {
                    store.createGroup(name: newGroupName, icon: newGroupIcon, colorHex: newGroupColor)
                    newGroupName = ""
                    store.showNewGroupSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 6)
        }
        .padding(20)
        .frame(width: 380)
    }
}
