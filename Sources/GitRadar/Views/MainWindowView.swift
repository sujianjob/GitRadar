import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @ObservedObject var store: RadarStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 200, ideal: 225, max: 280)
        } detail: {
            HStack(spacing: 0) {
                // 中间主列表区域
                dashboardContent
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)

                // 右侧仓库详情与 README 简介面板（固定宽度并严守窗口内边界，绝不溢出裁剪）
                if store.showDetailInspector, let selectedRepo = store.selectedRepository {
                    Divider()
                    RepoDetailView(repo: selectedRepo, store: store)
                        .frame(width: 410)
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .toolbar {
            mainToolbar
        }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "搜索仓库、路径、分支、README 简介...")
        .sheet(isPresented: $store.showSettingsSheet) {
            SettingsSheetView(store: store)
        }
        .sheet(isPresented: $store.showFilterRulesSheet) {
            FilterRulesSheetView(store: store)
        }
        .sheet(item: $store.pendingConfirmation) { confirmation in
            TripleConfirmSheet(
                confirmation: confirmation,
                onCancel: {
                    store.pendingConfirmation = nil
                },
                onConfirmedExecute: {
                    let action = confirmation.action
                    store.pendingConfirmation = nil
                    Task {
                        await action()
                    }
                }
            )
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - 主看板内容
    private var dashboardContent: some View {
        VStack(spacing: 0) {
            // 1. 借鉴 Linear / Fork 风格的紧凑状态分段过滤条 + 批量操作与排序
            topControlHeader
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppTheme.canvasBackground)

            Divider()

            // 2. 状态反馈横幅
            if let banner = store.statusBannerMessage {
                HStack(spacing: 8) {
                    Circle()
                        .fill(store.statusBannerIsError ? AppTheme.statusDanger : AppTheme.statusClean)
                        .frame(width: 7, height: 7)
                    Text(banner)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        store.statusBannerMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(AppTheme.subtleSurface)
            }

            // 3. 仓库列表主体（卡片网格 or 表格视图）
            if store.filteredRepositories.isEmpty {
                emptyStateView
            } else {
                switch store.viewMode {
                case .grid:
                    gridRepositoriesView
                case .table:
                    tableRepositoriesView
                }
            }
        }
    }

    // MARK: - 紧凑型专业顶部状态栏（左侧展示当前视图标题与计数，消除与侧边栏分类重复）
    private var topControlHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: currentFilterIcon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(currentFilterTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("\(store.filteredRepositories.count)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(AppTheme.subtleSurface)
                        )
                        .overlay(
                            Capsule()
                                .stroke(AppTheme.hairlineBorder, lineWidth: 1)
                        )
                }

                Spacer()

                // 过滤规则入口按钮（直接打开设置中的「过滤管理」Tab）
                Button {
                    store.openSettings(tab: .filter)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: store.excludedRepositories.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                            .font(.system(size: 10.5))
                            .foregroundStyle(store.excludedRepositories.isEmpty ? Color.secondary : AppTheme.accent)
                        Text(store.excludedRepositories.isEmpty ? "过滤规则" : "已过滤 (\(store.excludedRepositories.count))")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                .help("打开设置 → 过滤管理")

                // 批量操作按钮（接入三次风险确认）
                Button {
                    store.requestBatchFetchAllVisible()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10.5))
                        Text("批量 Fetch")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                .help("并发拉取远程引用（需三次确认）")

                if store.behindReposCount > 0 {
                    Button {
                        store.requestBatchPullAllBehind()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.to.line")
                                .font(.system(size: 10.5))
                            Text("一键 Pull (\(store.behindReposCount))")
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
                    .help("批量更新落后仓库（需三次确认）")
                }

                Picker("", selection: $store.sortOption) {
                    ForEach(RepoSortOption.allCases, id: \.self) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 145)
                .onChange(of: store.sortOption) { _, _ in
                    store.saveConfig()
                }
            }
        }
    }

    private var currentFilterTitle: String {
        switch store.selectedFilter {
        case .all:
            return "全部仓库"
        case .dirty:
            return "未提交改动"
        case .unpushed:
            return "待推送提交"
        case .needsPull:
            return "待拉取更新"
        case .favorites:
            return "星标常用"
        case .provider(let provider):
            return provider.rawValue
        case .group(let groupID):
            return store.groups.first(where: { $0.id == groupID })?.name ?? "虚拟分组"
        case .rootDirectory(let path):
            return URL(fileURLWithPath: path).lastPathComponent
        case .domain(let host):
            return host
        case .organization(let host, let org):
            return "\(host)/\(org)"
        }
    }

    private var currentFilterIcon: String {
        switch store.selectedFilter {
        case .all:
            return "square.stack.3d.up"
        case .dirty:
            return "pencil.line"
        case .unpushed:
            return "arrow.up.right"
        case .needsPull:
            return "arrow.down.left"
        case .favorites:
            return "star"
        case .provider(let provider):
            return provider.sfSymbol
        case .group(let groupID):
            return store.groups.first(where: { $0.id == groupID })?.icon ?? "folder"
        case .rootDirectory:
            return "folder"
        case .domain:
            return "network"
        case .organization:
            return "person.2"
        }
    }

    // MARK: - 视图模式 1：响应式卡片网格
    private var gridRepositoriesView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 310, maximum: 460), spacing: 10)],
                spacing: 10
            ) {
                ForEach(store.filteredRepositories) { repo in
                    RepoCardView(
                        repo: repo,
                        isSelected: store.selectedRepoID == repo.id,
                        isBusy: store.busyRepoIDs.contains(repo.id),
                        store: store
                    )
                    .onTapGesture {
                        store.selectedRepoID = repo.id
                        if !store.showDetailInspector {
                            store.showDetailInspector = true
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    // MARK: - 视图模式 2：紧凑表格视图（带真实项目图标）
    private var tableRepositoriesView: some View {
        Table(store.filteredRepositories, selection: $store.selectedRepoID) {
            TableColumn("项目") { repo in
                HStack(spacing: 8) {
                    ProjectAvatarView(repo: repo, size: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(repo.name)
                                .font(.system(size: 12, weight: .semibold))
                            if repo.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(AppTheme.statusDirty)
                            }
                        }
                        Text(repo.displayPath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .width(min: 190, ideal: 230)

            TableColumn("平台 / Remote") { repo in
                VStack(alignment: .leading, spacing: 1) {
                    Text(repo.primaryProvider.rawValue)
                        .font(.system(size: 11, weight: .medium))
                    if let slug = repo.primaryRemoteSlug, !slug.isEmpty {
                        Text(slug)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .width(min: 120, ideal: 150)

            TableColumn("当前分支") { repo in
                HStack(spacing: 4) {
                    Text(repo.currentBranch)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    if repo.aheadCount > 0 {
                        Text("↑\(repo.aheadCount)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.statusSync)
                    }
                    if repo.behindCount > 0 {
                        Text("↓\(repo.behindCount)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.statusSync)
                    }
                }
            }
            .width(min: 105, ideal: 130)

            TableColumn("状态") { repo in
                HStack(spacing: 5) {
                    Circle()
                        .fill(repo.healthState.color)
                        .frame(width: 6, height: 6)
                    Text(repo.healthState.rawValue)
                        .font(.system(size: 11, weight: .medium))
                    if repo.totalUncommittedCount > 0 {
                        Text("(\(repo.totalUncommittedCount))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 95, ideal: 115)

            TableColumn("项目简介 / 最近提交") { repo in
                Text(repo.readmeExcerpt?.components(separatedBy: .newlines).first ?? repo.lastCommitMessage ?? "—")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 150, ideal: 220)

            TableColumn("操作") { repo in
                HStack(spacing: 8) {
                    Button {
                        ExternalLauncher.openInFinder(path: repo.path)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("在 Finder 中打开")

                    if let webURL = repo.primaryWebURL {
                        Button {
                            ExternalLauncher.openInBrowser(urlString: webURL)
                        } label: {
                            Image(systemName: "safari")
                        }
                        .buttonStyle(.borderless)
                        .help("打开远程主页")
                    }
                }
            }
            .width(min: 65, ideal: 80)
        }
        .contextMenu(forSelectionType: String.self) { items in
            if let firstID = items.first,
               let repo = store.repositories.first(where: { $0.id == firstID }) {
                Button {
                    ExternalLauncher.openInVSCode(path: repo.path)
                } label: {
                    Label("在 VS Code 中打开", systemImage: "chevron.left.forwardslash.chevron.right")
                }

                Button {
                    ExternalLauncher.openInAntigravity(path: repo.path)
                } label: {
                    Label("在 Antigravity IDE 中打开", systemImage: "sparkles")
                }

                Button {
                    ExternalLauncher.openInFinder(path: repo.path)
                } label: {
                    Label("在 Finder 中显示", systemImage: "folder")
                }

                if let webURL = repo.primaryWebURL {
                    Button {
                        ExternalLauncher.openInBrowser(urlString: webURL)
                    } label: {
                        Label("打开远程主页 (\(repo.primaryProvider.rawValue))", systemImage: "safari")
                    }
                }
            }
        }
    }

    // MARK: - 空状态引导视图
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            if store.repositories.isEmpty {
                Text("尚未添加 Git 扫描目录")
                    .font(.headline)
                Text("添加任意本地开发目录，自动发现并管理 GitHub、GitLab、Gitee、自建 Git 等所有仓库")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                HStack(spacing: 10) {
                    Button {
                        store.promptAddDirectory()
                    } label: {
                        Label("添加扫描目录...", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        store.addQuickDirectory("~/AI")
                    } label: {
                        Text("扫描 ~/AI 目录")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            } else {
                Text("没有匹配的仓库")
                    .font(.subheadline.bold())
                Button("重置筛选条件") {
                    store.selectedFilter = .all
                    store.searchText = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    // MARK: - 顶部系统工具栏
    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                store.promptAddDirectory()
            } label: {
                Label("添加目录", systemImage: "folder.badge.plus")
            }
            .help("添加扫描目录或仓库 (⌘O)")

            Button {
                Task { await store.scanAndRefreshAll() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .help("重新扫描并刷新全部状态 (⌘R)")
            .disabled(store.isScanning)

            Picker("视图", selection: $store.viewMode) {
                ForEach(DashboardViewMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("切换卡片 / 表格视图")
            .onChange(of: store.viewMode) { _, _ in
                store.saveConfig()
            }

            Button {
                withAnimation {
                    store.showDetailInspector.toggle()
                }
            } label: {
                Label("详情栏", systemImage: "sidebar.right")
            }
            .help("显示/隐藏右侧详情栏")

            Button {
                store.openSettings(tab: store.selectedSettingsTab)
            } label: {
                Label("设置", systemImage: "gearshape")
            }
            .help("打开设置与关于我们 (⌘,)")
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { @MainActor in
                        store.addQuickDirectory(url.path)
                    }
                }
            }
        }
        return handled
    }
}
