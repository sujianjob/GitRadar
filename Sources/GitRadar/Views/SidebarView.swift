import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: RadarStore
    @State private var newGroupName: String = ""
    @State private var newGroupIcon: String = "folder"
    @State private var newGroupColor: String = "blue"

    private let availableIcons = [
        "folder", "sparkles", "briefcase", "wrench.and.screwdriver",
        "globe", "cpu", "terminal", "cube.box", "bolt", "star"
    ]
    private let availableColors = ["blue", "purple", "orange", "green", "pink", "teal", "indigo", "red"]

    var body: some View {
        List(selection: $store.selectedFilter) {
            // MARK: 1. 仓库状态概览（克制的单色图标 + 状态小圆点）
            Section("仓库视图") {
                sidebarRow(
                    filter: .all,
                    title: "全部仓库",
                    icon: "square.stack.3d.up",
                    dotColor: nil,
                    count: store.repositories.count
                )
                sidebarRow(
                    filter: .dirty,
                    title: "未提交改动",
                    icon: "pencil.line",
                    dotColor: store.dirtyReposCount > 0 ? AppTheme.statusDirty : nil,
                    count: store.dirtyReposCount
                )
                sidebarRow(
                    filter: .unpushed,
                    title: "待推送提交",
                    icon: "arrow.up.right",
                    dotColor: store.unpushedReposCount > 0 ? AppTheme.statusSync : nil,
                    count: store.unpushedReposCount
                )
                sidebarRow(
                    filter: .needsPull,
                    title: "待拉取更新",
                    icon: "arrow.down.left",
                    dotColor: store.behindReposCount > 0 ? AppTheme.statusSync : nil,
                    count: store.behindReposCount
                )
                sidebarRow(
                    filter: .favorites,
                    title: "星标常用",
                    icon: "star",
                    dotColor: nil,
                    count: store.favoriteReposCount
                )
            }

            // MARK: 2. 托管平台
            Section("远程平台") {
                ForEach(GitProvider.allCases) { provider in
                    let count = store.countForProvider(provider)
                    if count > 0 || provider == .github || provider == .gitlab || provider == .gitee || provider == .localOnly {
                        sidebarRow(
                            filter: .provider(provider),
                            title: provider.rawValue,
                            icon: provider.sfSymbol,
                            dotColor: nil,
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
                        dotColor: group.color,
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
                        Image(systemName: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("新建虚拟分组")
                }
            }

            // MARK: 4. 跨目录扫描根路径
            Section {
                if store.watchedDirectories.isEmpty {
                    Text("尚未添加扫描目录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.watchedDirectories) { dir in
                        sidebarRow(
                            filter: .rootDirectory(dir.path),
                            title: dir.displayName,
                            subtitle: dir.path,
                            icon: "folder",
                            dotColor: nil,
                            count: store.countForRootDirectory(dir.path)
                        )
                        .contextMenu {
                            Button {
                                ExternalLauncher.openInFinder(path: dir.path)
                            } label: {
                                Label("在 Finder 中显示", systemImage: "folder")
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
                                Label("移除扫描目录", systemImage: "trash")
                            }
                        }
                    }
                }

                Button {
                    store.promptAddDirectory()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.square.on.square")
                            .font(.system(size: 12))
                        Text("添加本地目录...")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            } header: {
                HStack {
                    Text("扫描根目录")
                    Spacer()
                    Button {
                        store.promptAddDirectory()
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("添加扫描目录")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 8) {
                    if store.isScanning {
                        ProgressView()
                            .controlSize(.mini)
                        Text("正在扫描仓库...")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Circle()
                            .fill(AppTheme.statusClean)
                            .frame(width: 6, height: 6)
                        Text("已索引 \(store.repositories.count) 个仓库")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        store.showSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("偏好设置与执行日志")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.bar)
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
        dotColor: Color?,
        count: Int
    ) -> some View {
        NavigationLink(value: filter) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 4)

                if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                }

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var newGroupSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("新建虚拟分组")
                .font(.headline)
            Text("按业务或主题归类不同目录下的 Git 仓库，不会移动磁盘上的真实目录。")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("分组名称（如：公司核心服务、AI 工具）", text: $newGroupName)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("图标")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(availableIcons, id: \.self) { icon in
                        Button {
                            newGroupIcon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 13))
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(newGroupIcon == icon ? AppTheme.elevatedSurface : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(newGroupIcon == icon ? AppTheme.selectedBorder : AppTheme.hairlineBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("标识色")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(availableColors, id: \.self) { colorHex in
                        let dummy = RepoGroup(name: "", icon: "", colorHex: colorHex)
                        Button {
                            newGroupColor = colorHex
                        } label: {
                            Circle()
                                .fill(dummy.color)
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: newGroupColor == colorHex ? 1.5 : 0)
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
                Button("创建") {
                    store.createGroup(name: newGroupName, icon: newGroupIcon, colorHex: newGroupColor)
                    newGroupName = ""
                    store.showNewGroupSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 360)
    }
}
