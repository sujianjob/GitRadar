import Foundation
import SwiftUI

// MARK: - 项目主要技术栈识别（用于为无图片仓库生成差异化专属图标）
enum ProjectTechStack: String, Codable, CaseIterable, Hashable {
    case swift = "Swift"
    case python = "Python"
    case typescript = "TypeScript"
    case javascript = "Node.js"
    case rust = "Rust"
    case golang = "Go"
    case javaKotlin = "JVM"
    case aiSkill = "AI Skill"
    case docs = "Docs"
    case generic = "Git"

    var shortTag: String {
        switch self {
        case .swift: return "SW"
        case .python: return "PY"
        case .typescript: return "TS"
        case .javascript: return "JS"
        case .rust: return "RS"
        case .golang: return "GO"
        case .javaKotlin: return "JV"
        case .aiSkill: return "AI"
        case .docs: return "MD"
        case .generic: return "GIT"
        }
    }

    var sfSymbol: String {
        switch self {
        case .swift: return "swift"
        case .python: return "terminal.fill"
        case .typescript: return "curlybraces.square.fill"
        case .javascript: return "shippingbox.fill"
        case .rust: return "gearshape.2.fill"
        case .golang: return "cpu.fill"
        case .javaKotlin: return "cup.and.saucer.fill"
        case .aiSkill: return "wand.and.stars"
        case .docs: return "book.closed.fill"
        case .generic: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

// MARK: - Git 托管平台枚举（支持全平台，不止 GitHub）
enum GitProvider: String, Codable, CaseIterable, Identifiable, Hashable {
    case github = "GitHub"
    case gitlab = "GitLab"
    case gitee = "Gitee"
    case bitbucket = "Bitbucket"
    case codeberg = "Codeberg / Gitea"
    case cnb = "CNB / Coding"
    case selfHosted = "自建 / 其他远程"
    case localOnly = "仅本地仓库"

    var id: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .gitlab: return "flame"
        case .gitee: return "g.circle"
        case .bitbucket: return "cylinder.split.1x2"
        case .codeberg: return "mountain.2"
        case .cnb: return "cloud"
        case .selfHosted: return "server.rack"
        case .localOnly: return "folder"
        }
    }

    // 克制的石墨灰/岩石色系（去除刺眼彩虹色）
    var badgeColor: Color {
        switch self {
        case .github: return Color(red: 0.34, green: 0.44, blue: 0.56)
        case .gitlab: return Color(red: 0.68, green: 0.42, blue: 0.28)
        case .gitee: return Color(red: 0.66, green: 0.32, blue: 0.34)
        case .bitbucket: return Color(red: 0.28, green: 0.48, blue: 0.68)
        case .codeberg: return Color(red: 0.28, green: 0.54, blue: 0.46)
        case .cnb: return Color(red: 0.62, green: 0.48, blue: 0.26)
        case .selfHosted: return Color(red: 0.46, green: 0.42, blue: 0.58)
        case .localOnly: return Color.secondary
        }
    }

    static func detect(from host: String) -> GitProvider {
        let lower = host.lowercased()
        if lower.contains("github.com") || lower.contains("github.") {
            return .github
        } else if lower.contains("gitlab.com") || lower.contains("gitlab.") {
            return .gitlab
        } else if lower.contains("gitee.com") {
            return .gitee
        } else if lower.contains("bitbucket.org") || lower.contains("bitbucket.") {
            return .bitbucket
        } else if lower.contains("codeberg.org") || lower.contains("gitea") || lower.contains("forgejo") {
            return .codeberg
        } else if lower.contains("cnb.cool") || lower.contains("coding.net") || lower.contains("aliyun.com") {
            return .cnb
        } else if lower.isEmpty {
            return .localOnly
        } else {
            return .selfHosted
        }
    }
}

// MARK: - 仓库健康状态
enum RepoHealthState: String, Codable, CaseIterable, Hashable {
    case conflict = "存在冲突"
    case dirty = "未提交改动"
    case diverged = "分支分叉"
    case ahead = "待推送"
    case behind = "待拉取"
    case clean = "已同步"
    case localOnly = "本地仓库"

