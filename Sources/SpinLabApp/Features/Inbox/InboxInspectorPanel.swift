import SwiftUI

struct InboxInspectorPanel: View {
    let pending: SpinLabDomain.PendingImport
    @Environment(SpinLabAppState.self) private var appState
    private var routingSnapshot: SpinLabDomain.PendingRoutingSnapshot {
        appState.pendingRoutingSnapshot(for: pending)
    }
    private var routePlan: SpinLabDomain.RoutePlan { routingSnapshot.routePlan }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Inspector")
                .font(AppFontScale.sectionTitle)

            GroupBox("File Summary") {
                VStack(alignment: .leading, spacing: 10) {
                    MetadataValueRow(label: "Workflow", value: pending.workflow.rawValue)
                    MetadataValueRow(label: "File", value: pending.fileName)
                    MetadataValueRow(label: "File Path", value: pending.sourceFilePath, monospaced: true)
                    MetadataValueRow(label: "Status", value: pending.status.rawValue)
                    MetadataValueRow(label: "Route Status", value: routingSnapshot.verdict.displayTitle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Routing Summary") {
                VStack(alignment: .leading, spacing: 8) {
                    MetadataValueRow(label: "Scopes", value: "\(routingSnapshot.scopes.count)")
                    MetadataValueRow(label: "Unresolved", value: "\(routingSnapshot.unresolvedScopes.count)")
                    if !routingSnapshot.unresolvedScopes.isEmpty {
                        Text(routingSnapshot.unresolvedScopes.joined(separator: ", "))
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !routingSnapshot.scopes.isEmpty {
                        ForEach(routingSnapshot.scopes) { scope in
                            let sample = scope.sampleId ?? "?"
                            let drawer = scope.matchedDrawer ?? "?"
                            Text("\(scope.scope): \(sample) -> \(drawer)")
                                .font(.callout)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            let warnings = appState.pendingDisplayWarningItems(for: pending)
            if !warnings.isEmpty {
                GroupBox("Warnings") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(warnings, id: \.self) { warning in
                            Text(displayText(for: warning))
                                .font(.callout)
                                .foregroundStyle(.orange)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func displayText(for warning: PendingDisplayWarning) -> String {
        guard let scopeSummary = warning.scopeSummary else {
            return warning.message
        }
        return "\(warning.message) [Scope: \(scopeSummary)]"
    }
}
