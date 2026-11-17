import Foundation

enum GitHubStarServiceError: LocalizedError {
    case invalidUsername
    case rateLimited(String)
    case userNotFound(String)
    case httpError(Int, String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidUsername:
            return "GitHub 用户名格式无效"
        case .rateLimited(let msg):
            return "GitHub API 触发限流：\(msg)（可在账号设置中配置 Token 提升额度）"
        case .userNotFound(let user):
            return "未找到 GitHub 用户「@\(user)」"
        case .httpError(let code, let msg):
            return "GitHub API 请求失败 (HTTP \(code))：\(msg)"
        case .networkError(let msg):
            return "网络请求异常：\(msg)"
        }
    }
}

enum GitHubStarService {
    /// 一键跳转到 GitHub Personal Access Token 创建页面（已预填备注与最小只读权限）
    static let tokenCreationURL = "https://github.com/settings/tokens/new?description=GitRadar&scopes=read:user,public_repo"

    struct TokenVerificationResult: Sendable {
        let isValid: Bool
        let message: String
        let authenticatedLogin: String?
    }

    /// 验证用户输入的 GitHub Personal Access Token 是否有效，并返回对应账号与剩余 API 配额
    static func verifyToken(_ rawToken: String) async -> TokenVerificationResult {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return TokenVerificationResult(
                isValid: false,
                message: "请先输入 GitHub Personal Access Token",
                authenticatedLogin: nil
            )
        }

        guard let userURL = URL(string: "https://api.github.com/user") else {
            return TokenVerificationResult(isValid: false, message: "请求地址无效", authenticatedLogin: nil)
        }

