import SwiftUI

struct RankedRepoDetailView: View {
    let repo: RankedRepository
    let localRepo: GitRepository?
    let starredAccounts: [String]
    @ObservedObject var store: RadarStore

    enum RankedInspectorTab: String, CaseIterable {
        case release = "最新版本动态"
        case metadata = "仓库与克隆"
    }

    @State private var selectedTab: RankedInspectorTab = .release
    @State private var isReadmeExpanded: Bool = false

    var isCloning: Bool {
        store.cloningStarredIDs.contains(repo.id)
    }

    var isHydrating: Bool {
        store.hydratingRankedIDs.contains(repo.id)
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // MARK: 1. 顶部榜单项目信息与操作栏
                headerSection
                    .padding(.leading, 16)
                    .padding(.trailing, 20)
                    .padding(.vertical, 12)
                    .frame(width: geo.size.width)
                    .background(AppTheme.canvasBackground)

                Divider()

                // MARK: 2. 上方项目简介与 README 预览区域（占约 42% 高度）
                readmeOverviewSection
                    .frame(width: geo.size.width, height: max(220, geo.size.height * 0.42))
                    .background(AppTheme.cardBackground)

                Divider()

                // MARK: 3. 下方标签页切换器
                HStack {
                    Picker("", selection: $selectedTab) {
                        Text(repo.latestReleaseTag != nil ? "Release (\(repo.latestReleaseTag!))" : "最新版本动态")
                            .tag(RankedInspectorTab.release)
                        Text(localRepo != nil ? "本地已克隆" : "仓库与克隆")
                            .tag(RankedInspectorTab.metadata)
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

                // MARK: 4. 下方详情内容区
                Group {
                    switch selectedTab {
                    case .release:
                        releaseDetailTab
                    case .metadata:
                        metadataAndCloneTab
                    }
                }
                .frame(width: geo.size.width)
                .frame(maxHeight: .infinity)
            }
        }
        .task(id: repo.id) {
            isReadmeExpanded = false
            await store.hydrateRankedRepoDetailsIfNeeded(repo)
        }
    }

    // MARK: - 1. 顶部栏
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ProjectAvatarView(
                    rankedRepo: repo,
                    localIconPath: localRepo?.projectIconPath,
                    size: 38
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text("NO.\(repo.rank)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.statusDirty)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(AppTheme.statusDirty.opacity(0.14))
                            )

                        Text(repo.name)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if isCloning || isHydrating {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }

                    HStack(spacing: 4) {
                        Text(repo.fullName)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button {
                            ExternalLauncher.copyToPasteboard(repo.htmlURL)
                            store.showBanner("已复制地址：\(repo.htmlURL)")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("复制 GitHub 链接")
                    }
                }

                Spacer(minLength: 6)

                // 右上角主操作
                HStack(spacing: 5) {
                    if let local = localRepo {
                        compactActionButton(
                            title: "已克隆",
                            icon: "checkmark.circle.fill",
                            highlightColor: AppTheme.statusClean
                        ) {
                            store.selectedFilter = .all
                            store.selectedRepoID = local.id
                        }
                    } else {
                        compactActionButton(
                            title: isCloning ? "正在克隆..." : "一键 Clone",
                            icon: "arrow.down.circle.fill",
                            highlightColor: AppTheme.accent,
                            disabled: isCloning
                        ) {
                            store.cloneRankedRepository(repo)
                        }
                    }

                    compactActionButton(
                        title: "刷新",
                        icon: "arrow.clockwise",
                        disabled: isHydrating
                    ) {
                        Task { await store.hydrateRankedRepoDetailsIfNeeded(repo, force: true) }
                    }
                }
            }