    var color: Color {
        switch self {
        case .conflict: return AppTheme.statusDanger
        case .dirty: return AppTheme.statusDirty
        case .diverged: return AppTheme.statusDanger
        case .ahead: return AppTheme.statusSync
        case .behind: return AppTheme.statusSync
        case .clean: return AppTheme.statusClean
        case .localOnly: return AppTheme.statusNeutral
        }
    }

    var sfSymbol: String {
        switch self {
        case .conflict: return "exclamationmark.triangle.fill"
        case .dirty: return "circle.fill"
        case .diverged: return "arrow.triangle.branch"
        case .ahead: return "arrow.up.circle.fill"
        case .behind: return "arrow.down.circle.fill"
        case .clean: return "checkmark.circle.fill"
        case .localOnly: return "circle.dotted"
        }
    }

    var priority: Int {
        switch self {
        case .conflict: return 0
        case .dirty: return 1
        case .diverged: return 2
        case .ahead: return 3
        case .behind: return 4
        case .localOnly: return 5
        case .clean: return 6
        }
    }
}

// MARK: - Remote 远程信息
struct RemoteInfo: Identifiable, Codable, Hashable {
    var id: String { name }
    let name: String          // e.g. "origin", "upstream"
    let fetchURL: String
    let pushURL: String
    let host: String          // e.g. "github.com", "gitlab.company.com"
    let ownerAndRepo: String  // e.g. "apple/swift"
    let webURL: String?       // e.g. "https://github.com/apple/swift"
    let provider: GitProvider
}

// MARK: - 变更文件项
struct ChangedFile: Identifiable, Hashable, Codable {
    var id: String { "\(statusCode):\(path)" }
    let path: String
    let indexStatus: String   // X in XY porcelain
    let workTreeStatus: String // Y in XY porcelain
    let statusCode: String    // XY trimmed

    var isStaged: Bool {
        indexStatus != " " && indexStatus != "?" && !indexStatus.isEmpty
    }

    var isUntracked: Bool {
        statusCode == "??"
    }

    var isConflict: Bool {
        statusCode == "UU" || statusCode == "AA" || statusCode == "DD" || indexStatus == "U" || workTreeStatus == "U"
    }

    var badgeText: String {
        if isUntracked { return "U" }
        if isConflict { return "!" }
        let trimmed = statusCode.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "M" : trimmed
    }

    var badgeColor: Color {
        if isConflict { return AppTheme.statusDanger }
        if isUntracked { return AppTheme.statusNeutral }
        if statusCode.contains("A") { return AppTheme.statusClean }
        if statusCode.contains("D") { return AppTheme.statusDanger }
        if statusCode.contains("R") { return AppTheme.statusSync }
        return AppTheme.statusDirty
    }

    var statusDescription: String {
        if isConflict { return "冲突" }
        if isUntracked { return "未跟踪" }
        if isStaged && workTreeStatus != " " { return "已暂存 + 修改" }
        if isStaged { return "已暂存" }
        if workTreeStatus == "M" { return "已修改" }
        if workTreeStatus == "D" { return "已删除" }
        return "变更"
    }
}

// MARK: - Commit 历史记录
struct CommitItem: Identifiable, Hashable, Codable {
    var id: String { hash }
    let hash: String
    let shortHash: String
    let subject: String
    let author: String
    let relativeDate: String
    let timestamp: Date
    let refs: String
}

// MARK: - 自定义虚拟分组
struct RepoGroup: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var icon: String
    var colorHex: String

    var color: Color {
        switch colorHex {
        case "blue": return Color(red: 0.28, green: 0.48, blue: 0.72)
        case "purple": return Color(red: 0.48, green: 0.42, blue: 0.68)
        case "orange": return Color(red: 0.76, green: 0.52, blue: 0.22)
        case "green": return Color(red: 0.24, green: 0.58, blue: 0.36)
        case "pink": return Color(red: 0.68, green: 0.36, blue: 0.48)
        case "teal": return Color(red: 0.24, green: 0.54, blue: 0.58)
        case "indigo": return Color(red: 0.36, green: 0.44, blue: 0.66)
        case "red": return Color(red: 0.72, green: 0.28, blue: 0.28)
        default: return AppTheme.accent
        }
    }
}

