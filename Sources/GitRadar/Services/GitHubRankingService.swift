import Foundation

enum GitHubRankingServiceError: LocalizedError {
    case rateLimited(String)
    case httpError(Int, String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .rateLimited(let msg):
            return "GitHub API 触发限流：\(msg)（可在远程 Star 中配置 Token 提升额度至 30 次/分钟）"
        case .httpError(let code, let msg):
            return "排行榜请求失败 (HTTP \(code))：\(msg)"
        case .networkError(let msg):
            return "排行榜网络请求异常：\(msg)"
        }
    }
}

enum GitHubRankingService {
    struct RankingFetchResult: Sendable {
        let items: [RankedRepository]
        let sourceLabel: String
    }

    private struct SearchResponseDTO: Decodable {
        let total_count: Int?
        let items: [SearchRepoDTO]
    }

    private struct SearchRepoDTO: Decodable {
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
        let default_branch: String?
        let created_at: String?
        let pushed_at: String?
    }

    static func cacheKey(
        board: GitHubRankingBoard,
        period: GitHubRankingPeriod,
        language: GitHubRankingLanguage
    ) -> String {
        let periodPart = board.supportsPeriodFilter ? period.rawValue : "all"
        let langPart = language.rawValue.isEmpty ? "all" : language.rawValue.lowercased()
        return "\(board.rawValue)_\(periodPart)_\(langPart)"
    }

    // MARK: - 统一入口：拉取四大排行榜
    static func fetchRanking(
        board: GitHubRankingBoard,
        period: GitHubRankingPeriod,
        language: GitHubRankingLanguage,
        token: String?
    ) async throws -> RankingFetchResult {
        switch board {
        case .trending:
            // 优先通过 GitHub Trending 页面解析真实热榜与今日/本周新增 Star；失败时无缝降级到 Search API
            if let htmlItems = try? await fetchGitHubTrendingHTML(period: period, language: language),
               !htmlItems.isEmpty {
                return RankingFetchResult(
                    items: htmlItems,
                    sourceLabel: "GitHub Trending 官方热榜"
                )
            }
            let fallbackItems = try await fetchTrendingFallbackViaSearchAPI(
                period: period,
                language: language,
                token: token
            )
            return RankingFetchResult(
                items: fallbackItems,
                sourceLabel: "GitHub Search API (趋势回退)"
            )

        case .breakout:
            let items = try await fetchBreakoutRanking(
                period: period,
                language: language,
                token: token
            )
            return RankingFetchResult(
                items: items,
                sourceLabel: "GitHub Search API · 新建高增榜"
            )

        case .aiAgent:
            let items = try await fetchAIAgentRanking(
                period: period,
                language: language,
                token: token
            )
            return RankingFetchResult(
                items: items,
                sourceLabel: "GitHub Search API · AI / Agent 专题"
            )

        case .allTime:
            let items = try await fetchAllTimeTopRanking(
                language: language,
                token: token
            )
            return RankingFetchResult(
                items: items,
                sourceLabel: "GitHub Search API · 全站殿堂总榜"
            )
        }
    }

    // MARK: - 1. GitHub Trending 官方网页解析引擎
    private static func fetchGitHubTrendingHTML(
        period: GitHubRankingPeriod,
        language: GitHubRankingLanguage
    ) async throws -> [RankedRepository] {
        var urlStr = "https://github.com/trending"
        if let slug = language.trendingSlug {
            urlStr += "/\(slug)"
        }
        urlStr += "?since=\(period.rawValue)"

        guard let url = URL(string: urlStr) else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            return []
        }

