import SwiftUI

struct RepoDetailView: View {
    let repo: GitRepository
    @ObservedObject var store: RadarStore

    enum InspectorTab: String, CaseIterable {
        case changes = "变更与 Diff"
        case commits = "最近提交"
        case remotes = "远程与分支"
    }

    @State private var selectedTab: InspectorTab = .changes
    @State private var selectedFile: ChangedFile? = nil
    @State private var diffText: String = ""
    @State private var isLoadingDiff: Bool = false
    @State private var commitMessage: String = ""
    @State private var showNewBranchPopover: Bool = false
    @State private var newBranchName: String = ""

    var isBusy: Bool {
        store.busyRepoIDs.contains(repo.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: 1. 顶部仓库概览头
            headerSection
                .padding(16)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // MARK: 2. 外部工具联动与 Git 快捷操作栏
            actionToolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.05))

            Divider()

            // MARK: 3. 标签页切换器
            Picker("", selection: $selectedTab) {
                Text("变更与 Diff (\(repo.changedFiles.count))").tag(InspectorTab.changes)
                Text("最近提交 (\(repo.recentCommits.count))").tag(InspectorTab.commits)
                Text("远程与分支 (\(repo.remotes.count))").tag(InspectorTab.remotes)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // MARK: 4. 标签页主体内容
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

    // MARK: - 1. Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(repo.primaryProvider.badgeColor.opacity(0.16))
                        .frame(width: 40, height: 40)
                    Image(systemName: repo.primaryProvider.sfSymbol)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(repo.primaryProvider.badgeColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(repo.name)
                            .font(.system(size: 18, weight: .bold))
                            .lineLimit(1)

                        Text(repo.primaryProvider.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(repo.primaryProvider.badgeColor.opacity(0.15)))
                            .foregroundStyle(repo.primaryProvider.badgeColor)

                        if isBusy {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    HStack(spacing: 6) {
                        Text(repo.displayPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button {
                            ExternalLauncher.copyToPasteboard(repo.path)
                            store.showBanner("已复制路径：\(repo.path)")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("复制完整本地路径")
                    }
                }

                Spacer()

                // 收藏按钮
                Button {
                    store.toggleFavorite(for: repo.id)
                } label: {
                    Image(systemName: repo.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 15))
                        .foregroundStyle(repo.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help(repo.isFavorite ? "取消星标收藏" : "设为星标收藏")

                // 分组管理下拉
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
                        Label("新建虚拟分组...", systemImage: "plus.circle")
                    }
                } label: {
                    Label("分组", systemImage: "tag")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            // 外部启动器按钮栏（IDE / 终端 / Finder / 远程网页）
            HStack(spacing: 8) {
                if let editor = store.preferredEditor {
                    Button {
                        ExternalLauncher.openRepository(path: repo.path, with: editor)
                    } label: {
                        Label("用 \(editor.name) 打开", systemImage: editor.sfSymbol)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
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
                            .font(.system(size: 10))
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 18)
                    .help("选择其他已安装的 IDE 打开")
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
                    Label("Finder", systemImage: "folder")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if let webURL = repo.primaryWebURL {
                    Button {
                        ExternalLauncher.openInBrowser(urlString: webURL)
                    } label: {
                        Label("远程主页", systemImage: "safari")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()
            }
        }
    }

    // MARK: - 2. 分支切换与 Git 操作条
    private var actionToolbar: some View {
        HStack(spacing: 8) {
            // 分支切换下拉菜单
            Menu {
                Section("切换本地分支") {
                    ForEach(repo.localBranches, id: \.self) { br in
                        Button {
                            guard br != repo.currentBranch else { return }
                            Task { await store.checkoutBranch(for: repo, branch: br) }
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
                    Label("基于当前新建分支...", systemImage: "plus.circle")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11, weight: .semibold))
                    Text(repo.currentBranch)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.08))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .popover(isPresented: $showNewBranchPopover) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("新建并切换分支 (git checkout -b)")
                        .font(.caption.bold())
                    TextField("新分支名称，如 feat/radar-ui", text: $newBranchName)
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
                            Task { await store.checkoutBranch(for: repo, branch: name, createNew: true) }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(12)
            }

            Spacer()

            // Git 同步按钮组
            Button {
                Task { await store.refreshRepository(id: repo.id) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("刷新本地 Git 状态")
            .disabled(isBusy)

            if !repo.remotes.isEmpty {
                Button {
                    Task { await store.fetchRepository(repo) }
                } label: {
                    Label("Fetch", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy)

                Button {
                    Task { await store.pullRepository(repo) }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.to.line")
                        Text(repo.behindCount > 0 ? "Pull (\(repo.behindCount))" : "Pull")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(repo.behindCount > 0 ? .cyan : nil)
                .disabled(isBusy)

                Button {
                    Task { await store.pushRepository(repo) }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.to.line")
                        Text(repo.aheadCount > 0 ? "Push (\(repo.aheadCount))" : "Push")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(repo.aheadCount > 0 ? .blue : nil)
                .disabled(isBusy)
            }
        }
    }

    // MARK: - 3A. 变更文件列表 + 快捷提交 + 彩色 Diff 预览
    private var changesAndDiffTab: some View {
        VStack(spacing: 0) {
            if repo.changedFiles.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)
                    Text("工作区非常干净")
                        .font(.headline)
                    Text("当前没有未提交的修改或未跟踪文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 快速提交栏
                HStack(spacing: 8) {
                    TextField("输入 Commit Message 快速暂存全部并提交...", text: $commitMessage)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    Button("提交") {
                        let msg = commitMessage
                        Task {
                            if await store.commitAllChanges(for: repo, message: msg, andPush: false) {
                                commitMessage = ""
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)

                    if !repo.remotes.isEmpty {
                        Button("提交并 Push") {
                            let msg = commitMessage
                            Task {
                                if await store.commitAllChanges(for: repo, message: msg, andPush: true) {
                                    commitMessage = ""
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.04))

                Divider()

                VSplitView {
                    // 上半部分：变更文件列表
                    List(selection: $selectedFile) {
                        ForEach(repo.changedFiles) { file in
                            HStack(spacing: 8) {
                                Text(file.badgeText)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .frame(width: 22, height: 18)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(file.badgeColor.opacity(0.18))
                                    )
                                    .foregroundStyle(file.badgeColor)

                                Text(file.path)
                                    .font(.system(size: 12, design: .monospaced))
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
                                    Task { await store.discardFile(in: repo, file: file) }
                                } label: {
                                    Label("放弃此文件修改 (Discard)", systemImage: "arrow.uturn.backward")
                                }
                            }
                        }
                    }
                    .frame(minHeight: 120, idealHeight: 180)
                    .onChange(of: selectedFile) { _, _ in
                        loadSelectedFileDiff()
                    }

                    // 下半部分：Unified Diff 语法着色预览
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(selectedFile?.path ?? "选择上方文件预览 Diff")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            Spacer()
                            if isLoadingDiff {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.08))

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
                    .frame(minHeight: 180)
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
            return .green
        } else if line.hasPrefix("-") {
            return .red
        } else if line.hasPrefix("@@") {
            return .cyan
        }
        return .primary
    }

    private func diffLineBackground(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return Color.green.opacity(0.10)
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return Color.red.opacity(0.10)
        } else if line.hasPrefix("@@") {
            return Color.cyan.opacity(0.08)
        }
        return .clear
    }

    // MARK: - 3B. 最近提交历史
    private var commitsTab: some View {
        List(repo.recentCommits) { commit in
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(commit.shortHash)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor.opacity(0.14))
                        )
                        .foregroundStyle(Color.accentColor)

                    if !commit.refs.isEmpty {
                        Text(commit.refs)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.orange.opacity(0.15))
                            )
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(commit.relativeDate)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Text(commit.subject)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)

                HStack {
                    Image(systemName: "person.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(commit.author)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
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

    // MARK: - 3C. 远程仓库与分支列表（支持多 Remote 与任意自建 Git）
    private var remotesAndBranchesTab: some View {
        List {
            Section("远程地址 (Remotes - 支持 GitHub / GitLab / Gitee / 自建 Git 等)") {
                if repo.remotes.isEmpty {
                    Text("此仓库尚未配置任何远程地址 (git remote)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(repo.remotes) { remote in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(remote.name, systemImage: remote.provider.sfSymbol)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(remote.provider.badgeColor)

                                Text(remote.provider.rawValue)
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(remote.provider.badgeColor.opacity(0.14)))
                                    .foregroundStyle(remote.provider.badgeColor)

                                Spacer()

                                Button {
                                    ExternalLauncher.copyToPasteboard(remote.fetchURL)
                                    store.showBanner("已复制远程地址：\(remote.fetchURL)")
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                                .help("复制 Remote URL")

                                if let web = remote.webURL {
                                    Button {
                                        ExternalLauncher.openInBrowser(urlString: web)
                                    } label: {
                                        Image(systemName: "safari")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("在浏览器打开仓库主页")
                                }
                            }

                            Text(remote.fetchURL)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("本地分支 (\(repo.localBranches.count))") {
                ForEach(repo.localBranches, id: \.self) { br in
                    HStack {
                        Image(systemName: br == repo.currentBranch ? "checkmark.circle.fill" : "arrow.triangle.branch")
                            .foregroundStyle(br == repo.currentBranch ? .green : .secondary)
                        Text(br)
                            .font(.system(size: 12, weight: br == repo.currentBranch ? .bold : .regular, design: .monospaced))
                        Spacer()
                        if br != repo.currentBranch {
                            Button("切换") {
                                Task { await store.checkoutBranch(for: repo, branch: br) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        } else {
                            Text("当前分支")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                }
            }

            if !repo.remoteBranches.isEmpty {
                Section("远程跟踪分支 (\(repo.remoteBranches.count))") {
                    ForEach(repo.remoteBranches, id: \.self) { rbr in
                        HStack {
                            Image(systemName: "cloud")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text(rbr)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
