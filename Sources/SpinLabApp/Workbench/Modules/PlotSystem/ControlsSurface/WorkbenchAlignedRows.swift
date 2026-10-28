import SwiftUI

/// Structurally identical rows (a row label + the same ordered controls) that share semantic
/// column edges: every column is as wide as its widest cell across all rows, so a short label
/// or a short value never shifts the controls after it (`04_UI_RULES.md` Repeated-row
/// alignment). Applies only to such repeated rows, never to the Workbench as a whole.
///
/// Content is flat and row-major: for each row, one label view followed by exactly `columns`
/// cells. When the width is short the whole table wraps by column bands: every row breaks at the
/// same column and the label column keeps its width in each band, so cells stay aligned. A layout
/// subview can be placed once, so the row label shows in the first band only.
struct WorkbenchAlignedRows<Content: View>: View {
    let columns: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        WorkbenchAlignedRowsLayout(columns: columns) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkbenchAlignedRowsLayout: Layout {
    var columns: Int
    var columnSpacing: CGFloat = WorkbenchControlMetrics.groupSpacing
    var labelGap: CGFloat = WorkbenchControlMetrics.labelGap
    var rowSpacing: CGFloat = WorkbenchControlMetrics.rowStackSpacing
    var bandSpacing: CGFloat = WorkbenchControlMetrics.lineSpacing

    private struct Plan {
        var columnWidths: [CGFloat]
        /// Cell-column ranges (1-based; column 0 is the row label) per band.
        var bands: [Range<Int>]
        var rowCount: Int
        var rowBaselines: [[CGFloat]]   // [band][row]
        var rowHeights: [[CGFloat]]
        var bandYs: [CGFloat]
        var size: CGSize
        var firstBaseline: CGFloat
    }

    private var stride: Int { columns + 1 }

    private func plan(width: CGFloat?, subviews: Subviews) -> Plan {
        let rowCount = stride > 0 ? subviews.count / stride : 0
        guard rowCount > 0 else {
            return Plan(columnWidths: [], bands: [], rowCount: 0, rowBaselines: [], rowHeights: [], bandYs: [], size: .zero, firstBaseline: 0)
        }
        func cell(_ row: Int, _ column: Int) -> LayoutSubview { subviews[row * stride + column] }
        var ideals = [[CGSize]](repeating: [CGSize](repeating: .zero, count: stride), count: rowCount)
        var baselines = ideals.map { $0.map { _ in CGFloat(0) } }
        var columnWidths = [CGFloat](repeating: 0, count: stride)
        for row in 0..<rowCount {
            for column in 0..<stride {
                let view = cell(row, column)
                let size = view.sizeThatFits(.unspecified)
                ideals[row][column] = size
                baselines[row][column] = view.dimensions(in: ProposedViewSize(size))[.firstTextBaseline]
                columnWidths[column] = max(columnWidths[column], size.width)
            }
        }
        // Wrap by whole column bands.
        let limit = width ?? .infinity
        var bands: [Range<Int>] = []
        var start = 1
        var used = columnWidths[0]
        var column = 1
        while column <= columns {
            let add = (column == start ? labelGap : columnSpacing) + columnWidths[column]
            if column > start, used + add > limit + 0.001 {
                bands.append(start..<column)
                start = column
                used = columnWidths[0]
                continue
            }
            used += add
            column += 1
        }
        bands.append(start..<(columns + 1))

        var rowBaselines: [[CGFloat]] = []
        var rowHeights: [[CGFloat]] = []
        var bandYs: [CGFloat] = []
        var y: CGFloat = 0
        var usedWidth: CGFloat = 0
        for band in bands {
            bandYs.append(y)
            var bandBaselines: [CGFloat] = []
            var bandHeights: [CGFloat] = []
            for row in 0..<rowCount {
                let members = [0] + Array(band)
                let baseline = members.map { baselines[row][$0] }.max() ?? 0
                let height = members.map { baseline - baselines[row][$0] + ideals[row][$0].height }.max() ?? 0
                bandBaselines.append(baseline)
                bandHeights.append(height)
            }
            rowBaselines.append(bandBaselines)
            rowHeights.append(bandHeights)
            y += bandHeights.reduce(0, +) + rowSpacing * CGFloat(rowCount - 1) + bandSpacing
            let bandWidth = columnWidths[0] + band.reduce(CGFloat(0)) { $0 + columnWidths[$1] }
                + labelGap + columnSpacing * CGFloat(max(band.count - 1, 0))
            usedWidth = max(usedWidth, bandWidth)
        }
        return Plan(columnWidths: columnWidths, bands: bands, rowCount: rowCount, rowBaselines: rowBaselines,
                    rowHeights: rowHeights, bandYs: bandYs,
                    size: CGSize(width: usedWidth, height: max(y - bandSpacing, 0)),
                    firstBaseline: rowBaselines.first?.first ?? 0)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        plan(width: proposal.width, subviews: subviews).size
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .firstTextBaseline, !subviews.isEmpty else { return nil }
        return bounds.minY + plan(width: bounds.width, subviews: subviews).firstBaseline
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let p = plan(width: bounds.width, subviews: subviews)
        for (bandIndex, band) in p.bands.enumerated() {
            var rowY = bounds.minY + p.bandYs[bandIndex]
            for row in 0..<p.rowCount {
                let baseline = p.rowBaselines[bandIndex][row]
                var x = bounds.minX
                for column in [0] + Array(band) {
                    if column == 0, bandIndex > 0 {
                        x += p.columnWidths[0] + labelGap
                        continue
                    }
                    let view = subviews[row * stride + column]
                    let size = view.sizeThatFits(.unspecified)
                    let own = view.dimensions(in: ProposedViewSize(size))[.firstTextBaseline]
                    view.place(at: CGPoint(x: x, y: rowY + baseline - own), anchor: .topLeading, proposal: ProposedViewSize(size))
                    x += p.columnWidths[column] + (column == 0 ? labelGap : columnSpacing)
                }
                rowY += p.rowHeights[bandIndex][row] + rowSpacing
            }
        }
    }
}
