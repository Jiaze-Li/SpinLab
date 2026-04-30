import SwiftUI

struct RecomputePreviewPanel: View {
    let library: LibraryFeatureStore
    @Environment(\.dismiss) private var dismiss
    @State private var showNoChange = false

    private var group0: [RecomputeDiffItem] { library.recomputeDiffItems.filter { $0.status.groupIndex == 0 } }
    private var group1: [RecomputeDiffItem] { library.recomputeDiffItems.filter { $0.status.groupIndex == 1 } }
    private var group2: [RecomputeDiffItem] { library.recomputeDiffItems.filter { $0.status.groupIndex == 2 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if library.isComputingRecomputePreview {
                ProgressView("计算中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                diffList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(minWidth: 680, idealWidth: 900, maxWidth: .infinity, minHeight: 460, idealHeight: 600, maxHeight: .infinity)
        .padding(AppSpacing.xxl)
        .onChange(of: library.isShowingRecomputePreview) { _, showing in
            if !showing { dismiss() }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Recompute Preview")
                .font(AppFontScale.sectionTitle)
            if !library.isComputingRecomputePreview {
                HStack(spacing: AppSpacing.xl) {
                    summaryCell(label: "将处理", value: "\(library.recomputeDiffItems.map(\.sourceFileName).uniqued().count) 个测量")
                    summaryCell(label: "将更新", value: "\(group0.count) 字段")
                    summaryCell(label: "手动覆盖保留", value: "\(group1.count) 字段")
                }
                .font(.callout)
            }
        }
        .padding(.bottom, AppSpacing.lg)
    }

    private func summaryCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(label).foregroundStyle(.secondary).font(.caption)
            Text(value).font(.callout)
        }
    }

    // MARK: Diff list

    private var diffList: some View {
        List {
            if group0.isEmpty && group1.isEmpty {
                Text("所有测量均已是最新规则，无需重算。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, AppSpacing.xl)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            if !group0.isEmpty {
                Section {
                    ForEach(group0) { item in
                        diffTableRow(item)
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    diffSectionHeader("将更新 (\(group0.count) 字段)")
                }
            }
            if !group1.isEmpty {
                Section {
                    ForEach(group1) { item in
                        diffTableRow(item)
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    diffSectionHeader("手动覆盖保留 (\(group1.count) 字段)")
                }
            }
            if !group2.isEmpty {
                Section {
                    if showNoChange {
                        ForEach(group2) { item in
                            diffTableRow(item)
                                .listRowBackground(Color.clear)
                        }
                    }
                } header: {
                    Button {
                        showNoChange.toggle()
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: showNoChange ? "chevron.down" : "chevron.right")
                                .font(.caption)
                            Text("无变化 (\(group2.count) 字段)")
                                .font(.callout.weight(.semibold))
                            Spacer()
                        }
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, AppSpacing.xxs)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func diffSectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
            diffTableHeader
        }
        .padding(.bottom, AppSpacing.xxs)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var diffTableHeader: some View {
        HStack(spacing: 0) {
            Text("Measurement").font(.caption).foregroundStyle(.secondary).frame(width: 160, alignment: .leading)
            Text("Field").font(.caption).foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
            Text("旧值").font(.caption).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            Text("新值").font(.caption).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            Text("来源变化").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            Text("状态").font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, AppSpacing.xs)
    }

    private func diffTableRow(_ item: RecomputeDiffItem) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(item.sampleID.isEmpty ? "—" : item.sampleID)
                    .font(.callout)
                    .lineLimit(1)
                Text(item.sourceFileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: 160, alignment: .leading)

            Text(item.fieldKey)
                .font(.callout)
                .frame(width: 140, alignment: .leading)
                .lineLimit(1)

            Text(item.oldValue ?? "∅")
                .font(.callout)
                .foregroundStyle(item.oldValue == nil ? .secondary : .primary)
                .frame(width: 100, alignment: .leading)
                .lineLimit(1)

            Text(item.newValue ?? "∅")
                .font(.callout)
                .foregroundStyle(item.newValue == nil ? .secondary : .primary)
                .frame(width: 100, alignment: .leading)
                .lineLimit(1)

            sourceChangeLabel(item)
                .frame(maxWidth: .infinity, alignment: .leading)

            statusBadge(item.status)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, AppSpacing.xxs)
    }

    @ViewBuilder
    private func sourceChangeLabel(_ item: RecomputeDiffItem) -> some View {
        let old = shortRef(item.oldSource)
        let new = shortRef(item.newSource)
        if old == new {
            Text(old).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        } else {
            HStack(spacing: AppSpacing.xxs) {
                Text(old).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Image(systemName: "arrow.right").font(.caption2)
                Text(new).font(.caption).foregroundStyle(item.status == .migration ? .orange : .primary).lineLimit(1)
            }
        }
    }

    private func shortRef(_ ref: String?) -> String {
        guard let ref else { return "—" }
        if ref.hasPrefix("rule:") { return String(ref.dropFirst(5)) }
        return ref
    }

    @ViewBuilder
    private func statusBadge(_ status: RecomputeDiffStatus) -> some View {
        let (color, text): (Color, String) = {
            switch status {
            case .willUpdate:     return (.blue, "将更新")
            case .migration:      return (.orange, "迁移")
            case .added:          return (.green, "新增")
            case .ruleRemoved:    return (.red, "规则未命中")
            case .manualOverride: return (.purple, "手动覆盖保留")
            case .noChange:       return (.secondary, "无变化")
            }
        }()
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .padding(.horizontal, AppSpacing.xs)
            .padding(.vertical, AppSpacing.xxs)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if let error = library.recomputeApplyError {
                Text(error).font(.callout).foregroundStyle(.red)
            } else if let message = library.recomputeApplyMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("取消") { dismiss() }
                .buttonStyle(.bordered)
            Button("确认重算并应用") {
                library.applyRecompute()
            }
            .buttonStyle(.borderedProminent)
            .disabled(library.isComputingRecomputePreview || library.isApplyingRecompute || group0.isEmpty)
        }
        .padding(.top, AppSpacing.lg)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