        var req = URLRequest(url: userURL)
        req.timeoutInterval = 10
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("GitRadar/0.3.0", forHTTPHeaderField: "User-Agent")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                return TokenVerificationResult(isValid: false, message: "无效的响应", authenticatedLogin: nil)
            }

            let remaining = http.value(forHTTPHeaderField: "x-ratelimit-remaining")
            let limit = http.value(forHTTPHeaderField: "x-ratelimit-limit")
            let quotaText: String = {
                if let r = remaining, let l = limit {
                    return " · 剩余额度 \(r)/\(l) 次/小时"
                }
                return ""
            }()

            if (200...299).contains(http.statusCode) {
                struct UserDTO: Decodable {
                    let login: String
                    let name: String?
                }
                if let user = try? JSONDecoder().decode(UserDTO.self, from: data) {
                    return TokenVerificationResult(
                        isValid: true,
                        message: "Token 有效（认证账号：@\(user.login)\(quotaText)）",
                        authenticatedLogin: user.login
                    )
                }
                return TokenVerificationResult(
                    isValid: true,
                    message: "Token 验证通过\(quotaText)",
                    authenticatedLogin: nil
                )
            } else if http.statusCode == 401 {
                return TokenVerificationResult(
                    isValid: false,
                    message: "Token 无效或已过期 (HTTP 401 Bad credentials)",
                    authenticatedLogin: nil
                )
            } else if http.statusCode == 403 {
                // Fine-grained token 可能未勾选 user 读取权限，回退检测 rate_limit 接口验证 Token 本身是否合法
                if let rateURL = URL(string: "https://api.github.com/rate_limit") {
                    var rateReq = URLRequest(url: rateURL)
                    rateReq.timeoutInterval = 10
                    rateReq.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                    rateReq.setValue("GitRadar/0.3.0", forHTTPHeaderField: "User-Agent")
                    rateReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    if let (_, rateResp) = try? await URLSession.shared.data(for: rateReq),
                       let rateHttp = rateResp as? HTTPURLResponse,
                       (200...299).contains(rateHttp.statusCode) {
                        let rem = rateHttp.value(forHTTPHeaderField: "x-ratelimit-remaining") ?? "5000"
                        let lim = rateHttp.value(forHTTPHeaderField: "x-ratelimit-limit") ?? "5000"
                        return TokenVerificationResult(
                            isValid: true,
                            message: "Token 有效（Fine-grained Token · 剩余额度 \(rem)/\(lim) 次/小时）",
                            authenticatedLogin: nil
                        )
                    }
                }
                let errMsg = extractErrorMessage(from: data) ?? "权限受限"
                return TokenVerificationResult(
                    isValid: false,
                    message: "Token 访问受限 (HTTP 403)：\(errMsg)",
                    authenticatedLogin: nil
                )
            } else {
                let errMsg = extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
                return TokenVerificationResult(
                    isValid: false,
                    message: "验证失败：\(errMsg)",
                    authenticatedLogin: nil
                )
            }
        } catch {
            return TokenVerificationResult(
                isValid: false,
                message: "网络请求失败：\(error.localizedDescription)",
                authenticatedLogin: nil
            )
        }
    }

    private struct StarredEnvelopeDTO: Decodable {
        let starred_at: String?
        let repo: RepoDTO
    }

    private struct RepoDTO: Decodable {
        struct OwnerDTO: Decodable {
            let login: String
            let avatar_url: String?
        }
        let id: Int
        let name: String
        let full_name: String
        let owner: OwnerDTO
        let html_url: String
        let clone_url: String?
        let ssh_url: String?
        let description: String?
        let language: String?
        let topics: [String]?
        let stargazers_count: Int?
        let forks_count: Int?
        let open_issues_count: Int?
        let archived: Bool?
        let default_branch: String?
        let pushed_at: String?
    }

    private struct ReleaseDTO: Decodable {
        let tag_name: String
        let name: String?
        let published_at: String?
        let body: String?
        let html_url: String?
    }

    private static func parseISO8601(_ str: String?) -> Date? {
        guard let str, !str.isEmpty else { return nil }
        let fmtWithFrac = ISO8601DateFormatter()
        fmtWithFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmtWithFrac.date(from: str) { return d }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.date(from: str)
    }

    // MARK: - 1. 拉取指定 GitHub 账号的全部 Star 仓库列表（自动分页直至拉完）
    static func fetchStarredRepositories(
        account: GitHubStarAccount,
        maxPages: Int = 200,
        onPageFetched: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [StarredRepository] {
        let username = account.username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        guard !username.isEmpty,
              let encodedUser = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw GitHubStarServiceError.invalidUsername
        }

        let token = account.token.trimmingCharacters(in: .whitespacesAndNewlines)
        var collected: [StarredRepository] = []
        var seenIDs: Set<String> = []

        for page in 1...maxPages {
            let urlStr = "https://api.github.com/users/\(encodedUser)/starred?per_page=100&page=\(page)&sort=created&direction=desc"
            guard let url = URL(string: urlStr) else { break }

            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("application/vnd.github.star+json", forHTTPHeaderField: "Accept")
            request.setValue("GitRadar/0.3.0", forHTTPHeaderField: "User-Agent")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            if !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                throw GitHubStarServiceError.networkError(error.localizedDescription)
            }

            guard let http = response as? HTTPURLResponse else {
                throw GitHubStarServiceError.networkError("无效的 HTTP 响应")
            }

            if http.statusCode == 404 {
                throw GitHubStarServiceError.userNotFound(username)
            }
            if http.statusCode == 403 || http.statusCode == 429 {
                let msg = extractErrorMessage(from: data) ?? "API 速率限制已达上限"
                throw GitHubStarServiceError.rateLimited(msg)
            }
            guard (200...299).contains(http.statusCode) else {
                let msg = extractErrorMessage(from: data) ?? "状态码 \(http.statusCode)"
                throw GitHubStarServiceError.httpError(http.statusCode, msg)
            }

            let decoder = JSONDecoder()
            var pageItems: [(starredAt: Date?, dto: RepoDTO)] = []

            if let envelopes = try? decoder.decode([StarredEnvelopeDTO].self, from: data) {
                pageItems = envelopes.map { (parseISO8601($0.starred_at), $0.repo) }
            } else if let plainRepos = try? decoder.decode([RepoDTO].self, from: data) {
                pageItems = plainRepos.map { (nil, $0) }
            }

            if pageItems.isEmpty {
                break
            }

            for item in pageItems {
                let dto = item.dto
                let key = dto.full_name.lowercased()
                guard !seenIDs.contains(key) else { continue }
                seenIDs.insert(key)

                let cloneURL = dto.clone_url ?? "https://github.com/\(dto.full_name).git"
                let sshURL = dto.ssh_url ?? "git@github.com:\(dto.full_name).git"
                let avatarURL = dto.owner.avatar_url ?? "https://github.com/\(dto.owner.login).png?size=128"

                // 检查本地头像缓存
                let safeOwner = dto.owner.login.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
                let cachedFile = ProjectMetadataInspector.avatarCacheDirectory
                    .appendingPathComponent("\(GitProvider.github.rawValue)_\(safeOwner).png")
                let cachedAvatarPath = FileManager.default.fileExists(atPath: cachedFile.path) ? cachedFile.path : nil

                let repo = StarredRepository(
                    repoId: dto.id,
                    name: dto.name,
                    owner: dto.owner.login,
                    fullName: dto.full_name,
                    htmlURL: dto.html_url,
                    cloneURL: cloneURL,
                    sshURL: sshURL,
                    description: dto.description,
                    language: dto.language,
                    topics: dto.topics ?? [],
                    stargazersCount: dto.stargazers_count ?? 0,
                    forksCount: dto.forks_count ?? 0,
                    openIssuesCount: dto.open_issues_count ?? 0,
                    isArchived: dto.archived ?? false,
                    defaultBranch: dto.default_branch ?? "main",
                    avatarURL: avatarURL,
                    cachedAvatarPath: cachedAvatarPath,
                    pushedAt: parseISO8601(dto.pushed_at),
                    starredAt: item.starredAt,
                    starredByAccounts: [username],
                    latestReleaseTag: nil,
                    latestReleaseName: nil,
                    latestReleasePublishedAt: nil,
                    latestReleaseBody: nil,
                    latestReleaseHTMLURL: nil,
                    readmeExcerpt: nil,
                    readmeFullText: nil
                )
                collected.append(repo)
            }

            onPageFetched?(page, collected.count)

            if pageItems.count < 100 {
                break
            }
        }

        return collected
    }

    // MARK: - 2. 按需拉取单个远程 Star 项目的最新 Release 与 README
    struct RemoteRepoHydrationResult: Sendable {
        var latestReleaseTag: String?
        var latestReleaseName: String?
        var latestReleasePublishedAt: Date?
        var latestReleaseBody: String?
        var latestReleaseHTMLURL: String?
        var readmeExcerpt: String?
        var readmeFullText: String?
    }

    static func fetchReleaseAndReadme(
        fullName: String,
        defaultBranch: String,
        token: String?
    ) async -> RemoteRepoHydrationResult {
        async let releaseInfo = fetchLatestRelease(fullName: fullName, token: token)
        async let readmeInfo = fetchRemoteReadme(fullName: fullName, defaultBranch: defaultBranch, token: token)

        let (rel, readme) = await (releaseInfo, readmeInfo)
        return RemoteRepoHydrationResult(
            latestReleaseTag: rel?.tag_name,
            latestReleaseName: rel?.name,
            latestReleasePublishedAt: parseISO8601(rel?.published_at),
            latestReleaseBody: rel?.body,
            latestReleaseHTMLURL: rel?.html_url,
            readmeExcerpt: readme?.excerpt,
            readmeFullText: readme?.fullText
        )
    }

    private static func fetchLatestRelease(fullName: String, token: String?) async -> ReleaseDTO? {
        guard let url = URL(string: "https://api.github.com/repos/\(fullName)/releases/latest") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GitRadar/0.3.0", forHTTPHeaderField: "User-Agent")
        if let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let dto = try? JSONDecoder().decode(ReleaseDTO.self, from: data) else {
            return nil
        }
        return dto
    }

    private static func fetchRemoteReadme(
        fullName: String,
        defaultBranch: String,
        token: String?
    ) async -> (excerpt: String, fullText: String)? {
        // 优先通过 raw.githubusercontent.com 拉取 README（不消耗 GitHub REST API 限流配额）
        let candidates = [
            "https://raw.githubusercontent.com/\(fullName)/\(defaultBranch)/README.zh-CN.md",
            "https://raw.githubusercontent.com/\(fullName)/\(defaultBranch)/README_CN.md",
            "https://raw.githubusercontent.com/\(fullName)/\(defaultBranch)/README.md",
            "https://raw.githubusercontent.com/\(fullName)/\(defaultBranch)/readme.md"
        ]

        for rawURLStr in candidates {
            guard let url = URL(string: rawURLStr) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            req.setValue("GitRadar/0.3.0", forHTTPHeaderField: "User-Agent")
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse,
               (200...299).contains(http.statusCode),
               let text = String(data: data.prefix(65_536), encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let cleaned = ProjectMetadataInspector.cleanMarkdownForPreview(text)
                let excerpt = ProjectMetadataInspector.buildBriefIntro(from: cleaned)
                return (excerpt, cleaned)
            }
        }

        // 兜底使用 GitHub API /repos/{owner}/{repo}/readme
        if let apiURL = URL(string: "https://api.github.com/repos/\(fullName)/readme") {
            var req = URLRequest(url: apiURL)
            req.timeoutInterval = 8
            req.setValue("application/vnd.github.raw+json", forHTTPHeaderField: "Accept")
            req.setValue("GitRadar/0.3.0", forHTTPHeaderField: "User-Agent")
            if let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                req.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
            }
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse,
               (200...299).contains(http.statusCode),
               let text = String(data: data.prefix(65_536), encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let cleaned = ProjectMetadataInspector.cleanMarkdownForPreview(text)
                let excerpt = ProjectMetadataInspector.buildBriefIntro(from: cleaned)
                return (excerpt, cleaned)
            }
        }

        return nil
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        struct ErrorResp: Decodable { let message: String? }
        return (try? JSONDecoder().decode(ErrorResp.self, from: data))?.message
    }
}
