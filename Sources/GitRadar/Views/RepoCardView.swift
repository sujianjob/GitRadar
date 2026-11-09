import SwiftUI

struct RepoCardView: View {
    let repo: GitRepository
    let isSelected: Bool
    let isBusy: Bool
    @ObservedObject var store: RadarStore
    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: 1. 顶部：仓库名 + 平台徽章 + 星标 + 健康状态
            HStack(alignment: .top, spacing: 8) {
                // 托管平台色块图标
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(repo.primaryProvider.badgeColor.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: repo.primaryProvider.sfSymbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(repo.primaryProvider.badgeColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(repo.name)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)

                        if repo.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.yellow)
                        }

                        if isBusy {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }

                    Text(repo.displayPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                // 状态胶囊
                healthBadge
            }

            // MARK: 2. 分支与变更指标条
            HStack(spacing: 6) {
                // 当前分支
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10, weight: .semibold))
                    Text(repo.currentBranch)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.06))
                )

                // Ahead / Behind 指示器
                if repo.aheadCount > 0 || repo.behindCount > 0 {
                    HStack(spacing: 4) {
                        if repo.aheadCount > 0 {
                            Label("\(repo.aheadCount)", systemImage: "arrow.up")
                                .foregroundStyle(.blue)
                        }
                        if repo.behindCount > 0 {
                            Label("\(repo.behindCount)", systemImage: "arrow.down")
                                .foregroundStyle(.cyan)
                        }
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.blue.opacity(0.1))
                    )
                }

                // 未提交文件细分
                if repo.stagedCount > 0 {
                    metricPill(label: "暂存 \(repo.stagedCount)", color: .green)
                }
                if repo.modifiedCount > 0 {
                    metricPill(label: "修改 \(repo.modifiedCount)", color: .orange)
                }
                if repo.untrackedCount > 0 {
                    metricPill(label: "未跟踪 \(repo.untrackedCount)", color: .secondary)
                }
                if repo.stashCount > 0 {
                    metricPill(label: "Stash \(repo.stashCount)", color: .purple)
                }

                Spacer(minLength: 0)
            }

            // MARK: 3. 远程平台与最后一次 Commit 摘要
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(repo.primaryProvider.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(repo.primaryProvider.badgeColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(repo.primaryProvider.badgeColor.opacity(0.12))
                        )

                    if let slug = repo.primaryRemoteSlug, !slug.isEmpty {
                        Text(slug)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("未配置远程 Remote")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    // 分组标签
                    ForEach(assignedGroups.prefix(2)) { grp in
                        HStack(spacing: 3) {
                            Image(systemName: grp.icon)
                                .font(.system(size: 8))
                            Text(grp.name)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(grp.color.opacity(0.15)))
                        .foregroundStyle(grp.color)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    if let msg = repo.lastCommitMessage {
                        Text(msg)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("暂无 Commit 记录")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if let rel = repo.lastCommitRelativeTime {
                        Text(rel)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Divider()
                .opacity(0.6)

            // MARK: 4. 底部快捷操作栏（一键打开编辑器 / 终端 / Finder / Web / Git 同步）
            HStack(spacing: 8) {
                if let editor = store.preferredEditor {
                    quickActionButton(title: editor.name, icon: editor.sfSymbol) {
                        ExternalLauncher.openRepository(path: repo.path, with: editor)
                    }
                }

                if let term = store.preferredTerminal {
                    quickActionButton(title: term.name, icon: term.sfSymbol) {
                        ExternalLauncher.openRepository(path: repo.path, with: term)
                    }
                }

                quickActionButton(title: "Finder", icon: "folder") {
                    ExternalLauncher.openInFinder(path: repo.path)
                }

                if let webURL = repo.primaryWebURL {
                    quickActionButton(title: "网页", icon: "safari") {
                        ExternalLauncher.openInBrowser(urlString: webURL)
                    }
                }

                Spacer()

                if !repo.remotes.isEmpty {
                    Button {
                        Task { await store.fetchRepository(repo) }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .help("git fetch 刷新远程状态")

                    if repo.behindCount > 0 {
                        Button {
                            Task { await store.pullRepository(repo) }
                        } label: {
                            Label("Pull", systemImage: "arrow.down.to.line")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.cyan)
                        }
                        .buttonStyle(.borderless)
                        .help("拉取远程更新 (git pull)")
                    }

                    if repo.aheadCount > 0 {
                        Button {
                            Task { await store.pushRepository(repo) }
                        } label: {
                            Label("Push", systemImage: "arrow.up.to.line")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.borderless)
                        .help("推送本地提交 (git push)")
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(isHovered ? 0.10 : 0.04), radius: isHovered ? 8 : 3, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? Color.accentColor : (isHovered ? Color.secondary.opacity(0.35) : Color.secondary.opacity(0.15)),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            repoContextMenu
        }
    }

    private var assignedGroups: [RepoGroup] {
        store.groups.filter { repo.groupIDs.contains($0.id) }
    }

    private var healthBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: repo.healthState.sfSymbol)
                .font(.system(size: 10))
            Text(repo.healthState.rawValue)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(
            Capsule()
                .fill(repo.healthState.color.opacity(0.14))
        )
        .foregroundStyle(repo.healthState.color)
    }

    private func metricPill(label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.14))
            )
            .foregroundStyle(color)
    }

    private func quickActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.secondary.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    var repoContextMenu: some View {
        Button {
            store.toggleFavorite(for: repo.id)
        } label: {
            Label(repo.isFavorite ? "取消星标收藏" : "设为星标收藏", systemImage: repo.isFavorite ? "star.slash" : "star.fill")
        }

        Menu("归入虚拟分组") {
            ForEach(store.groups) { grp in
                let isIn = repo.groupIDs.contains(grp.id)
                Button {
                    store.toggleGroup(grp.id, for: repo.id)
                } label: {
                    Label(grp.name, systemImage: isIn ? "checkmark.circle.fill" : "circle")
                }
            }
        }

        Divider()

        Menu("在编辑器 / IDE 中打开") {
            ForEach(store.installedEditors) { app in
                Button {
                    ExternalLauncher.openRepository(path: repo.path, with: app)
                } label: {
                    Label(app.name, systemImage: app.sfSymbol)
                }
            }
        }

        Menu("在终端中打开") {
            ForEach(store.installedTerminals) { app in
                Button {
                    ExternalLauncher.openRepository(path: repo.path, with: app)
                } label: {
                    Label(app.name, systemImage: app.sfSymbol)
                }
            }
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
                Label("在浏览器打开远程主页 (\(repo.primaryProvider.rawValue))", systemImage: "safari")
            }
        }

        Divider()

        Button {
            Task { await store.refreshRepository(id: repo.id) }
        } label: {
            Label("刷新本地状态", systemImage: "arrow.clockwise")
        }

        if !repo.remotes.isEmpty {
            Button {
                Task { await store.fetchRepository(repo) }
            } label: {
                Label("Git Fetch (更新远程分支引用)", systemImage: "arrow.triangle.2.circlepath")
            }
            Button {
                Task { await store.pullRepository(repo) }
            } label: {
                Label("Git Pull (拉取合并)", systemImage: "arrow.down.circle")
            }
            Button {
                Task { await store.pushRepository(repo) }
            } label: {
                Label("Git Push (推送到远程)", systemImage: "arrow.up.circle")
            }
        }

        Divider()

        Button {
            ExternalLauncher.copyToPasteboard(repo.path)
            store.showBanner("已复制本地路径：\(repo.path)")
        } label: {
            Label("复制本地目录路径", systemImage: "doc.on.doc")
        }

        if let remoteURL = repo.remotes.first?.fetchURL {
            Button {
                ExternalLauncher.copyToPasteboard(remoteURL)
                store.showBanner("已复制 Remote URL：\(remoteURL)")
            } label: {
                Label("复制 Remote URL", systemImage: "link")
            }
        }
    }
}
