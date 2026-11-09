import AppKit
import Foundation

enum ProjectMetadataInspector {
    private static let candidateRelativeIconPaths: [String] = [
        "Resources/AppIcon.png",
        "Resources/AppIcon.icns",
        "AppIcon.png",
        "AppIcon.icns",
        "icon.png",
        "logo.png",
        "logo/apple-touch-icon.png",
        "logo/android-chrome-192x192.png",
        "logo/android-chrome-512x512.png",
        "logo/favicon-32x32.png",
        "logo/favicon.ico",
        "public/apple-touch-icon.png",
        "public/logo.png",
        "public/icon.png",
        "public/favicon.png",
        "public/favicon.ico",
        "web/favicon.png",
        "web/public/logo.png",
        "web/public/favicon.ico",
        "frontend/public/favicon.ico",
        "frontend/public/logo.png",
        "assets/icon.png",
        "assets/logo.png",
        "src/assets/logo.png",
        "src-tauri/icons/128x128.png",
        "src-tauri/icons/icon.png",
        "static/logo.png",
        "static/favicon.png"
    ]

    private static let candidateReadmeFiles: [String] = [
        "README.zh-CN.md",
        "README_CN.md",
        "README.zh.md",
        "README.md",
        "readme.md",
        "Readme.md",
        "README.txt",
        "SKILL.md"
    ]

