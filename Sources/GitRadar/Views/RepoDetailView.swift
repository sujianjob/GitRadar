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
    @State private var selectedFile: ChangedFile? = nil
    @State private var diffText: String = ""
    @State private var isLoadingDiff: Bool = false
    @State private var commitMessage: String = ""
    @State private var showNewBranchPopover: Bool = false
    @State private var newBranchName: String = ""
    @State private var isReadmeExpanded: Bool = false

    var isBusy: Bool {
        store.busyRepoIDs.contains(repo.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: 1. 紧凑头部（项目真实图标 + 名称 + 外部打开工具栏 + 分支与同步操作栏）
            headerSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.canvasBackground)

            Divider()

            // MARK: 2. 上方核心展示区：项目简介（截取 README 前面核心简介，支持展开全文）
            readmeOverviewSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.cardBackground)

            Divider()

            // MARK: 3. 下方工作区：变更 Diff / 提交历史 / 远程与分支
            HStack {
                Picker("", selection: $selectedTab) {
                    Text("工作区变更 (\(repo.changedFiles.count))").tag(InspectorTab.changes)
                    Text("提交历史 (\(repo.recentCommits.count))").tag(InspectorTab.commits)
                    Text("远程与分支 (\(repo.remotes.count))").tag(InspectorTab.remotes)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppTheme.canvasBackground)

            Divider()

            Group {
                switch selectedTab {
                case .changes:
                    changesAndDiffTab
                case .commits:
                    commitsTab
                case .remotes:
                    remotesAndBranchesTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: repo.id) { _, _ in
            isReadmeExpanded = false
            selectedFile = repo.changedFiles.first
            loadSelectedFileDiff()
        }
        .onChange(of: repo.changedFiles) { _, newFiles in
            if let current = selectedFile, newFiles.contains(where: { $0.id == current.id }) {
                loadSelectedFileDiff()
            } else {
                selectedFile = newFiles.first
                loadSelectedFileDiff()
            }
        }
        .onAppear {
            if selectedFile == nil {
                selectedFile = repo.changedFiles.first
            }
            loadSelectedFileDiff()
        }
    }

    // MARK: - 1. 紧凑头部与快捷栏
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                ProjectAvatarView(repo: repo, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(repo.name)
                            .font(.system(size: 16, weight: .bold))
                            .lineLimit(1)

                        Text(repo.techStack.rawValue)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(RoundedRectangle(cornerRadius: 4).fill(AppTheme.subtleSurface))
                            .foregroundStyle(.secondary)

                        if isBusy {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }

                    HStack(spacing: 5) {
                        Text(repo.displayPath)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button {
                            ExternalLauncher.copyToPasteboard(repo.path)
                            store.showBanner("已复制路径：\(repo.path)")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("复制本地路径")
                    }
                }

                Spacer()

                Button {
                    store.toggleFavorite(for: repo.id)
                } label: {
                    Image(systemName: repo.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 14))
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

            // 外部工具打开 + 分支与 Git 同步合并在一行紧凑工具条
            HStack(spacing: 6) {
                if let editor = store.preferredEditor {
                    Button {
                        ExternalLauncher.openRepository(path: repo.path, with: editor)
                    } label: {
                        Label(editor.name, systemImage: editor.sfSymbol)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if store.installedEditors.count > 1 {
                    Menu {
                        ForEach(store.installedEditors) { app in
                            Button {
                                ExternalLauncher.openRepository(path: repo.path, with: app)
                            } label: {
                                Label("用 \(app.name) 打开", systemImage: app.sfSymbol)
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 14)
                }

                if let term = store.preferredTerminal {
                    Button {
                        ExternalLauncher.openRepository(path: repo.path, with: term)
                    } label: {
                        Label(term.name, systemImage: term.sfSymbol)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    ExternalLauncher.openInFinder(path: repo.path)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("在 Finder 中打开")

                if let webURL = repo.primaryWebURL {
                    Button {
                        ExternalLauncher.openInBrowser(urlString: webURL)
                    } label: {
                        Image(systemName: "safari")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("打开远程网页 (\(repo.primaryProvider.rawValue))")
                }

                Spacer()

                // 分支切换（三次确认保护）
                Menu {
                    Section("切换本地分支（三次确认）") {
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
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                    }
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)
                .fixedSize()
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
                            Button("下一步（三次确认）") {
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

                if !repo.remotes.isEmpty {
                    Button("Fetch") {
                        store.requestFetchRepository(repo)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isBusy)

                    Button(repo.behindCount > 0 ? "Pull ↓\(repo.behindCount)" : "Pull") {
                        store.requestPullRepository(repo)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isBusy)

                    Button(repo.aheadCount > 0 ? "Push ↑\(repo.aheadCount)" : "Push") {
                        store.requestPushRepository(repo)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isBusy)
                }
            }
        }
    }

    // MARK: - 2. 上方项目简介（README 摘要截取 + 可展开全文）
    private var readmeOverviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "book.pages")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("项目简介")
                    .font(.system(size: 12, weight: .semibold))
                if let fileName = repo.readmeFileName {
                    Text("(\(fileName))")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let full = repo.readmeFullText, let excerpt = repo.readmeExcerpt, full.count > excerpt.count {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isReadmeExpanded.toggle()
                        }
                    } label: {
                        Text(isReadmeExpanded ? "收起简介" : "展开全文")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let excerpt = repo.readmeExcerpt, !excerpt.isEmpty {
                ScrollView {
                    Text(isReadmeExpanded ? (repo.readmeFullText ?? excerpt) : excerpt)
                        .font(.system(size: 11.5))
                        .lineSpacing(3.5)
                        .foregroundStyle(.primary.opacity(0.86))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: isReadmeExpanded ? 240 : 108)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppTheme.subtleSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppTheme.hairlineBorder, lineWidth: 1)
                )
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "doc.questionmark")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Text("该仓库根目录下暂未检测到 README.md 简介文档")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppTheme.subtleSurface)
                )
            }
        }
    }

    // MARK: - 3A. 变更文件列表 + 快捷提交（含三次确认） + Diff 预览
    private var changesAndDiffTab: some View {
        VStack(spacing: 0) {
            if repo.changedFiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(AppTheme.statusClean)
                    Text("工作区干净")
                        .font(.system(size: 13, weight: .semibold))
                    Text("当前没有未提交的修改或未跟踪文件")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 快速提交栏（接入三次确认）
                HStack(spacing: 8) {
                    TextField("输入 Commit Message（点击提交将进入三次安全确认）...", text: $commitMessage)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))

                    Button("提交") {
                        store.requestCommitAllChanges(
                            for: repo,
                            message: commitMessage,
                            andPush: false
                        ) {
                            commitMessage = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .controlSize(.small)
                    .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)

                    if !repo.remotes.isEmpty {
                        Button("提交并 Push") {
                            store.requestCommitAllChanges(
                                for: repo,
                                message: commitMessage,
                                andPush: true
                            ) {
                                commitMessage = ""
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppTheme.subtleSurface)

                Divider()

                VSplitView {
                    List(selection: $selectedFile) {
                        ForEach(repo.changedFiles) { file in
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
                            }
                            .tag(file)
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
                    .frame(minHeight: 100, idealHeight: 150)
                    .onChange(of: selectedFile) { _, _ in
                        loadSelectedFileDiff()
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Image(systemName: "doc.text")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(selectedFile?.path ?? "选择上方文件查看 Diff")
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if isLoadingDiff {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(AppTheme.subtleSurface)

                        Divider()

                        ScrollView([.vertical, .horizontal]) {
                            LazyVStack(alignment: .leading, spacing: 1) {
                                ForEach(Array(diffText.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                                    Text(line.isEmpty ? " " : line)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(diffLineColor(line))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 1)
                                        .background(diffLineBackground(line))
                                }
                            }
                            .padding(.vertical, 6)
                            .textSelection(.enabled)
                        }
                        .background(Color(nsColor: .textBackgroundColor))
                    }
                    .frame(minHeight: 150)
                }
            }
        }
    }

    private func loadSelectedFileDiff() {
        guard let file = selectedFile else {
            diffText = ""
            return
        }
        isLoadingDiff = true
        let repoPath = repo.path
        Task {
            let text = await GitService.fileDiff(at: repoPath, file: file)
            await MainActor.run {
                self.diffText = text
                self.isLoadingDiff = false
            }
        }
    }

    private func diffLineColor(_ line: String) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") {
            return .secondary
        } else if line.hasPrefix("+") {
            return AppTheme.statusClean
        } else if line.hasPrefix("-") {
            return AppTheme.statusDanger
        } else if line.hasPrefix("@@") {
            return AppTheme.statusSync
        }
        return .primary
    }

    private func diffLineBackground(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return AppTheme.statusClean.opacity(0.08)
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return AppTheme.statusDanger.opacity(0.08)
        } else if line.hasPrefix("@@") {
            return AppTheme.statusSync.opacity(0.06)
        }
        return .clear
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
                }

                Text(commit.subject)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)

                Text(commit.author)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
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
                                .textSelection(.enabled)
                        }
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
                }
            }

            if !repo.remoteBranches.isEmpty {
                Section("远程跟踪分支 (\(repo.remoteBranches.count))") {
                    ForEach(repo.remoteBranches, id: \.self) { rbr in
                        Text(rbr)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
