import AppKit
import Foundation
import SwiftUI

struct RepoUserMeta: Codable, Hashable {
    var isFavorite: Bool = false
    var groupIDs: Set<UUID> = []
    var customNote: String = ""
}

struct PersistedRadarConfig: Codable {
    var watchedDirectories: [WatchedDirectory]
    var manualRepoPaths: Set<String>
    var groups: [RepoGroup]
    var repoMetaMap: [String: RepoUserMeta]
    var preferredEditorPath: String?
    var preferredTerminalPath: String?
    var viewMode: DashboardViewMode
    var sortOption: RepoSortOption
    var defaultScanDepth: Int
}

@MainActor
final class RadarStore: ObservableObject {
    // 核心数据状态
    @Published var repositories: [GitRepository] = []
    @Published var watchedDirectories: [WatchedDirectory] = []
    @Published var manualRepoPaths: Set<String> = []
    @Published var groups: [RepoGroup] = []
    @Published var repoMetaMap: [String: RepoUserMeta] = [:]

    // 导航与筛选状态
    @Published var selectedFilter: SidebarFilter = .all
    @Published var selectedRepoID: String? = nil
    @Published var searchText: String = ""
    @Published var viewMode: DashboardViewMode = .grid
    @Published var sortOption: RepoSortOption = .healthPriority
    @Published var showDetailInspector: Bool = true

    // 外部工具偏好
    @Published var installedEditors: [ExternalApp] = []
    @Published var installedTerminals: [ExternalApp] = []
    @Published var preferredEditorPath: String? = nil
    @Published var preferredTerminalPath: String? = nil
    @Published var defaultScanDepth: Int = 4

    // 运行状态与反馈
    @Published var isScanning: Bool = false
    @Published var busyRepoIDs: Set<String> = []
    @Published var statusBannerMessage: String? = nil
    @Published var statusBannerIsError: Bool = false
    @Published var actionLogs: [GitActionLog] = []

    // 弹窗控制
    @Published var showNewGroupSheet: Bool = false
    @Published var showSettingsSheet: Bool = false

    private let configFileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("GitRadar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.configFileURL = dir.appendingPathComponent("config.json")

        self.installedEditors = ExternalLauncher.installedEditors()
        self.installedTerminals = ExternalLauncher.installedTerminals()

        loadConfig()

        if preferredEditorPath == nil {
            preferredEditorPath = installedEditors.first?.bundlePath
        }
        if preferredTerminalPath == nil {
            preferredTerminalPath = installedTerminals.first?.bundlePath
        }

        Task {
            await scanAndRefreshAll()
        }
    }

    // MARK: - 配置持久化
    private func loadConfig() {
        if let data = try? Data(contentsOf: configFileURL),
           let decoded = try? JSONDecoder().decode(PersistedRadarConfig.self, from: data) {
            self.watchedDirectories = decoded.watchedDirectories
            self.manualRepoPaths = decoded.manualRepoPaths
            self.groups = decoded.groups
            self.repoMetaMap = decoded.repoMetaMap
            self.preferredEditorPath = decoded.preferredEditorPath
            self.preferredTerminalPath = decoded.preferredTerminalPath
            self.viewMode = decoded.viewMode
            self.sortOption = decoded.sortOption
            self.defaultScanDepth = max(1, min(8, decoded.defaultScanDepth))
            return
        }

        // 首次启动默认初始化
        let defaultGroups = [
            RepoGroup(name: "AI 与探索", icon: "sparkles", colorHex: "purple"),
            RepoGroup(name: "核心工作区", icon: "briefcase.fill", colorHex: "blue"),
            RepoGroup(name: "个人工具箱", icon: "wrench.and.screwdriver.fill", colorHex: "orange"),
            RepoGroup(name: "开源参考", icon: "globe", colorHex: "teal")
        ]
        self.groups = defaultGroups

        // 自动检测常用开发目录（如果存在 ~/AI 则默认加入扫描）
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let defaultAIDir = (home as NSString).appendingPathComponent("AI")
        if FileManager.default.fileExists(atPath: defaultAIDir) {
            self.watchedDirectories = [WatchedDirectory(path: defaultAIDir, maxDepth: 3)]
        }
        saveConfig()
    }

