import SwiftUI

/// Persistent notice shown when another SpinLab process holds this Library's write lease.
struct LibraryReadOnlyBanner: View {
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "lock.fill")
            Text(LibraryWriteLease.readOnlyMessage)
                .font(.callout)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.18))
        .accessibilityIdentifier("library-read-only-banner")
    }
}
