import SwiftUI

struct RepoDetailView: View {
    let repo: GitRepository
    @ObservedObject var store: RadarStore

    enum InspectorTab: String, CaseIterable {
        case changes = "工作区变更"
        case commits = "提交记录"
        case remotes = "远程与分支"
    }

    @State private var selectedTab: InspectorTab = .changes
    @State private var commitMessage: String = ""
    @State private var showNewBranchPopover: Bool = false
    @State private var newBranchName: String = ""
    @State private var isReadmeExpanded: Bool = false

    var isBusy: Bool {
        store.busyRepoIDs.contains(repo.id)
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // MARK: 1. 顶部仓库信息与右上角操作栏（带充足右边距）
                headerSection
                    .padding(.leading, 16)
                    .padding(.trailing, 20)
                    .padding(.vertical, 12)
                    .frame(width: geo.size.width)
                    .background(AppTheme.canvasBackground)

                Divider()

                // MARK: 2. 上方 README 简介区域（至少占右侧栏总高度的 2/5，无 README 时留空）
                readmeOverviewSection
                    .frame(width: geo.size.width, height: max(220, geo.size.height * 0.42))
                    .background(AppTheme.cardBackground)

                Divider()

                // MARK: 3. 下方标签页切换器（带充足右边距）
                HStack {
                    Picker("", selection: $selectedTab) {
                        Text("变更 (\(repo.changedFiles.count))").tag(InspectorTab.changes)
                        Text("提交 (\(repo.recentCommits.count))").tag(InspectorTab.commits)
                        Text("远程 (\(repo.remotes.count))").tag(InspectorTab.remotes)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.leading, 16)
                .padding(.trailing, 20)
                .padding(.vertical, 8)
                .frame(width: geo.size.width)
                .background(AppTheme.canvasBackground)

                Divider()

                // MARK: 4. 下方列表内容
                Group {
                    switch selectedTab {
                    case .changes:
                        changesListTab
                    case .commits:
                        commitsTab
                    case .remotes:
                        remotesAndBranchesTab
                    }
                }
                .frame(width: geo.size.width)
                .frame(maxHeight: .infinity)
            }
        }
        .onChange(of: repo.id) { _, _ in
            isReadmeExpanded = false
        }
    }

    // MARK: - 1. 头部：右上角放置 Fetch / Pull / Push 按钮，第二行放置 Finder / 远程主页 / 分支
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 第一行：左侧项目图标+名称，右上角显示 Fetch / Pull / Push 按钮
            HStack(alignment: .top, spacing: 10) {
                ProjectAvatarView(repo: repo, size: 38)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(repo.name)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if isBusy {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }

                    HStack(spacing: 4) {
                        Text(repo.displayPath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button {
                            ExternalLauncher.copyToPasteboard(repo.path)
                            store.showBanner("已复制路径：\(repo.path)")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("复制本地路径")
                    }
                }

                Spacer(minLength: 6)

                // 右上角：Fetch / Pull / Push 操作按钮组
                if !repo.remotes.isEmpty {
                    HStack(spacing: 5) {
                        compactActionButton(title: "Fetch", icon: "arrow.triangle.2.circlepath", disabled: isBusy) {
                            store.requestFetchRepository(repo)
                        }

                        compactActionButton(
                            title: repo.behindCount > 0 ? "Pull ↓\(repo.behindCount)" : "Pull",
                            icon: "arrow.down.to.line",
                            highlightColor: repo.behindCount > 0 ? AppTheme.statusSync : nil,
                            disabled: isBusy
                        ) {
                            store.requestPullRepository(repo)
                        }

                        compactActionButton(
                            title: repo.aheadCount > 0 ? "Push ↑\(repo.aheadCount)" : "Push",
                            icon: "arrow.up.to.line",
                            highlightColor: repo.aheadCount > 0 ? AppTheme.statusSync : nil,
                            disabled: isBusy
                        ) {
                            store.requestPushRepository(repo)
                        }
                    }
                }
            }

            // 第二行：Finder、远程主页、分支切换、收藏与分组
            HStack(spacing: 6) {
                compactActionButton(title: "Finder", icon: "folder") {
                    ExternalLauncher.openInFinder(path: repo.path)
                }

                if let webURL = repo.primaryWebURL {
                    compactActionButton(title: "远程主页", icon: "safari") {
                        ExternalLauncher.openInBrowser(urlString: webURL)
                    }
                }

                // 分支切换菜单
                Menu {
                    Section("切换本地分支") {
                        ForEach(repo.localBranches, id: \.self) { br in
                            Button {
                                guard br != repo.currentBranch else { return }
                                store.requestCheckoutBranch(for: repo, branch: br)
                            } label: {
                                HStack {
                                    Text(br)
                                    if br == repo.currentBranch {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        showNewBranchPopover = true
                    } label: {
                        Label("新建并切换分支...", systemImage: "plus")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10))
                        Text(repo.currentBranch)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                    }
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)
                .frame(maxWidth: 130, alignment: .leading)
                .popover(isPresented: $showNewBranchPopover) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("新建并切换分支 (git checkout -b)")
                            .font(.caption.bold())
                        TextField("新分支名称，如 feat/new-ui", text: $newBranchName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                        HStack {
                            Spacer()
                            Button("取消") { showNewBranchPopover = false }
                                .controlSize(.small)
                            Button("创建") {
                                let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !name.isEmpty else { return }
                                showNewBranchPopover = false
                                newBranchName = ""
                                store.requestCheckoutBranch(for: repo, branch: name, createNew: true)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(12)
                }

                Spacer(minLength: 4)

                Button {
                    store.toggleFavorite(for: repo.id)
                } label: {
                    Image(systemName: repo.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 13))
                        .foregroundStyle(repo.isFavorite ? AppTheme.statusDirty : .secondary)
                }
                .buttonStyle(.plain)
                .help("星标收藏")

                Menu {
                    ForEach(store.groups) { grp in
                        let selected = repo.groupIDs.contains(grp.id)
                        Button {
                            store.toggleGroup(grp.id, for: repo.id)
                        } label: {
                            Label(grp.name, systemImage: selected ? "checkmark.circle.fill" : "circle")
                        }
                    }
                    Divider()
                    Button {
                        store.showNewGroupSheet = true
                    } label: {
                        Label("新建分组...", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "tag")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("归入虚拟分组")
            }
        }
    }

    private func compactActionButton(
        title: String,
        icon: String,
        highlightColor: Color? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3.5) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(highlightColor ?? .secondary)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(highlightColor ?? Color.primary.opacity(0.88))
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(AppTheme.subtleSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(highlightColor?.opacity(0.45) ?? AppTheme.hairlineBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: true)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
    }

    // MARK: - 2. 上方 README 简介区域（占 2/5 高度；若无 README 则直接留空）
    @ViewBuilder
    private var readmeOverviewSection: some View {
        if let excerpt = repo.readmeExcerpt, !excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "book.pages")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("项目简介")
                        .font(.system(size: 12, weight: .semibold))
                    if let fileName = repo.readmeFileName {
                        Text(fileName)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let full = repo.readmeFullText, full.count > excerpt.count {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isReadmeExpanded.toggle()
                            }
                        } label: {
                            Text(isReadmeExpanded ? "收起全文" : "展开全文")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                    }
                }

                ScrollView {
                    Text(isReadmeExpanded ? (repo.readmeFullText ?? excerpt) : excerpt)
                        .font(.system(size: 12))
                        .lineSpacing(4)
                        .foregroundStyle(Color.primary.opacity(0.86))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                }
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppTheme.subtleSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppTheme.hairlineBorder, lineWidth: 1)
                )
            }
            .padding(.leading, 16)
            .padding(.trailing, 20)
            .padding(.vertical, 12)
        } else {
            // 项目没有 README 时完全留空，不显示任何“未检测到 xxx”提示文字
            Color.clear
        }
    }

    // MARK: - 3A. 工作区变更列表
    private var changesListTab: some View {
        VStack(spacing: 0) {
            if repo.changedFiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 26))
                        .foregroundStyle(AppTheme.statusClean)
                    Text("工作区干净")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("没有未提交的修改或未跟踪文件")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 快速提交栏（带充足右边距）
                HStack(spacing: 6) {
                    TextField("输入提交信息 (Commit Message)...", text: $commitMessage)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))

                    compactActionButton(
                        title: "提交",
                        icon: "checkmark.circle",
                        highlightColor: AppTheme.accent,
                        disabled: commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy
                    ) {
                        store.requestCommitAllChanges(
                            for: repo,
                            message: commitMessage,
                            andPush: false
                        ) {
                            commitMessage = ""
                        }
                    }

                    if !repo.remotes.isEmpty {
                        compactActionButton(
                            title: "提交并 Push",
                            icon: "arrow.up.circle",
                            disabled: commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy
                        ) {
                            store.requestCommitAllChanges(
                                for: repo,
                                message: commitMessage,
                                andPush: true
                            ) {
                                commitMessage = ""
                            }
                        }
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, 20)
                .padding(.vertical, 8)
                .background(AppTheme.subtleSurface)

                Divider()

                List(repo.changedFiles) { file in
                    HStack(spacing: 8) {
                        Text(file.badgeText)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .frame(width: 20, height: 16)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(file.badgeColor.opacity(0.15))
                            )
                            .foregroundStyle(file.badgeColor)

                        Text(file.path)
                            .font(.system(size: 11.5, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Text(file.statusDescription)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    .padding(.trailing, 8)
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button {
                            let fullPath = (repo.path as NSString).appendingPathComponent(file.path)
                            ExternalLauncher.openInFinder(path: fullPath)
                        } label: {
                            Label("在 Finder 中定位文件", systemImage: "folder")
                        }
                        Divider()
                        Button(role: .destructive) {
                            store.requestDiscardFile(in: repo, file: file)
                        } label: {
                            Label("放弃此文件修改（需三次确认）", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }
        }
    }

    // MARK: - 3B. 提交历史
    private var commitsTab: some View {
        List(repo.recentCommits) { commit in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(commit.shortHash)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.subtleSurface)
                        )
                        .foregroundStyle(.secondary)

                    if !commit.refs.isEmpty {
                        Text(commit.refs)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(RoundedRectangle(cornerRadius: 4).fill(AppTheme.subtleSurface))
                            .foregroundStyle(AppTheme.statusSync)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(commit.relativeDate)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }

                Text(commit.subject)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)

                Text(commit.author)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 8)
            .padding(.vertical, 3)
            .contextMenu {
                Button {
                    ExternalLauncher.copyToPasteboard(commit.hash)
                    store.showBanner("已复制 Commit Hash：\(commit.shortHash)")
                } label: {
                    Label("复制完整 Commit Hash", systemImage: "doc.on.doc")
                }
                Button {
                    ExternalLauncher.copyToPasteboard(commit.subject)
                } label: {
                    Label("复制提交信息", systemImage: "text.quote")
                }
            }
        }
    }

    // MARK: - 3C. 远程仓库与分支列表
    private var remotesAndBranchesTab: some View {
        List {
            Section("远程地址 (Remotes)") {
                if repo.remotes.isEmpty {
                    Text("此仓库尚未配置任何远程地址 (git remote)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(repo.remotes) { remote in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(remote.name)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))

                                Text(remote.provider.rawValue)
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(AppTheme.subtleSurface))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Button {
                                    ExternalLauncher.copyToPasteboard(remote.fetchURL)
                                    store.showBanner("已复制远程地址：\(remote.fetchURL)")
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)

                                if let web = remote.webURL {
                                    Button {
                                        ExternalLauncher.openInBrowser(urlString: web)
                                    } label: {
                                        Image(systemName: "safari")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }

                            Text(remote.fetchURL)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        .padding(.trailing, 8)
                        .padding(.vertical, 3)
                    }
                }
            }

            Section("本地分支 (\(repo.localBranches.count))") {
                ForEach(repo.localBranches, id: \.self) { br in
                    HStack {
                        Circle()
                            .fill(br == repo.currentBranch ? AppTheme.statusClean : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                        Text(br)
                            .font(.system(size: 11.5, weight: br == repo.currentBranch ? .semibold : .regular, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        if br != repo.currentBranch {
                            Button("切换") {
                                store.requestCheckoutBranch(for: repo, branch: br)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        } else {
                            Text("当前")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.trailing, 8)
                }
            }

            if !repo.remoteBranches.isEmpty {
                Section("远程跟踪分支 (\(repo.remoteBranches.count))") {
                    ForEach(repo.remoteBranches, id: \.self) { rbr in
                        Text(rbr)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.trailing, 8)
                    }
                }
            }
        }
    }
}
