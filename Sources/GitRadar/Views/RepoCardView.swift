import SwiftUI

struct RepoCardView: View {
    let repo: GitRepository
    let isSelected: Bool
    let isBusy: Bool
    @ObservedObject var store: RadarStore
    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // MARK: 1. 顶部：真实项目图标 + 仓库名称 + 状态圆点
            HStack(alignment: .center, spacing: 10) {
                ProjectAvatarView(repo: repo, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(repo.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if repo.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.statusDirty)
                        }

                        if isBusy {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }

                    Text(repo.displayPath)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                // 克制的状态指示器（6px 状态圆点 + 文字）
                HStack(spacing: 5) {
                    Circle()
                        .fill(repo.healthState.color)
                        .frame(width: 6.5, height: 6.5)
                    Text(repo.healthState.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(repo.isDirty || repo.conflictCount > 0 ? repo.healthState.color : .secondary)
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

            // MARK: 2. 分支、领先/落后计数与工作区改动统计
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                    Text(repo.currentBranch)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.primary.opacity(0.88))
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppTheme.subtleSurface)
                )

                if repo.aheadCount > 0 || repo.behindCount > 0 {
                    HStack(spacing: 5) {
                        if repo.aheadCount > 0 {
                            Text("↑\(repo.aheadCount)")
                                .foregroundStyle(AppTheme.statusSync)
                        }
                        if repo.behindCount > 0 {
                            Text("↓\(repo.behindCount)")
                                .foregroundStyle(AppTheme.statusSync)
                        }
                    }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppTheme.subtleSurface)
                    )
                    .fixedSize()
                }

                if repo.stagedCount > 0 {
                    subtleCountTag(text: "暂存 \(repo.stagedCount)", dotColor: AppTheme.statusClean)
                }
                if repo.modifiedCount > 0 {
                    subtleCountTag(text: "修改 \(repo.modifiedCount)", dotColor: AppTheme.statusDirty)
                }
                if repo.untrackedCount > 0 {
                    subtleCountTag(text: "未跟踪 \(repo.untrackedCount)", dotColor: AppTheme.statusNeutral)
                }

                Spacer(minLength: 0)

                Text(repo.primaryProvider.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }

            // MARK: 3. 项目简介单行预览 或 最后一次提交信息
            HStack(spacing: 6) {
                if let excerpt = repo.readmeExcerpt,
                   let firstMeaningfulLine = excerpt
                       .components(separatedBy: .newlines)
                       .map({ $0.trimmingCharacters(in: .whitespaces) })
                       .first(where: { !$0.isEmpty && $0.lowercased() != repo.name.lowercased() }) {
                    Text(firstMeaningfulLine)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let msg = repo.lastCommitMessage {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("暂无提交记录")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 4)

                if let rel = repo.lastCommitRelativeTime {
                    Text(rel)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }
            }

            Divider()
                .opacity(0.45)

            // MARK: 4. 底部工具栏（左侧 Finder 与远程主页，右下角显示完整仓库地址）
            HStack(alignment: .center, spacing: 8) {
                toolButton(title: "Finder", icon: "folder") {
                    ExternalLauncher.openInFinder(path: repo.path)
                }

                if let webURL = repo.primaryWebURL {
                    toolButton(title: "远程主页", icon: "safari") {
                        ExternalLauncher.openInBrowser(urlString: webURL)
                    }
                }

                Spacer(minLength: 6)

                if let fullRepoAddress = repo.primaryWebURL ?? repo.remotes.first?.fetchURL {
                    Text(fullRepoAddress)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .help(fullRepoAddress)
                } else {
                    Text(repo.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .help(repo.path)
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
            repoContextMenu
        }
    }

    private func subtleCountTag(text: String, dotColor: Color) -> some View {
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
        .fixedSize(horizontal: true, vertical: true)
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

        Divider()

        Button {
            Task { await store.refreshRepository(id: repo.id) }
        } label: {
            Label("刷新本地状态", systemImage: "arrow.clockwise")
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

        Divider()

        Menu("过滤与屏蔽（不显示）") {
            Button {
                store.hideRepository(repo)
            } label: {
                Label("隐藏此仓库 (\(repo.name))", systemImage: "eye.slash")
            }

            if let org = repo.primaryOrganization, !org.isEmpty {
                Button {
                    store.hideRemoteOrganization(host: repo.primaryHost, org: org)
                } label: {
                    Label("屏蔽组织「\(org)」下所有仓库", systemImage: "person.2.slash")
                }
            }

            if let host = repo.primaryHost, !host.isEmpty {
                Button {
                    store.hideRemoteHost(host)
                } label: {
                    Label("屏蔽域名「\(host)」下所有仓库", systemImage: "network.slash")
                }
            }

            Divider()

            Button {
                store.openSettings(tab: .filter)
            } label: {
                Label("打开域名与过滤管理面板...", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }
}
