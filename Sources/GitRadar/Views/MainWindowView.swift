import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @ObservedObject var store: RadarStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 200, ideal: 225, max: 280)
        } detail: {
            HSplitView {
                // 中间主列表区域
                dashboardContent
                    .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)

                // 右侧仓库详情与 README 简介面板
                if store.showDetailInspector, let selectedRepo = store.selectedRepository {
                    RepoDetailView(repo: selectedRepo, store: store)
                        .frame(minWidth: 380, idealWidth: 440, maxWidth: 560, maxHeight: .infinity)
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

    // MARK: - 紧凑型专业顶部状态栏（替代原 AI 彩虹大卡片）
    private var topControlHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                statusFilterPill(
                    title: "全部",
                    count: store.repositories.count,
                    dotColor: nil,
                    isActive: store.selectedFilter == .all
                ) {
                    store.selectedFilter = .all
                }

                statusFilterPill(
                    title: "未提交改动",
                    count: store.dirtyReposCount,
                    dotColor: AppTheme.statusDirty,
                    isActive: store.selectedFilter == .dirty
                ) {
                    store.selectedFilter = .dirty
                }

                statusFilterPill(
                    title: "待推送",
                    count: store.unpushedReposCount,
                    dotColor: AppTheme.statusSync,
                    isActive: store.selectedFilter == .unpushed
                ) {
                    store.selectedFilter = .unpushed
                }

                statusFilterPill(
                    title: "待拉取",
                    count: store.behindReposCount,
                    dotColor: AppTheme.statusSync,
                    isActive: store.selectedFilter == .needsPull
                ) {
                    store.selectedFilter = .needsPull
                }

                statusFilterPill(
                    title: "已同步",
                    count: store.cleanReposCount,
                    dotColor: AppTheme.statusClean,
                    isActive: false
                ) {
                    store.selectedFilter = .all
                }

                Spacer()

                // 批量操作按钮（接入三次风险确认）
                Button {
                    store.requestBatchFetchAllVisible()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10.5))
                        Text("批量 Fetch")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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

    private func statusFilterPill(
        title: String,
        count: Int,
        dotColor: Color?,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                }
                Text(title)
                    .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? .primary : .secondary)
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isActive ? .primary : .secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? AppTheme.elevatedSurface : AppTheme.subtleSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? AppTheme.selectedBorder.opacity(0.65) : AppTheme.hairlineBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
                }
            }
            .width(min: 80, ideal: 95)
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
