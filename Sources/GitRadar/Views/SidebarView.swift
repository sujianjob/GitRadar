import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: RadarStore
    @State private var newGroupName: String = ""
    @State private var newGroupIcon: String = "folder"
    @State private var newGroupColor: String = "blue"

    @State private var newAccountUsername: String = ""
    @State private var newAccountToken: String = ""
    @State private var newAccountNote: String = ""
    @State private var isTestingAccountToken: Bool = false
    @State private var accountTokenTestMessage: String? = nil
    @State private var accountTokenTestSuccess: Bool = false

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
                    count: store.visibleRepositories.count
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

            // MARK: 1.5 远程 GitHub Star 仓库（支持多账号与本地联动）
            Section {
                sidebarRow(
                    filter: .starredAll,
                    title: "全部远程 Star",
                    icon: "star.circle",
                    dotColor: nil,
                    count: store.starredAllCount
                )
                sidebarRow(
                    filter: .starredRecentUpdated,
                    title: "近期版本更新",
                    icon: "sparkles",
                    dotColor: store.starredRecentUpdatedCount > 0 ? AppTheme.statusSync : nil,
                    count: store.starredRecentUpdatedCount
                )
                sidebarRow(
                    filter: .starredCloned,
                    title: "本机已克隆",
                    icon: "checkmark.circle",
                    dotColor: store.starredClonedCount > 0 ? AppTheme.statusClean : nil,
                    count: store.starredClonedCount
                )

                ForEach(store.githubStarAccounts) { account in
                    sidebarRow(
                        filter: .starredAccount(account.username),
                        title: "@\(account.username)",
                        subtitle: account.note.isEmpty ? nil : account.note,
                        icon: "person.crop.circle",
                        dotColor: account.lastSyncError != nil ? AppTheme.statusDanger : nil,
                        count: store.countForStarredAccount(account.username)
                    )
                    .contextMenu {
                        Button {
                            store.beginEditingGitHubAccount(account)
                        } label: {
                            Label("编辑账号 (@\(account.username))...", systemImage: "pencil")
                        }
                        Button {
                            Task { await store.syncGitHubStars(for: account) }
                        } label: {
                            Label("同步 @\(account.username) 的 Star", systemImage: "arrow.clockwise")
                        }
                        Button {
                            ExternalLauncher.openInBrowser(urlString: "https://github.com/\(account.username)?tab=stars")
                        } label: {
                            Label("打开 GitHub Star 页面", systemImage: "safari")
                        }
                        Button {
                            store.openSettings(tab: .githubStars)
                        } label: {
                            Label("管理账号与默认 Clone 目录...", systemImage: "gearshape")
                        }
                        Divider()
                        Button(role: .destructive) {
                            store.removeGitHubAccount(account)
                        } label: {
                            Label("移除账号 @\(account.username)", systemImage: "trash")
                        }
                    }
                }

                Button {
                    store.beginAddGitHubAccount()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 12))
                        Text("添加 GitHub 账号...")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            } header: {
                HStack(spacing: 8) {
                    Text("远程 Star 仓库")
                    Spacer()
                    if !store.githubStarAccounts.isEmpty {
                        Button {
                            Task { await store.syncAllGitHubStars() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isSyncingStars)
                        .help("同步全部账号的 GitHub Star")
                    }
                    Button {
                        store.beginAddGitHubAccount()
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("添加 GitHub 账号")
                }
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
                        if store.excludedRepositories.isEmpty {
                            Text("已显示 \(store.visibleRepositories.count) 个仓库")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("显示 \(store.visibleRepositories.count) · 已过滤 \(store.excludedRepositories.count)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
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
        .sheet(isPresented: $store.showAddGitHubAccountSheet) {
            addGitHubAccountSheet
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
            Text("新建分组")
                .font(.headline)

            TextField("分组名称", text: $newGroupName)
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

    private var addGitHubAccountSheet: some View {
        let isEditing = store.editingGitHubAccount != nil
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: isEditing ? "pencil.circle.fill" : "star.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.accent)
                Text(isEditing ? "编辑 GitHub 账号 (@\(store.editingGitHubAccount?.username ?? ""))" : "添加 GitHub 账号同步 Star")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("GitHub 用户名")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("例如：sujianjob", text: $newAccountUsername)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("备注说明（可选，支持配置多个账号区分用途）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("例如：个人主号 / 团队账号 / 大神关注", text: $newAccountNote)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Personal Access Token（可选，突破 60 次/小时限流）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        ExternalLauncher.openInBrowser(urlString: GitHubStarService.tokenCreationURL)
                    } label: {
                        HStack(spacing: 3) {
                            Text("获取 GitHub Token")
                            Image(systemName: "arrow.up.right.square")
                        }
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("在浏览器打开 GitHub Token 创建页面（已预填只读权限）")
                }

                HStack(spacing: 8) {
                    SecureField("ghp_... 或 github_pat_...", text: $newAccountToken)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: newAccountToken) { _, _ in
                            accountTokenTestMessage = nil
                        }

                    Button {
                        let tokenToTest = newAccountToken
                        isTestingAccountToken = true
                        accountTokenTestMessage = nil
                        Task {
                            let res = await GitHubStarService.verifyToken(tokenToTest)
                            isTestingAccountToken = false
                            accountTokenTestSuccess = res.isValid
                            accountTokenTestMessage = res.message
                            if res.isValid,
                               newAccountUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               let login = res.authenticatedLogin {
                                newAccountUsername = login
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if isTestingAccountToken {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                            Text(isTestingAccountToken ? "测试中..." : "测试 Token")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(newAccountToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTestingAccountToken)
                }

                if let testMsg = accountTokenTestMessage {
                    HStack(spacing: 5) {
                        Image(systemName: accountTokenTestSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 11))
                        Text(testMsg)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(2)
                    }
                    .foregroundStyle(accountTokenTestSuccess ? AppTheme.statusClean : AppTheme.statusDanger)
                    .padding(.top, 2)
                }
            }

            HStack {
                Button("打开更多设置...") {
                    store.editingGitHubAccount = nil
                    store.showAddGitHubAccountSheet = false
                    store.openSettings(tab: .githubStars)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(AppTheme.accent)

                Spacer()

                Button("取消") {
                    store.editingGitHubAccount = nil
                    store.showAddGitHubAccountSheet = false
                }
                Button(isEditing ? "保存修改并同步" : "添加并同步") {
                    let originalUser = store.editingGitHubAccount?.username
                    let user = newAccountUsername
                    let tok = newAccountToken
                    let note = newAccountNote
                    newAccountUsername = ""
                    newAccountToken = ""
                    newAccountNote = ""
                    store.editingGitHubAccount = nil
                    store.showAddGitHubAccountSheet = false
                    store.addOrUpdateGitHubAccount(
                        originalUsername: originalUser,
                        username: user,
                        token: tok,
                        note: note
                    )
                    let cleanedUser = user.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
                    if !cleanedUser.isEmpty {
                        store.selectedFilter = .starredAccount(cleanedUser)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .disabled(newAccountUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            accountTokenTestMessage = nil
            isTestingAccountToken = false
            if let editing = store.editingGitHubAccount {
                newAccountUsername = editing.username
                newAccountNote = editing.note
                newAccountToken = editing.token
            } else {
                newAccountUsername = ""
                newAccountNote = ""
                newAccountToken = ""
            }
        }
    }
}