            // 第二行：快捷跳转与榜单热度指标
            HStack(spacing: 6) {
                if let local = localRepo {
                    compactActionButton(title: "Finder", icon: "folder") {
                        ExternalLauncher.openInFinder(path: local.path)
                    }

                    if let editor = store.preferredEditor {
                        compactActionButton(title: editor.name, icon: editor.sfSymbol) {
                            ExternalLauncher.openRepository(path: local.path, with: editor)
                        }
                    }
                }

                compactActionButton(title: "GitHub 主页", icon: "safari") {
                    ExternalLauncher.openInBrowser(urlString: repo.htmlURL)
                }

                Spacer(minLength: 4)

                // 榜单飙升指标 + 总 Star / Fork
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(AppTheme.statusDirty)
                        Text(repo.deltaBadgeText)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.statusDirty)
                    }

                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(AppTheme.statusDirty)
                        Text(repo.formattedStars)
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    }
                }
            }
        }
    }

    // MARK: - 2. README 简介与正文区域
    private var readmeOverviewSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("项目简介 (README)")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                if let lang = repo.language, !lang.isEmpty {
                    Text(lang)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(AppTheme.subtleSurface)
                        )
                }

                Spacer()

                if (localRepo?.readmeFullText ?? repo.readmeFullText) != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isReadmeExpanded.toggle()
                        }
                    } label: {
                        Text(isReadmeExpanded ? "收起简介" : "展开全文")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 20)
            .padding(.vertical, 8)
            .background(AppTheme.subtleSurface)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let desc = repo.description, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(desc)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(AppTheme.subtleSurface)
                            )
                    }

                    let fullReadme = localRepo?.readmeFullText ?? repo.readmeFullText
                    let excerptReadme = localRepo?.readmeExcerpt ?? repo.readmeExcerpt

                    if let content = isReadmeExpanded ? fullReadme : (excerptReadme ?? fullReadme),
                       !content.isEmpty {
                        Text(content)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.primary.opacity(0.86))
                            .lineSpacing(3.5)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if isHydrating {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在从 GitHub 加载 README 与最新 Release...")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 16)
                    } else {
                        Text("暂无更多 README 预览内容，可点击右上角「刷新」或打开 GitHub 主页查看。")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 20)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - 3. Tab 1: 最新 Release 动态
    private var releaseDetailTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let tag = repo.latestReleaseTag, !tag.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 10))
                                Text(tag)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(AppTheme.statusSync)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(AppTheme.statusSync.opacity(0.12))
                            )

                            if let relName = repo.latestReleaseName, !relName.isEmpty, relName != tag {
                                Text(relName)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .lineLimit(1)
                            }

                            Spacer()

                            if let pubDate = repo.latestReleasePublishedAt {
                                Text(StarredRepository.formatRelativeDate(pubDate))
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let relURL = repo.latestReleaseHTMLURL {
                            Button {
                                ExternalLauncher.openInBrowser(urlString: relURL)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 10))
                                    Text("在 GitHub 查看完整 Release 页面")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(AppTheme.accent)
                            }
                            .buttonStyle(.plain)
                        }

                        Divider()

                        if let body = repo.latestReleaseBody, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(ProjectMetadataInspector.cleanMarkdownForPreview(body))
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color.primary.opacity(0.86))
                                .lineSpacing(3.5)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("该版本未填写详细 Release Notes。")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.hairlineBorder, lineWidth: 1)
                    )
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "flame.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.statusDirty)
                            Text("榜单指标：\(repo.deltaBadgeText)")
                                .font(.system(size: 12, weight: .semibold))
                        }

                        Text("该项目暂未发布正式 GitHub Release（或正在加载），可通过主分支 `\(repo.defaultBranch)` 直接克隆体验。")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.hairlineBorder, lineWidth: 1)
                    )
                }

                // Topics 标签展示
                if !repo.topics.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("主题标签 (Topics)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], alignment: .leading, spacing: 6) {
                            ForEach(repo.topics, id: \.self) { topic in
                                Text("#\(topic)")
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(AppTheme.subtleSurface)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(AppTheme.hairlineBorder, lineWidth: 0.8)
                                    )
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.hairlineBorder, lineWidth: 1)
                    )
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - 4. Tab 2: 仓库元数据与一键 Clone 配置
    private var metadataAndCloneTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // 本地状态卡片
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("本机克隆状态")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("修改默认目录...") {
                            store.openSettings(tab: .githubStars)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                    }

                    if let local = localRepo {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(AppTheme.statusClean)
                                .frame(width: 7, height: 7)
                            Text("已克隆在本机：\(local.displayPath)")
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                        }

                        HStack(spacing: 8) {
                            Button("在 Finder 中打开") {
                                ExternalLauncher.openInFinder(path: local.path)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("在 VS Code 中打开") {
                                ExternalLauncher.openInVSCode(path: local.path)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("在 Antigravity 中打开") {
                                ExternalLauncher.openInAntigravity(path: local.path)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.top, 2)
                    } else {
                        if let defaultDir = store.formattedDefaultCloneDirectory {
                            Text("默认保存目录：\(defaultDir)/\(repo.name)（点击「一键 Clone」将直接克隆，不弹窗）")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("当前未设置默认 Clone 目录，点击「一键 Clone」时将弹窗供你选择文件夹。")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            store.cloneRankedRepository(repo)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text(isCloning ? "正在 Clone 到本地..." : "立即 Clone 到本地")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                        .controlSize(.small)
                        .disabled(isCloning)
                        .padding(.top, 2)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.hairlineBorder, lineWidth: 1)
                )

                // 榜单与远程信息
                VStack(alignment: .leading, spacing: 8) {
                    Text("榜单指标与仓库信息")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)

                    infoRow(label: "当前榜单排名", value: "#\(repo.rank)")
                    infoRow(label: "热度指标", value: repo.deltaBadgeText)
                    infoRow(label: "总 Star / Fork", value: "★ \(repo.formattedStars) · ⑂ \(repo.formattedForks)")
                    if !starredAccounts.isEmpty {
                        infoRow(label: "已收藏账号", value: starredAccounts.map { "@\($0)" }.joined(separator: ", "))
                    }
                    infoRow(label: "HTTPS Clone", value: repo.cloneURL, copyable: true)
                    infoRow(label: "SSH Clone", value: repo.sshURL, copyable: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.hairlineBorder, lineWidth: 1)
                )
            }
            .padding(.leading, 16)
            .padding(.trailing, 20)
            .padding(.vertical, 12)
        }
    }

    private func infoRow(label: String, value: String, copyable: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if copyable {
                Button {
                    ExternalLauncher.copyToPasteboard(value)
                    store.showBanner("已复制：\(value)")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
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
                    .fill(highlightColor != nil ? highlightColor!.opacity(0.11) : AppTheme.subtleSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(highlightColor?.opacity(0.45) ?? AppTheme.hairlineBorder, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .fixedSize()
    }
}