    func saveConfig() {
        let cfg = PersistedRadarConfig(
            watchedDirectories: watchedDirectories,
            manualRepoPaths: manualRepoPaths,
            groups: groups,
            repoMetaMap: repoMetaMap,
            preferredEditorPath: preferredEditorPath,
            preferredTerminalPath: preferredTerminalPath,
            viewMode: viewMode,
            sortOption: sortOption,
            defaultScanDepth: defaultScanDepth
        )
        if let data = try? JSONEncoder().encode(cfg) {
            try? data.write(to: configFileURL, options: .atomic)
        }
    }

    // MARK: - 计算属性与过滤结果
    var preferredEditor: ExternalApp? {
        installedEditors.first(where: { $0.bundlePath == preferredEditorPath }) ?? installedEditors.first
    }

    var preferredTerminal: ExternalApp? {
        installedTerminals.first(where: { $0.bundlePath == preferredTerminalPath }) ?? installedTerminals.first
    }

    var selectedRepository: GitRepository? {
        guard let id = selectedRepoID else { return nil }
        return repositories.first(where: { $0.id == id })
    }

    var filteredRepositories: [GitRepository] {
        var list = repositories

        // 1. 侧边栏过滤
        switch selectedFilter {
        case .all:
            break
        case .dirty:
            list = list.filter { $0.totalUncommittedCount > 0 }
        case .unpushed:
            list = list.filter { $0.aheadCount > 0 }
        case .needsPull:
            list = list.filter { $0.behindCount > 0 }
        case .favorites:
            list = list.filter { $0.isFavorite }
        case .provider(let provider):
            list = list.filter { $0.primaryProvider == provider }
        case .group(let groupID):
            list = list.filter { $0.groupIDs.contains(groupID) }
        case .rootDirectory(let rootPath):
            list = list.filter { $0.rootSourcePath == rootPath || $0.path.hasPrefix(rootPath) }
        }

        // 2. 搜索框过滤
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            list = list.filter { repo in
                repo.name.lowercased().contains(query) ||
                repo.displayPath.lowercased().contains(query) ||
                repo.currentBranch.lowercased().contains(query) ||
                (repo.primaryRemoteSlug?.lowercased().contains(query) ?? false) ||
                (repo.primaryHost?.lowercased().contains(query) ?? false) ||
                (repo.lastCommitMessage?.lowercased().contains(query) ?? false) ||
                repo.customNote.lowercased().contains(query)
            }
        }

        // 3. 排序（收藏置顶优先，其次按所选规则）
        list.sort { a, b in
            if a.isFavorite != b.isFavorite {
                return a.isFavorite && !b.isFavorite
            }
            switch sortOption {
            case .healthPriority:
                if a.healthState.priority != b.healthState.priority {
                    return a.healthState.priority < b.healthState.priority
                }
                return (a.lastCommitDate ?? .distantPast) > (b.lastCommitDate ?? .distantPast)
            case .recentCommit:
                return (a.lastCommitDate ?? .distantPast) > (b.lastCommitDate ?? .distantPast)
            case .nameAsc:
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .uncommittedCount:
                if a.totalUncommittedCount != b.totalUncommittedCount {
                    return a.totalUncommittedCount > b.totalUncommittedCount
                }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .pathAsc:
                return a.path.localizedCaseInsensitiveCompare(b.path) == .orderedAscending
            }
        }