    static var avatarCacheDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("GitRadar/Avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - 1. 检测项目本地图标或已缓存的远程组织头像
    static func resolveProjectIcon(
        repoPath: String,
        primaryProvider: GitProvider,
        primaryRemoteSlug: String?,
        readmeRaw: String?
    ) -> (localIconPath: String?, remoteAvatarURL: String?) {
        let fm = FileManager.default

        // (A) 检查常见的固定图标相对路径
        for rel in candidateRelativeIconPaths {
            let full = (repoPath as NSString).appendingPathComponent(rel)
            if fm.fileExists(atPath: full), isRenderableImage(at: full) {
                return (full, nil)
            }
        }

        // (B) 检查 logo/ 或 Resources/ 文件夹下的首张 png/icns
        for folder in ["logo", "Resources", "assets/icons", "public"] {
            let dirPath = (repoPath as NSString).appendingPathComponent(folder)
            if let items = try? fm.contentsOfDirectory(atPath: dirPath) {
                if let match = items.first(where: { name in
                    let lower = name.lowercased()
                    return (lower.contains("icon") || lower.contains("logo") || lower.contains("favicon")) &&
                           (lower.hasSuffix(".png") || lower.hasSuffix(".icns") || lower.hasSuffix(".jpg") || lower.hasSuffix(".ico"))
                }) {
                    let full = (dirPath as NSString).appendingPathComponent(match)
                    if isRenderableImage(at: full) {
                        return (full, nil)
                    }
                }
            }
        }

        // (C) 从 README 前 40 行中提取本地图片引用（如 ![logo](docs/logo.png) 或 <img src="assets/banner.png">）
        if let readmeRaw, let extractedRel = extractLocalImageFromReadme(readmeRaw) {
            let full = (repoPath as NSString).appendingPathComponent(extractedRel)
            if fm.fileExists(atPath: full), isRenderableImage(at: full) {
                return (full, nil)
            }
        }

        // (D) 如果没有本地图标，尝试基于 Remote Owner 构造远程组织/作者头像 URL 并检查本地磁盘缓存
        if let slug = primaryRemoteSlug, let owner = slug.split(separator: "/").first.map(String.init), !owner.isEmpty {
            let safeOwner = owner.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
            let cachedFile = avatarCacheDirectory.appendingPathComponent("\(primaryProvider.rawValue)_\(safeOwner).png")

            var remoteURL: String? = nil
            switch primaryProvider {
            case .github:
                remoteURL = "https://github.com/\(owner).png?size=128"
            case .gitlab:
                remoteURL = "https://gitlab.com/uploads/-/system/user/avatar/\(owner)/avatar.png"
            default:
                break
            }

            if fm.fileExists(atPath: cachedFile.path), isRenderableImage(at: cachedFile.path) {
                return (cachedFile.path, remoteURL)
            }
            return (nil, remoteURL)
        }

        return (nil, nil)
    }

    static func downloadAndCacheAvatar(from urlString: String, provider: GitProvider, slug: String?) async -> String? {
        guard let slug,
              let owner = slug.split(separator: "/").first.map(String.init),
              !owner.isEmpty,
              let url = URL(string: urlString) else {
            return nil
        }

        let safeOwner = owner.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        let targetFile = avatarCacheDirectory.appendingPathComponent("\(provider.rawValue)_\(safeOwner).png")

        if FileManager.default.fileExists(atPath: targetFile.path), isRenderableImage(at: targetFile.path) {
            return targetFile.path
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("GitRadar/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  data.count > 100,
                  NSImage(data: data) != nil else {
                return nil
            }
            try data.write(to: targetFile, options: .atomic)
            return targetFile.path
        } catch {
            return nil
        }
    }

    private static func isRenderableImage(at path: String) -> Bool {
        guard let img = NSImage(contentsOfFile: path) else { return false }
        return img.size.width >= 8 && img.size.height >= 8
    }

    private static func extractLocalImageFromReadme(_ raw: String) -> String? {
        let lines = raw.components(separatedBy: .newlines).prefix(40)
        for line in lines {
            // 匹配 Markdown 图片 ![...](path)
            if let range = line.range(of: #"!\[[^\]]*\]\(([^)]+)\)"#, options: .regularExpression) {
                let match = String(line[range])
                if let openParen = match.firstIndex(of: "("),
                   let closeParen = match.lastIndex(of: ")") {
                    let inside = String(match[match.index(after: openParen)..<closeParen])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !inside.hasPrefix("http://") && !inside.hasPrefix("https://") && !inside.hasSuffix(".svg") {
                        return inside.hasPrefix("./") ? String(inside.dropFirst(2)) : inside
                    }
                }
            }
            // 匹配 HTML <img src="path">
            if let range = line.range(of: #"src=["']([^"']+)["']"#, options: .regularExpression) {
                let match = String(line[range])
                let cleaned = match
                    .replacingOccurrences(of: "src=", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                if !cleaned.hasPrefix("http://") && !cleaned.hasPrefix("https://") && !cleaned.hasSuffix(".svg") {
                    return cleaned.hasPrefix("./") ? String(cleaned.dropFirst(2)) : cleaned
                }
            }
        }
        return nil
    }

    // MARK: - 2. 检测项目主要技术栈
    static func detectTechStack(at repoPath: String) -> ProjectTechStack {
        let fm = FileManager.default
        func has(_ name: String) -> Bool {
            fm.fileExists(atPath: (repoPath as NSString).appendingPathComponent(name))
        }

        if has("Package.swift") { return .swift }
        if has("Cargo.toml") { return .rust }
        if has("go.mod") { return .golang }
        if has("pyproject.toml") || has("requirements.txt") || has("setup.py") || has("Pipfile") {
            return .python
        }
        if has("tsconfig.json") || has("next.config.ts") || has("vite.config.ts") {
            return .typescript
        }
        if has("package.json") { return .javascript }
        if has("pom.xml") || has("build.gradle") || has("build.gradle.kts") {
            return .javaKotlin
        }
        if has("SKILL.md") || has(".claude-plugin") {
            return .aiSkill
        }

        // 检查根目录后缀
        if let items = try? fm.contentsOfDirectory(atPath: repoPath) {
            if items.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") || $0.hasSuffix(".swift") }) {
                return .swift
            }
            if items.contains(where: { $0.hasSuffix(".py") || $0.hasSuffix(".ipynb") }) {
                return .python
            }
            if items.contains(where: { $0.hasSuffix(".ts") || $0.hasSuffix(".tsx") }) {
                return .typescript
            }
            if items.contains(where: { $0.hasSuffix(".md") }) && items.count <= 12 {
                return .docs
            }
        }

        return .generic
    }

    // MARK: - 3. 读取并提取 README 前置项目简介
    static func extractReadme(at repoPath: String) -> (fileName: String?, excerpt: String?, fullText: String?, rawText: String?) {
        let fm = FileManager.default

        var foundFileName: String? = nil
        var rawContent: String? = nil

        for candidate in candidateReadmeFiles {
            let full = (repoPath as NSString).appendingPathComponent(candidate)
            if fm.fileExists(atPath: full),
               let data = try? Data(contentsOf: URL(fileURLWithPath: full)),
               let text = String(data: data.prefix(65_536), encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                foundFileName = candidate
                rawContent = text
                break
            }
        }

        // 如果根目录没找到，检查常见的二级目录（如 docs/README.md）
        if rawContent == nil {
            for sub in ["docs/README.md", "web/README.md", "server/README.md"] {
                let full = (repoPath as NSString).appendingPathComponent(sub)
                if fm.fileExists(atPath: full),
                   let data = try? Data(contentsOf: URL(fileURLWithPath: full)),
                   let text = String(data: data.prefix(65_536), encoding: .utf8),
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    foundFileName = sub
                    rawContent = text
                    break
                }
            }
        }

        guard let raw = rawContent else {
            return (nil, nil, nil, nil)
        }

        let cleanedFull = cleanMarkdownForPreview(raw)
        let excerpt = buildBriefIntro(from: cleanedFull)
        return (foundFileName, excerpt, cleanedFull, raw)
    }

    /// 清洗 README 中的徽章盾牌、HTML 标签和 Frontmatter，保留干净易读的介绍文本
    private static func cleanMarkdownForPreview(_ raw: String) -> String {
        var text = raw

        // 1. 移除开头的 YAML Frontmatter (--- ... ---)
        if text.hasPrefix("---") {
            let lines = text.components(separatedBy: .newlines)
            if let endIdx = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
                text = lines[(endIdx + 1)...].joined(separator: "\n")
            }
        }

        var resultLines: [String] = []
        var inCodeBlock = false

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
                resultLines.append(line)
                continue
            }

