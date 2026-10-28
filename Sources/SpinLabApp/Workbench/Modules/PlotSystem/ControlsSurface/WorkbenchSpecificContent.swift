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

    /// `contentFit` opts the menu into its native intrinsic width (VC-8, `workbenchContentFitMenu`)
    /// instead of the shared compact-to-wide range; pair it with an `atomic` row.
    static func menu<Value: Hashable>(
        _ id: String, selection: Binding<Value>, options: [(title: String, value: Value)], contentFit: Bool = false
    ) -> WorkbenchSpecificInput {
        WorkbenchSpecificInput(id: id) {
            let picker = Picker("", selection: selection) {
                ForEach(options.indices, id: \.self) { Text(options[$0].title).tag(options[$0].value) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            if contentFit {
                return AnyView(picker.workbenchContentFitMenu().workbenchControl(.menu))
            }
            return AnyView(
                picker
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
    /// Logical line this row shares with the neighbouring rows of the same `line`, even across
    /// groups. The row keeps its group (identity, identifiers); only its placement is shared.
    /// nil = the row stays inside its group's own container (default).
    let line: String?
    /// A conditional companion of the row before it (VC-10): stays right after its main row and
    /// wraps with the other companions of that line as one whole.
    let accessory: Bool
    /// The row's input cannot be compressed (content-fit menus): the label moves above it instead.
    let atomic: Bool
    let inputs: [WorkbenchSpecificInput]

    init(_ id: String, label: String? = nil, line: String? = nil, accessory: Bool = false, atomic: Bool = false,
         @WorkbenchSpecificInputBuilder inputs: () -> [WorkbenchSpecificInput]) {
        self.id = id
        self.rowLabel = label
        self.line = line
        self.accessory = accessory
        self.atomic = atomic
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
    /// True when any row declares a shared `line`; otherwise every group keeps its own container.
    var usesLines: Bool { groups.contains { $0.rows.contains { $0.line != nil } } }

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

    /// A row together with the group that owns it.
    private struct Entry {
        let group: WorkbenchSpecificGroup
        let row: WorkbenchSpecificRow
    }

    var body: some View {
        if content.usesLines {
            // Lines are stacked, one per logical line; each wraps by whole rows on its own.
            VStack(alignment: .leading, spacing: WorkbenchControlMetrics.lineSpacing) {
                ForEach(lines(), id: \.id) { line in
                    WorkbenchControlGroup(id: "controls.specific.\(line.id)", title: accessibilityTitle(line.entries), titleVisible: false) {
                        lineFlow(line.entries)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            WorkbenchControlFlow {
                ForEach(content.groups, id: \.id) { group in
                    // Group titles stay the accessibility label but are not drawn (CS-18a).
                    WorkbenchControlGroup(id: "controls.specific.\(group.id)", title: group.title, titleVisible: false) {
                        ForEach(group.rows, id: \.id) { row in rowView(group, row) }
                    }
                }
            }
        }
    }

    /// Rows in group order, merged into lines: consecutive rows with the same `line`; a row
    /// without `line` is its own line named after the row.
    private func lines() -> [(id: String, entries: [Entry])] {
        var out: [(id: String, entries: [Entry])] = []
        for group in content.groups {
            for row in group.rows {
                let entry = Entry(group: group, row: row)
                if let line = row.line, out.last?.id == line {
                    out[out.count - 1].entries.append(entry)
                } else {
                    out.append((row.line ?? "\(group.id).\(row.id)", [entry]))
                }
            }
        }
        return out
    }

    /// A line spanning groups is announced by the titles of the groups it holds (CS-18a, CS-25a),
    /// so the group semantics stay available to assistive technology even though the group's own
    /// container is not drawn in line mode.
    private func accessibilityTitle(_ entries: [Entry]) -> String {
        var titles: [String] = []
        for entry in entries where !titles.contains(entry.group.title) { titles.append(entry.group.title) }
        return titles.joined(separator: " · ")
    }

    /// Main rows are flow items; the accessories that follow a main row form one nested flow item,
    /// so they stay beside their main row and wrap below it as a whole.
    @ViewBuilder
    private func lineFlow(_ entries: [Entry]) -> some View {
        let items = flowItems(entries)
        WorkbenchControlFlow(spacing: WorkbenchControlMetrics.groupSpacing, lineSpacing: AppSpacing.sm) {
            ForEach(items.indices, id: \.self) { index in
                if items[index].count == 1, !items[index][0].row.accessory {
                    rowView(items[index][0].group, items[index][0].row)
                } else {
                    WorkbenchControlFlow(spacing: WorkbenchControlMetrics.groupSpacing, lineSpacing: AppSpacing.sm) {
                        ForEach(items[index], id: \.row.id) { rowView($0.group, $0.row) }
                    }
                    .workbenchFlowFill(false)
                }
            }
        }
    }

    private func flowItems(_ entries: [Entry]) -> [[Entry]] {
        var items: [[Entry]] = []
        for entry in entries {
            if entry.row.accessory, let last = items.last, last.contains(where: \.row.accessory) {
                items[items.count - 1].append(entry)
            } else {
                items.append([entry])
            }
        }
        return items
    }

    private func rowView(_ group: WorkbenchSpecificGroup, _ row: WorkbenchSpecificRow) -> some View {
        WorkbenchControlRow(id: "controls.specific.\(group.id).\(row.id)", label: row.rowLabel, atomic: row.atomic) {
            WorkbenchControlFlow(spacing: WorkbenchControlMetrics.groupSpacing, lineSpacing: AppSpacing.sm) {
                ForEach(row.inputs, id: \.id) { input in
                    input.view()
                        .workbenchFlowFill(input.fills)
                        .accessibilityIdentifier("controls.specific.\(group.id).\(row.id).\(input.id)")
                }
            }
        }
        .workbenchFlowFill(false)
    }
}