// MARK: - 监控根目录
struct WatchedDirectory: Identifiable, Codable, Hashable {
    var id: String { path }
    var path: String
    var displayName: String
    var maxDepth: Int
    var lastScannedAt: Date?

    init(path: String, maxDepth: Int = 4, lastScannedAt: Date? = nil) {
        let standardized = (path as NSString).expandingTildeInPath
        self.path = standardized
        self.displayName = URL(fileURLWithPath: standardized).lastPathComponent
        self.maxDepth = maxDepth
        self.lastScannedAt = lastScannedAt
    }
}

// MARK: - 核心 Git 仓库实体
struct GitRepository: Identifiable, Hashable, Codable {
    var id: String { path }
    let name: String
    let path: String
    let parentPath: String
    let rootSourcePath: String

    // Git 状态
    var currentBranch: String
    var upstreamBranch: String?
    var isDetachedHEAD: Bool
    var aheadCount: Int
    var behindCount: Int
    var stagedCount: Int
    var modifiedCount: Int
    var untrackedCount: Int
    var conflictCount: Int
    var stashCount: Int

    // 远程与平台
    var remotes: [RemoteInfo]
    var primaryProvider: GitProvider
    var primaryWebURL: String?
    var primaryRemoteSlug: String?
    var primaryHost: String?

    // 项目专属图标与技术栈
    var projectIconPath: String?
    var remoteAvatarURL: String?
    var techStack: ProjectTechStack

    // README 简介与正文
    var readmeFileName: String?
    var readmeExcerpt: String?
    var readmeFullText: String?

    // 最近一次提交
    var lastCommitHash: String?
    var lastCommitMessage: String?
    var lastCommitAuthor: String?
    var lastCommitRelativeTime: String?
    var lastCommitDate: Date?

    // 分支列表与变更文件
    var localBranches: [String]
    var remoteBranches: [String]
    var changedFiles: [ChangedFile]
    var recentCommits: [CommitItem]

    // 用户元数据（持久化关联）
    var isFavorite: Bool = false
    var groupIDs: Set<UUID> = []
    var customNote: String = ""
    var lastRefreshedAt: Date = Date()

    // 计算属性
    var totalUncommittedCount: Int {
        stagedCount + modifiedCount + untrackedCount + conflictCount
    }

    /// 主远程所属组织/用户名（如从 "langchain-ai/langgraph" 提取 "langchain-ai"）
    var primaryOrganization: String? {
        guard let slug = primaryRemoteSlug, !slug.isEmpty else { return nil }
        let parts = slug.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        return parts.first
    }

    /// 完整的「域名/组织」标识（如 "gitea.corp.com/team-a"）
    var primaryHostAndOrg: String? {
        guard let host = primaryHost, !host.isEmpty, let org = primaryOrganization, !org.isEmpty else {
            return nil
        }
        return "\(host)/\(org)"
    }

    /// 该仓库所有 Remote 涉及的域名集合
    var allRemoteHosts: [String] {
        Array(Set(remotes.map(\.host).filter { !$0.isEmpty })).sorted()
    }

    /// 该仓库所有 Remote 涉及的组织/Owner 集合
    var allRemoteOrganizations: [String] {
        var orgs: Set<String> = []
        for r in remotes {
            let parts = r.ownerAndRepo.split(separator: "/").map(String.init)
            if parts.count >= 2 {
                orgs.insert(parts[0])
                if !r.host.isEmpty {
                    orgs.insert("\(r.host)/\(parts[0])")
                }
            }
        }
        return Array(orgs).sorted()
    }

    var isDirty: Bool {
        totalUncommittedCount > 0
    }

