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
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("Obsidian → Registry Import")
                    .font(AppFontScale.groupHeader)
                Spacer()
                Button("Close") { onDismiss() }
            }

            MetadataValueRow(label: "Vault", value: vaultPath ?? "Not set", monospaced: true)
            MetadataValueRow(label: "Registry", value: registryPath ?? "Not loaded", monospaced: true)

            if let plan {
                HStack(spacing: AppSpacing.lg) {
                    countBadge(title: "Ready", count: plan.items.filter { RegistryGrowthImportPresentation.filter(for: $0) == .ready }.count, color: .green)
                    countBadge(title: "Existing", count: plan.items.filter { RegistryGrowthImportPresentation.filter(for: $0) == .existing }.count, color: .secondary)
                    countBadge(title: "Blocked", count: plan.items.filter { RegistryGrowthImportPresentation.filter(for: $0) == .blocked }.count, color: .red)
                    Spacer()
                }
            }

            if library.registryGrowthImportNeedsRefresh {
                Text("Registry changed since this preview was generated. Refresh Preview before applying.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let error = library.registryGrowthImportError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let message = library.registryGrowthImportMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppSpacing.lg)
    }

    private func countBadge(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
                .foregroundStyle(.secondary)
            Button("Refresh Preview") { onRefresh() }
                .disabled(vaultPath == nil || registryPath == nil)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List column

    private func listColumn(plan: RegistryGrowthImportPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Filter", selection: Binding(
                get: { library.registryGrowthImportSelectedFilter },
                set: { onSelectFilter($0) }
            )) {
                ForEach(RegistryGrowthImportPresentation.Filter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(AppSpacing.md)

            if library.registryGrowthImportSelectedFilter == .ready {
                HStack {
                    Button("Select All") { onSelectAll() }
                    Button("Select None") { onSelectNone() }
                    Spacer()
                }
                .font(.caption)
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.sm)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(itemsForFilter) { item in
                        RegistryGrowthImportRow(
                            item: item,
                            isSelected: library.registryGrowthImportSelectedItemId == item.id,
                            isChecked: library.registryGrowthImportSelectedReadyBatchIds.contains(item.batchId),
                            showsCheckbox: RegistryGrowthImportPresentation.filter(for: item) == .ready,
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
            } else {
                VStack {
                    Spacer(minLength: AppSpacing.xxl)
                    Text("Select an item to see details.")
                        .foregroundStyle(.secondary)
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
            .disabled(selectedApplyCount == 0 || library.isRegistryGrowthImportApplying || library.registryGrowthImportNeedsRefresh)

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
    let isSelected: Bool
    let isChecked: Bool
    let showsCheckbox: Bool
    let onSelect: () -> Void
    let onToggleCheck: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                if showsCheckbox {
                    Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                        .onTapGesture { onToggleCheck() }
                } else {
                    Image(systemName: RegistryGrowthImportPresentation.actionIcon(for: item))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.batchId)
                            .font(.subheadline.weight(.medium))
                        if !item.warnings.isEmpty {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text("\(item.warnings.count) difference(s)")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    Text("\(RegistryGrowthImportPresentation.actionTitle(for: item)) → \(RegistryGrowthImportPresentation.targetSheetText(for: item))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let subtitle = RegistryGrowthImportPresentation.summarySubtitle(for: item)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if case .blocked = item.action {
                        Text(RegistryGrowthImportPresentation.blockingReasonsText(for: item))
                            .font(.caption2)
                            .foregroundStyle(.red)
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
}

// MARK: - Detail

private struct RegistryGrowthImportDetailView: View {
    let item: RegistryGrowthImportItem

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text(item.batchId)
                .font(AppFontScale.groupHeader)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Action").font(.caption).foregroundStyle(.secondary)
                Text(RegistryGrowthImportPresentation.actionTitle(for: item))
                Text("Target: \(RegistryGrowthImportPresentation.targetSheetText(for: item))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .skipExisting = item.action {
                    Text(RegistryGrowthImportPresentation.existingSummary(for: item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !item.columnValues.isEmpty {
                GroupBox("Registry Preview") {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        ForEach(item.columnValues.sorted(by: { $0.key < $1.key }), id: \.key) { header, value in
                            MetadataValueRow(label: header, value: value)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !item.expectedSampleKeys.isEmpty {
                GroupBox("Expected Samples") {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        ForEach(item.expectedSampleKeys, id: \.self) { key in
                            Text(key).font(.caption).monospaced()
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
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                                .font(.caption)
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
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            GroupBox("Source") {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    ForEach(item.sourceNotePaths, id: \.self) { path in
                        Text(path).font(.caption).monospaced()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !item.provenance.isEmpty {
                DisclosureGroup("Source details") {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        ForEach(Array(item.provenance.enumerated()), id: \.offset) { _, entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.columnHeader).font(.caption.weight(.medium))
                                Text("\(entry.notePath)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("raw key: \(entry.rawKey)  raw value: \(entry.rawValue)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, AppSpacing.xs)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
