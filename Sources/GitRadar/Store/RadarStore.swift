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
    var filterRules: [RepoFilterRule]?
}

@MainActor
final class RadarStore: ObservableObject {
    // 核心数据状态
    @Published var repositories: [GitRepository] = []
    @Published var watchedDirectories: [WatchedDirectory] = []
    @Published var manualRepoPaths: Set<String> = []
    @Published var groups: [RepoGroup] = []
    @Published var repoMetaMap: [String: RepoUserMeta] = [:]
    @Published var filterRules: [RepoFilterRule] = []

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

    // 弹窗控制与三次风险确认
    @Published var showNewGroupSheet: Bool = false
    @Published var showSettingsSheet: Bool = false
    @Published var showFilterRulesSheet: Bool = false
    @Published var pendingConfirmation: PendingGitConfirmation? = nil

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
            self.filterRules = decoded.filterRules ?? []
            return
        }

        let defaultGroups = [
            RepoGroup(name: "AI 与探索", icon: "sparkles", colorHex: "purple"),
            RepoGroup(name: "核心工作区", icon: "briefcase.fill", colorHex: "blue"),
            RepoGroup(name: "个人工具箱", icon: "wrench.and.screwdriver.fill", colorHex: "orange"),
            RepoGroup(name: "开源参考", icon: "globe", colorHex: "teal")
        ]
        self.groups = defaultGroups

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
            defaultScanDepth: defaultScanDepth,
            filterRules: filterRules
        )
        if let data = try? JSONEncoder().encode(cfg) {
            try? data.write(to: configFileURL, options: .atomic)
        }
    }

    // MARK: - 过滤规则匹配与可见仓库计算
    func isRepositoryExcluded(_ repo: GitRepository) -> Bool {
        filterRules.contains { $0.matches(repo) }
    }

    func matchingRules(for repo: GitRepository) -> [RepoFilterRule] {
        filterRules.filter { $0.matches(repo) }
    }

    /// 排除命中过滤规则后的所有可见仓库
    var visibleRepositories: [GitRepository] {
        repositories.filter { !isRepositoryExcluded($0) }
    }

    /// 当前被过滤规则隐藏的仓库列表
    var excludedRepositories: [GitRepository] {
        repositories.filter { isRepositoryExcluded($0) }
    }

    var activeFilterRulesCount: Int {
        filterRules.filter(\.isEnabled).count
    }

    func addFilterRule(field: FilterRuleMatchField, pattern: String, note: String = "") {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if filterRules.contains(where: { $0.field == field && $0.pattern.lowercased() == trimmed.lowercased() }) {
            showBanner("该过滤规则已存在")
            return
        }
        let rule = RepoFilterRule(field: field, pattern: trimmed, isEnabled: true, note: note)
        filterRules.insert(rule, at: 0)
        reconcileSelectionAfterFilterChange()
        saveConfig()
        showBanner("已添加过滤规则：\(field.rawValue)「\(trimmed)」")
    }

    func hideRepository(_ repo: GitRepository) {
        addFilterRule(field: .exactPath, pattern: repo.path, note: "手动隐藏仓库：\(repo.name)")
    }

    func hideRemoteHost(_ host: String) {
        addFilterRule(field: .remoteHost, pattern: host, note: "屏蔽域名：\(host)")
    }

    func hideRemoteOrganization(host: String?, org: String) {
        let pattern = (host != nil && !host!.isEmpty) ? "\(host!)/\(org)" : org
        addFilterRule(field: .remoteOrganization, pattern: pattern, note: "屏蔽组织：\(pattern)")
    }

    // MARK: - 域名与组织聚合统计（用于域名与组织管理面板及侧边栏）
    struct DiscoveredOrgSummary: Identifiable, Hashable {
        var id: String { "\(host)/\(org)" }
        let host: String
        let org: String
        let totalCount: Int
        let visibleCount: Int
        let isExcluded: Bool
    }

    struct DiscoveredHostSummary: Identifiable, Hashable {
        var id: String { host }
        let host: String
        let provider: GitProvider
        let totalCount: Int
        let visibleCount: Int
        let isExcluded: Bool
        let organizations: [DiscoveredOrgSummary]
    }

    var discoveredHosts: [DiscoveredHostSummary] {
        var hostReposMap: [String: [GitRepository]] = [:]
        for repo in repositories {
            for host in repo.allRemoteHosts {
                hostReposMap[host, default: []].append(repo)
            }
        }

        return hostReposMap.keys.sorted().map { host in
            let reposForHost = hostReposMap[host] ?? []
            let visibleForHost = reposForHost.filter { !isRepositoryExcluded($0) }
            let hostExcluded = isHostRuleEnabled(host)

            // 聚合该域名下的所有组织/Owner
            var orgReposMap: [String: [GitRepository]] = [:]
            for repo in reposForHost {
                for r in repo.remotes where r.host == host {
                    let parts = r.ownerAndRepo.split(separator: "/").map(String.init)
                    if parts.count >= 2 {
                        let org = parts[0]
                        orgReposMap[org, default: []].append(repo)
                    }
                }
            }

            let orgSummaries: [DiscoveredOrgSummary] = orgReposMap.keys.sorted().map { org in
                let orgRepos = Array(Set(orgReposMap[org] ?? []))
                let orgVisible = orgRepos.filter { !isRepositoryExcluded($0) }
                let orgExcluded = hostExcluded || isOrganizationRuleEnabled(host: host, org: org)
                return DiscoveredOrgSummary(
                    host: host,
                    org: org,
                    totalCount: orgRepos.count,
                    visibleCount: orgVisible.count,
                    isExcluded: orgExcluded
                )
            }

            return DiscoveredHostSummary(
                host: host,
                provider: GitProvider.detect(from: host),
                totalCount: reposForHost.count,
                visibleCount: visibleForHost.count,
                isExcluded: hostExcluded,
                organizations: orgSummaries
            )
        }
    }

    func isHostRuleEnabled(_ host: String) -> Bool {
        filterRules.contains {
            $0.isEnabled &&
            $0.field == .remoteHost &&
            $0.pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == host.lowercased()
        }
    }

    func isOrganizationRuleEnabled(host: String, org: String) -> Bool {
        let combined = "\(host)/\(org)".lowercased()
        let orgLower = org.lowercased()
        return filterRules.contains {
            guard $0.isEnabled && $0.field == .remoteOrganization else { return false }
            let pat = $0.pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return pat == combined || pat == orgLower
        }
    }

    func toggleHostFilter(_ host: String) {
        let lower = host.lowercased()
        if let idx = filterRules.firstIndex(where: { $0.field == .remoteHost && $0.pattern.lowercased() == lower }) {
            filterRules[idx].isEnabled.toggle()
            if !filterRules[idx].isEnabled {
                filterRules.remove(at: idx)
                showBanner("已恢复显示域名：\(host)")
            } else {
                showBanner("已过滤隐藏域名：\(host)")
            }
        } else {
            filterRules.insert(
                RepoFilterRule(field: .remoteHost, pattern: host, isEnabled: true, note: "按域名屏蔽"),
                at: 0
            )
            showBanner("已过滤隐藏域名：\(host)")
        }
        reconcileSelectionAfterFilterChange()
        saveConfig()
    }

    func toggleOrganizationFilter(host: String, org: String) {
        let combined = "\(host)/\(org)"
        let combinedLower = combined.lowercased()
        let orgLower = org.lowercased()

        if let idx = filterRules.firstIndex(where: {
            $0.field == .remoteOrganization &&
            ($0.pattern.lowercased() == combinedLower || $0.pattern.lowercased() == orgLower)
        }) {
            filterRules.remove(at: idx)
            showBanner("已恢复显示组织：\(combined)")
        } else {
            filterRules.insert(
                RepoFilterRule(field: .remoteOrganization, pattern: combined, isEnabled: true, note: "按组织屏蔽"),
                at: 0
            )
            showBanner("已过滤隐藏组织：\(combined)")
        }
        reconcileSelectionAfterFilterChange()
        saveConfig()
    }

    func toggleFilterRule(_ ruleID: UUID) {
        guard let idx = filterRules.firstIndex(where: { $0.id == ruleID }) else { return }
        filterRules[idx].isEnabled.toggle()
        reconcileSelectionAfterFilterChange()
        saveConfig()
    }

    func deleteFilterRule(_ ruleID: UUID) {
        filterRules.removeAll { $0.id == ruleID }
        reconcileSelectionAfterFilterChange()
        saveConfig()
    }

    func restoreExcludedRepository(_ repo: GitRepository) {
        filterRules.removeAll { $0.matches(repo) }
        reconcileSelectionAfterFilterChange()
        saveConfig()
        showBanner("已恢复显示：\(repo.name)")
    }

    private func reconcileSelectionAfterFilterChange() {
        if let currentID = selectedRepoID,
           !visibleRepositories.contains(where: { $0.id == currentID }) {
            selectedRepoID = filteredRepositories.first?.id
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
        return visibleRepositories.first(where: { $0.id == id })
    }

    var filteredRepositories: [GitRepository] {
        var list = visibleRepositories

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
        case .domain(let host):
            list = list.filter { $0.allRemoteHosts.contains(host) }
        case .organization(let host, let org):
            list = list.filter { repo in
                repo.remotes.contains { r in
                    r.host == host && r.ownerAndRepo.lowercased().hasPrefix("\(org.lowercased())/")
                }
            }
        case .group(let groupID):
            list = list.filter { $0.groupIDs.contains(groupID) }
        case .rootDirectory(let rootPath):
            list = list.filter { $0.rootSourcePath == rootPath || $0.path.hasPrefix(rootPath) }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            list = list.filter { repo in
                repo.name.lowercased().contains(query) ||
                repo.displayPath.lowercased().contains(query) ||
                repo.currentBranch.lowercased().contains(query) ||
                (repo.primaryRemoteSlug?.lowercased().contains(query) ?? false) ||
                (repo.primaryHost?.lowercased().contains(query) ?? false) ||
                (repo.lastCommitMessage?.lowercased().contains(query) ?? false) ||
                (repo.readmeExcerpt?.lowercased().contains(query) ?? false)
            }
        }

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

    var dirtyReposCount: Int { visibleRepositories.filter { $0.totalUncommittedCount > 0 }.count }
    var unpushedReposCount: Int { visibleRepositories.filter { $0.aheadCount > 0 }.count }
    var behindReposCount: Int { visibleRepositories.filter { $0.behindCount > 0 }.count }
    var cleanReposCount: Int { visibleRepositories.filter { $0.healthState == .clean }.count }
    var favoriteReposCount: Int { visibleRepositories.filter { $0.isFavorite }.count }

    func countForProvider(_ provider: GitProvider) -> Int {
        visibleRepositories.filter { $0.primaryProvider == provider }.count
    }

    func countForGroup(_ groupID: UUID) -> Int {
        visibleRepositories.filter { $0.groupIDs.contains(groupID) }.count
    }

    func countForRootDirectory(_ rootPath: String) -> Int {
        visibleRepositories.filter { $0.rootSourcePath == rootPath || $0.path.hasPrefix(rootPath) }.count
    }

    // MARK: - 目录与分组管理
    func promptAddDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择要扫描或添加的目录"
        panel.message = "GitRadar 将自动递归发现该目录下的所有 Git 仓库（支持 GitHub、GitLab、Gitee、自建 Git 等）"
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

    // MARK: - 并发扫描与状态刷新
    func scanAndRefreshAll() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let watchedSnapshot = watchedDirectories
        let manualSnapshot = manualRepoPaths

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

        for idx in loadedRepos.indices {
            let id = loadedRepos[idx].id
            if let meta = repoMetaMap[id] {
                loadedRepos[idx].isFavorite = meta.isFavorite
                loadedRepos[idx].groupIDs = meta.groupIDs
                loadedRepos[idx].customNote = meta.customNote
            }
        }

        let now = Date()
        for idx in watchedDirectories.indices {
            watchedDirectories[idx].lastScannedAt = now
        }

        self.repositories = loadedRepos
        if selectedRepoID == nil || !visibleRepositories.contains(where: { $0.id == selectedRepoID }) {
            selectedRepoID = filteredRepositories.first?.id
        }
        saveConfig()

        Task {
            await hydrateRemoteAvatarsIfNeeded()
        }
    }

    private func hydrateRemoteAvatarsIfNeeded() async {
        let candidates = repositories.filter { $0.projectIconPath == nil && $0.remoteAvatarURL != nil }
        guard !candidates.isEmpty else { return }

        for repo in candidates {
            guard let urlStr = repo.remoteAvatarURL else { continue }
            if let cachedPath = await ProjectMetadataInspector.downloadAndCacheAvatar(
                from: urlStr,
                provider: repo.primaryProvider,
                slug: repo.primaryRemoteSlug
            ) {
                if let idx = repositories.firstIndex(where: { $0.id == repo.id }) {
                    repositories[idx].projectIconPath = cachedPath
                }
            }
        }
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

    // MARK: - 一键操作（全部接入「三次风险确认」机制）

    func requestFetchRepository(_ repo: GitRepository) {
        pendingConfirmation = PendingGitConfirmation(
            title: "同步远程分支引用 (Git Fetch)",
            targetDescription: "\(repo.name) (\(repo.displayPath))",
            gitCommandPreview: "git fetch --all --prune",
            step1Warning: "将在仓库「\(repo.name)」下连接远程仓库并拉取所有远程分支最新引用。",
            step2Warning: "带有 `--prune` 参数会自动清理远程已删除的本地追踪分支引用（如 origin/*），请确认无需保留已废弃的远程引用。",
            step3Warning: "确认立即对「\(repo.name)」执行 `git fetch --all --prune`。",
            isDestructive: false
        ) { [weak self] in
            guard let self else { return }
            await self.executeFetchRepository(repo)
        }
    }

    func requestPullRepository(_ repo: GitRepository, rebase: Bool = false) {
        let cmd = rebase ? "git pull --rebase --autostash" : "git pull"
        pendingConfirmation = PendingGitConfirmation(
            title: "拉取并合并远程代码 (Git Pull)",
            targetDescription: "\(repo.name) · 当前分支 \(repo.currentBranch)",
            gitCommandPreview: cmd,
            step1Warning: "即将从远程分支拉取最新提交并合并到「\(repo.name)」的 `\(repo.currentBranch)` 分支。",
            step2Warning: repo.isDirty
                ? "⚠️ 当前工作区有 \(repo.totalUncommittedCount) 个未提交文件！执行 Pull 可能导致合并冲突或因本地修改冲突而中断。"
                : "拉取远程更新将直接推进本地 `\(repo.currentBranch)` 分支的 HEAD 指针，若存在分叉可能触发自动 Merge Commit 或冲突。",
            step3Warning: "最终确认：立即在「\(repo.name)」执行 `\(cmd)`，如有冲突需手动在 IDE 中解决。",
            isDestructive: repo.isDirty
        ) { [weak self] in
            guard let self else { return }
            await self.executePullRepository(repo, rebase: rebase)
        }
    }

    func requestPushRepository(_ repo: GitRepository) {
        pendingConfirmation = PendingGitConfirmation(
            title: "推送本地提交到远程仓库 (Git Push)",
            targetDescription: "\(repo.name) · 分支 \(repo.currentBranch) (待推送 \(repo.aheadCount) 个 Commit)",
            gitCommandPreview: "git push",
            step1Warning: "即将把「\(repo.name)」本地分支 `\(repo.currentBranch)` 上的提交推送至远程服务器 (\(repo.primaryProvider.rawValue))。",
            step2Warning: "推送后代码将立即对远程协作者可见，且可能触发远程仓库的 CI/CD 流水线、Webhook 或自动部署任务。",
            step3Warning: "最终确认：您已检查完所有待推送 Commit 不含敏感密钥或调试代码，立即执行 `git push`。",
            isDestructive: true
        ) { [weak self] in
            guard let self else { return }
            await self.executePushRepository(repo)
        }
    }

    func requestCheckoutBranch(for repo: GitRepository, branch: String, createNew: Bool = false) {
        let cmd = createNew ? "git checkout -b \(branch)" : "git checkout \(branch)"
        pendingConfirmation = PendingGitConfirmation(
            title: createNew ? "新建并切换分支" : "切换本地工作分支",
            targetDescription: "\(repo.name) (\(repo.currentBranch) → \(branch))",
            gitCommandPreview: cmd,
            step1Warning: "即将把「\(repo.name)」的工作区从 `\(repo.currentBranch)` 分支切换到 `\(branch)` 分支。",
            step2Warning: repo.isDirty
                ? "⚠️ 当前工作区存在 \(repo.totalUncommittedCount) 个未提交改动！切换分支可能将未提交改动带入目标分支，或因文件冲突导致切换失败。"
                : "切换分支将重写工作区文件以匹配目标分支 `\(branch)`，正在运行的开发服务或构建进程可能受影响。",
            step3Warning: "最终确认：立即在「\(repo.name)」执行 `\(cmd)`。",
            isDestructive: repo.isDirty
        ) { [weak self] in
            guard let self else { return }
            await self.executeCheckoutBranch(for: repo, branch: branch, createNew: createNew)
        }
    }

    func requestCommitAllChanges(
        for repo: GitRepository,
        message: String,
        andPush: Bool = false,
        onSuccess: @escaping @MainActor () -> Void
    ) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showBanner("请输入提交信息 (Commit Message)", isError: true)
            return
        }
        let cmd = andPush
            ? "git add -A && git commit -m \"\(trimmed)\" && git push"
            : "git add -A && git commit -m \"\(trimmed)\""

        pendingConfirmation = PendingGitConfirmation(
            title: andPush ? "一键全部暂存、提交并推送到远程" : "一键全部暂存并提交",
            targetDescription: "\(repo.name) · 共 \(repo.changedFiles.count) 个变更文件 → 分支 \(repo.currentBranch)",
            gitCommandPreview: cmd,
            step1Warning: "即将执行 `git add -A`，把「\(repo.name)」工作区中的所有修改、删除和未跟踪新文件全部纳入暂存区。",
            step2Warning: "请确认这 \(repo.changedFiles.count) 个变更文件中不包含临时测试文件、`.env` 密钥或大体积构建产物。" + (andPush ? "提交后还将立即推送到远程服务器！" : ""),
            step3Warning: "最终确认：立即以提交信息「\(trimmed)」执行 `\(cmd)`。",
            isDestructive: andPush
        ) { [weak self] in
            guard let self else { return }
            let ok = await self.executeCommitAllChanges(for: repo, message: trimmed, andPush: andPush)
            if ok {
                onSuccess()
            }
        }
    }

    func requestDiscardFile(in repo: GitRepository, file: ChangedFile) {
        let cmd = file.isUntracked ? "git clean -f -- \"\(file.path)\"" : "git checkout HEAD -- \"\(file.path)\""
        pendingConfirmation = PendingGitConfirmation(
            title: "放弃单文件未提交改动 (不可恢复)",
            targetDescription: "\(repo.name) · 文件：\(file.path)",
            gitCommandPreview: cmd,
            step1Warning: "即将针对仓库「\(repo.name)」中的文件 `\(file.path)` 执行永久还原/清理命令。",
            step2Warning: "⚠️ 高危风险：该文件在本地工作区的所有未提交修改（或未跟踪的新文件内容）将被直接抹除，Git 无法通过 reflog 找回未提交的更改！",
            step3Warning: "最终确认：我已确认不再需要 `\(file.path)` 的本地修改，立即执行抹除还原。",
            isDestructive: true
        ) { [weak self] in
            guard let self else { return }
            await self.executeDiscardFile(in: repo, file: file)
        }
    }

    func requestBatchFetchAllVisible() {
        let targets = filteredRepositories.filter { !$0.remotes.isEmpty }
        guard !targets.isEmpty else {
            showBanner("当前列表没有配置远程仓库的项目", isError: true)
            return
        }
        pendingConfirmation = PendingGitConfirmation(
            title: "批量 Fetch 所有远程仓库",
            targetDescription: "当前筛选列表中的 \(targets.count) 个远程仓库",
            gitCommandPreview: "for repo in [\(targets.count) repos]: git fetch --all --prune",
            step1Warning: "即将对当前列表中的 \(targets.count) 个仓库并发执行 `git fetch --all --prune`。",
            step2Warning: "批量网络请求可能在短时间内占用较多带宽与 SSH 连接数，且 `--prune` 会清理各仓库已失效的远程追踪分支引用。",
            step3Warning: "最终确认：立即启动 \(targets.count) 个仓库的批量远程状态拉取。",
            isDestructive: false
        ) { [weak self] in
            guard let self else { return }
            await self.executeBatchFetch(targets: targets)
        }
    }

    func requestBatchPullAllBehind() {
        let targets = filteredRepositories.filter { $0.behindCount > 0 && !$0.isDirty }
        guard !targets.isEmpty else {
            showBanner("当前没有可安全自动拉取的仓库（需落后远程且工作区干净）")
            return
        }
        let names = targets.map(\.name).joined(separator: "、")
        pendingConfirmation = PendingGitConfirmation(
            title: "一键批量 Pull 待更新仓库",
            targetDescription: "共 \(targets.count) 个落后远程的仓库：\(names)",
            gitCommandPreview: "for repo in [\(targets.count) repos]: git pull",
            step1Warning: "即将对 \(targets.count) 个工作区干净但落后于远程的仓库批量执行 `git pull`。",
            step2Warning: "⚠️ 批量拉取将直接更新这些仓库的本地代码文件与分支 HEAD；若某个仓库本地存在分叉提交，可能产生自动合并提交或合并冲突。",
            step3Warning: "最终确认：立即对这 \(targets.count) 个仓库批量执行 `git pull`。",
            isDestructive: true
        ) { [weak self] in
            guard let self else { return }
            await self.executeBatchPull(targets: targets)
        }
    }

    // MARK: - 底层实际执行函数（仅在完成三次确认后被调用）
    private func executeFetchRepository(_ repo: GitRepository) async {
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

    private func executePullRepository(_ repo: GitRepository, rebase: Bool = false) async {
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

    private func executePushRepository(_ repo: GitRepository) async {
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

    private func executeCheckoutBranch(for repo: GitRepository, branch: String, createNew: Bool = false) async {
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

    private func executeCommitAllChanges(for repo: GitRepository, message: String, andPush: Bool = false) async -> Bool {
        busyRepoIDs.insert(repo.id)
        defer { busyRepoIDs.remove(repo.id) }

        let commitRes = await GitService.stageAllAndCommit(at: repo.path, message: message)
        recordLog(repoName: repo.name, command: "git add -A && git commit -m \"\(message)\"", result: commitRes)

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

    private func executeDiscardFile(in repo: GitRepository, file: ChangedFile) async {
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

    private func executeBatchFetch(targets: [GitRepository]) async {
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

    private func executeBatchPull(targets: [GitRepository]) async {
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
