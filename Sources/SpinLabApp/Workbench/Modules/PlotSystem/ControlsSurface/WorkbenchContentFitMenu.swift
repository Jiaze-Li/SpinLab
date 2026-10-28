import SwiftUI

extension View {
    /// Content-fit menu Picker (`04_UI_RULES.md` VC-8): the Picker takes its own intrinsic width,
    /// which the native control derives from its widest option plus the system arrows and insets.
    /// Nothing is measured elsewhere and no width is imposed, so the control cannot be narrower
    /// than what it needs in whatever environment (font, control size, accessibility settings) it
    /// really renders in, and it does not change width with the selection. A row hosting it must
    /// not squeeze it (`WorkbenchControlRow(atomic: true)`): when it does not fit, the row wraps.
    func workbenchContentFitMenu() -> some View {
        fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: WorkbenchInputWidth.menuMinimum, alignment: .leading)
    }
}
