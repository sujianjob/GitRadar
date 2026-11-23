import AppKit
import SwiftUI

struct SettingsSheetView: View {
    @ObservedObject var store: RadarStore
    @Environment(\.dismiss) private var dismiss

    @State private var newGroupName: String = ""
    @State private var newGroupIcon: String = "folder"
    @State private var newGroupColor: String = "blue"

    @State private var newStarUsername: String = ""
    @State private var newStarNote: String = ""
    @State private var newStarToken: String = ""
    @State private var editingAccountOriginalUsername: String? = nil
    @State private var isTestingStarToken: Bool = false
    @State private var starTokenTestMessage: String? = nil
    @State private var starTokenTestSuccess: Bool = false

    private let availableIcons = [
        "folder", "sparkles", "briefcase", "wrench.and.screwdriver",
        "globe", "cpu", "terminal", "cube.box", "bolt", "star"
    ]
    private let availableColors = ["blue", "purple", "orange", "green", "pink", "teal", "indigo", "red"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: 1. 顶部导航栏：标题 + 居中胶囊 Tab 栏 + 完成按钮（全单行不换行）
            HStack(spacing: 14) {
                HStack(spacing: 7) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("偏好设置")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                }
                .fixedSize()

                Spacer(minLength: 8)

                // 顶部 Tab 切换器
                HStack(spacing: 3) {
                    ForEach(SettingsTab.allCases) { tab in
                        let isSelected = store.selectedSettingsTab == tab
                        Button {
                            withAnimation(.easeInOut(duration: 0.14)) {
                                store.selectedSettingsTab = tab
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: tab.sfSymbol)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                Text(tab.rawValue)
                                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5.5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? AppTheme.cardBackground : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isSelected ? AppTheme.selectedBorder.opacity(0.65) : Color.clear, lineWidth: 1)
                            )
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .contentShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .fixedSize(horizontal: true, vertical: true)
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.subtleSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.hairlineBorder, lineWidth: 1)
                )
                .fixedSize()

                Spacer(minLength: 8)

                Button("完成") {
                    store.saveConfig()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .controlSize(.small)
                .fixedSize()
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(AppTheme.canvasBackground)

            Divider()

            // MARK: 2. 主体内容区（统一留白与精致卡片表格布局）
            Group {
                switch store.selectedSettingsTab {
                case .directories:
                    directoriesTab
                case .githubStars:
                    githubStarsTab
                case .filter:
                    FilterRulesContentView(store: store)
                case .groups:
                    groupsTab
                case .gitAndCache:
                    gitAndCacheTab
                case .logs:
                    actionLogsTab
                case .about:
                    aboutUsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.canvasBackground)
        }
        .frame(width: 860, height: 560)
    }

    // MARK: - Tab 1: 扫描目录管理
    private var directoriesTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 顶部工具条卡片
            HStack(spacing: 10) {
                Button {
                    store.promptAddDirectory()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 11.5))
                        Text("添加扫描目录")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .controlSize(.small)
                .fixedSize()

                let availableCandidates = ["~/AI", "~/Projects", "~/Developer", "~/Desktop"].filter { candidate in
                    let expanded = (candidate as NSString).expandingTildeInPath
                    return FileManager.default.fileExists(atPath: expanded)
                        && !store.watchedDirectories.contains(where: { $0.path == expanded })
                }

