import SwiftUI

struct WorkflowWorkspaceResultsList<Store: WorkbenchWorkspaceProviding>: View {
    let workflowID: WorkbenchWorkflowID
    let store: Store
    let workbench: WorkbenchFeatureStore

    var body: some View {
        let results = workbench.searchResultsList(for: workflowID)
        let message = workbench.searchMessage(for: workflowID)

        return Group {
            if results.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    if let msg = message, !msg.isEmpty {
                        Text("\(msg)  Numeric tolerance: ±\(Int(NumericUnitMap.relativeTolerance * 100))%")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.top, AppSpacing.md)
                    }
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("Run a search to find measurements.")
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        if let msg = message, !msg.isEmpty {
                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                Text(msg)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Text("Numeric tolerance: ±\(Int(NumericUnitMap.relativeTolerance * 100))% (min ±\(NumericUnitMap.absoluteToleranceFloor, specifier: "%.0f"))")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        ForEach(results) { hit in
                            let isSelected = workbench.selectedSearchResultIDs(for: workflowID).contains(hit.id)
                            WorkflowHitRow(
                                hit: hit,
                                isSelected: isSelected,
                                numericDisplay: store.cachedSampleNumericDisplay[hit.sampleKey] ?? [:]
                            ) {
                                workbench.toggleSearchHitSelection(hit.id, for: workflowID)
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.md)
                }
            }
        }
    }
}
