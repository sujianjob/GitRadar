import SwiftUI

struct FilterRulesSheetView: View {
    @ObservedObject var store: RadarStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("过滤管理")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("完成") {
                    store.saveConfig()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .controlSize(.small)
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(AppTheme.canvasBackground)

            Divider()

            FilterRulesContentView(store: store)
                .background(AppTheme.canvasBackground)
        }
        .frame(width: 820, height: 550)
    }
}

struct FilterRulesContentView: View {
    @ObservedObject var store: RadarStore

    enum FilterTab: String, CaseIterable {
        case unfiltered = "未过滤"
        case filtered = "已过滤"
    }

    @State private var selectedTab: FilterTab = .unfiltered
    @State private var patternInput: String = ""

    private var unfilteredHosts: [RadarStore.DiscoveredHostSummary] {
        store.discoveredHosts.filter { !$0.isExcluded && $0.visibleCount > 0 }
    }

    private var unfilteredOrgs: [RadarStore.DiscoveredOrgSummary] {
        store.discoveredHosts
            .filter { !$0.isExcluded }
            .flatMap { $0.organizations }
            .filter { !$0.isExcluded && $0.visibleCount > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 顶部工具条卡片（未过滤 / 已过滤 切换 + 关键字快捷过滤）
            HStack(spacing: 12) {
                Picker("", selection: $selectedTab) {
                    Text("未过滤 (\(store.visibleRepositories.count))").tag(FilterTab.unfiltered)
                    Text("已过滤 (\(store.excludedRepositories.count))").tag(FilterTab.filtered)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)

                Spacer(minLength: 10)

                if selectedTab == .unfiltered {
                    HStack(spacing: 8) {
                        TextField("输入域名 / 组织 / 仓库关键字，如 gitea.xxx.com", text: $patternInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 290)
                            .onSubmit {
                                submitCustomPattern()
                            }

                        Button("+ 添加过滤") {
                            submitCustomPattern()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                        .controlSize(.small)
                        .fixedSize()
                        .disabled(patternInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.hairlineBorder, lineWidth: 1)
            )

            switch selectedTab {
            case .unfiltered:
                unfilteredTableCard
            case .filtered:
                filteredTablesSection
            }
        }
        .padding(18)
    }

    // MARK: - Tab 1: 未过滤（选择要过滤的域名 / 组织 / 仓库）
    private var unfilteredTableCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 表头
            HStack(spacing: 12) {
                Text("类型")
                    .frame(width: 84, alignment: .leading)
                Text("域名 / 组织 / 仓库标识")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("关联仓库数")
                    .frame(width: 90, alignment: .trailing)
                Text("操作")
                    .frame(width: 80, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(AppTheme.subtleSurface)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
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
                        Divider().padding(.horizontal, 16).opacity(0.45)
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
                        Divider().padding(.horizontal, 16).opacity(0.45)
                    }

                    // 3. 仓库行
                    ForEach(Array(store.visibleRepositories.enumerated()), id: \.element.id) { idx, repo in
                        unfilteredRow(
                            typeIcon: "shippingbox",
                            typeName: "仓库",
                            title: repo.name,
                            subtitle: repo.displayPath,
                            countText: "1 个"
                        ) {
                            store.hideRepository(repo)
                        }
                        if idx < store.visibleRepositories.count - 1 {
                            Divider().padding(.horizontal, 16).opacity(0.45)
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.hairlineBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func unfilteredRow(
        typeIcon: String,
        typeName: String,
        title: String,
        subtitle: String?,
        countText: String,
        onFilter: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: typeIcon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(typeName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 84, alignment: .leading)

            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(countText)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)

            HStack {
                Spacer()
                Button("过滤") {
                    onFilter()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
            }
            .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Tab 2: 已过滤（上下双卡片表格：已配置的过滤规则 & 已被过滤隐藏的仓库）
    private var filteredTablesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 上半卡片：已配置的过滤规则
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text("规则类型")
                        .frame(width: 100, alignment: .leading)
                    Text("已配置规则内容 (\(store.filterRules.count))")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("命中仓库")
                        .frame(width: 90, alignment: .trailing)
                    Text("操作")
                        .frame(width: 80, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppTheme.subtleSurface)

                Divider()

                if store.filterRules.isEmpty {
                    VStack {
                        Text("暂无已配置的过滤规则")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(store.filterRules.enumerated()), id: \.element.id) { idx, rule in
                                let hitCount = store.repositories.filter { rule.matches($0) }.count
                                HStack(spacing: 12) {
                                    Text(ruleTypeBadge(for: rule))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(width: 100, alignment: .leading)

                                    Text(rule.pattern)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text("\(hitCount) 个")
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 90, alignment: .trailing)

                                    HStack {
                                        Spacer()
                                        Button("移除") {
                                            store.deleteFilterRule(rule.id)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .fixedSize()
                                    }
                                    .frame(width: 80, alignment: .trailing)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)

                                if idx < store.filterRules.count - 1 {
                                    Divider().padding(.horizontal, 16).opacity(0.45)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.hairlineBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // 下半卡片：已被过滤隐藏的仓库
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text("已隐藏仓库 (\(store.excludedRepositories.count))")
                        .frame(width: 180, alignment: .leading)
                    Text("所属远程地址或本地路径")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("操作")
                        .frame(width: 80, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppTheme.subtleSurface)

                Divider()

                if store.excludedRepositories.isEmpty {
                    VStack {
                        Text("当前没有被过滤隐藏的仓库")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(store.excludedRepositories.enumerated()), id: \.element.id) { idx, repo in
                                HStack(spacing: 12) {
                                    HStack(spacing: 7) {
                                        ProjectAvatarView(repo: repo, size: 20)
                                        Text(repo.name)
                                            .font(.system(size: 12, weight: .semibold))
                                            .lineLimit(1)
                                    }
                                    .frame(width: 180, alignment: .leading)

                                    Text(repo.primaryWebURL ?? repo.primaryHostAndOrg ?? repo.displayPath)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    HStack {
                                        Spacer()
                                        Button("恢复") {
                                            store.restoreExcludedRepository(repo)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .fixedSize()
                                    }
                                    .frame(width: 80, alignment: .trailing)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)

                                if idx < store.excludedRepositories.count - 1 {
                                    Divider().padding(.horizontal, 16).opacity(0.45)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.hairlineBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func ruleTypeBadge(for rule: RepoFilterRule) -> String {
        switch rule.field {
        case .remoteHost: return "远程域名"
        case .remoteOrganization: return "远程组织"
        case .exactPath, .repoName: return "指定仓库"
        case .pathContains: return "目录路径"
        case .remoteContains, .smart: return "关键字"
        }
    }

    private func submitCustomPattern() {
        let trimmed = patternInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addFilterRule(field: .smart, pattern: trimmed)
        patternInput = ""
    }
}
