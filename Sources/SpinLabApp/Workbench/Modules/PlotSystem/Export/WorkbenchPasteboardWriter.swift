import AppKit
import Foundation

/// Writes already-rendered graphic artifacts straight to the system pasteboard.
/// No rendering happens here — callers pass the exact bytes shown on screen.
enum WorkbenchPasteboardWriter {

    static func copyPNG(_ data: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: .png)
    }

    static func copyPDF(_ data: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: .pdf)
    }
}