    var healthState: RepoHealthState {
        if conflictCount > 0 { return .conflict }
        if totalUncommittedCount > 0 { return .dirty }
        if remotes.isEmpty { return .localOnly }
        if aheadCount > 0 && behindCount > 0 { return .diverged }
        if aheadCount > 0 { return .ahead }
        if behindCount > 0 { return .behind }
        return .clean
    }

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // 生成两字母项目缩写（用于无图片时的差异化头像展示）
    var monogram: String {
        let separators = CharacterSet(charactersIn: "-_ .")
        let parts = name.components(separatedBy: separators).filter { !$0.isEmpty }
        if parts.count >= 2 {
            let first = parts[0].prefix(1).uppercased()
            let second = parts[1].prefix(1).uppercased()
            return "\(first)\(second)"
        }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count >= 2 {
            return String(clean.prefix(2)).uppercased()
        }
        return clean.uppercased()
    }
}

// MARK: - 侧边栏导航过滤条件
enum SidebarFilter: Hashable {
    case all
    case dirty
    case unpushed
    case needsPull
    case favorites
    case starredAll
    case starredRecentUpdated
    case starredCloned
    case starredAccount(String)
    case provider(GitProvider)
    case domain(String)
    case organization(host: String, org: String)
    case group(UUID)
    case rootDirectory(String)

    var isStarredSection: Bool {
        switch self {
        case .starredAll, .starredRecentUpdated, .starredCloned, .starredAccount:
            return true
        default:
            return false
        }
    }

    var title: String {
        switch self {
        case .all: return "全部仓库"
        case .dirty: return "未提交改动"
        case .unpushed: return "待推送提交"
        case .needsPull: return "待拉取更新"
        case .favorites: return "星标收藏"
        case .starredAll: return "全部远程 Star"
        case .starredRecentUpdated: return "近期版本更新"
        case .starredCloned: return "本机已克隆 Star"
        case .starredAccount(let username): return "@\(username) 的 Star"
        case .provider(let p): return p.rawValue
        case .domain(let host): return "域名：\(host)"
        case .organization(let host, let org): return "\(host)/\(org)"
        case .group: return "自定义分组"
        case .rootDirectory(let path):
            return URL(fileURLWithPath: path).lastPathComponent
        }
    }
}

// MARK: - GitHub 账号与远程 Star 仓库模型
struct GitHubStarAccount: Identifiable, Codable, Hashable, Sendable {
    var id: String { username.lowercased() }
    var username: String
    var token: String = ""
    var note: String = ""
    var lastSyncedAt: Date? = nil
    var lastSyncError: String? = nil
}

enum StarredRepoSortOption: String, Codable, CaseIterable, Sendable {
    case starredDateDesc = "按最近 Star 排序"
    case recentlyUpdated = "按最近更新排序"
    case starsDesc = "按 Star 热度排序"
    case nameAsc = "按项目名称 (A-Z)"
}

struct StarredRepository: Identifiable, Codable, Hashable, Sendable {
    var id: String { fullName.lowercased() }
    let repoId: Int
    let name: String
    let owner: String
    let fullName: String
    let htmlURL: String
    let cloneURL: String
    let sshURL: String
    var description: String?
    var language: String?
    var topics: [String]
    var stargazersCount: Int
    var forksCount: Int
    var openIssuesCount: Int
    var isArchived: Bool
    var defaultBranch: String
    var avatarURL: String?
    var cachedAvatarPath: String?
    var pushedAt: Date?
    var starredAt: Date?
    var starredByAccounts: [String]

    // Release 与 README 附加缓存信息
    var latestReleaseTag: String?
    var latestReleaseName: String?
    var latestReleasePublishedAt: Date?
    var latestReleaseBody: String?
    var latestReleaseHTMLURL: String?
    var readmeExcerpt: String?
    var readmeFullText: String?

    var techStack: ProjectTechStack {
        let lang = (language ?? "").lowercased()
        if lang.contains("swift") { return .swift }
        if lang.contains("python") || lang.contains("jupyter") { return .python }
        if lang.contains("typescript") || lang.contains("vue") || lang.contains("svelte") { return .typescript }
        if lang.contains("javascript") { return .javascript }
        if lang.contains("rust") { return .rust }
        if lang.contains("go") { return .golang }
        if lang.contains("java") || lang.contains("kotlin") || lang.contains("scala") { return .javaKotlin }
        if lang.contains("markdown") { return .docs }
        let topicStr = topics.joined(separator: " ").lowercased()
        if topicStr.contains("ai") || topicStr.contains("llm") || topicStr.contains("agent") || topicStr.contains("mcp") {
            return .aiSkill
        }
        return .generic
    }

