import Foundation

struct CommandResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var isSuccess: Bool { exitCode == 0 }
    var combinedOutput: String {
        let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty { return err }
        if err.isEmpty { return out }
        return "\(out)\n\(err)"
    }
}

enum GitService {
    private static let gitExecutable = "/usr/bin/git"

    private static let ignoredDirectoryNames: Set<String> = [
        "node_modules", ".build", "Pods", "DerivedData", "venv", ".venv",
        "target", "dist", "build", ".gradle", ".idea", ".vscode", ".Trash",
        "Library", "Applications", "Pictures", "Music", "Movies", ".npm", ".cache"
    ]

    // MARK: - 1. 递归扫描目录下的所有 Git 仓库
    static func discoverRepositories(
        in rootPath: String,
        maxDepth: Int = 4,
        customIgnored: Set<String> = []
    ) -> [String] {
        let fm = FileManager.default
        let standardizedRoot = (rootPath as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: standardizedRoot, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        // 如果根目录本身就是一个 Git 仓库
        if isGitRepository(at: standardizedRoot) {
            return [standardizedRoot]
        }

        var discovered: [String] = []
        let allIgnored = ignoredDirectoryNames.union(customIgnored)

        func walk(currentPath: String, depth: Int) {
            guard depth <= maxDepth else { return }
            guard let items = try? fm.contentsOfDirectory(atPath: currentPath) else { return }

            for item in items {
                if item.hasPrefix(".") && item != ".git" {
                    continue
                }
                if allIgnored.contains(item) {
                    continue
                }
                let fullPath = (currentPath as NSString).appendingPathComponent(item)
                var itemIsDir: ObjCBool = false
                guard fm.fileExists(atPath: fullPath, isDirectory: &itemIsDir), itemIsDir.boolValue else {
                    continue
                }

                if isGitRepository(at: fullPath) {
                    discovered.append(fullPath)
                    // 找到仓库后不再继续深入该仓库内部子目录（避免把子模块/构建产物重复扫出，除非用户单独添加）
                } else if depth < maxDepth {
                    walk(currentPath: fullPath, depth: depth + 1)
                }
            }
        }

        walk(currentPath: standardizedRoot, depth: 1)
        return discovered.sorted()
    }

    static func isGitRepository(at path: String) -> Bool {
        let gitPath = (path as NSString).appendingPathComponent(".git")
        return FileManager.default.fileExists(atPath: gitPath)
    }

    // MARK: - 2. 全面解析单个 Git 仓库状态
    static func inspectRepository(path: String, rootSourcePath: String) async -> GitRepository? {
        guard isGitRepository(at: path) else { return nil }

        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let parentPath = url.deletingLastPathComponent().path

        // 并发获取：status、remotes、log、branches、stash
        async let statusRes = runGit(["status", "--porcelain=v1", "-b"], in: path)
        async let remoteRes = runGit(["remote", "-v"], in: path)
        async let logRes = runGit(
            ["log", "-n", "20", "--date=relative", "--format=%H%x09%h%x09%s%x09%an%x09%cr%x09%ct%x09%D"],
            in: path
        )
        async let branchRes = runGit(
            ["for-each-ref", "--format=%(refname:short)%09%(refname)", "refs/heads", "refs/remotes"],
            in: path
        )
        async let stashRes = runGit(["stash", "list"], in: path)

        let (statusOut, remoteOut, logOut, branchOut, stashOut) = await (
            statusRes, remoteRes, logRes, branchRes, stashRes
        )

        // 解析 status
        let parsedStatus = parsePorcelainStatus(statusOut.stdout)

        // 解析 remotes
        let remotes = parseRemotes(remoteOut.stdout)
        let primaryRemote = remotes.first(where: { $0.name == "origin" }) ?? remotes.first
        let primaryProvider = primaryRemote?.provider ?? .localOnly
        let primaryWebURL = primaryRemote?.webURL
        let primarySlug = primaryRemote?.ownerAndRepo
        let primaryHost = primaryRemote?.host

        // 解析 commits
        let commits = parseCommits(logOut.stdout)
        let latestCommit = commits.first

        // 解析 branches
        let (localBranches, remoteBranches) = parseBranches(branchOut.stdout)

        // 解析 stash 数量
        let stashLines = stashOut.stdout
            .split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        return GitRepository(
            name: name,
            path: path,
            parentPath: parentPath,
            rootSourcePath: rootSourcePath,
            currentBranch: parsedStatus.currentBranch,
            upstreamBranch: parsedStatus.upstreamBranch,
            isDetachedHEAD: parsedStatus.isDetached,
            aheadCount: parsedStatus.ahead,
            behindCount: parsedStatus.behind,
            stagedCount: parsedStatus.stagedCount,
            modifiedCount: parsedStatus.modifiedCount,
            untrackedCount: parsedStatus.untrackedCount,
            conflictCount: parsedStatus.conflictCount,
            stashCount: stashLines.count,
            remotes: remotes,
            primaryProvider: primaryProvider,
            primaryWebURL: primaryWebURL,
            primaryRemoteSlug: primarySlug,
            primaryHost: primaryHost,
            lastCommitHash: latestCommit?.shortHash,
            lastCommitMessage: latestCommit?.subject,
            lastCommitAuthor: latestCommit?.author,
            lastCommitRelativeTime: latestCommit?.relativeDate,
            lastCommitDate: latestCommit?.timestamp,
            localBranches: localBranches,
            remoteBranches: remoteBranches,
            changedFiles: parsedStatus.changedFiles,
            recentCommits: commits,
            lastRefreshedAt: Date()
        )
    }

    // MARK: - 3. 解析 `git status --porcelain=v1 -b`
    private struct ParsedPorcelain {
        var currentBranch: String = "main"
        var upstreamBranch: String? = nil
        var isDetached: Bool = false
        var ahead: Int = 0
        var behind: Int = 0
        var stagedCount: Int = 0
        var modifiedCount: Int = 0
        var untrackedCount: Int = 0
        var conflictCount: Int = 0
        var changedFiles: [ChangedFile] = []
    }

    private static func parsePorcelainStatus(_ raw: String) -> ParsedPorcelain {
        var result = ParsedPorcelain()
        let lines = raw.components(separatedBy: .newlines)

        for line in lines where !line.isEmpty {
            if line.hasPrefix("## ") {
                let header = String(line.dropFirst(3))
                if header.hasPrefix("HEAD (no branch)") || header.hasPrefix("No commits yet on ") {
                    if header.hasPrefix("No commits yet on ") {
                        result.currentBranch = String(header.dropFirst("No commits yet on ".count))
                    } else {
                        result.currentBranch = "HEAD (游离)"
                        result.isDetached = true
                    }
                    continue
                }

                // 形如: main...origin/main [ahead 2, behind 1]
                var branchPart = header
                if let bracketRange = header.range(of: " [") {
                    branchPart = String(header[..<bracketRange.lowerBound])
                    let metaPart = String(header[bracketRange.upperBound...]).replacingOccurrences(of: "]", with: "")
                    let parts = metaPart.components(separatedBy: ",")
                    for p in parts {
                        let trimmed = p.trimmingCharacters(in: .whitespaces)
                        if trimmed.hasPrefix("ahead ") {
                            result.ahead = Int(trimmed.dropFirst("ahead ".count)) ?? 0
                        } else if trimmed.hasPrefix("behind ") {
                            result.behind = Int(trimmed.dropFirst("behind ".count)) ?? 0
                        }
                    }
                }

                if let dotsRange = branchPart.range(of: "...") {
                    result.currentBranch = String(branchPart[..<dotsRange.lowerBound])
                    result.upstreamBranch = String(branchPart[dotsRange.upperBound...])
                } else {
                    result.currentBranch = branchPart
                }
                continue
            }

            guard line.count >= 3 else { continue }
            let idx0 = line.startIndex
            let idx1 = line.index(after: idx0)
            let idx3 = line.index(idx0, offsetBy: 3)

            let x = String(line[idx0])
            let y = String(line[idx1])
            let xy = "\(x)\(y)"
            var filePath = String(line[idx3...])
            if let arrowRange = filePath.range(of: " -> ") {
                filePath = String(filePath[arrowRange.upperBound...])
            }
            filePath = filePath.trimmingCharacters(in: CharacterSet(charactersIn: "\""))

            let fileItem = ChangedFile(
                path: filePath,
                indexStatus: x,
                workTreeStatus: y,
                statusCode: xy
            )
            result.changedFiles.append(fileItem)

            if fileItem.isConflict {
                result.conflictCount += 1
            } else if fileItem.isUntracked {
                result.untrackedCount += 1
            } else {
                if x != " " && x != "?" {
                    result.stagedCount += 1
                }
                if y != " " && y != "?" {
                    result.modifiedCount += 1
                }
            }
        }

        return result
    }

    // MARK: - 4. 解析 `git remote -v`（支持任意平台 SSH/HTTPS/自建 Git）
    private static func parseRemotes(_ raw: String) -> [RemoteInfo] {
        var fetchMap: [String: String] = [:]
        var pushMap: [String: String] = [:]
        var orderedNames: [String] = []

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }
            let name = parts[0]
            let url = parts[1]
            let kind = parts.count >= 3 ? parts[2] : "(fetch)"

            if !orderedNames.contains(name) {
                orderedNames.append(name)
            }
            if kind.contains("push") {
                pushMap[name] = url
            } else {
                fetchMap[name] = url
            }
        }

