import SwiftUI

struct StarredRepoCardView: View {
    let repo: StarredRepository
    let localRepo: GitRepository?
    let isSelected: Bool
    let isCloning: Bool
    @ObservedObject var store: RadarStore
    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // MARK: 1. 顶部：头像 + 仓库名/Owner + 右上角 Star 数与状态圆点
            HStack(alignment: .center, spacing: 10) {
                ProjectAvatarView(
                    starredRepo: repo,
                    localIconPath: localRepo?.projectIconPath,
                    size: 36
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(repo.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if isCloning {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }

                    Text(repo.fullName)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                // 右上角：状态圆点 + Star 数胶囊
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 6.5, height: 6.5)

                    Image(systemName: "star.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppTheme.statusDirty)

                    Text(repo.formattedStars)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(AppTheme.subtleSurface)
                )
                .fixedSize()
            }

            // MARK: 2. 语言、最新 Release 标签、所属账号标签
            HStack(spacing: 6) {
                if let lang = repo.language, !lang.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: repo.techStack.sfSymbol)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(lang)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.88))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppTheme.subtleSurface)
                    )
                    .fixedSize()
                }

                if let tag = repo.latestReleaseTag, !tag.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 8.5))
                        Text(tag)
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                    }
                    .foregroundStyle(AppTheme.statusSync)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppTheme.statusSync.opacity(0.10))
                    )
                    .fixedSize()
                } else if repo.isArchived {
                    subtleBadge(text: "已归档", dotColor: AppTheme.statusDanger)
                } else if localRepo != nil {
                    subtleBadge(text: "本机已克隆", dotColor: AppTheme.statusClean)
                } else if repo.isRecentlyUpdated {
                    subtleBadge(text: "近期活跃", dotColor: AppTheme.statusSync)
                }

                if let firstTopic = repo.topics.first {
                    Text("#\(firstTopic)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.subtleSurface)
                        )
                }

                Spacer(minLength: 0)

                // 显示由哪个 GitHub 账号 Star
                if !repo.starredByAccounts.isEmpty {
                    let accountsLabel = repo.starredByAccounts.map { "@\($0)" }.joined(separator: " ")
                    Text(accountsLabel)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            // MARK: 3. 项目简介单行预览 + 最近更新时间
            HStack(spacing: 6) {
                if let desc = repo.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let excerpt = repo.readmeExcerpt?
                    .components(separatedBy: .newlines)
                    .map({ $0.trimmingCharacters(in: .whitespaces) })
                    .first(where: { !$0.isEmpty }) {
                    Text(excerpt)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("暂无项目描述")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 4)

                Text(repo.relativePushedTime)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }

            Divider()
                .opacity(0.45)

            // MARK: 4. 底部工具栏：未克隆显示「一键 Clone」，已克隆显示「Finder / IDE」
            HStack(alignment: .center, spacing: 8) {
                if let local = localRepo {
                    toolButton(title: "Finder", icon: "folder") {
                        ExternalLauncher.openInFinder(path: local.path)
                    }

                    if let editor = store.preferredEditor {
                        toolButton(title: editor.name, icon: editor.sfSymbol) {
                            ExternalLauncher.openRepository(path: local.path, with: editor)
                        }
                    }

                    toolButton(title: "GitHub", icon: "safari") {
                        ExternalLauncher.openInBrowser(urlString: repo.htmlURL)
                    }

                    Spacer(minLength: 6)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(AppTheme.statusClean)
                            .frame(width: 5.5, height: 5.5)
                        Text(local.displayPath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .help("本机路径：\(local.path)")
                } else {
                    toolButton(
                        title: isCloning ? "正在 Clone..." : "一键 Clone",
                        icon: "arrow.down.circle",
                        highlight: AppTheme.accent
                    ) {
                        store.cloneStarredRepository(repo)
                    }
                    .disabled(isCloning)

                    toolButton(title: "远程主页", icon: "safari") {
                        ExternalLauncher.openInBrowser(urlString: repo.htmlURL)
                    }

                    Spacer(minLength: 6)

                    Text(repo.htmlURL)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .help(repo.htmlURL)
                }
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? AppTheme.selectedBorder.opacity(0.06) : AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isSelected ? AppTheme.selectedBorder : (isHovered ? AppTheme.hoverBorder : AppTheme.hairlineBorder),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            starredContextMenu
        }
    }

    private var statusDotColor: Color {
        if localRepo != nil {
            return AppTheme.statusClean
        }
        if repo.isArchived {
            return AppTheme.statusDanger
        }
        if repo.isRecentlyUpdated {
            return AppTheme.statusSync
        }
        if repo.isStale {
            return AppTheme.statusDirty
        }
        return AppTheme.statusNeutral
    }

    private func subtleBadge(text: String, dotColor: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dotColor)
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(AppTheme.subtleSurface)
        )
        .fixedSize()
    }

    private func toolButton(title: String, icon: String, highlight: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(highlight ?? .secondary)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(highlight ?? Color.primary.opacity(0.85))
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppTheme.subtleSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(highlight?.opacity(0.45) ?? AppTheme.hairlineBorder, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    @ViewBuilder
    private var starredContextMenu: some View {
        if let local = localRepo {
            Button {
                ExternalLauncher.openInVSCode(path: local.path)
            } label: {
                Label("在 VS Code 中打开", systemImage: "chevron.left.forwardslash.chevron.right")
            }

            Button {
                ExternalLauncher.openInAntigravity(path: local.path)
            } label: {
                Label("在 Antigravity IDE 中打开", systemImage: "sparkles")
            }

            Button {
                ExternalLauncher.openInFinder(path: local.path)
            } label: {
                Label("在 Finder 中显示本地仓库", systemImage: "folder")
            }

            Button {
                store.selectedFilter = .all
                store.selectedRepoID = local.id
            } label: {
                Label("跳转到本地仓库视图", systemImage: "arrow.right.circle")
            }
        } else {
            Button {
                store.cloneStarredRepository(repo)
            } label: {
                if let defDir = store.formattedDefaultCloneDirectory {
                    Label("一键 Clone 到默认目录 (\(defDir))", systemImage: "arrow.down.circle")
                } else {
                    Label("Clone 到本地（选择目录...）", systemImage: "arrow.down.circle")
                }
            }
            .disabled(isCloning)
        }

        Divider()

        Button {
            ExternalLauncher.openInBrowser(urlString: repo.htmlURL)
        } label: {
            Label("在浏览器中打开 GitHub 主页", systemImage: "safari")
        }

        Button {
            ExternalLauncher.copyToPasteboard("git clone \(repo.cloneURL)")
            store.showBanner("已复制命令：git clone \(repo.cloneURL)")
        } label: {
            Label("复制 git clone 命令", systemImage: "terminal")
        }

        Button {
            ExternalLauncher.copyToPasteboard(repo.cloneURL)
            store.showBanner("已复制 HTTPS 地址：\(repo.cloneURL)")
        } label: {
            Label("复制 HTTPS 仓库地址", systemImage: "doc.on.doc")
        }

        Button {
            ExternalLauncher.copyToPasteboard(repo.sshURL)
            store.showBanner("已复制 SSH 地址：\(repo.sshURL)")
        } label: {
            Label("复制 SSH 仓库地址", systemImage: "key")
        }

        Divider()

        Button {
            Task { await store.hydrateStarredRepoDetailsIfNeeded(repo, force: true) }
        } label: {
            Label("刷新 Release 与 README 详情", systemImage: "arrow.clockwise")
        }
    }
}