        return list
    }

    // 统计指标
    var dirtyReposCount: Int { repositories.filter { $0.totalUncommittedCount > 0 }.count }
    var unpushedReposCount: Int { repositories.filter { $0.aheadCount > 0 }.count }
    var behindReposCount: Int { repositories.filter { $0.behindCount > 0 }.count }
    var cleanReposCount: Int { repositories.filter { $0.healthState == .clean }.count }
    var favoriteReposCount: Int { repositories.filter { $0.isFavorite }.count }

    func countForProvider(_ provider: GitProvider) -> Int {
        repositories.filter { $0.primaryProvider == provider }.count
    }

    func countForGroup(_ groupID: UUID) -> Int {
        repositories.filter { $0.groupIDs.contains(groupID) }.count
    }

    func countForRootDirectory(_ rootPath: String) -> Int {
        repositories.filter { $0.rootSourcePath == rootPath || $0.path.hasPrefix(rootPath) }.count
    }

    // MARK: - 目录与分组管理
    func promptAddDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择要扫描或添加的目录（支持包含多个 Git 项目的根目录，或单个 Git 仓库）"
        panel.message = "GitRadar 将自动递归发现该目录下的所有 Git 仓库（支持 GitHub、GitLab、Gitee、自建 Git 等所有仓库）"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false

        if panel.runModal() == .OK {
            var addedCount = 0
            for url in panel.urls {
                let path = url.path
                if GitService.isGitRepository(at: path) {
                    manualRepoPaths.insert(path)
                    addedCount += 1
                } else if !watchedDirectories.contains(where: { $0.path == path }) {
                    watchedDirectories.append(WatchedDirectory(path: path, maxDepth: defaultScanDepth))
                    addedCount += 1
                }
            }
            if addedCount > 0 {
                saveConfig()
                Task { await scanAndRefreshAll() }
            }
        }
    }

    func addQuickDirectory(_ rawPath: String) {
        let path = (rawPath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            showBanner("目录不存在：\(rawPath)", isError: true)
            return
        }
        if GitService.isGitRepository(at: path) {
            manualRepoPaths.insert(path)
        } else if !watchedDirectories.contains(where: { $0.path == path }) {
            watchedDirectories.append(WatchedDirectory(path: path, maxDepth: defaultScanDepth))
        }
        saveConfig()
        Task { await scanAndRefreshAll() }
    }

    func removeWatchedDirectory(_ dir: WatchedDirectory) {
        watchedDirectories.removeAll { $0.id == dir.id }
        if case .rootDirectory(let path) = selectedFilter, path == dir.path {
            selectedFilter = .all
        }
        saveConfig()
        Task { await scanAndRefreshAll() }
    }

    func removeRepository(_ repo: GitRepository) {
        manualRepoPaths.remove(repo.path)
        repositories.removeAll { $0.id == repo.id }
        if selectedRepoID == repo.id {
            selectedRepoID = repositories.first?.id
        }
        saveConfig()
    }

    func createGroup(name: String, icon: String, colorHex: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let group = RepoGroup(name: trimmed, icon: icon, colorHex: colorHex)
        groups.append(group)
        saveConfig()
    }

    func deleteGroup(_ group: RepoGroup) {
        groups.removeAll { $0.id == group.id }
        for key in repoMetaMap.keys {
            repoMetaMap[key]?.groupIDs.remove(group.id)
        }
        for idx in repositories.indices {
            repositories[idx].groupIDs.remove(group.id)
        }
        if case .group(let id) = selectedFilter, id == group.id {
            selectedFilter = .all
        }
        saveConfig()
    }

    func toggleFavorite(for repoID: String) {
        var meta = repoMetaMap[repoID] ?? RepoUserMeta()
        meta.isFavorite.toggle()
        repoMetaMap[repoID] = meta
        if let idx = repositories.firstIndex(where: { $0.id == repoID }) {
            repositories[idx].isFavorite = meta.isFavorite
        }
        saveConfig()
    }

    func toggleGroup(_ groupID: UUID, for repoID: String) {
        var meta = repoMetaMap[repoID] ?? RepoUserMeta()
        if meta.groupIDs.contains(groupID) {
            meta.groupIDs.remove(groupID)
        } else {
            meta.groupIDs.insert(groupID)
        }
        repoMetaMap[repoID] = meta
        if let idx = repositories.firstIndex(where: { $0.id == repoID }) {
            repositories[idx].groupIDs = meta.groupIDs
        }
        saveConfig()
    }

    func updateNote(_ note: String, for repoID: String) {
        var meta = repoMetaMap[repoID] ?? RepoUserMeta()
        meta.customNote = note
        repoMetaMap[repoID] = meta
        if let idx = repositories.firstIndex(where: { $0.id == repoID }) {
            repositories[idx].customNote = note
        }
        saveConfig()
    }

    // MARK: - 并发扫描与状态刷新
    func scanAndRefreshAll() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let watchedSnapshot = watchedDirectories
        let manualSnapshot = manualRepoPaths

        // 1. 后台线程扫描所有路径
        let discoveredPairs: [(repoPath: String, rootSource: String)] = await Task.detached(priority: .userInitiated) {
            var seen: Set<String> = []
            var pairs: [(String, String)] = []

            for dir in watchedSnapshot {
                let found = GitService.discoverRepositories(in: dir.path, maxDepth: dir.maxDepth)
                for path in found where !seen.contains(path) {
                    seen.insert(path)
                    pairs.append((path, dir.path))
                }
            }
            for path in manualSnapshot.sorted() where !seen.contains(path) {
                if GitService.isGitRepository(at: path) {
                    seen.insert(path)
                    pairs.append((path, path))
                }
            }
            return pairs
        }.value

        // 2. 并发执行 Git 状态解析
        var loadedRepos: [GitRepository] = await withTaskGroup(of: GitRepository?.self) { group in
            for item in discoveredPairs {
                group.addTask {
                    await GitService.inspectRepository(path: item.repoPath, rootSourcePath: item.rootSource)
                }
            }
            var results: [GitRepository] = []
            for await repo in group {
                if let repo {
                    results.append(repo)
                }
            }
            return results
        }

        // 3. 合并用户元数据（收藏、自定义分组、备注）
        for idx in loadedRepos.indices {
            let id = loadedRepos[idx].id
            if let meta = repoMetaMap[id] {
                loadedRepos[idx].isFavorite = meta.isFavorite
                loadedRepos[idx].groupIDs = meta.groupIDs
                loadedRepos[idx].customNote = meta.customNote
            }
        }

        // 更新扫描时间
        let now = Date()
        for idx in watchedDirectories.indices {
            watchedDirectories[idx].lastScannedAt = now
        }

        self.repositories = loadedRepos
        if selectedRepoID == nil || !loadedRepos.contains(where: { $0.id == selectedRepoID }) {
            selectedRepoID = filteredRepositories.first?.id
        }
        saveConfig()
    }

    func refreshRepository(id repoPath: String) async {
        busyRepoIDs.insert(repoPath)
        defer { busyRepoIDs.remove(repoPath) }

        let rootSource = repositories.first(where: { $0.id == repoPath })?.rootSourcePath ?? repoPath
        guard var updated = await GitService.inspectRepository(path: repoPath, rootSourcePath: rootSource) else {
            return
        }
        if let meta = repoMetaMap[repoPath] {
            updated.isFavorite = meta.isFavorite
            updated.groupIDs = meta.groupIDs
            updated.customNote = meta.customNote
        }
        if let idx = repositories.firstIndex(where: { $0.id == repoPath }) {
            repositories[idx] = updated
        }
    }

    // MARK: - 单个仓库与批量 Git 操作
    func fetchRepository(_ repo: GitRepository) async {
        busyRepoIDs.insert(repo.id)
        defer { busyRepoIDs.remove(repo.id) }

        let res = await GitService.fetch(at: repo.path)
        recordLog(repoName: repo.name, command: "git fetch --all --prune", result: res)
        await refreshRepository(id: repo.id)
        if res.isSuccess {
            showBanner("已刷新远程状态：\(repo.name)")
        } else {
            showBanner("\(repo.name) Fetch 失败：\(res.stderr)", isError: true)
        }
    }

    func pullRepository(_ repo: GitRepository, rebase: Bool = false) async {
        busyRepoIDs.insert(repo.id)
        defer { busyRepoIDs.remove(repo.id) }

        let cmdName = rebase ? "git pull --rebase --autostash" : "git pull"
        let res = await GitService.pull(at: repo.path, rebase: rebase)
        recordLog(repoName: repo.name, command: cmdName, result: res)
        await refreshRepository(id: repo.id)
        if res.isSuccess {
            showBanner("拉取成功：\(repo.name)")
        } else {
            showBanner("\(repo.name) Pull 失败：\(res.combinedOutput)", isError: true)
        }
    }

    func pushRepository(_ repo: GitRepository) async {
        busyRepoIDs.insert(repo.id)
        defer { busyRepoIDs.remove(repo.id) }

        let res = await GitService.push(at: repo.path)
        recordLog(repoName: repo.name, command: "git push", result: res)
        await refreshRepository(id: repo.id)
        if res.isSuccess {
            showBanner("推送成功：\(repo.name)")
        } else {
            showBanner("\(repo.name) Push 失败：\(res.combinedOutput)", isError: true)
        }
    }

    func checkoutBranch(for repo: GitRepository, branch: String, createNew: Bool = false) async {
        busyRepoIDs.insert(repo.id)
        defer { busyRepoIDs.remove(repo.id) }

        let res = await GitService.checkoutBranch(at: repo.path, branch: branch, createNew: createNew)
        recordLog(
            repoName: repo.name,
            command: createNew ? "git checkout -b \(branch)" : "git checkout \(branch)",
            result: res
        )
        await refreshRepository(id: repo.id)
        if res.isSuccess {
            showBanner("\(repo.name) 已切换至分支 \(branch)")
        } else {
            showBanner("切换分支失败：\(res.combinedOutput)", isError: true)
        }
    }

    func commitAllChanges(for repo: GitRepository, message: String, andPush: Bool = false) async -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showBanner("请输入提交信息 (Commit Message)", isError: true)
            return false
        }
        busyRepoIDs.insert(repo.id)
        defer { busyRepoIDs.remove(repo.id) }

        let commitRes = await GitService.stageAllAndCommit(at: repo.path, message: trimmed)
        recordLog(repoName: repo.name, command: "git add -A && git commit -m \"\(trimmed)\"", result: commitRes)

        guard commitRes.isSuccess else {
            await refreshRepository(id: repo.id)
            showBanner("提交失败：\(commitRes.combinedOutput)", isError: true)
            return false
        }

        if andPush {
            let pushRes = await GitService.push(at: repo.path)
            recordLog(repoName: repo.name, command: "git push", result: pushRes)
            await refreshRepository(id: repo.id)
            if pushRes.isSuccess {
                showBanner("\(repo.name) 已提交并推送到远程")
            } else {
                showBanner("\(repo.name) 已本地提交，但推送失败：\(pushRes.combinedOutput)", isError: true)
            }
            return pushRes.isSuccess
        } else {
            await refreshRepository(id: repo.id)
            showBanner("\(repo.name) 已完成本地提交")
            return true
        }
    }

    func discardFile(in repo: GitRepository, file: ChangedFile) async {
        busyRepoIDs.insert(repo.id)
        defer { busyRepoIDs.remove(repo.id) }

        let res = await GitService.discardFileChanges(at: repo.path, file: file)
        recordLog(repoName: repo.name, command: "discard \(file.path)", result: res)
        await refreshRepository(id: repo.id)
        if res.isSuccess {
            showBanner("已还原文件：\(file.path)")
        } else {
            showBanner("还原文件失败：\(res.combinedOutput)", isError: true)
        }
    }

    // 批量操作
    func batchFetchAllVisible() async {
        let targets = filteredRepositories.filter { !$0.remotes.isEmpty }
        guard !targets.isEmpty else {
            showBanner("当前列表没有配置远程仓库的项目", isError: true)
            return
        }
        showBanner("正在并发 Fetch \(targets.count) 个远程仓库...")
        for t in targets { busyRepoIDs.insert(t.id) }

        await withTaskGroup(of: (String, String, CommandResult).self) { group in
            for repo in targets {
                group.addTask {
                    let res = await GitService.fetch(at: repo.path)
                    return (repo.id, repo.name, res)
                }
            }
            for await (repoID, repoName, res) in group {
                recordLog(repoName: repoName, command: "git fetch --all --prune", result: res)
                await refreshRepository(id: repoID)
                busyRepoIDs.remove(repoID)
            }
        }
        showBanner("已完成 \(targets.count) 个仓库的远程状态同步")
    }

    func batchPullAllBehind() async {
        let targets = filteredRepositories.filter { $0.behindCount > 0 && !$0.isDirty }
        guard !targets.isEmpty else {
            showBanner("当前没有可安全自动拉取的仓库（需落后远程且工作区干净）")
            return
        }
        showBanner("正在批量 Pull \(targets.count) 个待更新仓库...")
        for t in targets { busyRepoIDs.insert(t.id) }

        var successCount = 0
        for repo in targets {
            let res = await GitService.pull(at: repo.path, rebase: false)
            recordLog(repoName: repo.name, command: "git pull", result: res)
            if res.isSuccess { successCount += 1 }
            await refreshRepository(id: repo.id)
            busyRepoIDs.remove(repo.id)
        }
        showBanner("批量拉取完成：成功 \(successCount)/\(targets.count) 个仓库")
    }

    // MARK: - 辅助日志与提示
    private func recordLog(repoName: String, command: String, result: CommandResult) {
        let entry = GitActionLog(
            timestamp: Date(),
            repoName: repoName,
            command: command,
            success: result.isSuccess,
            output: result.combinedOutput
        )
        actionLogs.insert(entry, at: 0)
        if actionLogs.count > 100 {
            actionLogs.removeLast(actionLogs.count - 100)
        }
    }

    func showBanner(_ message: String, isError: Bool = false) {
        statusBannerMessage = message
        statusBannerIsError = isError
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self.statusBannerMessage == message {
                withAnimation {
                    self.statusBannerMessage = nil
                }
            }
        }
    }
}
