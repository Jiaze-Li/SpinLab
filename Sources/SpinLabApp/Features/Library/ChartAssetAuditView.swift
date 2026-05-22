import SwiftUI

struct ChartAssetAuditView: View {
    let report: ChartAssetAuditReport?
    let isRunning: Bool
    let message: String?
    let onRefresh: () -> Void
    let onDeleteSelected: ([String]) -> Void
    let onDeleteAll: () -> Void
    let onCleanMissingRefs: () -> Void
    let onDismiss: () -> Void

    @State private var selectedOrphanIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if isRunning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning library root…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else if let report {
                summaryRow(report)
                Divider()
                fileListSection(report)
            }

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            actionBar
        }
        .padding(20)
        .frame(minWidth: 580, minHeight: 480)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Chart Asset Audit")
                .font(.title2.bold())
            Spacer()
        }
    }

    // MARK: - Summary counts

    @ViewBuilder
    private func summaryRow(_ report: ChartAssetAuditReport) -> some View {
        HStack(spacing: 0) {
            countBadge("Active Charts", count: report.activeChartCount, accent: .accentColor)
            countBadge("Orphan Images", count: report.orphanImages.count,
                       accent: report.orphanImages.isEmpty ? .secondary : .orange)
            countBadge("Orphan Manifests", count: report.orphanManifests.count,
                       accent: report.orphanManifests.isEmpty ? .secondary : .orange)
            countBadge("Missing PNGs", count: report.missingActiveImages.count,
                       accent: report.missingActiveImages.isEmpty ? .secondary : .red)
            countBadge("Missing Manifests", count: report.missingActiveManifests.count,
                       accent: report.missingActiveManifests.isEmpty ? .secondary : .red)
        }
        .padding(.vertical, 4)
    }

    private func countBadge(_ label: String, count: Int, accent: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3.bold())
                .foregroundStyle(accent)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - File lists

    @ViewBuilder
    private func fileListSection(_ report: ChartAssetAuditReport) -> some View {
        let allOrphans = report.orphanImages + report.orphanManifests

        if allOrphans.isEmpty && report.missingActiveImages.isEmpty && report.missingActiveManifests.isEmpty {
            Text("No orphan or missing files found.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if !allOrphans.isEmpty {
                    groupHeader("Orphan Files", count: allOrphans.count,
                                note: "on disk but not referenced by any active index — click to select for deletion")
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(allOrphans) { file in
                                orphanRow(file)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(maxHeight: 200)
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                let allMissing = report.missingActiveImages + report.missingActiveManifests
                if !allMissing.isEmpty {
                    groupHeader("Missing Active Files", count: allMissing.count,
                                note: "indexed but absent on disk — use Clean Missing References to remove stale entries")
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(allMissing, id: \.relativePath) { missing in
                                missingRow(missing)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(maxHeight: 120)
                    .background(Color.red.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func groupHeader(_ title: String, count: Int, note: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text("\(count)")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.18)))
                    .foregroundStyle(.secondary)
            }
            Text(note)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Orphan row (selectable)

    private func orphanRow(_ file: ChartAssetAuditReport.OrphanFile) -> some View {
        let isSelected = selectedOrphanIDs.contains(file.id)
        return HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.6))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.filename)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                if let sk = file.sampleKey {
                    Text(sk)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.09) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedOrphanIDs.remove(file.id)
            } else {
                selectedOrphanIDs.insert(file.id)
            }
        }
    }

    // MARK: - Missing row (display only)

    private func missingRow(_ missing: ChartAssetAuditReport.MissingActiveFile) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(URL(fileURLWithPath: missing.relativePath).lastPathComponent)
                .font(.caption.monospaced())
                .foregroundStyle(.red)
            Text(missing.sampleKey)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button("Refresh") { onRefresh() }
                .disabled(isRunning)

            let allOrphans = (report?.orphanImages ?? []) + (report?.orphanManifests ?? [])
            if !allOrphans.isEmpty {
                Button("Delete Selected Orphans (\(selectedOrphanIDs.count))") {
                    onDeleteSelected(Array(selectedOrphanIDs))
                    selectedOrphanIDs = []
                }
                .disabled(selectedOrphanIDs.isEmpty || isRunning)

                Button("Delete All Orphans") {
                    onDeleteAll()
                    selectedOrphanIDs = []
                }
                .disabled(isRunning)
            }

            let hasMissing = !(report?.missingActiveImages.isEmpty ?? true)
                || !(report?.missingActiveManifests.isEmpty ?? true)
            if hasMissing {
                Button("Clean Missing References") {
                    onCleanMissingRefs()
                }
                .disabled(isRunning)
            }

            Spacer()
            Button("Close") { onDismiss() }
        }
    }
}
