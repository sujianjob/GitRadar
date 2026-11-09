import SwiftUI

struct FilterRulesSheetView: View {
    @ObservedObject var store: RadarStore
    @Environment(\.dismiss) private var dismiss

    @State private var patternInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: 1. 简洁顶部栏（无多余解释文案）
            HStack {
                Text("过滤规则")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button("完成") {
                    store.saveConfig()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // MARK: 2. 极简添加栏（自动识别域名、组织、仓库名或路径）
            HStack(spacing: 8) {
                TextField("输入域名、组织名或仓库名关键字（如 gitea.xxx.com 或 org-name）", text: $patternInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit {
                        addRule()
                    }

                Button("添加") {
                    addRule()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .controlSize(.small)
                .disabled(patternInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppTheme.subtleSurface)

            Divider()

            // MARK: 3. 单列表清晰展示：已添加规则 + 域名/组织快捷开关
            List {
                if !store.filterRules.isEmpty {
                    Section("已添加的过滤规则 (\(store.filterRules.count))") {
                        ForEach(store.filterRules) { rule in
                            HStack(spacing: 10) {
                                Toggle("", isOn: Binding(
                                    get: { rule.isEnabled },
                                    set: { _ in store.toggleFilterRule(rule.id) }
                                ))
                                .labelsHidden()
                                .toggleStyle(.checkbox)

                                Text(rule.pattern)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .strikethrough(!rule.isEnabled)
                                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                let hitCount = store.repositories.filter { rule.matches($0) }.count
                                Text("已隐藏 \(hitCount) 个")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)

                                Button(role: .destructive) {
                                    store.deleteFilterRule(rule.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if !store.discoveredHosts.isEmpty {
                    Section("本机仓库域名与组织") {
                        ForEach(store.discoveredHosts) { hostItem in
                            // 域名行
                            HStack(spacing: 8) {
                                Image(systemName: "globe")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)

                                Text(hostItem.host)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(hostItem.isExcluded ? .secondary : .primary)
                                    .strikethrough(hostItem.isExcluded)

                                Text("\(hostItem.totalCount) 个仓库")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Button(hostItem.isExcluded ? "取消过滤" : "过滤此域名") {
                                    store.toggleHostFilter(hostItem.host)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                            .padding(.vertical, 2)

                            // 该域名下的组织行
                            ForEach(hostItem.organizations) { orgItem in
                                HStack(spacing: 8) {
                                    Color.clear.frame(width: 16)
                                    Image(systemName: "person.2")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 14)

                                    Text("\(hostItem.host) / \(orgItem.org)")
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(orgItem.isExcluded ? .secondary : .primary)
                                        .strikethrough(orgItem.isExcluded)

                                    Text("\(orgItem.totalCount)")
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(.tertiary)

                                    Spacer()

                                    if !hostItem.isExcluded {
                                        Button(orgItem.isExcluded ? "取消过滤" : "过滤此组织") {
                                            store.toggleOrganizationFilter(host: hostItem.host, org: orgItem.org)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                    }
                                }
                                .padding(.vertical, 1)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 500, height: 420)
    }

    private func addRule() {
        let trimmed = patternInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addFilterRule(field: .smart, pattern: trimmed)
        patternInput = ""
    }
}