            if !inCodeBlock {
                // 跳过纯徽章行 [![...](...)](...) 或 ![badge](https://img.shields.io...)
                if trimmed.hasPrefix("[![") || trimmed.contains("img.shields.io") || trimmed.contains("badge.svg") {
                    continue
                }
                // 跳过纯图片行
                if trimmed.hasPrefix("![") && trimmed.hasSuffix(")") && !trimmed.contains(" ") {
                    continue
                }
                // 跳过纯 HTML 布局标签行
                if trimmed.hasPrefix("<div") || trimmed.hasPrefix("</div>") ||
                   trimmed.hasPrefix("<p ") || trimmed.hasPrefix("<p>") || trimmed.hasPrefix("</p>") ||
                   trimmed.hasPrefix("<img ") || trimmed.hasPrefix("<picture") || trimmed.hasPrefix("</picture") ||
                   trimmed.hasPrefix("<source ") || trimmed.hasPrefix("<!--") {
                    continue
                }
            }

            // 清理行内简单 HTML 标签与 Markdown 链接包装 [text](url) -> text
            var cleanLine = line
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"!\[[^\]]*\]\([^)]+\)"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)

            // 美化标题符号
            if cleanLine.hasPrefix("# ") {
                cleanLine = String(cleanLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if cleanLine.hasPrefix("## ") {
                cleanLine = "▸ " + String(cleanLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if cleanLine.hasPrefix("### ") {
                cleanLine = "  • " + String(cleanLine.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            }

            cleanLine = cleanLine.replacingOccurrences(of: "**", with: "")
            resultLines.append(cleanLine)
        }

        // 合并多余空行
        var collapsed: [String] = []
        var previousBlank = true
        for l in resultLines {
            let isBlank = l.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank {
                if !previousBlank {
                    collapsed.append("")
                }
                previousBlank = true
            } else {
                collapsed.append(l)
                previousBlank = false
            }
        }

        return collapsed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 截取 README 前面的核心项目简介（前 6~10 行有效内容，约 420 字以内）
    private static func buildBriefIntro(from cleaned: String) -> String {
        guard !cleaned.isEmpty else { return "暂无项目简介" }
        let lines = cleaned.components(separatedBy: .newlines)
        var picked: [String] = []
        var charCount = 0

        for line in lines {
            picked.append(line)
            charCount += line.count
            if charCount >= 380 || picked.filter({ !$0.isEmpty }).count >= 8 {
                break
            }
        }

        let summary = picked.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.count < cleaned.count {
            return summary + "\n…"
        }
        return summary
    }
}
