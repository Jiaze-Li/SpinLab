import Foundation

/// Vocabulary that only the shared Controls Surface layout containers may use to measure
/// width or place whole groups (CS-25). The Controls Contract AST scan rejects these
/// identifiers in files that declare Specific content or leaf inputs.
///
/// Internal arrangement with ordinary stacks inside a leaf input is allowed; what is not
/// allowed is measuring/reacting to the container width or defining a placement `Layout`.
enum WorkbenchLayoutPolicyIdentifiers {
    static let widthMeasuring: [String] = [
        "GeometryReader",
        "ViewThatFits",
        "onGeometryChange",
        "containerRelativeFrame",
        "Layout",
        "AnyLayout",
        "WeightedRowLayout",
        "FlowLayout",
        "WorkbenchControlFlow",
        "WorkbenchControlRow",
        "WorkbenchControlGroup",
    ]
}
