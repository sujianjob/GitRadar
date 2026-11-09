import SwiftUI

struct FilterRulesSheetView: View {
    @ObservedObject var store: RadarStore
    @Environment(\.dismiss) private var dismiss

    enum FilterTab: String, CaseIterable {
        case unfiltered = "未过滤"
        case filtered = "已过滤"
    }

    @State private var selectedTab: FilterTab = .unfiltered
    @State private var patternInput: String = ""

    // 未过滤的域名列表
    private var unfilteredHosts: [RadarStore.DiscoveredHostSummary] {
        store.discoveredHosts.filter { !$0.isExcluded && $0.visibleCount > 0 }
    }

    // 未过滤的组织列表
    private var unfilteredOrgs: [RadarStore.DiscoveredOrgSummary] {
        store.discoveredHosts
            .filter { !$0.isExcluded }
            .flatMap { $0.organizations }
            .filter { !$0.isExcluded && $0.visibleCount > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: 1. 顶部栏：标题 + 双 Tab 切换（未过滤 / 已过滤） + 完成按钮
            HStack(spacing: 12) {
                Text("过滤管理")
                    .font(.system(size: 15, weight: .bold))

                Spacer()

                Picker("", selection: $selectedTab) {
                    Text("未过滤 (\(store.visibleRepositories.count))").tag(FilterTab.unfiltered)
                    Text("已过滤 (\(store.excludedRepositories.count))").tag(FilterTab.filtered)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)

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

            // MARK: 2. 双 Tab 主体内容
            switch selectedTab {
            case .unfiltered:
                unfilteredTableSection
            case .filtered:
                filteredTableSection
            }
        }
        .frame(width: 640, height: 480)
    }

    // MARK: - Tab 1: 未过滤（选择要过滤的域名 / 组织 / 仓库）
    private var unfilteredTableSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部手动输入过滤栏
            HStack(spacing: 8) {
                TextField("输入域名 / 组织 / 仓库关键字，如 gitea.xxx.com", text: $patternInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit {
                        submitCustomPattern()
                    }

                Button("+ 过滤") {
                    submitCustomPattern()
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

            // 表头
            HStack(spacing: 0) {
                Text("类型")
                    .frame(width: 80, alignment: .leading)
                Text("名称 / 标识")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("关联仓库数")
                    .frame(width: 90, alignment: .trailing)
                Text("操作")
                    .frame(width: 76, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(AppTheme.canvasBackground)

            Divider()

            // 表格内容列表
            List {
                // 1. 域名行
                ForEach(unfilteredHosts) { hostItem in
                    unfilteredRow(
                        typeIcon: "globe",
                        typeName: "域名",
                        title: hostItem.host,
                        subtitle: nil,
                        countText: "\(hostItem.visibleCount) 个"
                    ) {
                        store.hideRemoteHost(hostItem.host)
                    }
                }

                // 2. 组织行
                ForEach(unfilteredOrgs) { orgItem in
                    unfilteredRow(
                        typeIcon: "person.2",
                        typeName: "组织",
                        title: "\(orgItem.host) / \(orgItem.org)",
                        subtitle: nil,
                        countText: "\(orgItem.visibleCount) 个"
                    ) {
                        store.hideRemoteOrganization(host: orgItem.host, org: orgItem.org)
                    }
                }

                // 3. 仓库行
                ForEach(store.visibleRepositories) { repo in
                    unfilteredRow(
                        typeIcon: "shippingbox",
                        typeName: "仓库",
                        title: repo.name,
                        subtitle: repo.displayPath,
                        countText: "1 个"
                    ) {
                        store.hideRepository(repo)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func unfilteredRow(
        typeIcon: String,
        typeName: String,
        title: String,
        subtitle: String?,
        countText: String,
        onFilter: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 0) {
            // 类型列
            HStack(spacing: 4) {
                Image(systemName: typeIcon)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Text(typeName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80, alignment: .leading)

            // 名称 / 标识列
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                if let subtitle {
                    Text("(\(subtitle))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 关联仓库数列
            Text(countText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)

            // 操作列
            HStack {
                Spacer()
                Button("过滤") {
                    onFilter()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .frame(width: 76, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Tab 2: 已过滤（展示已配置的规则 & 已被过滤隐藏的仓库）
    private var filteredTableSection: some View {
        VSplitView {
            // 上半表：已配置的过滤规则
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("已配置的过滤规则 (\(store.filterRules.count))")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppTheme.subtleSurface)

                Divider()

                // 规则表头
                HStack(spacing: 0) {
                    Text("规则类型")
                        .frame(width: 100, alignment: .leading)
                    Text("规则内容")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("命中数量")
                        .frame(width: 90, alignment: .trailing)
                    Text("操作")
                        .frame(width: 76, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(AppTheme.canvasBackground)

                Divider()

                if store.filterRules.isEmpty {
                    VStack {
                        Text("暂无已配置的过滤规则")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(store.filterRules) { rule in
                            let hitCount = store.repositories.filter { rule.matches($0) }.count
                            HStack(spacing: 0) {
                                Text(ruleTypeBadge(for: rule))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 100, alignment: .leading)

                                Text(rule.pattern)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text("\(hitCount) 个仓库")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .trailing)

                                HStack {
                                    Spacer()
                                    Button("移除") {
                                        store.deleteFilterRule(rule.id)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                                .frame(width: 76, alignment: .trailing)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minHeight: 150, idealHeight: 190)

            // 下半表：已被过滤隐藏的仓库
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("已被过滤隐藏的仓库 (\(store.excludedRepositories.count))")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppTheme.subtleSurface)

                Divider()

                // 仓库表头
                HStack(spacing: 0) {
                    Text("仓库名称")
                        .frame(width: 170, alignment: .leading)
                    Text("所属域名/组织 或 路径")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("操作")
                        .frame(width: 76, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(AppTheme.canvasBackground)

                Divider()

                if store.excludedRepositories.isEmpty {
                    VStack {
                        Text("当前没有被过滤隐藏的仓库")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(store.excludedRepositories) { repo in
                            HStack(spacing: 0) {
                                HStack(spacing: 6) {
                                    ProjectAvatarView(repo: repo, size: 20)
                                    Text(repo.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                }
                                .frame(width: 170, alignment: .leading)

                                Text(repo.primaryWebURL ?? repo.primaryHostAndOrg ?? repo.displayPath)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                HStack {
                                    Spacer()
                                    Button("恢复") {
                                        store.restoreExcludedRepository(repo)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                                .frame(width: 76, alignment: .trailing)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minHeight: 160)
        }
    }

    private func ruleTypeBadge(for rule: RepoFilterRule) -> String {
        switch rule.field {
        case .remoteHost: return "🌐 远程域名"
        case .remoteOrganization: return "👥 远程组织"
        case .exactPath, .repoName: return "📦 指定仓库"
        case .pathContains: return "📁 目录路径"
        case .remoteContains, .smart: return "🔍 关键字"
        }
    }

    private func submitCustomPattern() {
        let trimmed = patternInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addFilterRule(field: .smart, pattern: trimmed)
        patternInput = ""
    }
}
