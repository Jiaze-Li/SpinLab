import SwiftUI

/// Phase 5B — Obsidian → Registry import preview sheet. Displays exactly
/// what `RegistryGrowthImportPlanner` decided (via `LibraryFeatureStore`'s
/// transient preview state) and lets the user select a subset of the
/// `.ready` items to apply. Never reparses Obsidian, never re-derives an
/// item's action/classification, never writes anything itself — every
/// mutation goes through `LibraryFeatureStore.applyRegistryGrowthImport()`.
struct RegistryGrowthImportSheet: View {
    let library: LibraryFeatureStore
    let vaultPath: String?
    let registryPath: String?
    let onRefresh: () -> Void
    let onToggleSelection: (String) -> Void
    let onSelectAll: () -> Void
    let onSelectNone: () -> Void
    let onSelectFilter: (RegistryGrowthImportPresentation.Filter) -> Void
    let onSelectItem: (String?) -> Void
    let onApply: () -> Void
    let onDismiss: () -> Void

    @State private var isShowingApplyConfirmation = false

    private var plan: RegistryGrowthImportPlan? { library.registryGrowthImportPlan }

    private var itemsForFilter: [RegistryGrowthImportItem] {
        guard let plan else { return [] }
        let filter = library.registryGrowthImportSelectedFilter
        return plan.items
            .filter { RegistryGrowthImportPresentation.filter(for: $0) == filter }
            .sorted { $0.batchId < $1.batchId }
    }

    private var selectedItem: RegistryGrowthImportItem? {
        guard let id = library.registryGrowthImportSelectedItemId, let plan else { return nil }
        return plan.items.first { $0.id == id }
    }

    private var selectedApplyCount: Int {
        guard let plan else { return 0 }
        return plan.items.filter { $0.isExecutable && library.registryGrowthImportSelectedReadyBatchIds.contains($0.batchId) }.count
    }

    private var vaultDisplayName: String {
        guard let vaultPath, !vaultPath.isEmpty else { return "Not set" }
        return URL(fileURLWithPath: vaultPath).lastPathComponent
    }

    private var registryDisplayName: String {
        guard let registryPath, !registryPath.isEmpty else { return "Not loaded" }
        return URL(fileURLWithPath: registryPath).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if library.isRegistryGrowthImportPreviewLoading {
                loadingView
            } else if let plan {
                HStack(spacing: 0) {
                    listColumn(plan: plan)
                        .frame(width: 340)
                    Divider()
                    detailColumn
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }

            Divider()
            footer
        }
        .frame(minWidth: 800, minHeight: 550)
        .confirmationDialog(
            "Write \(selectedApplyCount) new growth record(s) to Registry?",
            isPresented: $isShowingApplyConfirmation,
            titleVisibility: .visible
        ) {
            Button("Apply", role: .destructive) { onApply() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(selectedApplyCount) record(s) will be added/filled. Existing Registry records will not be overwritten. A backup will be created before replacement.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text("Obsidian → Registry Import")
                    .font(AppFontScale.groupHeader)
                Spacer()
                Button("Close") { onDismiss() }
                    .disabled(library.isRegistryGrowthImportApplying)
            }

            HStack(spacing: AppSpacing.lg) {
                pathLabel(title: "Vault", name: vaultDisplayName, fullPath: vaultPath)
                pathLabel(title: "Registry", name: registryDisplayName, fullPath: registryPath)
                Spacer()
            }

            if library.registryGrowthImportNeedsRefresh {
                Text("Registry changed since this preview was generated. Refresh Preview before applying.")
                    .font(AppFontScale.minimumReadable)
                    .foregroundStyle(.orange)
            }

            if let error = library.registryGrowthImportError {
                Text(error)
                    .font(AppFontScale.minimumReadable)
                    .foregroundStyle(.red)
            }

            if let message = library.registryGrowthImportMessage {
                Text(message)
                    .font(AppFontScale.minimumReadable)
                    .foregroundStyle(.primary)
            }
        }
        .padding(AppSpacing.lg)
    }

