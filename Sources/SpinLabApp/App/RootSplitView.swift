import SwiftUI

struct RootSplitView: View {
    @EnvironmentObject private var appState: SpinLabAppState
    private let sidebarTopInset: CGFloat = 64
    private let standardDetailTopInset: CGFloat = 86
    private let inboxDetailTopInset: CGFloat = 112
    private let libraryDetailTopInset: CGFloat = 28

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: sidebarTopInset)

                List(AppArea.allCases, selection: $appState.selectedArea) { area in
                    Label(area.rawValue, systemImage: iconName(for: area))
                        .tag(area)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } detail: {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaPadding(.top, currentDetailTopInset)
                .frame(maxHeight: .infinity, alignment: .top)
                .overlay(alignment: .topTrailing) {
                    Text(AppVersion.current)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                        .padding(.trailing, 16)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var contentView: some View {
        switch appState.selectedArea {
        case .inbox:
            InboxView()
        case .workbench:
            WorkbenchView()
        case .library:
            LibraryView()
        }
    }

    private var currentDetailTopInset: CGFloat {
        switch appState.selectedArea {
        case .inbox:
            return inboxDetailTopInset
        case .workbench:
            return standardDetailTopInset
        case .library:
            return libraryDetailTopInset
        }
    }

    private func iconName(for area: AppArea) -> String {
        switch area {
        case .inbox:
            return "tray.full"
        case .workbench:
            return "waveform.path.ecg.rectangle"
        case .library:
            return "books.vertical"
        }
    }
}