    var monogram: String {
        let separators = CharacterSet(charactersIn: "-_ .")
        let parts = name.components(separatedBy: separators).filter { !$0.isEmpty }
        if parts.count >= 2 {
            let first = parts[0].prefix(1).uppercased()
            let second = parts[1].prefix(1).uppercased()
            return "\(first)\(second)"
        }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count >= 2 {
            return String(clean.prefix(2)).uppercased()
        }
        return clean.uppercased()
    }

    var formattedStars: String {
        if stargazersCount >= 1000 {
            return String(format: "%.1fk", Double(stargazersCount) / 1000.0)
        }
        return "\(stargazersCount)"
    }

    var formattedForks: String {
        if forksCount >= 1000 {
            return String(format: "%.1fk", Double(forksCount) / 1000.0)
        }
        return "\(forksCount)"
    }

    var isRecentlyUpdated: Bool {
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        if let relDate = latestReleasePublishedAt, relDate >= cutoff {
            return true
        }
        if let pushed = pushedAt, pushed >= cutoff {
            return true
        }
        return false
    }

    var isStale: Bool {
        guard !isArchived, let pushed = pushedAt else { return false }
        return Date().timeIntervalSince(pushed) > 180 * 86_400
    }

    var relativePushedTime: String {
        guard let pushed = pushedAt else { return "未知" }
        return Self.formatRelativeDate(pushed)
    }

    var relativeStarredTime: String? {
        guard let starred = starredAt else { return nil }
        return Self.formatRelativeDate(starred)
    }

    static func formatRelativeDate(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        let minutes = seconds / 60
        if minutes < 1 { return "刚刚" }
        if minutes < 60 { return "\(minutes) 分钟前" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) 小时前" }
        let days = hours / 24
        if days < 30 { return "\(days) 天前" }
        let months = days / 30
        if months < 12 { return "\(months) 个月前" }
        let years = days / 365
        return "\(years) 年前"
    }
}

// MARK: - 视图与排序枚举
enum DashboardViewMode: String, Codable, CaseIterable {
    case grid = "卡片"
    case table = "表格"

    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .table: return "tablecells"
        }
    }
}

enum RepoSortOption: String, Codable, CaseIterable {
    case healthPriority = "按待处理状态优先"
    case recentCommit = "按最近提交时间"
    case nameAsc = "按仓库名称 (A-Z)"
    case uncommittedCount = "按未提交文件数"
    case pathAsc = "按所在目录路径"
}

// MARK: - 仓库过滤屏蔽规则（命中规则的仓库不显示）
enum FilterRuleMatchField: String, Codable, CaseIterable, Identifiable {
    case smart = "自动匹配"
    case remoteHost = "远程域名"
    case remoteOrganization = "远程组织"
    case repoName = "仓库名称"
    case pathContains = "目录路径"
    case exactPath = "指定路径"
    case remoteContains = "远程地址"

    var id: String { rawValue }
}