    private func pathLabel(title: String, name: String, fullPath: String?) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(AppFontScale.minimumReadable)
                .foregroundStyle(.primary)
            Text(name)
                .font(AppFontScale.minimumReadable.weight(.medium))
                .foregroundStyle(.primary)
        }
        .help(fullPath ?? name)
    }

    // MARK: - Loading / empty

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("Building preview…")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            Text("No preview available.")
                .foregroundStyle(.primary)
            Button("Refresh Preview") { onRefresh() }
                .disabled(vaultPath == nil || registryPath == nil)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List column

    private func filterTitle(_ filter: RegistryGrowthImportPresentation.Filter, plan: RegistryGrowthImportPlan) -> String {
        let count = plan.items.filter { RegistryGrowthImportPresentation.filter(for: $0) == filter }.count
        return "\(filter.title) \(count)"
    }

    private func listColumn(plan: RegistryGrowthImportPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Filter", selection: Binding(
                get: { library.registryGrowthImportSelectedFilter },
                set: { onSelectFilter($0) }
            )) {
                ForEach(RegistryGrowthImportPresentation.Filter.allCases) { filter in
                    Text(filterTitle(filter, plan: plan)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(AppSpacing.md)

            switch library.registryGrowthImportSelectedFilter {
            case .ready:
                HStack {
                    Button("Select All") { onSelectAll() }
                    Button("Select None") { onSelectNone() }
                    Spacer()
                }
                .buttonStyle(.borderless)
                .font(AppFontScale.minimumReadable)
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.sm)
            case .existing:
                Text("Existing records are read-only and will be skipped.")
                    .font(AppFontScale.minimumReadable)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.bottom, AppSpacing.sm)
            case .blocked:
                Text("Blocked records cannot be selected for import.")
                    .font(AppFontScale.minimumReadable)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.bottom, AppSpacing.sm)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(itemsForFilter) { item in
                        RegistryGrowthImportRow(
                            item: item,
                            filter: library.registryGrowthImportSelectedFilter,
                            isSelected: library.registryGrowthImportSelectedItemId == item.id,
                            isChecked: library.registryGrowthImportSelectedReadyBatchIds.contains(item.batchId),
                            onSelect: { onSelectItem(item.id) },
                            onToggleCheck: { onToggleSelection(item.batchId) }
                        )
                    }
                }
                .padding(AppSpacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Detail column

    private var detailColumn: some View {
        ScrollView {
            if let item = selectedItem {
                RegistryGrowthImportDetailView(item: item)
                    .padding(AppSpacing.lg)
                    .frame(maxWidth: 700, alignment: .leading)
            } else {
                VStack {
                    Spacer(minLength: AppSpacing.xxl)
                    Text("Select an item to see details.")
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.lg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Refresh Preview") { onRefresh() }
                .disabled(library.isRegistryGrowthImportPreviewLoading || library.isRegistryGrowthImportApplying)

            Spacer()

            Button("Cancel") { onDismiss() }
                .disabled(library.isRegistryGrowthImportApplying)

            Button("Apply \(selectedApplyCount)") {
                isShowingApplyConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedApplyCount == 0 || library.isRegistryGrowthImportApplying || library.isRegistryGrowthImportPreviewLoading || library.registryGrowthImportNeedsRefresh)

            if library.isRegistryGrowthImportApplying {
                ProgressView().controlSize(.small)
            }
        }
        .padding(AppSpacing.lg)
    }
}

// MARK: - Row

private struct RegistryGrowthImportRow: View {
    let item: RegistryGrowthImportItem
    let filter: RegistryGrowthImportPresentation.Filter
    let isSelected: Bool
    let isChecked: Bool
    let onSelect: () -> Void
    let onToggleCheck: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                leadingIndicator
                VStack(alignment: .leading, spacing: 2) {
                    switch filter {
                    case .ready:
                        readyContent
                    case .existing:
                        existingContent
                    case .blocked:
                        blockedContent
                    }
                }
                Spacer()
            }
            .padding(AppSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        switch filter {
        case .ready:
            Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
                .onTapGesture { onToggleCheck() }
        case .existing:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .blocked:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var readyContent: some View {
        Group {
            HStack(spacing: 6) {
                Text(item.batchId)
                    .font(AppFontScale.minimumReadable.weight(.medium))
                    .foregroundStyle(.primary)
                badge(RegistryGrowthImportPresentation.actionBadgeTitle(for: item), color: .green)
                if !item.warnings.isEmpty {
                    warningBadge
                }
            }
            let primary = RegistryGrowthImportPresentation.compactPrimaryLine(for: item)
            if !primary.isEmpty {
                Text(primary)
                    .font(AppFontScale.minimumReadable)
                    .foregroundStyle(.primary)
            }
            let secondary = RegistryGrowthImportPresentation.compactSecondaryLine(for: item)
            if !secondary.isEmpty {
                Text(secondary)
                    .font(AppFontScale.minimumReadable)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(secondary)
            }
        }
    }

    private var existingContent: some View {
        Group {
            HStack(spacing: 6) {
                Text(item.batchId)
                    .font(AppFontScale.minimumReadable.weight(.medium))
                    .foregroundStyle(.primary)
                if !item.warnings.isEmpty {
                    warningBadge
                }
            }
            Text("Already in Registry")
                .font(AppFontScale.minimumReadable)
                .foregroundStyle(.primary)
            let summary = RegistryGrowthImportPresentation.existingSummary(for: item)
            if !summary.isEmpty {
                Text(summary)
                    .font(AppFontScale.minimumReadable)
                    .foregroundStyle(.primary)
            }
        }
    }

    private var blockedContent: some View {
        Group {
            Text(item.batchId)
                .font(AppFontScale.minimumReadable.weight(.medium))
                .foregroundStyle(.primary)
            Text(RegistryGrowthImportPresentation.blockingReasonsText(for: item))
                .font(AppFontScale.minimumReadable)
                .foregroundStyle(.red)
        }
    }

    private var warningBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppFontScale.minimumReadable)
                .foregroundStyle(.orange)
            Text("\(item.warnings.count) difference(s)")
                .font(AppFontScale.minimumReadable)
                .foregroundStyle(.orange)
        }
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(AppFontScale.minimumReadable.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.15))
            )
    }
}