        // 确保 origin 排在第一位
        orderedNames.sort { a, b in
            if a == "origin" { return true }
            if b == "origin" { return false }
            return a < b
        }

        return orderedNames.compactMap { name in
            guard let fetchURL = fetchMap[name] ?? pushMap[name] else { return nil }
            let pushURL = pushMap[name] ?? fetchURL
            let parsed = parseRemoteURL(fetchURL)
            return RemoteInfo(
                name: name,
                fetchURL: fetchURL,
                pushURL: pushURL,
                host: parsed.host,
                ownerAndRepo: parsed.slug,
                webURL: parsed.webURL,
                provider: GitProvider.detect(from: parsed.host)
            )
        }
    }

    static func parseRemoteURL(_ rawURL: String) -> (host: String, slug: String, webURL: String?) {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. 标准 HTTP/HTTPS/SSH URL (e.g. https://github.com/owner/repo.git 或 ssh://git@gitlab.example.com:2222/group/repo.git)
        if trimmed.contains("://"), let url = URL(string: trimmed), let host = url.host {
            var path = url.path
            if path.hasPrefix("/") { path.removeFirst() }
            if path.hasSuffix(".git") { path = String(path.dropLast(4)) }
            let webScheme = (url.scheme == "http") ? "http" : "https"
            let webURL = path.isEmpty ? "\(webScheme)://\(host)" : "\(webScheme)://\(host)/\(path)"
            return (host, path, webURL)
        }

        // 2. SCP 风格 SSH URL (e.g. git@github.com:owner/repo.git 或 git@gitlab.corp.com:group/sub/repo.git)
        if let colonIndex = trimmed.firstIndex(of: ":"), !trimmed.hasPrefix("/") {
            let beforeColon = String(trimmed[..<colonIndex])
            var afterColon = String(trimmed[trimmed.index(after: colonIndex)...])
            let host: String
            if let atIndex = beforeColon.firstIndex(of: "@") {
                host = String(beforeColon[beforeColon.index(after: atIndex)...])
            } else {
                host = beforeColon
            }
            if afterColon.hasPrefix("/") { afterColon.removeFirst() }
            if afterColon.hasSuffix(".git") { afterColon = String(afterColon.dropLast(4)) }
            let webURL = afterColon.isEmpty ? nil : "https://\(host)/\(afterColon)"
            return (host, afterColon, webURL)
        }

        return ("", trimmed, nil)
    }

    // MARK: - 5. 解析提交记录与分支
    private static func parseCommits(_ raw: String) -> [CommitItem] {
        var items: [CommitItem] = []
        for line in raw.components(separatedBy: .newlines) where !line.isEmpty {
            let cols = line.components(separatedBy: "\t")
            guard cols.count >= 6 else { continue }
            let fullHash = cols[0]
            let shortHash = cols[1]
            let subject = cols[2]
            let author = cols[3]
            let relativeDate = cols[4]
            let epoch = TimeInterval(cols[5]) ?? Date().timeIntervalSince1970
            let refs = cols.count >= 7 ? cols[6] : ""
            items.append(
                CommitItem(
                    hash: fullHash,
                    shortHash: shortHash,
                    subject: subject,
                    author: author,
                    relativeDate: relativeDate,
                    timestamp: Date(timeIntervalSince1970: epoch),
                    refs: refs
                )
            )
        }
        return items
    }

    private static func parseBranches(_ raw: String) -> (local: [String], remote: [String]) {
        var local: [String] = []
        var remote: [String] = []
        for line in raw.components(separatedBy: .newlines) where !line.isEmpty {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { continue }
            let shortName = parts[0]
            let fullRef = parts[1]
            if fullRef.hasPrefix("refs/heads/") {
                local.append(shortName)
            } else if fullRef.hasPrefix("refs/remotes/") && !shortName.hasSuffix("/HEAD") {
                remote.append(shortName)
            }
        }
        return (local, remote)
    }

    // MARK: - 6. 交互式 Git 操作（Fetch / Pull / Push / 切换分支 / Diff / 快速提交）
    static func fetch(at path: String, allRemotes: Bool = true) async -> CommandResult {
        let args = allRemotes ? ["fetch", "--all", "--prune"] : ["fetch", "--prune"]
        return await runGit(args, in: path)
    }

    static func pull(at path: String, rebase: Bool = false) async -> CommandResult {
        let args = rebase ? ["pull", "--rebase", "--autostash"] : ["pull"]
        return await runGit(args, in: path)
    }

    static func push(at path: String) async -> CommandResult {
        return await runGit(["push"], in: path)
    }

    static func checkoutBranch(at path: String, branch: String, createNew: Bool = false) async -> CommandResult {
        let args = createNew ? ["checkout", "-b", branch] : ["checkout", branch]
        return await runGit(args, in: path)
    }

    static func stageAllAndCommit(at path: String, message: String) async -> CommandResult {
        let addRes = await runGit(["add", "-A"], in: path)
        guard addRes.isSuccess else { return addRes }
        return await runGit(["commit", "-m", message], in: path)
    }

    static func discardFileChanges(at path: String, file: ChangedFile) async -> CommandResult {
        if file.isUntracked {
            return await runGit(["clean", "-f", "--", file.path], in: path)
        } else {
            return await runGit(["checkout", "HEAD", "--", file.path], in: path)
        }
    }

    static func fileDiff(at repoPath: String, file: ChangedFile) async -> String {
        if file.isUntracked {
            let fullURL = URL(fileURLWithPath: repoPath).appendingPathComponent(file.path)
            if let data = try? Data(contentsOf: fullURL),
               let content = String(data: data.prefix(32_768), encoding: .utf8) {
                let numbered = content
                    .components(separatedBy: .newlines)
                    .prefix(300)
                    .map { "+ \($0)" }
                    .joined(separator: "\n")
                return "--- /dev/null\n+++ b/\(file.path) (未跟踪新文件预览)\n\(numbered)"
            }
            return "（二进制文件或无法预览的未跟踪文件：\(file.path)）"
        }

        // 先查工作区与 HEAD 的整体 diff，若无则查 --cached
        let headDiff = await runGit(["diff", "HEAD", "--", file.path], in: repoPath)
        if !headDiff.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return headDiff.stdout
        }
        let cachedDiff = await runGit(["diff", "--cached", "--", file.path], in: repoPath)
        if !cachedDiff.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return cachedDiff.stdout
        }
        let plainDiff = await runGit(["diff", "--", file.path], in: repoPath)
        return plainDiff.stdout.isEmpty ? "（无文本差异或文件仅模式变更）" : plainDiff.stdout
    }

    // MARK: - 7. 底层异步执行器
    static func runGit(_ arguments: [String], in directoryPath: String) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: gitExecutable)
                process.arguments = arguments
                process.currentDirectoryURL = URL(fileURLWithPath: directoryPath)

                var env = ProcessInfo.processInfo.environment
                env["GIT_TERMINAL_PROMPT"] = "0"
                env["GIT_OPTIONAL_LOCKS"] = "0"
                env["LC_ALL"] = "en_US.UTF-8"
                env["LANG"] = "en_US.UTF-8"
                if let existingPath = env["PATH"] {
                    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
                } else {
                    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                }
                process.environment = env

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    let stdout = String(data: outData, encoding: .utf8) ?? ""
                    let stderr = String(data: errData, encoding: .utf8) ?? ""
                    continuation.resume(
                        returning: CommandResult(
                            exitCode: process.terminationStatus,
                            stdout: stdout,
                            stderr: stderr
                        )
                    )
                } catch {
                    continuation.resume(
                        returning: CommandResult(
                            exitCode: -1,
                            stdout: "",
                            stderr: error.localizedDescription
                        )
                    )
                }
            }
        }
    }
}
