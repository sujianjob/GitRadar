import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct GitRadarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = RadarStore()

    var body: some Scene {
        WindowGroup("GitRadar — 全平台本地 Git 仓库全景管理") {
            MainWindowView(store: store)
                .frame(minWidth: 1020, idealWidth: 1280, minHeight: 660, idealHeight: 800)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(after: .newItem) {
                Button("添加扫描目录或仓库...") {
                    store.promptAddDirectory()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("新建虚拟分组...") {
                    store.showNewGroupSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandMenu("仓库操作") {
                Button("重新扫描并刷新全部状态") {
                    Task { await store.scanAndRefreshAll() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("批量 Fetch 所有远程仓库") {
                    Task { await store.batchFetchAllVisible() }
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("批量 Pull 待更新仓库") {
                    Task { await store.batchPullAllBehind() }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Divider()

                Button("切换为卡片视图") {
                    store.viewMode = .grid
                    store.saveConfig()
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("切换为表格视图") {
                    store.viewMode = .table
                    store.saveConfig()
                }
                .keyboardShortcut("2", modifiers: [.command])

                Divider()

                Button("偏好设置与执行日志...") {
                    store.showSettingsSheet = true
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}
