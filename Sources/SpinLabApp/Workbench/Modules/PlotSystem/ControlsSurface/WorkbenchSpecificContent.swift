import SwiftUI

/// A workflow's own *leaf* input view (CS-18). It may arrange its own internals and keep
/// local edit state, but outer placement, wrapping and breakpoints belong to the Surface.
protocol WorkbenchLeafInput: View {}

/// One input inside a Specific row. Typed constructors cover the common controls; a
/// workflow-owned leaf view enters through `.control(_:)`.
struct WorkbenchSpecificInput {
    let id: String
    let fills: Bool
    private let make: () -> AnyView

    /// Private on purpose (CS-18): inputs can only be created by the typed constructors below,
    /// so an arbitrary `AnyView` cannot enter Specific content.
    private init(id: String, fills: Bool = false, make: @escaping () -> AnyView) {
        self.id = id
        self.fills = fills
        self.make = make
    }

    @MainActor func view() -> AnyView { make() }

    static func toggle(_ id: String, title: String, isOn: Binding<Bool>) -> WorkbenchSpecificInput {
        WorkbenchSpecificInput(id: id) {
            AnyView(WorkbenchCheckbox(title: title, isOn: isOn))
        }
    }

    static func menu<Value: Hashable>(
        _ id: String, selection: Binding<Value>, options: [(title: String, value: Value)]
    ) -> WorkbenchSpecificInput {
        WorkbenchSpecificInput(id: id) {
            AnyView(
                Picker("", selection: selection) {
                    ForEach(options.indices, id: \.self) { Text(options[$0].title).tag(options[$0].value) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: WorkbenchInputWidth.compact, idealWidth: WorkbenchInputWidth.wide, maxWidth: WorkbenchInputWidth.wide, alignment: .leading)
                .workbenchControl(.menu)
            )
        }
    }

    static func text(_ id: String, prompt: String = "", text: Binding<String>, fills: Bool = true) -> WorkbenchSpecificInput {
        WorkbenchSpecificInput(id: id, fills: fills) {
            AnyView(
                TextField(prompt, text: text)
                    .textFieldStyle(.roundedBorder)
                    .font(WorkbenchUIStyle.controlValueFont)
                    .frame(minWidth: WorkbenchInputWidth.compact, idealWidth: WorkbenchInputWidth.standard, maxWidth: fills ? .infinity : WorkbenchInputWidth.wide)
                    .workbenchControl(.textField)
            )
        }
    }

    static func number(_ id: String, prompt: String = "", value: Binding<Double>, onCommit: (() -> Void)? = nil) -> WorkbenchSpecificInput {
        WorkbenchSpecificInput(id: id) {
            AnyView(
                TextField(prompt, value: value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(WorkbenchUIStyle.controlValueFont)
                    .frame(minWidth: WorkbenchInputWidth.compact, idealWidth: WorkbenchInputWidth.standard, maxWidth: WorkbenchInputWidth.standard)
                    .workbenchControl(.textField)
                    .onSubmit { onCommit?() }
            )
        }
    }

    static func button(_ id: String, title: String, action: @escaping () -> Void) -> WorkbenchSpecificInput {
        WorkbenchSpecificInput(id: id) {
            AnyView(Button(title, action: action).buttonStyle(.bordered).controlSize(.small))
        }
    }

    static func readout(_ id: String, text: String) -> WorkbenchSpecificInput {
        WorkbenchSpecificInput(id: id) {
            AnyView(Text(text).workbenchTextRole(.value).fixedSize(horizontal: false, vertical: true))
        }
    }

    static func control<Leaf: WorkbenchLeafInput>(_ id: String, fills: Bool = false, _ leaf: Leaf) -> WorkbenchSpecificInput {
        WorkbenchSpecificInput(id: id, fills: fills) { AnyView(leaf) }
    }
}

struct WorkbenchSpecificRow {
    let id: String
    let rowLabel: String?
    let inputs: [WorkbenchSpecificInput]

    init(_ id: String, label: String? = nil, @WorkbenchSpecificInputBuilder inputs: () -> [WorkbenchSpecificInput]) {
        self.id = id
        self.rowLabel = label
        self.inputs = inputs()
    }
}

struct WorkbenchSpecificGroup {
    let id: String
    let title: String
    let rows: [WorkbenchSpecificRow]

    init(_ id: String, title: String, @WorkbenchSpecificRowBuilder rows: () -> [WorkbenchSpecificRow]) {
        self.id = id
        self.title = title
        self.rows = rows()
    }
}

struct WorkbenchSpecificContent {
    let groups: [WorkbenchSpecificGroup]
    static let empty = WorkbenchSpecificContent(groups: [])
    var isEmpty: Bool { groups.isEmpty }

    init(groups: [WorkbenchSpecificGroup]) { self.groups = groups }

    init(@WorkbenchSpecificBuilder _ groups: () -> [WorkbenchSpecificGroup]) {
        self.groups = groups()
    }
}

@resultBuilder enum WorkbenchSpecificBuilder {
    static func buildExpression(_ e: WorkbenchSpecificGroup) -> [WorkbenchSpecificGroup] { [e] }
    static func buildExpression(_ e: [WorkbenchSpecificGroup]) -> [WorkbenchSpecificGroup] { e }
    static func buildBlock(_ c: [WorkbenchSpecificGroup]...) -> [WorkbenchSpecificGroup] { c.flatMap { $0 } }
    static func buildOptional(_ c: [WorkbenchSpecificGroup]?) -> [WorkbenchSpecificGroup] { c ?? [] }
    static func buildEither(first c: [WorkbenchSpecificGroup]) -> [WorkbenchSpecificGroup] { c }
    static func buildEither(second c: [WorkbenchSpecificGroup]) -> [WorkbenchSpecificGroup] { c }
    static func buildArray(_ c: [[WorkbenchSpecificGroup]]) -> [WorkbenchSpecificGroup] { c.flatMap { $0 } }
}

@resultBuilder enum WorkbenchSpecificRowBuilder {
    static func buildExpression(_ e: WorkbenchSpecificRow) -> [WorkbenchSpecificRow] { [e] }
    static func buildExpression(_ e: [WorkbenchSpecificRow]) -> [WorkbenchSpecificRow] { e }
    static func buildBlock(_ c: [WorkbenchSpecificRow]...) -> [WorkbenchSpecificRow] { c.flatMap { $0 } }
    static func buildOptional(_ c: [WorkbenchSpecificRow]?) -> [WorkbenchSpecificRow] { c ?? [] }
    static func buildEither(first c: [WorkbenchSpecificRow]) -> [WorkbenchSpecificRow] { c }
    static func buildEither(second c: [WorkbenchSpecificRow]) -> [WorkbenchSpecificRow] { c }
    static func buildArray(_ c: [[WorkbenchSpecificRow]]) -> [WorkbenchSpecificRow] { c.flatMap { $0 } }
}

@resultBuilder enum WorkbenchSpecificInputBuilder {
    static func buildExpression(_ e: WorkbenchSpecificInput) -> [WorkbenchSpecificInput] { [e] }
    static func buildExpression(_ e: [WorkbenchSpecificInput]) -> [WorkbenchSpecificInput] { e }
    static func buildBlock(_ c: [WorkbenchSpecificInput]...) -> [WorkbenchSpecificInput] { c.flatMap { $0 } }
    static func buildOptional(_ c: [WorkbenchSpecificInput]?) -> [WorkbenchSpecificInput] { c ?? [] }
    static func buildEither(first c: [WorkbenchSpecificInput]) -> [WorkbenchSpecificInput] { c }
    static func buildEither(second c: [WorkbenchSpecificInput]) -> [WorkbenchSpecificInput] { c }
    static func buildArray(_ c: [[WorkbenchSpecificInput]]) -> [WorkbenchSpecificInput] { c.flatMap { $0 } }
}

/// Renders Specific content with the shared containers (the only place it is laid out).
struct WorkbenchSpecificSection: View {
    let content: WorkbenchSpecificContent

    var body: some View {
        WorkbenchControlFlow {
            ForEach(content.groups, id: \.id) { group in
                WorkbenchControlGroup(id: "controls.specific.\(group.id)", title: group.title) {
                    ForEach(group.rows, id: \.id) { row in
                        WorkbenchControlRow(id: "controls.specific.\(group.id).\(row.id)", label: row.rowLabel) {
                            WorkbenchControlFlow(spacing: WorkbenchControlMetrics.groupSpacing, lineSpacing: AppSpacing.sm) {
                                ForEach(row.inputs, id: \.id) { input in
                                    input.view()
                                        .workbenchFlowFill(input.fills)
                                        .accessibilityIdentifier("controls.specific.\(group.id).\(row.id).\(input.id)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
