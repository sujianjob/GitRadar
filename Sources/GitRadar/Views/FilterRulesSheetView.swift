import SwiftUI

struct FilterRulesSheetView: View {
    @ObservedObject var store: RadarStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedField: FilterRuleMatchField = .repoName
    @State private var patternInput: String = ""
    @State private var noteInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: 1. 顶部标题栏
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("仓库过滤屏蔽规则")
                        .font(.system(size: 15, weight: .bold))
                    Text("命中任一启用规则的 Git 仓库将自动隐藏，不在主看板及统计中显示（支持 * 通配符）")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") {
                    store.saveConfig()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
            .padding(16)

            Divider()

            // MARK: 2. 新增过滤规则表单栏
            VStack(alignment: .leading, spacing: 8) {
                Text("新增过滤规则")
                    .font(.system(size: 12, weight: .semibold))

                HStack(spacing: 8) {
                    Picker("匹配维度", selection: $selectedField) {
                        ForEach(FilterRuleMatchField.allCases) { field in
                            Text(field.rawValue).tag(field)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)

                    TextField(placeholderText, text: $patternInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                    TextField("备注（选填）", text: $noteInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(width: 130)

                    Button {
                        store.addFilterRule(field: selectedField, pattern: patternInput, note: noteInput)
                        patternInput = ""
                        noteInput = ""
                    } label: {
                        Label("添加规则", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .disabled(patternInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
            .background(AppTheme.subtleSurface)

            Divider()

            // MARK: 3. 规则列表与已隐藏仓库预览
            HSplitView {
                // 左侧：已配置的过滤规则
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("生效规则列表 (\(store.filterRules.count))")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    Divider()

                    if store.filterRules.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 26))
                                .foregroundStyle(.tertiary)
                            Text("暂未设置过滤规则")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("可在上方输入规则，或在仓库卡片上右键选择「加入过滤规则（隐藏）」")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(store.filterRules) { rule in
                                HStack(spacing: 8) {
                                    Toggle("", isOn: Binding(
                                        get: { rule.isEnabled },
                                        set: { _ in store.toggleFilterRule(rule.id) }
                                    ))
                                    .labelsHidden()
                                    .toggleStyle(.checkbox)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(rule.field.rawValue)
                                                .font(.system(size: 10, weight: .semibold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1.5)
                                                .background(RoundedRectangle(cornerRadius: 4).fill(AppTheme.subtleSurface))
                                                .foregroundStyle(.secondary)

                                            Text(rule.pattern)
                                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                                .strikethrough(!rule.isEnabled)
                                                .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }

                                        if !rule.note.isEmpty {
                                            Text(rule.note)
                                                .font(.system(size: 10.5))
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    let hitCount = store.repositories.filter { rule.matches($0) }.count
                                    if hitCount > 0 {
                                        Text("命中 \(hitCount)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }

                                    Button(role: .destructive) {
                                        store.deleteFilterRule(rule.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("删除此过滤规则")
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }
                .frame(minWidth: 320, maxWidth: .infinity)

                // 右侧：当前被规则隐藏的仓库预览
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("当前已隐藏的仓库 (\(store.excludedRepositories.count))")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    Divider()

                    if store.excludedRepositories.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 24))
                                .foregroundStyle(.tertiary)
                            Text("当前没有仓库被隐藏")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(store.excludedRepositories) { repo in
                            HStack(spacing: 8) {
                                ProjectAvatarView(repo: repo, size: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(repo.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                    Text(repo.displayPath)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Button("恢复显示") {
                                    store.restoreExcludedRepository(repo)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(minWidth: 250, idealWidth: 280)
            }
        }
        .frame(width: 680, height: 460)
    }

    private var placeholderText: String {
        switch selectedField {
        case .repoName:
            return "输入仓库名关键字或通配符，如 test*、*-demo"
        case .pathContains:
            return "输入路径包含关键字，如 /vendor/、/archive/"
        case .exactPath:
            return "输入完整路径，如 ~/AI/some-repo"
        case .remoteContains:
            return "输入远程地址关键字，如 gitlab.internal"
        }
    }
}