        return parseTrendingHTML(html, period: period)
    }

    private static func parseTrendingHTML(_ html: String, period: GitHubRankingPeriod) -> [RankedRepository] {
        let parts = html.components(separatedBy: "<article")
        guard parts.count > 1 else { return [] }

        var results: [RankedRepository] = []
        let periodLabel: String = {
            switch period {
            case .daily: return "今日"
            case .weekly: return "本周"
            case .monthly: return "本月"
            }
        }()

        for articleChunk in parts.dropFirst() {
            let block: String
            if let endRange = articleChunk.range(of: "</article>") {
                block = String(articleChunk[..<endRange.lowerBound])
            } else {
                block = articleChunk
            }

            // 1. 提取 h2 内の href="/owner/repo"
            guard let fullName = extractRepoFullName(from: block) else { continue }
            let slugParts = fullName.split(separator: "/").map(String.init)
            guard slugParts.count == 2 else { continue }
            let owner = slugParts[0]
            let name = slugParts[1]

            // 2. 提取描述 <p class="col-9 ...">...</p>
            let description = extractParagraphText(from: block)

            // 3. 提取语言 itemprop="programmingLanguage">...</span>
            let language = extractFirstMatch(
                in: block,
                pattern: #"itemprop="programmingLanguage"[^>]*>([^<]+)<"#
            )?.trimmingCharacters(in: .whitespacesAndNewlines)

            // 4. 提取总 Star 数与 Fork 数
            let stargazersCount = extractMetricNumber(
                in: block,
                hrefSuffix: "/\(fullName)/stargazers"
            ) ?? 0
            let forksCount = extractMetricNumber(
                in: block,
                hrefSuffix: "/\(fullName)/forks"
            ) ?? 0

            // 5. 提取周期新增 Star（如 "1,428 stars today" / "4,210 stars this week"）
            let deltaStars = extractFirstMatch(
                in: block,
                pattern: #"([\d,]+)\s+stars\s+(?:today|this week|this month)"#
            ).flatMap { Int($0.replacingOccurrences(of: ",", with: "")) }

            let deltaBadge: String
            if let deltaStars, deltaStars > 0 {
                deltaBadge = "\(periodLabel) +\(formatNumberWithComma(deltaStars)) ★"
            } else {
                deltaBadge = "\(periodLabel)热门飙升"
            }

            let rank = results.count + 1
            let avatarURL = "https://github.com/\(owner).png?size=128"
            let safeOwner = owner.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
            let cachedFile = ProjectMetadataInspector.avatarCacheDirectory
                .appendingPathComponent("\(GitProvider.github.rawValue)_\(safeOwner).png")
            let cachedAvatarPath = FileManager.default.fileExists(atPath: cachedFile.path) ? cachedFile.path : nil

            let item = RankedRepository(
                rank: rank,
                name: name,
                owner: owner,
                fullName: fullName,
                htmlURL: "https://github.com/\(fullName)",
                cloneURL: "https://github.com/\(fullName).git",
                sshURL: "git@github.com:\(fullName).git",
                description: description,
                language: language,
                topics: [],
                stargazersCount: stargazersCount,
                forksCount: forksCount,
                periodStarsDelta: deltaStars,
                deltaBadgeText: deltaBadge,
                defaultBranch: "main",
                avatarURL: avatarURL,
                cachedAvatarPath: cachedAvatarPath,
                createdAt: nil,
                pushedAt: Date(),
                latestReleaseTag: nil,
                latestReleaseName: nil,
                latestReleasePublishedAt: nil,
                latestReleaseBody: nil,
                latestReleaseHTMLURL: nil,
                readmeExcerpt: nil,
                readmeFullText: nil
            )
            results.append(item)
        }

        return results
    }

    // MARK: - 2. Trending 回退通道（当网页不可达时使用 Search API）
    private static func fetchTrendingFallbackViaSearchAPI(
        period: GitHubRankingPeriod,
        language: GitHubRankingLanguage,
        token: String?
    ) async throws -> [RankedRepository] {
        let days: Int = {
            switch period {
            case .daily: return 7
            case .weekly: return 14
            case .monthly: return 30
            }
        }()
        let sinceDateStr = dateString(daysAgo: days)
        var query = "created:>\(sinceDateStr) stars:>30"
        if language != .all {
            query += " language:\"\(language.rawValue)\""
        }

        let dtos = try await performSearchQuery(query: query, perPage: 30, token: token)
        let periodLabel = period.label(for: .trending)
        return dtos.enumerated().map { idx, dto in
            buildRankedRepo(
                from: dto,
                rank: idx + 1,
                deltaBadgeText: "\(periodLabel)飙升 · ★ \(formatCompact(dto.stargazers_count ?? 0))",
                periodDelta: dto.stargazers_count
            )
        }
    }

    // MARK: - 3. 新晋黑马榜（近 7 / 30 / 90 天内新创建且 Star 暴涨的项目）
    private static func fetchBreakoutRanking(
        period: GitHubRankingPeriod,
        language: GitHubRankingLanguage,
        token: String?
    ) async throws -> [RankedRepository] {
        let days: Int = {
            switch period {
            case .daily: return 7
            case .weekly: return 30
            case .monthly: return 90
            }
        }()
        let sinceDateStr = dateString(daysAgo: days)
        var query = "created:>\(sinceDateStr) stars:>20"
        if language != .all {
            query += " language:\"\(language.rawValue)\""
        }

        let dtos = try await performSearchQuery(query: query, perPage: 40, token: token)
        return dtos.enumerated().map { idx, dto in
            let created = parseISO8601(dto.created_at)
            let stars = dto.stargazers_count ?? 0
            let ageDays = max(1, Int(Date().timeIntervalSince(created ?? Date()) / 86_400))
            let perDay = max(1, stars / ageDays)
            let badge = "新建 \(ageDays) 天 · 日均 +\(formatNumberWithComma(perDay)) ★"
            return buildRankedRepo(
                from: dto,
                rank: idx + 1,
                deltaBadgeText: badge,
                periodDelta: perDay
            )
        }
    }

    // MARK: - 4. AI / Agent / MCP 专题榜
    private static func fetchAIAgentRanking(
        period: GitHubRankingPeriod,
        language: GitHubRankingLanguage,
        token: String?
    ) async throws -> [RankedRepository] {
        // 注意：GitHub Search REST API 不支持括号分组或对 topic: 限定符做 OR 组合，需使用关键词 + in:name,description,topics
        let aiKeywords = "llm OR agent OR mcp OR skill in:name,description,topics"
        var query: String
        switch period {
        case .daily:
            // 近期新秀：近 45 天内创建的 AI / Agent / MCP 热门项目
            let since = dateString(daysAgo: 45)
            query = "\(aiKeywords) created:>\(since) stars:>30"
        case .weekly:
            // 近期活跃：近 180 天创建且近 7 天有推送更新的高热 AI 项目
            let createdSince = dateString(daysAgo: 180)
            let pushedSince = dateString(daysAgo: 7)
            query = "\(aiKeywords) created:>\(createdSince) pushed:>\(pushedSince) stars:>100"
        case .monthly:
            // AI 全量总榜
            query = "\(aiKeywords) stars:>1000"
        }

        if language != .all {
            query += " language:\"\(language.rawValue)\""
        }

        let dtos = try await performSearchQuery(query: query, perPage: 45, token: token)
        return dtos.enumerated().map { idx, dto in
            let aiTag = (dto.topics ?? []).first(where: {
                let l = $0.lowercased()
                return l.contains("mcp") || l.contains("agent") || l.contains("llm") || l.contains("ai")
            }) ?? "ai-agent"
            let badge: String = {
                switch period {
                case .daily:
                    if let created = parseISO8601(dto.created_at) {
                        let age = max(1, Int(Date().timeIntervalSince(created) / 86_400))
                        let daily = max(1, (dto.stargazers_count ?? 0) / age)
                        return "AI 新秀 · 日均 +\(formatNumberWithComma(daily)) ★"
                    }
                    return "AI 新秀 · #\(aiTag)"
                case .weekly:
                    return "近期活跃 · #\(aiTag)"
                case .monthly:
                    return "AI 殿堂 · #\(aiTag)"
                }
            }()
            return buildRankedRepo(
                from: dto,
                rank: idx + 1,
                deltaBadgeText: badge,
                periodDelta: nil
            )
        }
    }

    // MARK: - 5. 全站 Star 总榜 (Top 殿堂级项目)
    private static func fetchAllTimeTopRanking(
        language: GitHubRankingLanguage,
        token: String?
    ) async throws -> [RankedRepository] {
        var query = "stars:>3000"
        if language != .all {
            query += " language:\"\(language.rawValue)\""
        }

        let dtos = try await performSearchQuery(query: query, perPage: 60, token: token)
        return dtos.enumerated().map { idx, dto in
            let rank = idx + 1
            let langLabel = language == .all ? "全站总榜" : "\(language.displayName) 总榜"
            return buildRankedRepo(
                from: dto,
                rank: rank,
                deltaBadgeText: "\(langLabel) #\(rank)",
                periodDelta: nil
            )
        }
    }

    // MARK: - GitHub Search API 底层请求
    private static func performSearchQuery(
        query: String,
        perPage: Int,
        token: String?
    ) async throws -> [SearchRepoDTO] {
        var comps = URLComponents(string: "https://api.github.com/search/repositories")
        comps?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "sort", value: "stars"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "per_page", value: "\(min(100, perPage))")
        ]

        guard let url = comps?.url else {
            throw GitHubRankingServiceError.networkError("无效的查询 URL")
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("GitRadar/0.3.0", forHTTPHeaderField: "User-Agent")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw GitHubRankingServiceError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GitHubRankingServiceError.networkError("无效的 HTTP 响应")
        }

        if http.statusCode == 403 || http.statusCode == 429 {
            let msg = extractErrorMessage(from: data) ?? "API 请求速率已达上限"
            throw GitHubRankingServiceError.rateLimited(msg)
        }

        guard (200...299).contains(http.statusCode) else {
            let msg = extractErrorMessage(from: data) ?? "状态码 \(http.statusCode)"
            throw GitHubRankingServiceError.httpError(http.statusCode, msg)
        }

        let decoded = try JSONDecoder().decode(SearchResponseDTO.self, from: data)
        return decoded.items
    }

    // MARK: - 转换与 HTML 解析辅助函数
    private static func buildRankedRepo(
        from dto: SearchRepoDTO,
        rank: Int,
        deltaBadgeText: String,
        periodDelta: Int?
    ) -> RankedRepository {
        let cloneURL = dto.clone_url ?? "https://github.com/\(dto.full_name).git"
        let sshURL = dto.ssh_url ?? "git@github.com:\(dto.full_name).git"
        let avatarURL = dto.owner.avatar_url ?? "https://github.com/\(dto.owner.login).png?size=128"

        let safeOwner = dto.owner.login.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        let cachedFile = ProjectMetadataInspector.avatarCacheDirectory
            .appendingPathComponent("\(GitProvider.github.rawValue)_\(safeOwner).png")
        let cachedAvatarPath = FileManager.default.fileExists(atPath: cachedFile.path) ? cachedFile.path : nil

        return RankedRepository(
            rank: rank,
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
            periodStarsDelta: periodDelta,
            deltaBadgeText: deltaBadgeText,
            defaultBranch: dto.default_branch ?? "main",
            avatarURL: avatarURL,
            cachedAvatarPath: cachedAvatarPath,
            createdAt: parseISO8601(dto.created_at),
            pushedAt: parseISO8601(dto.pushed_at),
            latestReleaseTag: nil,
            latestReleaseName: nil,
            latestReleasePublishedAt: nil,
            latestReleaseBody: nil,
            latestReleaseHTMLURL: nil,
            readmeExcerpt: nil,
            readmeFullText: nil
        )
    }

    private static func extractRepoFullName(from block: String) -> String? {
        guard let h2Block = extractFirstMatch(in: block, pattern: #"<h2[^>]*>([\s\S]*?)</h2>"#),
              let href = extractFirstMatch(in: h2Block, pattern: #"href="/([^"/]+/[^"/\s?]+)""#) else {
            return nil
        }
        return href.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractParagraphText(from block: String) -> String? {
        guard let rawP = extractFirstMatch(in: block, pattern: #"<p[^>]*>([\s\S]*?)</p>"#) else {
            return nil
        }
        let stripped = rawP.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let decoded = decodeHTMLEntities(stripped)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return decoded.isEmpty ? nil : decoded
    }

    private static func extractMetricNumber(in block: String, hrefSuffix: String) -> Int? {
        let escaped = NSRegularExpression.escapedPattern(for: hrefSuffix)
        let pattern = #"href="\#(escaped)"[^>]*>([\s\S]*?)</a>"#
        guard let anchorContent = extractFirstMatch(in: block, pattern: pattern) else {
            return nil
        }
        let stripped = anchorContent.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let digits = stripped.components(separatedBy: CharacterSet(charactersIn: "0123456789").inverted).joined()
        return Int(digits)
    }

    private static func extractFirstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func dateString(daysAgo: Int) -> String {
        let target = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: target)
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

    private static func formatNumberWithComma(_ value: Int) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        return fmt.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func formatCompact(_ value: Int) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", Double(value) / 1000.0)
        }
        return "\(value)"
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        struct ErrorResp: Decodable { let message: String? }
        return (try? JSONDecoder().decode(ErrorResp.self, from: data))?.message
    }
}
