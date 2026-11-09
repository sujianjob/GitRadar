import Foundation
import SwiftUI

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

    var iconName: String {
        switch self {
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .gitlab: return " fox.fill" // fallback handled via symbol
        case .gitee: return "g.circle.fill"
        case .bitbucket: return "tray.full.fill"
        case .codeberg: return "mountain.2.fill"
        case .cnb: return "cloud.fill"
        case .selfHosted: return "server.rack"
        case .localOnly: return "internaldrive"
        }
    }

    var sfSymbol: String {
        switch self {
        case .github: return "globe.americas.fill"
        case .gitlab: return "flame.fill"
        case .gitee: return "g.circle.fill"
        case .bitbucket: return "cylinder.split.1x2.fill"
        case .codeberg: return "mountain.2.fill"
        case .cnb: return "cloud.fill"
        case .selfHosted: return "server.rack"
        case .localOnly: return "desktopcomputer"
        }
    }

    var badgeColor: Color {
        switch self {
        case .github: return Color(red: 0.35, green: 0.45, blue: 0.95)
        case .gitlab: return Color(red: 0.95, green: 0.42, blue: 0.15)
        case .gitee: return Color(red: 0.85, green: 0.18, blue: 0.20)
        case .bitbucket: return Color(red: 0.15, green: 0.52, blue: 1.0)
        case .codeberg: return Color(red: 0.20, green: 0.68, blue: 0.55)
        case .cnb: return Color(red: 0.95, green: 0.58, blue: 0.12)
        case .selfHosted: return Color.purple
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
        case .conflict: return .red
        case .dirty: return .orange
        case .diverged: return .purple
        case .ahead: return .blue
        case .behind: return .cyan
        case .clean: return .green
        case .localOnly: return .gray
        }
    }

    var sfSymbol: String {
        switch self {
        case .conflict: return "exclamationmark.triangle.fill"
        case .dirty: return "pencil.circle.fill"
        case .diverged: return "arrow.triangle.branch"
        case .ahead: return "arrow.up.circle.fill"
        case .behind: return "arrow.down.circle.fill"
        case .clean: return "checkmark.circle.fill"
        case .localOnly: return "internaldrive.fill"
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
        if isConflict { return .red }
        if isUntracked { return .gray }
        if statusCode.contains("A") { return .green }
        if statusCode.contains("D") { return .red }
        if statusCode.contains("R") { return .blue }
        return .orange
    }

    var statusDescription: String {
        if isConflict { return "冲突" }
        if isUntracked { return "未跟踪" }
        if isStaged && workTreeStatus != " " { return "已暂存 + 工作区修改" }
        if isStaged { return "已暂存 (Staged)" }
        if workTreeStatus == "M" { return "已修改 (Modified)" }
        if workTreeStatus == "D" { return "已删除 (Deleted)" }
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
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "green": return .green
        case "pink": return .pink
        case "teal": return .teal
        case "indigo": return .indigo
        case "red": return .red
        default: return .blue
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
    let rootSourcePath: String // 来自哪个扫描根目录（或手动添加）

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
}

// MARK: - 侧边栏导航过滤条件
enum SidebarFilter: Hashable {
    case all
    case dirty          // 有未提交改动
    case unpushed       // 待推送 (ahead > 0)
    case needsPull      // 落后远程 (behind > 0)
    case favorites      // 收藏项目
    case provider(GitProvider)
    case group(UUID)
    case rootDirectory(String)

    var title: String {
        switch self {
        case .all: return "全部 Git 仓库"
        case .dirty: return "未提交改动"
        case .unpushed: return "待推送 Commit"
        case .needsPull: return "待拉取更新"
        case .favorites: return "星标收藏"
        case .provider(let p): return p.rawValue
        case .group: return "自定义分组"
        case .rootDirectory(let path):
            return URL(fileURLWithPath: path).lastPathComponent
        }
    }
}

// MARK: - 视图与排序枚举
enum DashboardViewMode: String, Codable, CaseIterable {
    case grid = "卡片视图"
    case table = "表格视图"

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

// MARK: - 操作日志记录
struct GitActionLog: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let repoName: String
    let command: String
    let success: Bool
    let output: String
}