// MARK: - Detail

private struct RegistryGrowthImportDetailView: View {
    let item: RegistryGrowthImportItem

    private var detailBadgeColor: Color? {
        switch item.action {
        case .appendNewRow, .fillReservedRow: return .green
        case .skipExisting: return nil
        case .blocked: return .red
        }
    }

    private var detailActionText: String {
        switch item.action {
        case .appendNewRow, .fillReservedRow:
            return "\(RegistryGrowthImportPresentation.actionBadgeTitle(for: item)) → \(RegistryGrowthImportPresentation.targetSheetText(for: item))"
        case .skipExisting:
            return RegistryGrowthImportPresentation.actionBadgeTitle(for: item)
        case .blocked:
            return RegistryGrowthImportPresentation.actionBadgeTitle(for: item)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.batchId)
                    .font(AppFontScale.groupHeader)
                Spacer()
                Group {
                    if let detailBadgeColor {
                        Text(detailActionText)
                            .font(AppFontScale.minimumReadable.weight(.semibold))
                            .foregroundStyle(detailBadgeColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(detailBadgeColor.opacity(0.15))
                            )
                    } else {
                        Text(detailActionText)
                            .font(AppFontScale.minimumReadable.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }

            if case .skipExisting = item.action {
                Text(RegistryGrowthImportPresentation.existingSummary(for: item))
                    .font(AppFontScale.minimumReadable)
                    .foregroundStyle(.primary)
            }

            if !item.columnValues.isEmpty {
                GroupBox("Registry Preview") {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        ForEach(RegistryGrowthImportPresentation.orderedRegistryPreviewRows(for: item), id: \.header) { row in
                            RegistryPreviewRow(label: row.header, value: row.value)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !item.expectedSampleKeys.isEmpty {
                GroupBox(item.expectedSampleKeys.count == 1 ? "Expected Sample" : "Expected Samples") {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        ForEach(item.expectedSampleKeys, id: \.self) { key in
                            Text(RegistryGrowthImportPresentation.humanSampleLabel(for: key))
                                .font(AppFontScale.minimumReadable)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !item.blankColumns.isEmpty {
                GroupBox("Blank Columns") {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        ForEach(item.blankColumns, id: \.columnHeader) { blank in
                            Text("\(blank.columnHeader) — \(blank.reason)")
                                .font(AppFontScale.minimumReadable)
                                .foregroundStyle(.primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !item.blockingReasons.isEmpty {
                GroupBox("Blocking Reasons") {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        ForEach(Array(item.blockingReasons.enumerated()), id: \.offset) { _, reason in
                            Text(RegistryGrowthImportPresentation.blockingReasonText(reason))
                                .font(AppFontScale.minimumReadable)
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !item.warnings.isEmpty {
                GroupBox("Warnings") {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        ForEach(item.warnings, id: \.self) { warning in
                            Text(warning)
                                .font(AppFontScale.minimumReadable)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            let distinctSourcePaths = Array(Set(item.sourceNotePaths))
            if distinctSourcePaths.count == 1 {
                GroupBox("Source") {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(distinctSourcePaths[0])
                            .font(AppFontScale.minimumReadable)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if distinctSourcePaths.count > 1 {
                GroupBox("Sources") {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        ForEach(RegistryGrowthImportPresentation.sourceFieldHeaders(for: item), id: \.notePath) { group in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.notePath)
                                    .font(AppFontScale.minimumReadable.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                if !group.fieldHeaders.isEmpty {
                                    Text(group.fieldHeaders.joined(separator: " · "))
                                        .font(AppFontScale.minimumReadable)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Registry Preview row

private struct RegistryPreviewRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.md) {
            Text(label)
                .font(AppFontScale.minimumReadable)
                .foregroundStyle(.primary)
                .frame(minWidth: 130, maxWidth: 160, alignment: .leading)
            Text(value)
                .font(AppFontScale.minimumReadable.weight(.medium))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
