import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @ObservedObject var store: RadarStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            HSplitView {
                // 中间主看板区域
                dashboardContent
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)

                // 右侧仓库详情与操作面板
                if store.showDetailInspector, let selectedRepo = store.selectedRepository {
                    RepoDetailView(repo: selectedRepo, store: store)
                        .frame(minWidth: 360, idealWidth: 420, maxWidth: 540, maxHeight: .infinity)
                }
            }
        }
        .toolbar {
            mainToolbar
        }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "搜索仓库名、目录、分支、平台或提交信息...")
        .sheet(isPresented: $store.showSettingsSheet) {
            SettingsSheetView(store: store)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - 主看板内容
    private var dashboardContent: some View {
        VStack(spacing: 0) {
            // 1. 顶部全景 KPI 雷达指标卡
            kpiMetricsStrip
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // 2. 二级控制栏（当前筛选标题 + 排序 + 批量操作）
            subHeaderBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.04))

            Divider()

            // 3. 提示横幅（如有）
            if let banner = store.statusBannerMessage {
                HStack(spacing: 8) {
                    Image(systemName: store.statusBannerIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(store.statusBannerIsError ? .red : .green)
                    Text(banner)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        store.statusBannerMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(store.statusBannerIsError ? Color.red.opacity(0.12) : Color.accentColor.opacity(0.10))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 4. 仓库列表主体（卡片网格 or 表格视图）
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

    // MARK: - 顶部 KPI 雷达卡片条
    private var kpiMetricsStrip: some View {
        HStack(spacing: 10) {
            kpiCard(
                title: "监控仓库总数",
                value: "\(store.repositories.count)",
                subtitle: "\(store.watchedDirectories.count) 个根目录",
                icon: "dot.radiowaves.left.and.right",
                color: .blue,
                isActive: store.selectedFilter == .all
            ) {
                store.selectedFilter = .all
            }

            kpiCard(
                title: "未提交改动",
                value: "\(store.dirtyReposCount)",
                subtitle: "工作区有变更",
                icon: "pencil.circle.fill",
                color: .orange,
                isActive: store.selectedFilter == .dirty
            ) {
                store.selectedFilter = .dirty
            }

            kpiCard(
                title: "待推送 (Ahead)",
                value: "\(store.unpushedReposCount)",
                subtitle: "领先远程分支",
                icon: "arrow.up.circle.fill",
                color: .indigo,
                isActive: store.selectedFilter == .unpushed
            ) {
                store.selectedFilter = .unpushed
            }

            kpiCard(
                title: "待拉取 (Behind)",
                value: "\(store.behindReposCount)",
                subtitle: "落后远程分支",
                icon: "arrow.down.circle.fill",
                color: .cyan,
                isActive: store.selectedFilter == .needsPull
            ) {
                store.selectedFilter = .needsPull
            }

            kpiCard(
                title: "已同步健康",
                value: "\(store.cleanReposCount)",
                subtitle: "工作区干净",
                icon: "checkmark.seal.fill",
                color: .green,
                isActive: false
            ) {
                store.selectedFilter = .all
            }
        }
    }

    private func kpiCard(
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        color: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(value)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActive ? color : Color.secondary.opacity(0.15), lineWidth: isActive ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 二级控制条
    private var subHeaderBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text(currentFilterTitle)
                    .font(.system(size: 13, weight: .bold))
                Text("(\(store.filteredRepositories.count))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // 批量操作按钮
            Button {
                Task { await store.batchFetchAllVisible() }
            } label: {
                Label("批量 Fetch 远程", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("并发执行 git fetch 更新当前列表中所有远程仓库的状态")

            if store.behindReposCount > 0 {
                Button {
                    Task { await store.batchPullAllBehind() }
                } label: {
                    Label("一键 Pull 待更新 (\(store.behindReposCount))", systemImage: "arrow.down.to.line")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.cyan)
                .help("自动对工作区干净且落后的仓库执行 git pull")
            }

            Divider()
                .frame(height: 14)

            // 排序选择器
            Picker("排序", selection: $store.sortOption) {
                ForEach(RepoSortOption.allCases, id: \.self) { opt in
                    Text(opt.rawValue).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 155)
            .onChange(of: store.sortOption) { _, _ in
                store.saveConfig()
            }
        }
    }

    private var currentFilterTitle: String {
        if case .group(let id) = store.selectedFilter,
           let grp = store.groups.first(where: { $0.id == id }) {
            return "分组：\(grp.name)"
        }
        return store.selectedFilter.title
    }

    // MARK: - 视图模式 1：响应式卡片网格
    private var gridRepositoriesView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 320, maximum: 480), spacing: 12)],
                spacing: 12
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
            .padding(16)
        }
    }

    // MARK: - 视图模式 2：紧凑高密度表格视图
    private var tableRepositoriesView: some View {
        Table(store.filteredRepositories, selection: $store.selectedRepoID) {
            TableColumn("仓库名称") { repo in
                HStack(spacing: 8) {
                    if repo.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(repo.name)
                            .font(.system(size: 12, weight: .semibold))
                        Text(repo.displayPath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .width(min: 180, ideal: 220)

            TableColumn("平台 / Remote") { repo in
                HStack(spacing: 5) {
                    Image(systemName: repo.primaryProvider.sfSymbol)
                        .foregroundStyle(repo.primaryProvider.badgeColor)
                        .font(.system(size: 11))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(repo.primaryProvider.rawValue)
                            .font(.system(size: 11, weight: .medium))
                        if let slug = repo.primaryRemoteSlug, !slug.isEmpty {
                            Text(slug)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .width(min: 130, ideal: 160)

            TableColumn("当前分支") { repo in
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(repo.currentBranch)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    if repo.aheadCount > 0 {
                        Text("↑\(repo.aheadCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.blue)
                    }
                    if repo.behindCount > 0 {
                        Text("↓\(repo.behindCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.cyan)
                    }
                }
            }
            .width(min: 110, ideal: 140)

            TableColumn("状态") { repo in
                HStack(spacing: 5) {
                    Image(systemName: repo.healthState.sfSymbol)
                        .foregroundStyle(repo.healthState.color)
                        .font(.system(size: 11))
                    Text(repo.healthState.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(repo.healthState.color)
                    if repo.totalUncommittedCount > 0 {
                        Text("(\(repo.totalUncommittedCount))")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 100, ideal: 120)

            TableColumn("最后提交") { repo in
                VStack(alignment: .leading, spacing: 1) {
                    Text(repo.lastCommitMessage ?? "无提交")
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Text(repo.lastCommitRelativeTime ?? "")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 150, ideal: 220)

            TableColumn("快捷打开") { repo in
                HStack(spacing: 6) {
                    if let editor = store.preferredEditor {
                        Button {
                            ExternalLauncher.openRepository(path: repo.path, with: editor)
                        } label: {
                            Image(systemName: editor.sfSymbol)
                        }
                        .buttonStyle(.borderless)
                        .help("在 \(editor.name) 中打开")
                    }
                    if let term = store.preferredTerminal {
                        Button {
                            ExternalLauncher.openRepository(path: repo.path, with: term)
                        } label: {
                            Image(systemName: term.sfSymbol)
                        }
                        .buttonStyle(.borderless)
                        .help("在 \(term.name) 中打开")
                    }
                    Button {
                        ExternalLauncher.openInFinder(path: repo.path)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("在 Finder 中打开")

                    if let web = repo.primaryWebURL {
                        Button {
                            ExternalLauncher.openInBrowser(urlString: web)
                        } label: {
                            Image(systemName: "safari")
                        }
                        .buttonStyle(.borderless)
                        .help("打开远程网页")
                    }
                }
            }
            .width(min: 95, ideal: 110)
        }
    }

    // MARK: - 空状态引导视图
    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor.opacity(0.75))

            if store.repositories.isEmpty {
                Text("欢迎使用 GitRadar 本地仓库全景雷达")
                    .font(.title3.bold())
                Text("添加本机任意开发目录（支持多个分散目录），自动发现并管理 GitHub、GitLab、Gitee、自建 Git 等所有仓库")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)

                HStack(spacing: 10) {
                    Button {
                        store.promptAddDirectory()
                    } label: {
                        Label("选择文件夹添加扫描...", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        store.addQuickDirectory("~/AI")
                    } label: {
                        Label("一键扫描 ~/AI 目录", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.top, 4)
            } else {
                Text("没有匹配的 Git 仓库")
                    .font(.headline)
                Text("请尝试清除搜索关键词或切换左侧过滤条件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("重置筛选条件") {
                    store.selectedFilter = .all
                    store.searchText = ""
                }
                .buttonStyle(.bordered)
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
            .help("添加根目录或单个 Git 仓库 (⌘O)")

            Button {
                Task { await store.scanAndRefreshAll() }
            } label: {
                Label("刷新全部", systemImage: "arrow.clockwise")
            }
            .help("重新扫描并刷新所有仓库状态 (⌘R)")
            .disabled(store.isScanning)

            Picker("视图", selection: $store.viewMode) {
                ForEach(DashboardViewMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("切换卡片视图 / 表格视图")
            .onChange(of: store.viewMode) { _, _ in
                store.saveConfig()
            }

            Button {
                withAnimation {
                    store.showDetailInspector.toggle()
                }
            } label: {
                Label("详情面板", systemImage: "sidebar.right")
            }
            .help("显示/隐藏右侧仓库详情检查器")
        }
    }

    // MARK: - 拖拽文件夹添加支持
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