struct RepoFilterRule: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var field: FilterRuleMatchField = .smart
    var pattern: String
    var isEnabled: Bool = true
    var note: String = ""

    func matches(_ repo: GitRepository) -> Bool {
        guard isEnabled else { return false }
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let cleaned = Self.stripSchemeAndTrailingSlash(trimmed)

        switch field {
        case .exactPath:
            return repo.path == trimmed || repo.displayPath == trimmed
        case .remoteHost:
            return repo.remotes.contains {
                !$0.host.isEmpty && Self.wildcardOrExactOrSubdomainMatch(host: $0.host, pattern: cleaned)
            }
        case .remoteOrganization:
            return Self.matchesOrganization(repo: repo, pattern: cleaned)
        case .repoName:
            return Self.wildcardOrSubstringMatch(text: repo.name, pattern: trimmed)
        case .pathContains:
            return Self.wildcardOrSubstringMatch(text: repo.path, pattern: trimmed) ||
                   Self.wildcardOrSubstringMatch(text: repo.displayPath, pattern: trimmed)
        case .remoteContains:
            let remoteStr = (repo.primaryWebURL ?? repo.remotes.first?.fetchURL ?? "")
            return Self.wildcardOrSubstringMatch(text: remoteStr, pattern: trimmed)
        case .smart:
            // 自动匹配：域名、组织(host/org 或 org)、仓库名、路径、远程地址任一命中即过滤
            if repo.path == trimmed || repo.displayPath == trimmed { return true }
            if Self.wildcardOrSubstringMatch(text: repo.name, pattern: cleaned) { return true }
            if repo.remotes.contains(where: { !$0.host.isEmpty && Self.wildcardOrExactOrSubdomainMatch(host: $0.host, pattern: cleaned) }) {
                return true
            }
            if Self.matchesOrganization(repo: repo, pattern: cleaned) { return true }
            let remoteStr = (repo.primaryWebURL ?? repo.remotes.first?.fetchURL ?? "")
            if !remoteStr.isEmpty && Self.wildcardOrSubstringMatch(text: remoteStr, pattern: cleaned) { return true }
            if Self.wildcardOrSubstringMatch(text: repo.path, pattern: trimmed) { return true }
            return false
        }
    }

    private static func matchesOrganization(repo: GitRepository, pattern: String) -> Bool {
        repo.remotes.contains { remote in
            let parts = remote.ownerAndRepo.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { return false }
            let orgOnly = parts[0]
            let subGroupPath = parts.dropLast().joined(separator: "/")
            let hostAndOrg = "\(remote.host)/\(orgOnly)"
            let hostAndSubGroup = "\(remote.host)/\(subGroupPath)"

            if pattern.contains("/") {
                return wildcardOrSubstringMatch(text: hostAndOrg, pattern: pattern) ||
                       wildcardOrSubstringMatch(text: hostAndSubGroup, pattern: pattern) ||
                       wildcardOrSubstringMatch(text: subGroupPath, pattern: pattern)
            } else {
                return orgOnly.caseInsensitiveCompare(pattern) == .orderedSame ||
                       wildcardOrSubstringMatch(text: orgOnly, pattern: pattern)
            }
        }
    }

    private static func stripSchemeAndTrailingSlash(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://", "ssh://", "git@"] {
            if s.lowercased().hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count))
            }
        }
        while s.hasSuffix("/") {
            s.removeLast()
        }
        return s
    }

    private static func wildcardOrExactOrSubdomainMatch(host: String, pattern: String) -> Bool {
        let lowerHost = host.lowercased()
        let lowerPattern = pattern.lowercased()
        if lowerHost == lowerPattern { return true }
        if lowerPattern.hasPrefix("*.") {
            let suffix = String(lowerPattern.dropFirst(1)) // ".company.com"
            return lowerHost.hasSuffix(suffix) || lowerHost == String(suffix.dropFirst())
        }
        return wildcardOrSubstringMatch(text: lowerHost, pattern: lowerPattern)
    }

    private static func wildcardOrSubstringMatch(text: String, pattern: String) -> Bool {
        let lowerText = text.lowercased()
        let lowerPattern = pattern.lowercased()
        if lowerPattern.contains("*") {
            let regexPattern = "^" + NSRegularExpression.escapedPattern(for: lowerPattern)
                .replacingOccurrences(of: "\\*", with: ".*") + "$"
            return lowerText.range(of: regexPattern, options: .regularExpression) != nil
        }
        return lowerText.contains(lowerPattern)
    }
}

// MARK: - 操作日志记录
struct GitActionLog: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let repoName: String
    let command: String
    let success: Bool
    let output: String
}

// MARK: - 操作确认请求模型（批量操作需三次确认，单项目操作仅需单次确认）
struct PendingGitConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let targetDescription: String
    let gitCommandPreview: String
    let isBatchTripleConfirm: Bool
    let step1Warning: String
    let step2Warning: String
    let step3Warning: String
    let isDestructive: Bool
    let action: @MainActor () async -> Void
}