                if !availableCandidates.isEmpty {
                    Divider()
                        .frame(height: 16)

                    HStack(spacing: 6) {
                        Text("快捷添加")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()

                        ForEach(availableCandidates, id: \.self) { candidate in
                            Button("+ \(candidate)") {
                                store.addQuickDirectory(candidate)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .fixedSize()
                        }
                    }
                }

                Spacer(minLength: 12)

                // 默认递归深度调节器（不折行）
                HStack(spacing: 8) {
                    Text("默认扫描深度")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()

                    Stepper(value: $store.defaultScanDepth, in: 1...8) {
                        Text("\(store.defaultScanDepth) 层")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .fixedSize()
                    .onChange(of: store.defaultScanDepth) { _, newValue in
                        for idx in store.watchedDirectories.indices {
                            store.watchedDirectories[idx].maxDepth = newValue
                        }
                        store.saveConfig()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.hairlineBorder, lineWidth: 1)
            )

            // 扫描目录表格卡片
            VStack(alignment: .leading, spacing: 0) {
                // 表头
                HStack(spacing: 12) {
                    Text("目录名称")
                        .frame(width: 150, alignment: .leading)
                    Text("本地完整路径")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("扫描深度")
                        .frame(width: 72, alignment: .center)
                    Text("发现仓库")
                        .frame(width: 80, alignment: .trailing)
                    Text("操作")
                        .frame(width: 130, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(AppTheme.subtleSurface)

                Divider()

                if store.watchedDirectories.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 26))
                            .foregroundStyle(.tertiary)
                        Text("尚未添加本地扫描目录，请点击左上角「添加扫描目录」")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(store.watchedDirectories.enumerated()), id: \.element.id) { idx, dir in
                                HStack(spacing: 12) {
                                    HStack(spacing: 7) {
                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(AppTheme.accent)
                                        Text(dir.displayName)
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .lineLimit(1)
                                    }
                                    .frame(width: 150, alignment: .leading)

                                    Text(dir.path)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .help(dir.path)

                                    Text("\(dir.maxDepth) 层")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(AppTheme.subtleSurface)
                                        )
                                        .frame(width: 72, alignment: .center)

                                    Text("\(store.countForRootDirectory(dir.path)) 个")
                                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .frame(width: 80, alignment: .trailing)

                                    HStack(spacing: 6) {
                                        Button("Finder") {
                                            ExternalLauncher.openInFinder(path: dir.path)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .fixedSize()

                                        Button("移除") {
                                            store.removeWatchedDirectory(dir)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .fixedSize()
                                    }
                                    .frame(width: 130, alignment: .trailing)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)

                                if idx < store.watchedDirectories.count - 1 {
                                    Divider()
                                        .padding(.horizontal, 16)
                                        .opacity(0.5)
                                }
                            }
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.hairlineBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(18)
    }

    // MARK: - Tab 1.5: 远程 Star 账号管理与默认 Clone 目录设置
    private var githubStarsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. 默认 Clone 目录设置卡片（设置后不弹窗，未设置则每次弹窗选择目录）
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("远程 Star 默认 Clone 保存目录")
                                .font(.system(size: 12.5, weight: .semibold))
                            if store.defaultCloneDirectory != nil {
                                Text("已设置默认目录（直接 Clone 不弹窗）")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(AppTheme.statusClean)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(AppTheme.statusClean.opacity(0.12))
                                    )
                            } else {
                                Text("未设置（每次 Clone 时弹窗选择目录）")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(AppTheme.subtleSurface)
                                    )
                            }
                        }

                        if let dir = store.defaultCloneDirectory, !dir.isEmpty {
                            Text("当前默认路径：\(dir)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("说明：若设置了默认目录，点击远程 Star 仓库的「一键 Clone」将直接克隆至该目录下；若留空则每次弹窗选目录。")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if let dir = store.defaultCloneDirectory, !dir.isEmpty {
                        Button("Finder") {
                            ExternalLauncher.openInFinder(path: dir)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("清除（恢复每次弹窗）") {
                            store.setDefaultCloneDirectory(nil)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button("选择默认目录...") {
                        store.promptSelectDefaultCloneDirectory()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .controlSize(.small)
                }

                if !store.watchedDirectories.isEmpty {
                    HStack(spacing: 6) {
                        Text("快捷设为已监控根目录：")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        ForEach(store.watchedDirectories) { dir in
                            let isCurrent = store.defaultCloneDirectory == dir.path
                            Button(isCurrent ? "✓ \(dir.displayName)" : dir.displayName) {
                                store.setDefaultCloneDirectory(dir.path)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .disabled(isCurrent)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.hairlineBorder, lineWidth: 1)
            )

            // 2. 添加或编辑 GitHub 账号工具条（含 Token 测试与获取 Token 超链接）
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let editingUser = editingAccountOriginalUsername {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 11.5))
                                .foregroundStyle(AppTheme.accent)
                            Text("正在编辑账号 @\(editingUser)（可直接修改用户名、备注或 Token）")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
                    } else {
                        HStack(spacing: 5) {
                            Image(systemName: "person.badge.key.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text("添加或更新 GitHub 账号（公开 Star 免填 Token；填入 Token 可突破 60 次/小时 API 限流）")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        ExternalLauncher.openInBrowser(urlString: GitHubStarService.tokenCreationURL)
                    } label: {
                        HStack(spacing: 3) {
                            Text("获取 GitHub Token")
                            Image(systemName: "arrow.up.right.square")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("在浏览器打开 GitHub Personal Access Token 创建页面")

                    if editingAccountOriginalUsername != nil {
                        Divider().frame(height: 12)
                        Button("取消编辑") {
                            editingAccountOriginalUsername = nil
                            newStarUsername = ""
                            newStarNote = ""
                            newStarToken = ""
                            starTokenTestMessage = nil
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    TextField("GitHub 用户名（如 sujianjob）", text: $newStarUsername)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(width: 170)

                    TextField("备注（可选，如 个人主号）", text: $newStarNote)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(width: 145)

                    SecureField("Token（ghp_... 或 github_pat_...）", text: $newStarToken)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .onChange(of: newStarToken) { _, _ in
                            starTokenTestMessage = nil
                        }

                    Button {
                        let tokenToTest = newStarToken
                        isTestingStarToken = true
                        starTokenTestMessage = nil
                        Task {
                            let res = await GitHubStarService.verifyToken(tokenToTest)
                            isTestingStarToken = false
                            starTokenTestSuccess = res.isValid
                            starTokenTestMessage = res.message
                            if res.isValid,
                               newStarUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               let login = res.authenticatedLogin {
                                newStarUsername = login
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if isTestingStarToken {
                                ProgressView().controlSize(.mini)
                            }
                            Text(isTestingStarToken ? "测试中..." : "测试 Token")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(newStarToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTestingStarToken)
                    .help("验证输入的 GitHub Token 是否有效并查看剩余额度")

                    if editingAccountOriginalUsername != nil {
                        Button("取消") {
                            editingAccountOriginalUsername = nil
                            newStarUsername = ""
                            newStarNote = ""
                            newStarToken = ""
                            starTokenTestMessage = nil
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .fixedSize()
                    }

                    Button(editingAccountOriginalUsername != nil ? "保存修改并同步" : "+ 添加账号") {
                        store.addOrUpdateGitHubAccount(
                            originalUsername: editingAccountOriginalUsername,
                            username: newStarUsername,
                            token: newStarToken,
                            note: newStarNote
                        )
                        editingAccountOriginalUsername = nil
                        newStarUsername = ""
                        newStarNote = ""
                        newStarToken = ""
                        starTokenTestMessage = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(newStarUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if !store.githubStarAccounts.isEmpty && editingAccountOriginalUsername == nil {
                        Button(store.isSyncingStars ? "同步中..." : "同步全部") {
                            Task { await store.syncAllGitHubStars() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .fixedSize()
                        .disabled(store.isSyncingStars)
                    }
                }

                if let testMsg = starTokenTestMessage {
                    HStack(spacing: 5) {
                        Image(systemName: starTokenTestSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 11))
                        Text(testMsg)
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Button {
                            starTokenTestMessage = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(starTokenTestSuccess ? AppTheme.statusClean : AppTheme.statusDanger)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(editingAccountOriginalUsername != nil ? AppTheme.selectedBorder : AppTheme.hairlineBorder, lineWidth: editingAccountOriginalUsername != nil ? 1.2 : 1)
            )

            // 3. 多账号列表表格
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text("GitHub 账号")
                        .frame(width: 150, alignment: .leading)
                    Text("备注与认证方式")
                        .frame(width: 170, alignment: .leading)
                    Text("Star 仓库数")
                        .frame(width: 85, alignment: .trailing)
                    Text("最近同步状态")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("操作")
                        .frame(width: 215, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(AppTheme.subtleSurface)

                Divider()

                if store.githubStarAccounts.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 26))
                            .foregroundStyle(.tertiary)
                        Text("尚未添加任何 GitHub 账号，请在上方输入 GitHub 用户名后点击「+ 添加账号」")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(store.githubStarAccounts.enumerated()), id: \.element.id) { idx, acc in
                                let isSyncingThis = store.syncingAccountIDs.contains(acc.id)
                                let isEditingThis = editingAccountOriginalUsername?.caseInsensitiveCompare(acc.username) == .orderedSame
                                HStack(spacing: 12) {
                                    HStack(spacing: 7) {
                                        Image(systemName: "person.crop.circle.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(AppTheme.accent)
                                        Text("@\(acc.username)")
                                            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                                            .lineLimit(1)
                                    }
                                    .frame(width: 150, alignment: .leading)

                                    HStack(spacing: 6) {
                                        Text(acc.token.isEmpty ? "公开免密" : "已配 Token")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(acc.token.isEmpty ? .secondary : AppTheme.statusClean)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(AppTheme.subtleSurface)
                                            )
                                        if !acc.note.isEmpty {
                                            Text(acc.note)
                                                .font(.system(size: 11.5))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(width: 170, alignment: .leading)

                                    Text("\(store.countForStarredAccount(acc.username)) 个")
                                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                        .frame(width: 85, alignment: .trailing)

                                    Group {
                                        if isSyncingThis {
                                            HStack(spacing: 6) {
                                                ProgressView().controlSize(.mini)
                                                Text("正在拉取 Star...")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.secondary)
                                            }
                                        } else if let err = acc.lastSyncError, !err.isEmpty {
                                            HStack(spacing: 5) {
                                                Circle().fill(AppTheme.statusDanger).frame(width: 6, height: 6)
                                                Text(err)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(AppTheme.statusDanger)
                                                    .lineLimit(1)
                                            }
                                        } else if let syncedAt = acc.lastSyncedAt {
                                            HStack(spacing: 5) {
                                                Circle().fill(AppTheme.statusClean).frame(width: 6, height: 6)
                                                Text("同步于 \(StarredRepository.formatRelativeDate(syncedAt))")
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                            }
                                        } else {
                                            Text("尚未同步")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    HStack(spacing: 6) {
                                        Button("编辑") {
                                            editingAccountOriginalUsername = acc.username
                                            newStarUsername = acc.username
                                            newStarNote = acc.note
                                            newStarToken = acc.token
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)

                                        Button("同步") {
                                            Task { await store.syncGitHubStars(for: acc) }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .disabled(isSyncingThis)

                                        Button("主页") {
                                            ExternalLauncher.openInBrowser(urlString: "https://github.com/\(acc.username)?tab=stars")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)

                                        Button("移除") {
                                            if isEditingThis {
                                                editingAccountOriginalUsername = nil
                                                newStarUsername = ""
                                                newStarNote = ""
                                                newStarToken = ""
                                            }
                                            store.removeGitHubAccount(acc)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                    .frame(width: 215, alignment: .trailing)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(isEditingThis ? AppTheme.selectedBorder.opacity(0.08) : Color.clear)

                                if idx < store.githubStarAccounts.count - 1 {
                                    Divider()
                                        .padding(.horizontal, 16)
                                        .opacity(0.5)
                                }
                            }
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.hairlineBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(18)
    }

    // MARK: - Tab 3: 虚拟分组管理
    private var groupsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 顶部新建分组卡片
            HStack(spacing: 12) {
                TextField("输入新分组名称...", text: $newGroupName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 190)

                Divider()
                    .frame(height: 16)

                HStack(spacing: 4) {
                    ForEach(availableIcons, id: \.self) { icon in
                        Button {
                            newGroupIcon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 11))
                                .frame(width: 24, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(newGroupIcon == icon ? AppTheme.elevatedSurface : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(newGroupIcon == icon ? AppTheme.selectedBorder : AppTheme.hairlineBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .fixedSize()

                Divider()
                    .frame(height: 16)

                HStack(spacing: 6) {
                    ForEach(availableColors, id: \.self) { colorHex in
                        let dummy = RepoGroup(name: "", icon: "", colorHex: colorHex)
                        Button {
                            newGroupColor = colorHex
                        } label: {
                            Circle()
                                .fill(dummy.color)
                                .frame(width: 14, height: 14)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: newGroupColor == colorHex ? 1.5 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .fixedSize()

                Spacer(minLength: 8)

                Button("+ 新建分组") {
                    store.createGroup(name: newGroupName, icon: newGroupIcon, colorHex: newGroupColor)
                    newGroupName = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .controlSize(.small)
                .fixedSize()
                .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.hairlineBorder, lineWidth: 1)
            )

            // 分组表格卡片
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text("分组名称")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("颜色标识")
                        .frame(width: 90, alignment: .center)
                    Text("关联仓库数")
                        .frame(width: 100, alignment: .trailing)
                    Text("操作")
                        .frame(width: 80, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(AppTheme.subtleSurface)

                Divider()

                if store.groups.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 26))
                            .foregroundStyle(.tertiary)
                        Text("暂无自定义虚拟分组")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(store.groups.enumerated()), id: \.element.id) { idx, group in
                                HStack(spacing: 12) {
                                    HStack(spacing: 8) {
                                        Image(systemName: group.icon)
                                            .font(.system(size: 12))
                                            .foregroundStyle(group.color)
                                            .frame(width: 18)
                                        Text(group.name)
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    HStack(spacing: 5) {
                                        Circle()
                                            .fill(group.color)
                                            .frame(width: 7, height: 7)
                                        Text(group.colorHex)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 90, alignment: .center)

                                    Text("\(store.countForGroup(group.id)) 个")
                                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                        .frame(width: 100, alignment: .trailing)

                                    HStack {
                                        Spacer()
                                        Button("删除") {
                                            store.deleteGroup(group)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .fixedSize()
                                    }
                                    .frame(width: 80, alignment: .trailing)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)

                                if idx < store.groups.count - 1 {
                                    Divider()
                                        .padding(.horizontal, 16)
                                        .opacity(0.5)
                                }
                            }
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.hairlineBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(18)
    }

    // MARK: - Tab 4: Git 参数与缓存管理
    private var gitAndCacheTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text("设置项")
                        .frame(width: 170, alignment: .leading)
                    Text("当前策略与路径说明")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("配置操作")
                        .frame(width: 180, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(AppTheme.subtleSurface)

                Divider()

                ScrollView {
                    VStack(spacing: 0) {
                        settingCardRow(
                            icon: "arrow.down.to.line",
                            title: "Git Pull 拉取策略",
                            subtitle: store.pullUseRebase ? "git pull --rebase --autostash（推荐，保持线性历史）" : "git pull（默认合并模式）"
                        ) {
                            Toggle("使用 Rebase", isOn: $store.pullUseRebase)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .fixedSize()
                                .onChange(of: store.pullUseRebase) { _, _ in store.saveConfig() }
                        }

                        Divider().padding(.horizontal, 16).opacity(0.5)

                        settingCardRow(
                            icon: "arrow.triangle.2.circlepath",
                            title: "Git Fetch 清理引用",
                            subtitle: store.fetchUsePrune ? "git fetch --all --prune（自动清理远程已删除分支）" : "git fetch --all（保留全部远程引用）"
                        ) {
                            Toggle("启用 --prune", isOn: $store.fetchUsePrune)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .fixedSize()
                                .onChange(of: store.fetchUsePrune) { _, _ in store.saveConfig() }
                        }

                        Divider().padding(.horizontal, 16).opacity(0.5)

                        settingCardRow(
                            icon: "square.grid.2x2",
                            title: "默认主看板布局",
                            subtitle: "设置主窗口仓库列表默认展示为卡片网格或紧凑表格"
                        ) {
                            Picker("", selection: $store.viewMode) {
                                ForEach(DashboardViewMode.allCases, id: \.self) { m in
                                    Text(m.rawValue).tag(m)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 120)
                            .onChange(of: store.viewMode) { _, _ in store.saveConfig() }
                        }

                        Divider().padding(.horizontal, 16).opacity(0.5)

                        settingCardRow(
                            icon: "arrow.up.arrow.down",
                            title: "默认排序规则",
                            subtitle: "当前按「\(store.sortOption.rawValue)」排序"
                        ) {
                            Picker("", selection: $store.sortOption) {
                                ForEach(RepoSortOption.allCases, id: \.self) { opt in
                                    Text(opt.rawValue).tag(opt)
                                }
                            }
                            .labelsHidden()
                            .controlSize(.small)
                            .frame(width: 150)
                            .onChange(of: store.sortOption) { _, _ in store.saveConfig() }
                        }

                        Divider().padding(.horizontal, 16).opacity(0.5)

                        settingCardRow(
                            icon: "photo.stack",
                            title: "项目图标与头像缓存",
                            subtitle: ProjectMetadataInspector.avatarCacheDirectory.path
                        ) {
                            Button("清空缓存并重扫") {
                                store.clearAvatarCacheAndReload()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .fixedSize()
                        }

                        Divider().padding(.horizontal, 16).opacity(0.5)

                        settingCardRow(
                            icon: "doc.badge.gearshape",
                            title: "本地配置文件路径",
                            subtitle: store.configFileURL.path
                        ) {
                            Button("在 Finder 中打开") {
                                ExternalLauncher.openInFinder(path: store.configFileURL.deletingLastPathComponent().path)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .fixedSize()
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.hairlineBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(18)
    }

    private func settingCardRow<Control: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(width: 170, alignment: .leading)

            Text(subtitle)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(subtitle)

            HStack {
                Spacer()
                control()
            }
            .frame(width: 180, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - Tab 5: Git 执行日志
    private var actionLogsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("共记录 \(store.actionLogs.count) 条 Git 命令执行记录")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.actionLogs.isEmpty {
                    Button("清空执行日志") {
                        store.clearActionLogs()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text("状态")
                        .frame(width: 56, alignment: .leading)
                    Text("执行时间")
                        .frame(width: 82, alignment: .leading)
                    Text("仓库名称")
                        .frame(width: 130, alignment: .leading)
                    Text("Git 命令")
                        .frame(width: 190, alignment: .leading)
                    Text("输出摘要")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(AppTheme.subtleSurface)

                Divider()

                if store.actionLogs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "terminal")
                            .font(.system(size: 26))
                            .foregroundStyle(.tertiary)
                        Text("暂无手动 Git 命令执行记录")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(store.actionLogs.enumerated()), id: \.element.id) { idx, log in
                                HStack(spacing: 12) {
                                    HStack(spacing: 5) {
                                        Circle()
                                            .fill(log.success ? AppTheme.statusClean : AppTheme.statusDanger)
                                            .frame(width: 6, height: 6)
                                        Text(log.success ? "成功" : "失败")
                                            .font(.system(size: 11, weight: .medium))
                                            .lineLimit(1)
                                    }
                                    .frame(width: 56, alignment: .leading)

                                    Text(log.timestamp.formatted(date: .omitted, time: .standard))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(width: 82, alignment: .leading)

                                    Text(log.repoName)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                        .frame(width: 130, alignment: .leading)

                                    Text(log.command)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(width: 190, alignment: .leading)
                                        .help(log.command)

                                    Text(log.output.isEmpty ? "—" : log.output.replacingOccurrences(of: "\n", with: " "))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .help(log.output)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .contextMenu {
                                    Button("复制完整输出") {
                                        ExternalLauncher.copyToPasteboard(log.output)
                                    }
                                }

                                if idx < store.actionLogs.count - 1 {
                                    Divider().padding(.horizontal, 16).opacity(0.5)
                                }
                            }
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.hairlineBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(18)
    }

    private var appVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.3.0"
    }

    // MARK: - Tab 6: 关于我们与版本信息
    private var aboutUsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 顶部品牌卡片
            HStack(spacing: 16) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("GitRadar")
                            .font(.system(size: 18, weight: .bold))
                        Text("v\(appVersionString)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(AppTheme.subtleSurface))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.hairlineBorder, lineWidth: 1))
                    }

                    Text("macOS 原生全平台本地 Git 仓库全景管理工具")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)

                    Text("GitHub · GitLab · Gitee · Bitbucket · Gitea/Codeberg · 自建 Git · 本地仓库")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.hairlineBorder, lineWidth: 1)
            )

            // 版本与环境详情表格卡片
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text("属性项")
                        .frame(width: 170, alignment: .leading)
                    Text("详细信息")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(AppTheme.subtleSurface)

                Divider()

                VStack(spacing: 0) {
                    aboutTableRow(label: "应用标识", value: "GitRadar (com.gitradar.app)")
                    Divider().padding(.horizontal, 16).opacity(0.5)
                    aboutTableRow(label: "当前版本", value: "v\(appVersionString) (Release · Tag v\(appVersionString))")
                    Divider().padding(.horizontal, 16).opacity(0.5)
                    aboutTableRow(label: "技术架构", value: "macOS Native · Swift 6 + SwiftUI + AppKit (Apple Silicon)")
                    Divider().padding(.horizontal, 16).opacity(0.5)
                    aboutTableRow(label: "操作系统版本", value: ProcessInfo.processInfo.operatingSystemVersionString)
                    Divider().padding(.horizontal, 16).opacity(0.5)
                    aboutTableRow(label: "当前监控统计", value: "共扫描 \(store.repositories.count) 个仓库（可见 \(store.visibleRepositories.count) 个，已过滤 \(store.excludedRepositories.count) 个）")
                    Divider().padding(.horizontal, 16).opacity(0.5)
                    aboutTableRow(label: "隐私与安全机制", value: "纯本地离线运行，配置与缓存仅存储于本机，不上传任何代码或仓库信息")
                    Divider().padding(.horizontal, 16).opacity(0.5)
                    aboutTableRow(label: "开源协议与版权", value: "MIT License · © 2026 GitRadar")
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.hairlineBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer(minLength: 0)
        }
        .padding(18)
    }

    private func aboutTableRow(label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 170, alignment: .leading)

            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}
