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
    var pullUseRebase: Bool?
    var fetchUsePrune: Bool?
    var autoScanOnLaunch: Bool?
    var githubStarAccounts: [GitHubStarAccount]?
    var defaultCloneDirectory: String?
    var starredSortOption: StarredRepoSortOption?
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case directories = "扫描目录"
    case githubStars = "远程 Star"
    case filter = "过滤管理"
    case groups = "分组管理"
    case gitAndCache = "Git 与缓存"
    case logs = "执行日志"
    case about = "关于我们"

    var id: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .directories: return "folder"
        case .githubStars: return "star.circle"
        case .filter: return "line.3.horizontal.decrease.circle"
        case .groups: return "tag"
        case .gitAndCache: return "slider.horizontal.3"
        case .logs: return "terminal"
        case .about: return "info.circle"
        }
    }
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

    // 远程 GitHub Star 数据状态（支持多账号与默认 Clone 目录设置）
    @Published var githubStarAccounts: [GitHubStarAccount] = []
    @Published var starredRepositories: [StarredRepository] = []
    @Published var defaultCloneDirectory: String? = nil
    @Published var starredSortOption: StarredRepoSortOption = .starredDateDesc
    @Published var selectedStarredRepoID: String? = nil
    @Published var isSyncingStars: Bool = false
    @Published var syncingAccountIDs: Set<String> = []
    @Published var cloningStarredIDs: Set<String> = []
    @Published var hydratingStarredIDs: Set<String> = []
    @Published var showAddGitHubAccountSheet: Bool = false
    @Published var editingGitHubAccount: GitHubStarAccount? = nil

    // 导航与筛选状态
    @Published var selectedFilter: SidebarFilter = .all
    @Published var selectedRepoID: String? = nil
    @Published var searchText: String = ""
    @Published var viewMode: DashboardViewMode = .grid
    @Published var sortOption: RepoSortOption = .healthPriority
    @Published var showDetailInspector: Bool = true

    // 外部工具与 Git 偏好
    @Published var installedEditors: [ExternalApp] = []
    @Published var installedTerminals: [ExternalApp] = []
    @Published var preferredEditorPath: String? = nil
    @Published var preferredTerminalPath: String? = nil
    @Published var defaultScanDepth: Int = 4
    @Published var pullUseRebase: Bool = false
    @Published var fetchUsePrune: Bool = true
    @Published var autoScanOnLaunch: Bool = true

    // 运行状态与反馈
    @Published var isScanning: Bool = false
    @Published var busyRepoIDs: Set<String> = []
    @Published var statusBannerMessage: String? = nil
    @Published var statusBannerIsError: Bool = false
    @Published var actionLogs: [GitActionLog] = []

    // 弹窗控制与三次风险确认
    @Published var showNewGroupSheet: Bool = false
    @Published var showSettingsSheet: Bool = false
    @Published var selectedSettingsTab: SettingsTab = .directories
    @Published var showFilterRulesSheet: Bool = false
    @Published var pendingConfirmation: PendingGitConfirmation? = nil

    let configFileURL: URL
    let starredCacheFileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("GitRadar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.configFileURL = dir.appendingPathComponent("config.json")
        self.starredCacheFileURL = dir.appendingPathComponent("starred_cache.json")

        self.installedEditors = ExternalLauncher.installedEditors()
        self.installedTerminals = ExternalLauncher.installedTerminals()

        loadConfig()
        loadStarredCache()

        if preferredEditorPath == nil {
            preferredEditorPath = installedEditors.first?.bundlePath
        }
        if preferredTerminalPath == nil {
            preferredTerminalPath = installedTerminals.first?.bundlePath
        }

        Task {
            await scanAndRefreshAll()
            if !githubStarAccounts.isEmpty && starredRepositories.isEmpty {
                await syncAllGitHubStars()
            } else {
                await hydrateStarredAvatarsIfNeeded()
            }
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
            self.pullUseRebase = decoded.pullUseRebase ?? false
            self.fetchUsePrune = decoded.fetchUsePrune ?? true
            self.autoScanOnLaunch = decoded.autoScanOnLaunch ?? true
            self.githubStarAccounts = decoded.githubStarAccounts ?? []
            self.defaultCloneDirectory = decoded.defaultCloneDirectory
            self.starredSortOption = decoded.starredSortOption ?? .starredDateDesc
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
            filterRules: filterRules,
            pullUseRebase: pullUseRebase,
            fetchUsePrune: fetchUsePrune,
            autoScanOnLaunch: autoScanOnLaunch,
            githubStarAccounts: githubStarAccounts,
            defaultCloneDirectory: defaultCloneDirectory,
            starredSortOption: starredSortOption
        )
        if let data = try? JSONEncoder().encode(cfg) {
            try? data.write(to: configFileURL, options: .atomic)
        }
    }

    private func loadStarredCache() {
        if let data = try? Data(contentsOf: starredCacheFileURL),
           let decoded = try? JSONDecoder().decode([StarredRepository].self, from: data) {
            self.starredRepositories = decoded
            if selectedStarredRepoID == nil {
                selectedStarredRepoID = decoded.first?.id
            }
        }
    }

    func saveStarredCache() {
        if let data = try? JSONEncoder().encode(starredRepositories) {
            try? data.write(to: starredCacheFileURL, options: .atomic)
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

    var selectedStarredRepository: StarredRepository? {
        guard let id = selectedStarredRepoID else { return nil }
        return starredRepositories.first(where: { $0.id == id })
    }

    /// 查找某个远程 Star 仓库在本机是否已被克隆（匹配 github.com 的 owner/repo）
    func localRepository(matching starred: StarredRepository) -> GitRepository? {
        let targetSlug = starred.fullName.lowercased()
        return repositories.first { repo in
            if let slug = repo.primaryRemoteSlug?.lowercased(), slug == targetSlug {
                return true
            }
            return repo.remotes.contains { $0.ownerAndRepo.lowercased() == targetSlug }
        }
    }

    var starredAllCount: Int { starredRepositories.count }
    var starredRecentUpdatedCount: Int { starredRepositories.filter(\.isRecentlyUpdated).count }
    var starredClonedCount: Int { starredRepositories.filter { localRepository(matching: $0) != nil }.count }

    func countForStarredAccount(_ username: String) -> Int {
        let lower = username.lowercased()
        return starredRepositories.filter { repo in
            repo.starredByAccounts.contains { $0.lowercased() == lower }
        }.count
    }

    var filteredStarredRepositories: [StarredRepository] {
        var list = starredRepositories

        switch selectedFilter {
        case .starredAll:
            break
        case .starredRecentUpdated:
            list = list.filter(\.isRecentlyUpdated)
        case .starredCloned:
            list = list.filter { localRepository(matching: $0) != nil }
        case .starredAccount(let username):
            let lower = username.lowercased()
            list = list.filter { repo in
                repo.starredByAccounts.contains { $0.lowercased() == lower }
            }
        default:
            break
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            list = list.filter { repo in
                repo.fullName.lowercased().contains(query) ||
                repo.name.lowercased().contains(query) ||
                repo.owner.lowercased().contains(query) ||
                (repo.description?.lowercased().contains(query) ?? false) ||
                (repo.language?.lowercased().contains(query) ?? false) ||
                repo.topics.contains(where: { $0.lowercased().contains(query) }) ||
                (repo.latestReleaseTag?.lowercased().contains(query) ?? false) ||
                repo.starredByAccounts.contains(where: { $0.lowercased().contains(query) })
            }
        }

        list.sort { a, b in
            switch starredSortOption {
            case .starredDateDesc:
                let da = a.starredAt ?? a.pushedAt ?? .distantPast
                let db = b.starredAt ?? b.pushedAt ?? .distantPast
                if da != db { return da > db }
                return a.stargazersCount > b.stargazersCount
            case .recentlyUpdated:
                let da = a.pushedAt ?? .distantPast
                let db = b.pushedAt ?? .distantPast
                if da != db { return da > db }
                return a.stargazersCount > b.stargazersCount
            case .starsDesc:
                if a.stargazersCount != b.stargazersCount {
                    return a.stargazersCount > b.stargazersCount
                }
                return a.fullName.localizedCaseInsensitiveCompare(b.fullName) == .orderedAscending
            case .nameAsc:
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }

        return list
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
        case .starredAll, .starredRecentUpdated, .starredCloned, .starredAccount:
            break
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

    // MARK: - Git 操作确认机制（单项目操作仅需单次确认，批量操作需三次确认）

    func requestFetchRepository(_ repo: GitRepository) {
        pendingConfirmation = PendingGitConfirmation(
            title: "确认同步远程引用 (Git Fetch)",
            targetDescription: "\(repo.name) (\(repo.displayPath))",
            gitCommandPreview: "git fetch --all --prune",
            isBatchTripleConfirm: false,
            step1Warning: "将拉取远程仓库的所有最新分支引用，并清理已删除的远程追踪分支。",
            step2Warning: "",
            step3Warning: "",
            isDestructive: false
        ) { [weak self] in
            guard let self else { return }
            await self.executeFetchRepository(repo)
        }
    }

    func requestPullRepository(_ repo: GitRepository, rebase: Bool = false) {
        let cmd = rebase ? "git pull --rebase --autostash" : "git pull"
        pendingConfirmation = PendingGitConfirmation(
            title: "确认拉取远程代码 (Git Pull)",
            targetDescription: "\(repo.name) · 当前分支 \(repo.currentBranch)",
            gitCommandPreview: cmd,
            isBatchTripleConfirm: false,
            step1Warning: repo.isDirty
                ? "⚠️ 当前工作区有 \(repo.totalUncommittedCount) 个未提交文件，执行拉取可能产生合并冲突。"
                : "将从远程分支拉取最新提交并合并到当前本地分支 `\(repo.currentBranch)`。",
            step2Warning: "",
            step3Warning: "",
            isDestructive: repo.isDirty
        ) { [weak self] in
            guard let self else { return }
            await self.executePullRepository(repo, rebase: rebase)
        }
    }

    func requestPushRepository(_ repo: GitRepository) {
        pendingConfirmation = PendingGitConfirmation(
            title: "确认推送到远程仓库 (Git Push)",
            targetDescription: "\(repo.name) · 分支 \(repo.currentBranch) (待推送 \(repo.aheadCount) 个提交)",
            gitCommandPreview: "git push",
            isBatchTripleConfirm: false,
            step1Warning: "将把本地分支 `\(repo.currentBranch)` 的提交推送到远程服务器 (\(repo.primaryProvider.rawValue))。",
            step2Warning: "",
            step3Warning: "",
            isDestructive: false
        ) { [weak self] in
            guard let self else { return }
            await self.executePushRepository(repo)
        }
    }

    func requestCheckoutBranch(for repo: GitRepository, branch: String, createNew: Bool = false) {
        let cmd = createNew ? "git checkout -b \(branch)" : "git checkout \(branch)"
        pendingConfirmation = PendingGitConfirmation(
            title: createNew ? "确认新建并切换分支" : "确认切换本地分支",
            targetDescription: "\(repo.name) (\(repo.currentBranch) → \(branch))",
            gitCommandPreview: cmd,
            isBatchTripleConfirm: false,
            step1Warning: repo.isDirty
                ? "⚠️ 当前工作区存在 \(repo.totalUncommittedCount) 个未提交改动，切换分支可能带入改动或因冲突失败。"
                : "将把工作区切换至分支 `\(branch)`。",
            step2Warning: "",
            step3Warning: "",
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
            title: andPush ? "确认暂存全部、提交并推送" : "确认暂存全部并提交",
            targetDescription: "\(repo.name) · 共 \(repo.changedFiles.count) 个变更文件 → 分支 \(repo.currentBranch)",
            gitCommandPreview: cmd,
            isBatchTripleConfirm: false,
            step1Warning: andPush
                ? "将暂存工作区全部 \(repo.changedFiles.count) 个变更文件进行本地提交，并立即推送至远程服务器。"
                : "将暂存工作区全部 \(repo.changedFiles.count) 个变更文件并提交到本地分支 `\(repo.currentBranch)`。",
            step2Warning: "",
            step3Warning: "",
            isDestructive: false
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
            title: "确认放弃文件修改",
            targetDescription: "\(repo.name) · 文件：\(file.path)",
            gitCommandPreview: cmd,
            isBatchTripleConfirm: false,
            step1Warning: "⚠️ 该文件在本地工作区的未提交修改将被直接还原清除，无法恢复。",
            step2Warning: "",
            step3Warning: "",
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
            isBatchTripleConfirm: true,
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
            isBatchTripleConfirm: true,
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

    // MARK: - 远程 GitHub Star 账号管理、同步与一键 Clone
    func beginAddGitHubAccount() {
        editingGitHubAccount = nil
        showAddGitHubAccountSheet = true
    }

    func beginEditingGitHubAccount(_ account: GitHubStarAccount) {
        editingGitHubAccount = account
        showAddGitHubAccountSheet = true
    }

    func addOrUpdateGitHubAccount(
        originalUsername: String? = nil,
        username: String,
        token: String = "",
        note: String = ""
    ) {
        let cleanedUser = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        guard !cleanedUser.isEmpty else {
            showBanner("请输入有效的 GitHub 用户名", isError: true)
            return
        }

        let cleanedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedOriginal = originalUsername?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")

        // 如果是从已有账号编辑且修改了用户名，先清理旧用户名关联的数据并在原位置更新
        if let oldUser = cleanedOriginal,
           !oldUser.isEmpty,
           oldUser.caseInsensitiveCompare(cleanedUser) != .orderedSame {
            let oldLower = oldUser.lowercased()
            var updatedList: [StarredRepository] = []
            for var repo in starredRepositories {
                repo.starredByAccounts.removeAll { $0.lowercased() == oldLower }
                if !repo.starredByAccounts.isEmpty {
                    updatedList.append(repo)
                }
            }
            starredRepositories = updatedList
            saveStarredCache()

            // 如果新用户名与列表中另一个账号重名，先移除旧项再合并到目标项
            if let existingTargetIdx = githubStarAccounts.firstIndex(where: { $0.username.caseInsensitiveCompare(cleanedUser) == .orderedSame }) {
                githubStarAccounts.removeAll { $0.username.caseInsensitiveCompare(oldUser) == .orderedSame && $0.username.caseInsensitiveCompare(cleanedUser) != .orderedSame }
                if let mergedIdx = githubStarAccounts.firstIndex(where: { $0.username.caseInsensitiveCompare(cleanedUser) == .orderedSame }) {
                    githubStarAccounts[mergedIdx].username = cleanedUser
                    githubStarAccounts[mergedIdx].token = cleanedToken
                    githubStarAccounts[mergedIdx].note = cleanedNote
                    let account = githubStarAccounts[mergedIdx]
                    if case .starredAccount(let selectedUser) = selectedFilter,
                       selectedUser.caseInsensitiveCompare(oldUser) == .orderedSame {
                        selectedFilter = .starredAccount(cleanedUser)
                    }
                    saveConfig()
                    Task { await syncGitHubStars(for: account) }
                    return
                }
                _ = existingTargetIdx
            } else if let oldIdx = githubStarAccounts.firstIndex(where: { $0.username.caseInsensitiveCompare(oldUser) == .orderedSame }) {
                githubStarAccounts[oldIdx] = GitHubStarAccount(
                    username: cleanedUser,
                    token: cleanedToken,
                    note: cleanedNote,
                    lastSyncedAt: nil,
                    lastSyncError: nil
                )
                let account = githubStarAccounts[oldIdx]
                if case .starredAccount(let selectedUser) = selectedFilter,
                   selectedUser.caseInsensitiveCompare(oldUser) == .orderedSame {
                    selectedFilter = .starredAccount(cleanedUser)
                }
                saveConfig()
                Task { await syncGitHubStars(for: account) }
                return
            }
        }

        let account: GitHubStarAccount
        if let idx = githubStarAccounts.firstIndex(where: { $0.username.caseInsensitiveCompare(cleanedUser) == .orderedSame }) {
            githubStarAccounts[idx].username = cleanedUser
            githubStarAccounts[idx].token = cleanedToken
            githubStarAccounts[idx].note = cleanedNote
            account = githubStarAccounts[idx]
        } else {
            let newAcc = GitHubStarAccount(username: cleanedUser, token: cleanedToken, note: cleanedNote)
            githubStarAccounts.append(newAcc)
            account = newAcc
        }

        saveConfig()
        Task {
            await syncGitHubStars(for: account)
        }
    }

    func removeGitHubAccount(_ account: GitHubStarAccount) {
        let lowerUser = account.username.lowercased()
        githubStarAccounts.removeAll { $0.id == account.id }

        // 移除仅由该账号关联的 Star，保留同时被其他已配置账号 Star 的仓库
        var updatedList: [StarredRepository] = []
        for var repo in starredRepositories {
            repo.starredByAccounts.removeAll { $0.lowercased() == lowerUser }
            if !repo.starredByAccounts.isEmpty {
                updatedList.append(repo)
            }
        }
        starredRepositories = updatedList

        if case .starredAccount(let selectedUser) = selectedFilter,
           selectedUser.lowercased() == lowerUser {
            selectedFilter = .starredAll
        }
        if selectedStarredRepoID == nil || !starredRepositories.contains(where: { $0.id == selectedStarredRepoID }) {
            selectedStarredRepoID = filteredStarredRepositories.first?.id
        }

        saveConfig()
        saveStarredCache()
        showBanner("已移除 GitHub 账号 @\(account.username)")
    }

    func syncAllGitHubStars() async {
        guard !githubStarAccounts.isEmpty else {
            showAddGitHubAccountSheet = true
            return
        }
        guard !isSyncingStars else { return }
        isSyncingStars = true
        defer { isSyncingStars = false }

        let accountsSnapshot = githubStarAccounts
        showBanner("正在同步 \(accountsSnapshot.count) 个 GitHub 账号的 Star 列表...")

        for acc in accountsSnapshot {
            await syncGitHubStars(for: acc, silentBanner: accountsSnapshot.count > 1)
        }

        showBanner("远程 Star 同步完成，共 \(starredRepositories.count) 个项目")
    }

    func syncGitHubStars(for account: GitHubStarAccount, silentBanner: Bool = false) async {
        let accID = account.id
        guard !syncingAccountIDs.contains(accID) else { return }
        syncingAccountIDs.insert(accID)
        defer { syncingAccountIDs.remove(accID) }

        if !silentBanner {
            showBanner("正在拉取 @\(account.username) 的 GitHub Star...")
        }

        do {
            let usernameForBanner = account.username
            let fetched = try await GitHubStarService.fetchStarredRepositories(account: account) { [weak self] page, totalCount in
                guard page > 1 else { return }
                Task { @MainActor in
                    self?.statusBannerMessage = "正在拉取 @\(usernameForBanner) 的 GitHub Star（第 \(page) 页 · 已获取 \(totalCount) 个）..."
                }
            }
            mergeFetchedStars(fetched, forAccount: account.username)

            if let idx = githubStarAccounts.firstIndex(where: { $0.id == accID }) {
                githubStarAccounts[idx].lastSyncedAt = Date()
                githubStarAccounts[idx].lastSyncError = nil
            }
            saveConfig()
            saveStarredCache()

            if selectedStarredRepoID == nil || !starredRepositories.contains(where: { $0.id == selectedStarredRepoID }) {
                selectedStarredRepoID = filteredStarredRepositories.first?.id
            }

            if !silentBanner {
                showBanner("已同步 @\(account.username)：共 \(fetched.count) 个 Star 项目")
            }

            Task {
                await hydrateStarredAvatarsIfNeeded()
                if let current = selectedStarredRepository {
                    await hydrateStarredRepoDetailsIfNeeded(current)
                }
            }
        } catch {
            let msg = error.localizedDescription
            if let idx = githubStarAccounts.firstIndex(where: { $0.id == accID }) {
                githubStarAccounts[idx].lastSyncError = msg
            }
            saveConfig()
            showBanner("@\(account.username) 同步失败：\(msg)", isError: true)
        }
    }

    private func mergeFetchedStars(_ fetched: [StarredRepository], forAccount username: String) {
        let lowerUser = username.lowercased()
        var existingMap: [String: StarredRepository] = [:]

        // 先从现有列表中清理该账号旧标记，稍后按最新拉取结果重新合并
        for var repo in starredRepositories {
            repo.starredByAccounts.removeAll { $0.lowercased() == lowerUser }
            existingMap[repo.id] = repo
        }

        for incoming in fetched {
            if var old = existingMap[incoming.id] {
                old.description = incoming.description ?? old.description
                old.language = incoming.language ?? old.language
                old.topics = incoming.topics.isEmpty ? old.topics : incoming.topics
                old.stargazersCount = incoming.stargazersCount
                old.forksCount = incoming.forksCount
                old.openIssuesCount = incoming.openIssuesCount
                old.isArchived = incoming.isArchived
                old.defaultBranch = incoming.defaultBranch
                old.avatarURL = incoming.avatarURL ?? old.avatarURL
                old.cachedAvatarPath = incoming.cachedAvatarPath ?? old.cachedAvatarPath
                old.pushedAt = incoming.pushedAt ?? old.pushedAt
                if let incomingStarred = incoming.starredAt {
                    if let existingStarred = old.starredAt {
                        old.starredAt = max(existingStarred, incomingStarred)
                    } else {
                        old.starredAt = incomingStarred
                    }
                }
                if !old.starredByAccounts.contains(where: { $0.lowercased() == lowerUser }) {
                    old.starredByAccounts.append(username)
                }
                existingMap[incoming.id] = old
            } else {
                existingMap[incoming.id] = incoming
            }
        }

        // 只保留至少属于一个已配置账号的 Star 仓库
        self.starredRepositories = existingMap.values
            .filter { !$0.starredByAccounts.isEmpty }
            .sorted { ($0.starredAt ?? $0.pushedAt ?? .distantPast) > ($1.starredAt ?? $1.pushedAt ?? .distantPast) }
    }

    func hydrateStarredAvatarsIfNeeded() async {
        let candidates = starredRepositories.filter { $0.cachedAvatarPath == nil && $0.avatarURL != nil }
        guard !candidates.isEmpty else { return }

        var changed = false
        for repo in candidates.prefix(60) {
            guard let urlStr = repo.avatarURL else { continue }
            if let cachedPath = await ProjectMetadataInspector.downloadAndCacheAvatar(
                from: urlStr,
                provider: .github,
                slug: repo.fullName
            ) {
                if let idx = starredRepositories.firstIndex(where: { $0.id == repo.id }) {
                    starredRepositories[idx].cachedAvatarPath = cachedPath
                    changed = true
                }
            }
        }
        if changed {
            saveStarredCache()
        }
    }

    func hydrateStarredRepoDetailsIfNeeded(_ repo: StarredRepository, force: Bool = false) async {
        if !force && repo.readmeFullText != nil && repo.latestReleaseTag != nil {
            return
        }
        guard !hydratingStarredIDs.contains(repo.id) else { return }
        hydratingStarredIDs.insert(repo.id)
        defer { hydratingStarredIDs.remove(repo.id) }

        // 优先使用关联账号中配置了 Token 的凭据
        let token = githubStarAccounts
            .first(where: { acc in
                !acc.token.isEmpty && repo.starredByAccounts.contains(where: { $0.caseInsensitiveCompare(acc.username) == .orderedSame })
            })?.token
            ?? githubStarAccounts.first(where: { !$0.token.isEmpty })?.token

        let result = await GitHubStarService.fetchReleaseAndReadme(
            fullName: repo.fullName,
            defaultBranch: repo.defaultBranch,
            token: token
        )

        if let idx = starredRepositories.firstIndex(where: { $0.id == repo.id }) {
            if let tag = result.latestReleaseTag {
                starredRepositories[idx].latestReleaseTag = tag
                starredRepositories[idx].latestReleaseName = result.latestReleaseName
                starredRepositories[idx].latestReleasePublishedAt = result.latestReleasePublishedAt
                starredRepositories[idx].latestReleaseBody = result.latestReleaseBody
                starredRepositories[idx].latestReleaseHTMLURL = result.latestReleaseHTMLURL
            }
            if let full = result.readmeFullText {
                starredRepositories[idx].readmeExcerpt = result.readmeExcerpt
                starredRepositories[idx].readmeFullText = full
            }
            saveStarredCache()
        }
    }

    // MARK: - 默认 Clone 目录设置与一键 Clone 逻辑
    var formattedDefaultCloneDirectory: String? {
        guard let dir = defaultCloneDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !dir.isEmpty else {
            return nil
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if dir.hasPrefix(home) {
            return "~" + dir.dropFirst(home.count)
        }
        return dir
    }

    func setDefaultCloneDirectory(_ rawPath: String?) {
        if let rawPath, !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = (rawPath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
            defaultCloneDirectory = expanded
            showBanner("已设置默认 Clone 目录：\(expanded)")
        } else {
            defaultCloneDirectory = nil
            showBanner("已清除默认 Clone 目录（每次 Clone 时将弹窗选择）")
        }
        saveConfig()
    }

    func promptSelectDefaultCloneDirectory() {
        let panel = NSOpenPanel()
        panel.title = "设置远程 Star 默认 Clone 目录"
        panel.message = "设置后，点击远程 Star 仓库的「一键 Clone」将直接克隆到此目录下，不再弹窗询问"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            setDefaultCloneDirectory(url.path)
        }
    }

    /// 触发远程 Star 仓库 Clone：若已设置默认目录则直接克隆；否则弹窗选择保存目录
    func cloneStarredRepository(_ starred: StarredRepository) {
        if let existingLocal = localRepository(matching: starred) {
            showBanner("该仓库已存在于本地：\(existingLocal.displayPath)")
            return
        }
        guard !cloningStarredIDs.contains(starred.id) else { return }

        let targetParentDir: String
        if let configuredDir = defaultCloneDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredDir.isEmpty {
            targetParentDir = (configuredDir as NSString).expandingTildeInPath
        } else {
            // 未设置默认目录：弹窗让用户选择目录
            let panel = NSOpenPanel()
            panel.title = "选择 Clone 保存目录"
            panel.message = "将克隆「\(starred.fullName)」到所选文件夹下的 \(starred.name) 目录（可在设置 → 远程 Star 中配置默认目录免弹窗）"
            panel.prompt = "克隆到此目录"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            if let firstWatched = watchedDirectories.first {
                panel.directoryURL = URL(fileURLWithPath: firstWatched.path)
            }

            guard panel.runModal() == .OK, let pickedURL = panel.url else {
                return
            }
            targetParentDir = pickedURL.path
        }

        let destinationPath = (targetParentDir as NSString).appendingPathComponent(starred.name)
        if FileManager.default.fileExists(atPath: destinationPath) {
            if GitService.isGitRepository(at: destinationPath) {
                manualRepoPaths.insert(destinationPath)
                saveConfig()
                showBanner("检测到本地已存在该仓库，正在刷新本地列表...")
                Task { await scanAndRefreshAll() }
            } else {
                showBanner("目标目录已存在同名非 Git 文件夹：\(destinationPath)", isError: true)
            }
            return
        }

        Task {
            await executeCloneStarredRepository(starred, destinationPath: destinationPath, parentDir: targetParentDir)
        }
    }

    private func executeCloneStarredRepository(
        _ starred: StarredRepository,
        destinationPath: String,
        parentDir: String
    ) async {
        cloningStarredIDs.insert(starred.id)
        defer { cloningStarredIDs.remove(starred.id) }

        showBanner("正在克隆 \(starred.fullName) → \(destinationPath)...")
        let res = await GitService.clone(url: starred.cloneURL, to: destinationPath)
        recordLog(
            repoName: starred.name,
            command: "git clone \(starred.cloneURL) \"\(destinationPath)\"",
            result: res
        )

        guard res.isSuccess else {
            showBanner("克隆 \(starred.name) 失败：\(res.combinedOutput)", isError: true)
            return
        }

        // 确保克隆后的仓库能被本地仓库列表立即收录
        let isCoveredByWatched = watchedDirectories.contains { destinationPath.hasPrefix($0.path) }
        if !isCoveredByWatched {
            manualRepoPaths.insert(destinationPath)
            saveConfig()
        }

        await scanAndRefreshAll()
        showBanner("已克隆完成并纳入本地管理：\(starred.name)")
    }

    // MARK: - 辅助日志与提示
    func openSettings(tab: SettingsTab = .directories) {
        selectedSettingsTab = tab
        showSettingsSheet = true
    }

    func clearAvatarCacheAndReload() {
        let dir = ProjectMetadataInspector.avatarCacheDirectory
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        showBanner("已清空图标缓存，正在重新扫描获取...")
        Task {
            await scanAndRefreshAll()
        }
    }

    func clearActionLogs() {
        actionLogs.removeAll()
    }

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
