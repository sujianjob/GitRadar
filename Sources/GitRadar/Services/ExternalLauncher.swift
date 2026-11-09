import AppKit
import Foundation

struct ExternalApp: Identifiable, Hashable, Codable {
    var id: String { bundlePath }
    let name: String
    let category: Category
    let bundlePath: String
    let sfSymbol: String

    enum Category: String, Codable, Hashable {
        case editor = "编辑器 / IDE"
        case terminal = "终端工具"
        case gitClient = "Git 客户端"
    }
}

@MainActor
enum ExternalLauncher {
    private static let candidateApps: [(name: String, category: ExternalApp.Category, paths: [String], symbol: String)] = [
        // 编辑器 / IDE
        ("Antigravity", .editor, ["/Applications/Antigravity.app", "/Applications/Antigravity IDE.app"], "sparkles"),
        ("VS Code", .editor, ["/Applications/Visual Studio Code.app"], "chevron.left.forwardslash.chevron.right"),
        ("Cursor", .editor, ["/Applications/Cursor.app"], "cursorarrow.rays"),
        ("Zed", .editor, ["/Applications/Zed.app"], "bolt.fill"),
        ("Trae", .editor, ["/Applications/Trae.app"], "wand.and.stars"),
        ("Windsurf", .editor, ["/Applications/Windsurf.app"], "wind"),
        ("IntelliJ IDEA", .editor, ["/Applications/IntelliJ IDEA.app", "/Applications/IntelliJ IDEA CE.app"], "hammer.fill"),
        ("PyCharm", .editor, ["/Applications/PyCharm.app", "/Applications/PyCharm CE.app"], "terminal.fill"),
        ("GoLand", .editor, ["/Applications/GoLand.app"], "cpu.fill"),
        ("Android Studio", .editor, ["/Applications/Android Studio.app"], "iphone"),
        ("DataSpell", .editor, ["/Applications/DataSpell.app"], "chart.bar.doc.horizontal"),
        ("Xcode", .editor, ["/Applications/Xcode.app"], "hammer.circle.fill"),
        ("Typora", .editor, ["/Applications/Typora.app"], "doc.richtext"),
        ("Obsidian", .editor, ["/Applications/Obsidian.app"], "book.closed.fill"),

        // 终端
        ("Warp", .terminal, ["/Applications/Warp.app"], "bolt.horizontal.circle.fill"),
        ("iTerm2", .terminal, ["/Applications/iTerm.app"], "apple.terminal.fill"),
        ("Termora", .terminal, ["/Applications/Termora.app"], "terminal"),
        ("系统终端 (Terminal)", .terminal, ["/System/Applications/Utilities/Terminal.app"], "terminal"),

        // 外部 Git GUI
        ("Fork", .gitClient, ["/Applications/Fork.app"], "tuningfork"),
        ("GitHub Desktop", .gitClient, ["/Applications/GitHub Desktop.app"], "desktopcomputer"),
        ("Sourcetree", .gitClient, ["/Applications/Sourcetree.app"], "arrow.triangle.branch")
    ]

    static func installedApps() -> [ExternalApp] {
        let fm = FileManager.default
        var found: [ExternalApp] = []

        for item in candidateApps {
            if let existingPath = item.paths.first(where: { fm.fileExists(atPath: $0) }) {
                found.append(
                    ExternalApp(
                        name: item.name,
                        category: item.category,
                        bundlePath: existingPath,
                        sfSymbol: item.symbol
                    )
                )
            }
        }
        return found
    }

    static func installedEditors() -> [ExternalApp] {
        installedApps().filter { $0.category == .editor }
    }

    static func installedTerminals() -> [ExternalApp] {
        installedApps().filter { $0.category == .terminal }
    }

    static func openInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    static func openInBrowser(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    static func openInVSCode(path: String) {
        let candidatePaths = [
            "/Applications/Visual Studio Code.app",
            (NSHomeDirectory() as NSString).appendingPathComponent("Applications/Visual Studio Code.app")
        ]
        if let appPath = candidatePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            let app = ExternalApp(
                name: "VS Code",
                category: .editor,
                bundlePath: appPath,
                sfSymbol: "chevron.left.forwardslash.chevron.right"
            )
            openRepository(path: path, with: app)
        } else {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["-a", "Visual Studio Code", path]
            try? proc.run()
        }
    }

    static func openInAntigravity(path: String) {
        let candidatePaths = [
            "/Applications/Antigravity.app",
            "/Applications/Antigravity IDE.app",
            (NSHomeDirectory() as NSString).appendingPathComponent("Applications/Antigravity.app"),
            (NSHomeDirectory() as NSString).appendingPathComponent("Applications/Antigravity IDE.app")
        ]
        if let appPath = candidatePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            let app = ExternalApp(
                name: "Antigravity IDE",
                category: .editor,
                bundlePath: appPath,
                sfSymbol: "sparkles"
            )
            openRepository(path: path, with: app)
        } else {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["-a", "Antigravity", path]
            try? proc.run()
        }
    }

    static func openRepository(path: String, with app: ExternalApp) {
        let repoURL = URL(fileURLWithPath: path)
        let appURL = URL(fileURLWithPath: app.bundlePath)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        NSWorkspace.shared.open(
            [repoURL],
            withApplicationAt: appURL,
            configuration: config
        ) { _, error in
            if let error {
                // 回退使用 `open -a`
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                proc.arguments = ["-a", app.bundlePath, path]
                try? proc.run()
                print("Fallback open -a for \(app.name): \(error.localizedDescription)")
            }
        }
    }

    static func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
