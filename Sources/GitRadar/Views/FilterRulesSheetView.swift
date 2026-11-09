import SwiftUI

struct FilterRulesSheetView: View {
    @ObservedObject var store: RadarStore
    @Environment(\.dismiss) private var dismiss

    enum FilterManageTab: String, CaseIterable {
        case domainsAndOrgs = "域名与组织管理"
        case customRules = "全部过滤规则与已隐藏仓库"
    }

    @State private var currentTab: FilterManageTab = .domainsAndOrgs
    @State private var quickDomainOrOrgInput: String = ""
    @State private var quickInputMode: FilterRuleMatchField = .remoteHost

    @State private var selectedField: FilterRuleMatchField = .remoteHost
    @State private var patternInput: String = ""
    @State private var noteInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: 1. 顶部标题与模式切换栏
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("域名、组织与仓库过滤管理")
                        .font(.system(size: 15, weight: .bold))
                    Text("支持按自建 Gitea / GitLab 域名、GitHub 组织/Owner、路径或名称一键屏蔽，过滤后的仓库将不显示")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("", selection: $currentTab) {
                    ForEach(FilterManageTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 310)

                Button("完成") {
                    store.saveConfig()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
            .padding(16)

            Divider()

            switch currentTab {
            case .domainsAndOrgs:
                domainsAndOrganizationsView
            case .customRules:
                customRulesAndExcludedReposView
            }
        }
        .frame(width: 740, height: 520)
    }

    // MARK: - Tab 1: 域名与组织可视化管理面板
    private var domainsAndOrganizationsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部：手动快速输入任意自建域名或组织进行屏蔽
            HStack(spacing: 8) {
                Picker("", selection: $quickInputMode) {
                    Text("按远程域名屏蔽").tag(FilterRuleMatchField.remoteHost)
                    Text("按组织 / Owner 屏蔽").tag(FilterRuleMatchField.remoteOrganization)
                }
                .labelsHidden()
                .frame(width: 150)

                TextField(
                    quickInputMode == .remoteHost
                        ? "输入要过滤的域名，如 gitea.company.com 或 *.internal.local"
                        : "输入要过滤的组织名，如 my-org 或 gitea.company.com/my-org",
                    text: $quickDomainOrOrgInput
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

                Button {
                    store.addFilterRule(
                        field: quickInputMode,
                        pattern: quickDomainOrOrgInput,
                        note: quickInputMode == .remoteHost ? "手动屏蔽域名" : "手动屏蔽组织"
                    )
                    quickDomainOrOrgInput = ""
                } label: {
                    Label("添加屏蔽", systemImage: "eye.slash")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .disabled(quickDomainOrOrgInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppTheme.subtleSurface)

            Divider()

            // 主体：自动聚合本机所有仓库中发现的「远程域名 -> 组织/Owner」树状列表
            if store.discoveredHosts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("当前扫描的仓库中尚未检测到远程域名")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("您仍可通过上方输入框预先添加要过滤的自建 Gitea / GitLab 域名或组织")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.discoveredHosts) { hostItem in
                        Section {
                            // 域名下的各个组织 / Owner 行
                            ForEach(hostItem.organizations) { orgItem in
                                HStack(spacing: 10) {
                                    Image(systemName: "person.2")
                                        .font(.system(size: 11))
                                        .foregroundStyle(orgItem.isExcluded ? .tertiary : .secondary)
                                        .frame(width: 18)

                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(spacing: 6) {
                                            Text(orgItem.org)
                                                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                                                .strikethrough(orgItem.isExcluded)
                                                .foregroundStyle(orgItem.isExcluded ? .secondary : .primary)

                                            Text("\(hostItem.host)/\(orgItem.org)")
                                                .font(.system(size: 10.5, design: .monospaced))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }

                                    Spacer()

                                    Text("共 \(orgItem.totalCount) 个仓库")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)

                                    if hostItem.isExcluded {
                                        Text("已随域名屏蔽")
                                            .font(.system(size: 10.5, weight: .medium))
                                            .foregroundStyle(AppTheme.statusDanger)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2.5)
                                            .background(RoundedRectangle(cornerRadius: 4).fill(AppTheme.subtleSurface))
                                    } else {
                                        Button {
                                            store.toggleOrganizationFilter(host: hostItem.host, org: orgItem.org)
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: orgItem.isExcluded ? "eye" : "eye.slash")
                                                    .font(.system(size: 10))
                                                Text(orgItem.isExcluded ? "已屏蔽 · 点击恢复" : "屏蔽此组织")
                                                    .font(.system(size: 11, weight: .medium))
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3.5)
                                            .background(
                                                RoundedRectangle(cornerRadius: 5)
                                                    .fill(orgItem.isExcluded ? AppTheme.statusDanger.opacity(0.12) : AppTheme.subtleSurface)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 5)
                                                    .stroke(orgItem.isExcluded ? AppTheme.statusDanger.opacity(0.4) : AppTheme.hairlineBorder, lineWidth: 1)
                                            )
                                            .foregroundStyle(orgItem.isExcluded ? AppTheme.statusDanger : .primary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        } header: {
                            HStack(spacing: 8) {
                                Image(systemName: hostItem.provider.sfSymbol)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                Text(hostItem.host)
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(hostItem.isExcluded ? .secondary : .primary)
                                    .strikethrough(hostItem.isExcluded)

                                Text(hostItem.provider.rawValue)
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(AppTheme.subtleSurface))
                                    .foregroundStyle(.secondary)

                                Text("(\(hostItem.visibleCount)/\(hostItem.totalCount) 显示中)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Button {
                                    store.toggleHostFilter(hostItem.host)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: hostItem.isExcluded ? "eye" : "eye.slash")
                                            .font(.system(size: 10))
                                        Text(hostItem.isExcluded ? "整站已屏蔽 · 点击恢复" : "屏蔽整个域名")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3.5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(hostItem.isExcluded ? AppTheme.statusDanger.opacity(0.14) : AppTheme.subtleSurface)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(hostItem.isExcluded ? AppTheme.statusDanger.opacity(0.45) : AppTheme.hairlineBorder, lineWidth: 1)
                                    )
                                    .foregroundStyle(hostItem.isExcluded ? AppTheme.statusDanger : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tab 2: 自定义过滤规则明细与已隐藏仓库列表
    private var customRulesAndExcludedReposView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("新增自定义过滤规则")
                    .font(.system(size: 12, weight: .semibold))

                HStack(spacing: 8) {
                    Picker("匹配维度", selection: $selectedField) {
                        ForEach(FilterRuleMatchField.allCases) { field in
                            Text(field.rawValue).tag(field)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 145)

                    TextField(placeholderText, text: $patternInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                    TextField("备注（选填）", text: $noteInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(width: 120)

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
                .frame(minWidth: 340, maxWidth: .infinity)

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
                                    Text(repo.primaryHostAndOrg ?? repo.displayPath)
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
                .frame(minWidth: 260, idealWidth: 300)
            }
        }
    }

    private var placeholderText: String {
        switch selectedField {
        case .remoteHost:
            return "输入远程域名，如 gitea.company.com 或 *.internal.local"
        case .remoteOrganization:
            return "输入组织/用户名，如 my-org 或 gitea.company.com/my-org"
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
