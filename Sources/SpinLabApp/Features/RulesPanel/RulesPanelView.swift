import AppKit
import SwiftUI

struct RulesPanelView: View {
    @Environment(SpinLabAppState.self) private var appState

    @State private var isPresentingCloseAlert = false
    @State private var pendingCloseWindow: NSWindow?

    private var store: RulesManagementStore { appState.rulesPanel }

    var body: some View {
        NavigationSplitView {
            List(selection: sectionSelection) {
                ForEach(RulesPanelSection.allCases) { section in
                    sidebarRow(for: section)
                        .tag(section)
                }
            }
            .navigationTitle("Rules")
        } detail: {
            detailView(for: store.currentSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(AppSpacing.xl)
        }
        .background(
            RulesWindowCloseInterceptor(
                hasUnsavedChanges: { !store.dirtySections.isEmpty },
                onAttemptClose: { window in
                    pendingCloseWindow = window
                    isPresentingCloseAlert = true
                }
            )
        )
        .alert("You have unsaved rules changes.", isPresented: $isPresentingCloseAlert) {
            Button("Discard Changes", role: .destructive) {
                discardAllDirtySections()
                closePendingWindow()
            }
            Button("Cancel", role: .cancel) {
                pendingCloseWindow = nil
            }
            Button("Save All") {
                saveAllDirtySectionsAndCloseIfSuccessful()
            }
        } message: {
            Text("Save all sections before closing this window?")
        }
        .onAppear {
            store.present()
        }
    }

    private var sectionSelection: Binding<RulesPanelSection?> {
        Binding(
            get: { store.currentSection },
            set: { newValue in
                guard let newValue else { return }
                store.selectSection(newValue)
            }
        )
    }

    @ViewBuilder
    private func sidebarRow(for section: RulesPanelSection) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Text(section.displayName)
            if store.dirtySections.contains(section) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 7, height: 7)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func detailView(for section: RulesPanelSection) -> some View {
        switch section {
        case .importFilters:
            ImportFiltersSection()
        case .filenameTokenization:
            FilenameTokenizationSection()
        case .sampleIdentification:
            SampleIdentificationSection()
        case .workflow:
            WorkflowSection()
        case .measuringCondition:
            MeasuringConditionSection()
        }
    }

    private func discardAllDirtySections() {
        let previous = store.currentSection
        for section in RulesPanelSection.allCases where store.dirtySections.contains(section) {
            store.selectSection(section)
            store.discardCurrent()
        }
        store.selectSection(previous)
    }

    private func saveAllDirtySectionsAndCloseIfSuccessful() {
        let previous = store.currentSection
        // Fixed order per allCases (not Set order) so cross-section deps are deterministic
        for section in RulesPanelSection.allCases where store.dirtySections.contains(section) {
            store.selectSection(section)
            let outcome = store.saveCurrent()
            switch outcome {
            case .saved, .savedWithMirrorWarning:
                continue
            case .validationFailed, .externalConflict, .ioError:
                pendingCloseWindow = nil
                return
            }
        }
        store.selectSection(previous)
        closePendingWindow()
    }

    private func closePendingWindow() {
        pendingCloseWindow?.close()
        pendingCloseWindow = nil
    }
}

private struct RulesWindowCloseInterceptor: NSViewRepresentable {
    let hasUnsavedChanges: () -> Bool
    let onAttemptClose: (NSWindow) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(hasUnsavedChanges: hasUnsavedChanges, onAttemptClose: onAttemptClose)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in
            if let window = view.window {
                context.coordinator.attachIfNeeded(to: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            if let window = nsView.window {
                context.coordinator.attachIfNeeded(to: window)
            }
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        private let hasUnsavedChanges: () -> Bool
        private let onAttemptClose: (NSWindow) -> Void
        private weak var installedWindow: NSWindow?

        init(hasUnsavedChanges: @escaping () -> Bool, onAttemptClose: @escaping (NSWindow) -> Void) {
            self.hasUnsavedChanges = hasUnsavedChanges
            self.onAttemptClose = onAttemptClose
        }

        func attachIfNeeded(to window: NSWindow) {
            guard installedWindow !== window else { return }
            window.delegate = self
            installedWindow = window
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if hasUnsavedChanges() {
                onAttemptClose(sender)
                return false
            }
            return true
        }
    }
}
