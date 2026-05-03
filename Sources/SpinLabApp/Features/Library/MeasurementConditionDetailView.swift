import SwiftUI

struct MeasurementConditionDetailView: View {
    let measurement: AppliedMeasurement
    let onLoadSidecar: () -> SpinLabFileSidecar?
    let onSaveOverride: (_ conditionId: String, _ value: String) -> Void
    let onRemoveOverride: (_ conditionId: String) -> Void
    let onDismiss: () -> Void

    @State private var sidecar: SpinLabFileSidecar? = nil
    @State private var editingConditionId: String? = nil
    @State private var editingValue: String = ""
    @State private var removeConfirmId: String? = nil

    private var conditionOrder: [String] {
        var keys = sidecar?.ruleSnapshot.fields.conditions.keys.sorted() ?? []
        let overrideKeys = sidecar?.userOverrides.conditions.keys.sorted() ?? []
        for k in overrideKeys where !keys.contains(k) { keys.append(k) }
        return keys
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let sidecar {
                conditionTable(sidecar: sidecar)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("无 sidecar 数据")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Spacer()
                Button("完成") { onDismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(.top, AppSpacing.lg)
        }
        .padding(AppSpacing.xxl)
        .frame(minWidth: 520, minHeight: 360)
        .onAppear { reloadSidecar() }
        .confirmationDialog(
            "确认恢复规则默认？",
            isPresented: Binding(get: { removeConfirmId != nil }, set: { if !$0 { removeConfirmId = nil } }),
            titleVisibility: .visible
        ) {
            Button("恢复规则默认", role: .destructive) {
                if let id = removeConfirmId {
                    onRemoveOverride(id)
                    removeConfirmId = nil
                    Task { try? await Task.sleep(nanoseconds: 100_000_000); reloadSidecar() }
                }
            }
            Button("取消", role: .cancel) { removeConfirmId = nil }
        } message: {
            if let id = removeConfirmId,
               let sidecar,
               sidecar.ruleSnapshotConditionValue(id) == nil {
                Text("此字段在当前规则集中不存在，恢复将清除该字段。")
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Conditions — \(measurement.workflowDisplayName)")
                .font(AppFontScale.sectionTitle)
            Text(measurement.sourceFileName)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let sidecar {
                let v = sidecar.ruleSnapshot.ruleSetVersion
                let fp = String(sidecar.ruleSnapshot.ruleSetFingerprint.prefix(8))
                Text("规则集 v\(v) (\(fp)…)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.bottom, AppSpacing.lg)
    }

    // MARK: Condition table

    @ViewBuilder
    private func conditionTable(sidecar: SpinLabFileSidecar) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                tableHeader
                Divider()
                if conditionOrder.isEmpty {
                    Text("无 condition 数据")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, AppSpacing.xl)
                } else {
                    ForEach(conditionOrder, id: \.self) { key in
                        conditionRow(key: key, sidecar: sidecar)
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("Condition").font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text("值").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            Text("来源").font(.caption).foregroundStyle(.secondary).frame(width: 200, alignment: .leading)
            Text("").frame(width: 60)
        }
        .padding(.horizontal, AppSpacing.xs)
    }

    @ViewBuilder
    private func conditionRow(key: String, sidecar: SpinLabFileSidecar) -> some View {
        let isManual = sidecar.isConditionManuallyOverridden(key)
        let effectiveValue = sidecar.effectiveConditions[key] ?? ""
        let isEditing = editingConditionId == key

        HStack(spacing: 0) {
            Text(key)
                .font(.callout)
                .frame(width: 110, alignment: .leading)

            if isEditing {
                TextField("值", text: $editingValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .onSubmit { commitEdit(key: key) }
                    .padding(.trailing, AppSpacing.sm)
            } else {
                HStack(spacing: AppSpacing.xs) {
                    if isManual {
                        Circle().fill(Color.blue).frame(width: 6, height: 6)
                    }
                    Text(effectiveValue.isEmpty ? "—" : effectiveValue)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(tooltipText(for: key, sidecar: sidecar))
            }

            if isEditing {
                Button { commitEdit(key: key) } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("确认编辑")
                Button { editingConditionId = nil } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("取消编辑")
            } else {
                sourceLabel(for: key, sidecar: sidecar)
                    .frame(width: 200, alignment: .leading)

                HStack(spacing: AppSpacing.xs) {
                    if isManual {
                        Button {
                            removeConfirmId = key
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.callout)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("恢复规则默认")
                    } else {
                        Button {
                            editingConditionId = key
                            editingValue = effectiveValue
                        } label: {
                            Image(systemName: "pencil")
                                .font(.callout)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("编辑")
                    }
                }
                .frame(width: 60, alignment: .center)
            }
        }
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, AppSpacing.xs)
    }

    @ViewBuilder
    private func sourceLabel(for key: String, sidecar: SpinLabFileSidecar) -> some View {
        let source = sidecar.effectiveConditionSource(key)
        if source == "manual", let override = sidecar.userOverrides.conditions[key] {
            HStack(spacing: AppSpacing.xxs) {
                Image(systemName: "lock.fill").font(.caption2)
                Text("手动编辑（\(Self.dateLabel(override.at))）").font(.caption)
            }
            .foregroundStyle(.blue)
        } else if let ref = source {
            Text(shortRef(ref))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text("—").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private static func dateLabel(_ date: Date) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return fmt.string(from: date)
    }

    // MARK: Tooltip text (§3.5 six types)

    private func tooltipText(for key: String, sidecar: SpinLabFileSidecar) -> String {
        let source = sidecar.effectiveConditionSource(key)
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "yyyy-MM-dd HH:mm"
        timeFmt.timeZone = TimeZone(identifier: "Asia/Singapore")

        if source == "manual" {
            guard let override = sidecar.userOverrides.conditions[key] else { return "" }
            let dateStr = timeFmt.string(from: override.at)
            let ruleValue = sidecar.ruleSnapshotConditionValue(key)
            if let rv = ruleValue, !rv.isEmpty {
                let ruleRef = sidecar.ruleSnapshot.fields.conditions[key]?.source ?? ""
                return "手动编辑（\(dateStr)）\n当前规则候选值: \(rv)（\(ruleRef)）"
            }
            return "手动编辑（\(dateStr)）"
        }

        guard let ref = source else { return "来源未知（旧版本 sidecar）" }

        if ref.hasPrefix("rule:migration.v1") {
            return "来自旧版 sidecar（前规则集时代）；点 Library 顶部「查看预览」可由当前规则集重算"
        }
        if ref.hasPrefix("rule:fallback") || sidecar.ruleSnapshot.ruleSetFingerprint.hasPrefix("builtin:") {
            return "来自内置兜底规则；规则文件未加载成功，运行于 fallback 模式"
        }
        let v = sidecar.ruleSnapshot.ruleSetVersion
        return "来自规则 \(ref)（v\(v) 规则集）"
    }

    private func shortRef(_ ref: String) -> String {
        ref.hasPrefix("rule:") ? String(ref.dropFirst(5)) : ref
    }

    // MARK: Helpers

    private func reloadSidecar() {
        sidecar = onLoadSidecar()
    }

    private func commitEdit(key: String) {
        let value = editingValue
        editingConditionId = nil
        onSaveOverride(key, value)
        Task { try? await Task.sleep(nanoseconds: 100_000_000); reloadSidecar() }
    }
}
