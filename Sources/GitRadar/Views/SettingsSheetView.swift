import SwiftUI

struct SettingsSheetView: View {
    @ObservedObject var store: RadarStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("GitRadar 偏好设置与执行日志", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()
                Button("完成") {
                    store.saveConfig()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)

            Divider()

            TabView {
                generalSettingsTab
                    .tabItem {
                        Label("通用与外部工具", systemImage: "gearshape")
                    }

                directoriesSettingsTab
                    .tabItem {
                        Label("扫描目录管理", systemImage: "folder.badge.gearshape")
                    }

                actionLogsTab
                    .tabItem {
                        Label("Git 执行日志 (\(store.actionLogs.count))", systemImage: "terminal")
                    }
            }
            .padding(16)
        }
        .frame(width: 620, height: 460)
    }

    private var generalSettingsTab: some View {
        Form {
            Section("目录递归扫描配置") {
                Stepper(
                    "默认最大递归扫描深度：\(store.defaultScanDepth) 层",
                    value: $store.defaultScanDepth,
                    in: 1...8
                )
                .onChange(of: store.defaultScanDepth) { _, newValue in
                    for idx in store.watchedDirectories.indices {
                        store.watchedDirectories[idx].maxDepth = newValue
                    }
                    store.saveConfig()
                }

                Text("已自动跳过 node_modules、.build、Pods、DerivedData、venv、target、dist 等构建与依赖目录，保证毫秒级扫描响应。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var directoriesSettingsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("当前监控的根目录列表")
                    .font(.subheadline.bold())
                Spacer()
                Button {
                    store.promptAddDirectory()
                } label: {
                    Label("添加目录", systemImage: "plus")
                }
                .controlSize(.small)
            }

            List {
                ForEach(store.watchedDirectories) { dir in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dir.displayName)
                                .font(.system(size: 13, weight: .semibold))
                            Text(dir.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(store.countForRootDirectory(dir.path)) 个仓库")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            store.removeWatchedDirectory(dir)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack(spacing: 8) {
                Text("快速添加本机常用目录：")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(["~/AI", "~/Projects", "~/Developer", "~/Desktop", "~/Documents"], id: \.self) { candidate in
                    let expanded = (candidate as NSString).expandingTildeInPath
                    if FileManager.default.fileExists(atPath: expanded),
                       !store.watchedDirectories.contains(where: { $0.path == expanded }) {
                        Button(candidate) {
                            store.addQuickDirectory(candidate)
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var actionLogsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.actionLogs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("暂无手动 Git 命令执行记录")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.actionLogs) { log in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: log.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(log.success ? .green : .red)
                            Text(log.repoName)
                                .font(.system(size: 12, weight: .bold))
                            Text(log.command)
                                .font(.system(size: 11, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)))
                            Spacer()
                            Text(log.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if !log.output.isEmpty {
                            Text(log.output)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }
}
