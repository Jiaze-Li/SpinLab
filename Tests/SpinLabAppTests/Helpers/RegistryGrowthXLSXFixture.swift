import Foundation
@testable import SpinLabApp

/// Builds a minimal, from-scratch .xlsx fixture for Phase 5A tests — no
/// helper/fixture .xlsx existed anywhere in the repo prior to this phase, so
/// this constructs one directly from raw OOXML parts (reusing
/// `XLSXWorkbookKit`'s tested cell-writing primitives for the worksheet
/// bodies) rather than adapting a hand-picked binary file. Every test that
/// needs to write to a workbook operates on a fresh temp copy of what this
/// produces — never on any real file.
enum RegistryGrowthXLSXFixture {
    static let materialSheetHeaders = ["编号", "日期", "substrate", "靶", "生长温度", "靶机距", "氧压", "能量", "预打/生长次数", "生长", "remark"]
    /// PLD-N样品's schema deliberately differs in column order, and column
    /// J here is "其他备注" (not 生长) — this is the fixture spec §6 asks
    /// for: proof that field mapping is header-driven, not positional.
    static let pldnHeaders = ["编号", "靶", "日期", "substrate", "生长温度", "靶机距", "氧压", "能量", "预打/生长次数", "其他备注", "生长"]

    struct FixtureCell {
        var header: String
        var value: String
        var style: String?
        /// When set, this cell is written as a numeric-typed cell (an
        /// Excel date serial) instead of the usual inlineStr text every
        /// other fixture cell uses — needed to reproduce a genuine Excel
        /// date whose *display* format can omit the year (e.g. "8月2日")
        /// even though the serial always carries the full date.
        var numericSerial: Double?

        /// When true, this cell is written as a genuine shared-string cell
        /// (`t="s"`, `<v>` holding an index into `xl/sharedStrings.xml`) —
        /// the actual on-disk representation confirmed (via raw OOXML
        /// inspection of the real production registry) for a Registry 日期
        /// cell typed as literal text like "8月2日" with a `m月d日`-style
        /// custom format but NO underlying date value at all: unlike the
        /// numeric-date case above, there is no serial anywhere to recover
        /// a year from. Every other fixture cell uses `t="inlineStr"`
        /// instead, which this app's own writer always produces but which
        /// real third-party-authored workbooks (the actual production
        /// file) never do for plain typed text.
        var isSharedString: Bool = false

        init(_ header: String, _ value: String, style: String? = nil) {
            self.header = header
            self.value = value
            self.style = style
            self.numericSerial = nil
        }

        /// A numeric-typed date cell. `value` is unused for writing (kept
        /// only so `FixtureCell` stays a single type) but is meaningless
        /// here — pass the intended display text for readability only.
        static func numericDate(_ header: String, serial: Double) -> FixtureCell {
            var cell = FixtureCell(header, "")
            cell.numericSerial = serial
            return cell
        }

        /// A genuine shared-string text cell — see `isSharedString` above.
        static func sharedString(_ header: String, _ value: String) -> FixtureCell {
            var cell = FixtureCell(header, value)
            cell.isSharedString = true
            return cell
        }
    }

    /// Builds the standard fixture workbook at `url`. `includeLSMO`
    /// controls whether the LSMO sheet exists at all (used by the
    /// missing-target-sheet test).
    static func build(includeLSMO: Bool = true, to url: URL) throws {
        var docs: [String: XMLDocument] = [:]

        docs["LNO"] = try sheetDoc(headers: materialSheetHeaders, rows: [
            [
                FixtureCell("编号", "LNO1"),
                FixtureCell("日期", "2026.1.1"),
                FixtureCell("substrate", "STO(001)"),
                FixtureCell("靶", "LNO"),
                FixtureCell("生长温度", "650", style: "7"),
                FixtureCell("靶机距", "45"),
                FixtureCell("氧压", "100"),
                FixtureCell("能量", "1.2"),
                FixtureCell("预打/生长次数", "200/3000"),
                FixtureCell("生长", "done"),
                FixtureCell("remark", "baseline")
            ],
            [FixtureCell("编号", "LNO5", style: "2")],
            [FixtureCell("编号", "LNO9")],
            [FixtureCell("编号", "LNO9")]
        ])

        docs["NCO"] = try sheetDoc(headers: materialSheetHeaders, rows: [
            [
                FixtureCell("编号", "NCO1"),
                FixtureCell("日期", "2026.2.2"),
                FixtureCell("substrate", "STO(001)"),
                FixtureCell("靶", "NCO"),
                FixtureCell("生长温度", "700"),
                FixtureCell("靶机距", "50"),
                FixtureCell("氧压", "90"),
                FixtureCell("能量", "1.5"),
                FixtureCell("预打/生长次数", "100/2500"),
                FixtureCell("生长", "done")
            ]
        ])

        docs["NNO"] = try sheetDoc(headers: materialSheetHeaders, rows: [
            [FixtureCell("编号", "NNO4", style: "5")]
        ])

        if includeLSMO {
            docs["LSMO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])
        }

        docs["PLD-N样品"] = try sheetDoc(headers: pldnHeaders, rows: [
            [
                FixtureCell("编号", "PN1"),
                FixtureCell("靶", "SRO"),
                FixtureCell("日期", "2026.3.3"),
                FixtureCell("substrate", "STO(001)"),
                FixtureCell("生长温度", "800"),
                FixtureCell("靶机距", "40"),
                FixtureCell("氧压", "80"),
                FixtureCell("能量", "2.0"),
                FixtureCell("预打/生长次数", "50/1000"),
                FixtureCell("其他备注", "note"),
                FixtureCell("生长", "done")
            ]
        ])

        let sheetOrder = ["LNO", "NCO", "NNO"] + (includeLSMO ? ["LSMO"] : []) + ["PLD-N样品"]
        try assemble(sheetOrder: sheetOrder, docs: docs, to: url)
    }

    /// A second fixture, purpose-built for content-aware routing tests.
    /// `build(to:)` above is left untouched so every existing test keeps its
    /// exact row layout; this one exists solely so routing tests can control
    /// exactly which series appears on which sheet.
    ///
    /// Every sheet here is deliberately single-series/clean (or empty) —
    /// multi-series scenarios are covered by `buildForMultiSeriesSheet(to:)`
    /// instead, so a stray extra series doesn't change what these routing
    /// tests observe.
    ///
    /// - PLD-N样品 carries a dense, clean PN series (mostly reserved
    ///   ID-only rows, one fully populated row) — the primary
    ///   observed-routing scenario.
    /// - NNO carries only its own reserved `NNO4`.
    /// - NCO carries zero rows, so it contributes no observed NCO evidence
    ///   of its own.
    /// - LSMO exists but has zero rows — the empty-sheet fallback scenario.
    static func buildForRouting(to url: URL) throws {
        var docs: [String: XMLDocument] = [:]

        docs["LNO"] = try sheetDoc(headers: materialSheetHeaders, rows: [
            [FixtureCell("编号", "LNO1")],
            [FixtureCell("编号", "LNO2")]
        ])

        docs["NCO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])

        docs["NNO"] = try sheetDoc(headers: materialSheetHeaders, rows: [
            [FixtureCell("编号", "NNO4")]
        ])

        // LSMO sheet exists but carries no rows at all — the empty-sheet
        // fallback test (no observed series evidence, explicit prefix
        // routing still applies).
        docs["LSMO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])

        docs["PLD-N样品"] = try sheetDoc(headers: pldnHeaders, rows: [
            [FixtureCell("编号", "PN100")],
            [FixtureCell("编号", "PN101")],
            [
                FixtureCell("编号", "PN109"),
                FixtureCell("靶", "SRO"),
                FixtureCell("日期", "2026.8.9"),
                FixtureCell("substrate", "STO(001)")
            ],
            // Reserved ID-only row — must still count as PN series evidence.
            [FixtureCell("编号", "PN114")]
        ])

        let sheetOrder = ["LNO", "NCO", "NNO", "LSMO", "PLD-N样品"]
        try assemble(sheetOrder: sheetOrder, docs: docs, to: url)
    }

    /// A fourth fixture, purpose-built for "compact clean Existing" coverage
    /// (compacting bulk historical `.skipExisting` rows out of the plan
    /// preview — see `RegistryGrowthImportPlanner.isCleanExisting`). All rows
    /// live on one caller-chosen sheet under one series prefix, so the sheet
    /// stays a valid single-series `RegistrySheetProfile` and new batches of
    /// the same series route to it via observed evidence. Every other
    /// routable sheet is present but empty.
    static func buildForCompactExisting(
        seriesPrefix: String,
        sheetName: String,
        populatedNumbers: [Int],
        reservedNumbers: [Int] = [],
        duplicateBatchIds: [String] = [],
        to url: URL
    ) throws {
        var docs: [String: XMLDocument] = [:]
        let allSheets = ["LNO", "NCO", "NNO", "LSMO", "PLD-N样品"]
        for other in allSheets where other != sheetName {
            docs[other] = try sheetDoc(headers: other == "PLD-N样品" ? pldnHeaders : materialSheetHeaders, rows: [])
        }

        let headers = sheetName == "PLD-N样品" ? pldnHeaders : materialSheetHeaders
        var rows: [[FixtureCell]] = []
        for number in populatedNumbers {
            rows.append([
                FixtureCell("编号", "\(seriesPrefix)\(number)"),
                FixtureCell("日期", "2026.1.1"),
                FixtureCell("substrate", "STO(001)"),
                FixtureCell("靶", "LNO"),
                FixtureCell("生长温度", "650"),
                FixtureCell("靶机距", "45"),
                FixtureCell("氧压", "100"),
                FixtureCell("能量", "1.2"),
                FixtureCell("预打/生长次数", "200/3000"),
                FixtureCell("生长", "done")
            ])
        }
        for number in reservedNumbers {
            rows.append([FixtureCell("编号", "\(seriesPrefix)\(number)")])
        }
        for batchId in duplicateBatchIds {
            rows.append([FixtureCell("编号", batchId)])
            rows.append([FixtureCell("编号", batchId)])
        }
        docs[sheetName] = try sheetDoc(headers: headers, rows: rows)

        try assemble(sheetOrder: allSheets, docs: docs, to: url)
    }

    /// A fifth fixture, purpose-built for the Human Identifier layer: one
    /// "编号" cell may name more than one identifier (e.g. `"PN110/SRO1"`),
    /// and the sheet those rows live on legitimately observes more than one
    /// series as a result — this is a VALID profile, not mixed/invalid.
    ///
    /// - PLD-N样品 carries `PN110/SRO1` (fully populated — the exact-match
    ///   and "composite cell is not a duplicate" scenarios) and
    ///   `PN111/SRO2` (reserved ID-only — the "reserved composite row still
    ///   fills" scenario).
    /// - LNO, NCO, NNO, LSMO are empty; not used by these tests.
    static func buildForMultiSeriesSheet(to url: URL) throws {
        var docs: [String: XMLDocument] = [:]

        docs["LNO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])
        docs["NCO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])
        docs["NNO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])
        docs["LSMO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])

        docs["PLD-N样品"] = try sheetDoc(headers: pldnHeaders, rows: [
            [
                FixtureCell("编号", "PN110/SRO1"),
                FixtureCell("靶", "SRO"),
                FixtureCell("日期", "2026.8.10"),
                FixtureCell("substrate", "STO(001)")
            ],
            // Reserved ID-only composite row.
            [FixtureCell("编号", "PN111/SRO2")]
        ])

        let sheetOrder = ["LNO", "NCO", "NNO", "LSMO", "PLD-N样品"]
        try assemble(sheetOrder: sheetOrder, docs: docs, to: url)
    }

    /// A sixth fixture: the same human identifier (`PN110`) appears on two
    /// different rows — once inside a composite cell, once alone — which
    /// must still be detected as a duplicate (spec: a composite cell is not
    /// itself a duplicate, but the same identifier repeated across rows is).
    static func buildForDuplicateHumanIdentifier(to url: URL) throws {
        var docs: [String: XMLDocument] = [:]

        docs["LNO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])
        docs["NCO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])
        docs["NNO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])
        docs["LSMO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])

        docs["PLD-N样品"] = try sheetDoc(headers: pldnHeaders, rows: [
            [
                FixtureCell("编号", "PN110/SRO1"),
                FixtureCell("靶", "SRO"),
                FixtureCell("日期", "2026.8.10"),
                FixtureCell("substrate", "STO(001)")
            ],
            [FixtureCell("编号", "PN110")]
        ])

        let sheetOrder = ["LNO", "NCO", "NNO", "LSMO", "PLD-N样品"]
        try assemble(sheetOrder: sheetOrder, docs: docs, to: url)
    }

    /// A seventh fixture: `PLD-N样品` carries a fully *populated* row whose
    /// identifier cell is `"PN110/???"` — a valid `PN110` identifier plus a
    /// malformed fragment. Used to prove a populated Registry row with a
    /// malformed identifier fragment stays visible (Blocked) rather than
    /// disappearing through Existing compaction.
    static func buildForPopulatedMalformedRow(to url: URL) throws {
        var docs: [String: XMLDocument] = [:]

        docs["LNO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])
        docs["NCO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])
        docs["NNO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])
        docs["LSMO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])

        docs["PLD-N样品"] = try sheetDoc(headers: pldnHeaders, rows: [
            [
                FixtureCell("编号", "PN110/???"),
                FixtureCell("靶", "SRO"),
                FixtureCell("日期", "2026.8.10"),
                FixtureCell("substrate", "STO(001)")
            ]
        ])

        let sheetOrder = ["LNO", "NCO", "NNO", "LSMO", "PLD-N样品"]
        try assemble(sheetOrder: sheetOrder, docs: docs, to: url)
    }

    /// An eighth fixture, purpose-built for Existing semantic date/pulse
    /// equality coverage (Phase 5.4.4). All rows live on LNO so the sheet
    /// stays a valid single-series profile.
    ///
    /// - LNO1: 日期 is a genuine numeric-typed Excel date cell (serial
    ///   46236 == 2026-08-02, per the standard 1899-12-30 epoch — matches
    ///   the well-known reference serial 45292 == 2024-01-01) — the
    ///   "display omits the year but the underlying date has one" case.
    /// - LNO2: same numeric-date mechanism, but serial 45871 == 2025-08-02
    ///   — a genuinely different underlying year, for the "must not guess
    ///   equal" regression.
    /// - LNO3: 日期 stored as ordinary Registry text with its own year
    ///   ("2026.8.2") — the pre-existing text-date convention, unaffected
    ///   by the new numeric-cell path.
    /// - LNO4: 预打/生长次数 already carries the explicit default annotation
    ///   ("1000 (2Hz) /3000 (2Hz)").
    /// - LNO5: 预打/生长次数 stored in shorthand ("1000/3000").
    /// - LNO6: 预打/生长次数 carries an EXPLICIT non-default pre-ablation
    ///   frequency ("1000 (5Hz) /3000 (2Hz)") — must never be normalized
    ///   away.
    static func buildForSemanticDateAndPulse(to url: URL) throws {
        var docs: [String: XMLDocument] = [:]
        docs["NCO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])
        docs["NNO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])
        docs["LSMO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])
        docs["PLD-N样品"] = try sheetDoc(headers: pldnHeaders, rows: [])

        func populatedRow(id: String, dateCell: FixtureCell, pulse: String) -> [FixtureCell] {
            [
                FixtureCell("编号", id),
                dateCell,
                FixtureCell("substrate", "STO(001)"),
                FixtureCell("靶", "LNO"),
                FixtureCell("生长温度", "650"),
                FixtureCell("靶机距", "45"),
                FixtureCell("氧压", "100"),
                FixtureCell("能量", "1.2"),
                FixtureCell("预打/生长次数", pulse),
                FixtureCell("生长", "done")
            ]
        }

        docs["LNO"] = try sheetDoc(headers: materialSheetHeaders, rows: [
            populatedRow(id: "LNO1", dateCell: .numericDate("日期", serial: 46236), pulse: "200/3000"),
            populatedRow(id: "LNO2", dateCell: .numericDate("日期", serial: 45871), pulse: "200/3000"),
            populatedRow(id: "LNO3", dateCell: FixtureCell("日期", "2026.8.2"), pulse: "200/3000"),
            populatedRow(id: "LNO4", dateCell: FixtureCell("日期", "2026.1.1"), pulse: "1000 (2Hz) /3000 (2Hz)"),
            populatedRow(id: "LNO5", dateCell: FixtureCell("日期", "2026.1.1"), pulse: "1000/3000"),
            populatedRow(id: "LNO6", dateCell: FixtureCell("日期", "2026.1.1"), pulse: "1000 (5Hz) /3000 (2Hz)")
        ])

        let sheetOrder = ["LNO", "NCO", "NNO", "LSMO", "PLD-N样品"]
        try assemble(sheetOrder: sheetOrder, docs: docs, to: url)
    }

    /// A ninth fixture, reproducing the exact production row that
    /// motivated this investigation: LNO's real Registry workbook
    /// (`~/Library/Application Support/SpinLab/registry/实验记录.xlsx`,
    /// sheet "LNO") stores 日期 for several rows as a genuine
    /// shared-string cell (`t="s"`) whose text is the bare, year-omitting
    /// "8月2日" — confirmed by extracting the workbook's raw
    /// `xl/worksheets/*.xml` and `xl/sharedStrings.xml` and cross-
    /// referencing the shared-string index used by those cells. There is
    /// no numeric serial anywhere for this cell (unlike the "display
    /// format hides the year but the serial carries it" case covered by
    /// `buildForSemanticDateAndPulse`'s LNO1/LNO2), and no other column in
    /// the same row carries a year either — so this is a genuinely
    /// unresolvable case, not a display-format false positive.
    ///
    /// - LNO1: 日期 = shared-string "8月2日" (the production
    ///   representation), no other trustworthy year source in the row.
    ///   Must remain a real Existing difference against Obsidian
    ///   2026-08-02 — never silently accepted as equal.
    static func buildForProductionYearlessSharedStringDate(to url: URL) throws {
        let sharedStrings = SharedStringsTable()
        var docs: [String: XMLDocument] = [:]
        docs["NCO"] = try sheetDoc(headers: materialSheetHeaders, rows: [], sharedStrings: sharedStrings)
        docs["NNO"] = try sheetDoc(headers: materialSheetHeaders, rows: [], sharedStrings: sharedStrings)
        docs["LSMO"] = try sheetDoc(headers: materialSheetHeaders, rows: [], sharedStrings: sharedStrings)
        docs["PLD-N样品"] = try sheetDoc(headers: pldnHeaders, rows: [], sharedStrings: sharedStrings)

        docs["LNO"] = try sheetDoc(headers: materialSheetHeaders, rows: [
            [
                FixtureCell("编号", "LNO1"),
                .sharedString("日期", "8月2日"),
                FixtureCell("substrate", "STO(001)"),
                FixtureCell("靶", "LNO"),
                FixtureCell("生长温度", "650"),
                FixtureCell("靶机距", "45"),
                FixtureCell("氧压", "100"),
                FixtureCell("能量", "1.2"),
                FixtureCell("预打/生长次数", "1000 (2Hz) /3000 (2Hz)"),
                FixtureCell("生长", "done")
            ]
        ], sharedStrings: sharedStrings)

        let sheetOrder = ["LNO", "NCO", "NNO", "LSMO", "PLD-N样品"]
        try assemble(sheetOrder: sheetOrder, docs: docs, sharedStrings: sharedStrings, to: url)
    }

    /// Phase 5.4.5 compatible-completion fixture — real production 能量
    /// syntax (audited from `实验记录.xlsx` and the Obsidian vault; see
    /// `RegistryGrowthEnergyMapper`'s doc comment), one row per required
    /// energy reconciliation scenario. Date/pulse/other fields are held
    /// constant across rows (matching claims) so only 能量 varies.
    static func buildForEnergyReconciliation(to url: URL) throws {
        var docs: [String: XMLDocument] = [:]
        docs["NCO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])
        docs["NNO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])
        docs["LSMO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])
        docs["PLD-N样品"] = try sheetDoc(headers: pldnHeaders, rows: [])

        func populatedRow(id: String, energy: String) -> [FixtureCell] {
            [
                FixtureCell("编号", id),
                FixtureCell("日期", "2026.1.1"),
                FixtureCell("substrate", "STO(001)"),
                FixtureCell("靶", "LNO"),
                FixtureCell("生长温度", "650"),
                FixtureCell("靶机距", "45"),
                FixtureCell("氧压", "100"),
                FixtureCell("能量", energy),
                FixtureCell("预打/生长次数", "1000/3000"),
                FixtureCell("生长", "done")
            ]
        }

        docs["LNO"] = try sheetDoc(headers: materialSheetHeaders, rows: [
            populatedRow(id: "LNO1", energy: "100mJ"),
            populatedRow(id: "LNO2", energy: "100mJ (20.2kV)"),
            populatedRow(id: "LNO3", energy: "镜前100mJ，激光238 mJ (24kV)"),
            populatedRow(id: "LNO4", energy: "镜前100mJ"),
            populatedRow(id: "LNO5", energy: "镜前100mJ，激光238 mJ (24kV)"),
            populatedRow(id: "LNO6", energy: "衰减镜220mJ (25.1kV) 镜前57mJ")
        ])

        let sheetOrder = ["LNO", "NCO", "NNO", "LSMO", "PLD-N样品"]
        try assemble(sheetOrder: sheetOrder, docs: docs, to: url)
    }

    // MARK: - Shared strings

    /// Accumulates text for genuine `t="s"` shared-string cells across a
    /// whole fixture workbook build, so `assemble` can emit one
    /// `xl/sharedStrings.xml` part shared by every sheet — mirroring how a
    /// real workbook's shared-strings table works. Every other fixture cell
    /// keeps using `t="inlineStr"` and never touches this table.
    final class SharedStringsTable {
        private(set) var strings: [String] = []

        func index(for text: String) -> Int {
            if let existing = strings.firstIndex(of: text) {
                return existing
            }
            strings.append(text)
            return strings.count - 1
        }
    }

    // MARK: - Worksheet body

    private static func sheetDoc(headers: [String], rows: [[FixtureCell]], sharedStrings: SharedStringsTable? = nil) throws -> XMLDocument {
        let skeleton = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData/></worksheet>"
        var doc = try XMLDocument(xmlString: skeleton, options: [.nodePreserveAll])

        for (index, header) in headers.enumerated() {
            let column = XLSXWorkbookKit.columnLetters(from: index + 1)
            XLSXWorkbookKit.setCellValue(doc: &doc, row: 1, column: column, value: header)
        }

        for (rowOffset, cells) in rows.enumerated() {
            let rowNumber = rowOffset + 2
            for cell in cells {
                guard let columnIndex = headers.firstIndex(of: cell.header) else {
                    fatalError("Fixture header '\(cell.header)' not present in \(headers)")
                }
                let column = XLSXWorkbookKit.columnLetters(from: columnIndex + 1)
                if cell.isSharedString {
                    guard let sharedStrings else {
                        fatalError("Fixture cell for header '\(cell.header)' requested a shared-string cell but no SharedStringsTable was provided")
                    }
                    setSharedStringCellValue(doc: &doc, row: rowNumber, column: column, index: sharedStrings.index(for: cell.value))
                    continue
                }
                if let style = cell.style {
                    XLSXWorkbookKit.setCellStyle(doc: &doc, row: rowNumber, column: column, style: style)
                }
                if let serial = cell.numericSerial {
                    setNumericCellValue(doc: &doc, row: rowNumber, column: column, serial: serial)
                } else {
                    XLSXWorkbookKit.setCellValue(doc: &doc, row: rowNumber, column: column, value: cell.value)
                }
            }
        }

        return doc
    }

    /// Writes a numeric-typed cell (`<v>` only, no `t` attribute — OOXML
    /// defaults an absent type to numeric), unlike every other fixture
    /// cell which goes through `XLSXWorkbookKit.setCellValue` (always
    /// `t="inlineStr"`). Mirrors `setCellValue`'s style-preserving
    /// structure via the same internal `ensure*` helpers.
    private static func setNumericCellValue(doc: inout XMLDocument, row: Int, column: String, serial: Double) {
        let sheetData = XLSXWorkbookKit.ensureSheetData(in: &doc)
        let rowElement = XLSXWorkbookKit.ensureRow(in: sheetData, row: row)
        let ref = "\(column)\(row)"
        let cellElement = XLSXWorkbookKit.ensureCell(in: rowElement, ref: ref)

        for attribute in (cellElement.attributes ?? []) where attribute.name != "r" && attribute.name != "s" {
            attribute.detach()
        }
        for child in cellElement.children ?? [] {
            child.detach()
        }
        let serialText = serial.rounded() == serial ? String(Int(serial)) : String(serial)
        let vNode = XMLElement(name: "v", stringValue: serialText)
        cellElement.addChild(vNode)
    }

    /// Writes a genuine `t="s"` shared-string cell (`<v>` holds the index
    /// into `xl/sharedStrings.xml`, written separately by `assemble`) — the
    /// real production representation for a Registry text cell like
    /// "8月2日". See `SharedStringsTable`/`FixtureCell.sharedString`.
    private static func setSharedStringCellValue(doc: inout XMLDocument, row: Int, column: String, index: Int) {
        let sheetData = XLSXWorkbookKit.ensureSheetData(in: &doc)
        let rowElement = XLSXWorkbookKit.ensureRow(in: sheetData, row: row)
        let ref = "\(column)\(row)"
        let cellElement = XLSXWorkbookKit.ensureCell(in: rowElement, ref: ref)

        for attribute in (cellElement.attributes ?? []) where attribute.name != "r" && attribute.name != "s" {
            attribute.detach()
        }
        for child in cellElement.children ?? [] {
            child.detach()
        }
        cellElement.addAttribute(XMLNode.attribute(withName: "t", stringValue: "s") as! XMLNode)
        let vNode = XMLElement(name: "v", stringValue: String(index))
        cellElement.addChild(vNode)
    }

    // MARK: - Workbook assembly

    private static func assemble(sheetOrder: [String], docs: [String: XMLDocument], sharedStrings: SharedStringsTable? = nil, to url: URL) throws {
        let fileManager = FileManager.default
        let workDir = fileManager.temporaryDirectory.appending(path: "fixture_\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: workDir.appending(path: "_rels"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workDir.appending(path: "xl/_rels"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workDir.appending(path: "xl/worksheets"), withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workDir) }

        var sheetsXML = ""
        var relsXML = ""
        var overridesXML = ""
        for (index, name) in sheetOrder.enumerated() {
            let rId = "rId\(index + 1)"
            let file = "sheet\(index + 1).xml"
            sheetsXML += "<sheet name=\"\(xmlEscape(name))\" sheetId=\"\(index + 1)\" r:id=\"\(rId)\"/>"
            relsXML += "<Relationship Id=\"\(rId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/\(file)\"/>"
            overridesXML += "<Override PartName=\"/xl/worksheets/\(file)\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
            guard let doc = docs[name] else { fatalError("Missing sheet doc for \(name)") }
            try doc.xmlData(options: [.nodePrettyPrint]).write(to: workDir.appending(path: "xl/worksheets/\(file)"), options: .atomic)
        }
        let stylesRelId = "rId\(sheetOrder.count + 1)"
        relsXML += "<Relationship Id=\"\(stylesRelId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"

        var sharedStringsOverrideXML = ""
        if let sharedStrings, !sharedStrings.strings.isEmpty {
            let sharedStringsRelId = "rId\(sheetOrder.count + 2)"
            relsXML += "<Relationship Id=\"\(sharedStringsRelId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"sharedStrings.xml\"/>"
            sharedStringsOverrideXML = "<Override PartName=\"/xl/sharedStrings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml\"/>"
            let siXML = sharedStrings.strings.map { "<si><t>\(xmlEscape($0))</t></si>" }.joined()
            let sharedStringsXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" count=\"\(sharedStrings.strings.count)\" uniqueCount=\"\(sharedStrings.strings.count)\">\(siXML)</sst>"
            try write(sharedStringsXML, to: workDir.appending(path: "xl/sharedStrings.xml"))
        }

        let workbookXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>\(sheetsXML)</sheets></workbook>"
        try write(workbookXML, to: workDir.appending(path: "xl/workbook.xml"))

        let workbookRelsXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(relsXML)</Relationships>"
        try write(workbookRelsXML, to: workDir.appending(path: "xl/_rels/workbook.xml.rels"))

        try write(stylesXML, to: workDir.appending(path: "xl/styles.xml"))

        let contentTypesXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>\(overridesXML)\(sharedStringsOverrideXML)</Types>"
        try write(contentTypesXML, to: workDir.appending(path: "[Content_Types].xml"))

        let rootRelsXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"
        try write(rootRelsXML, to: workDir.appending(path: "_rels/.rels"))

        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        let output = try XLSXWorkbookKit.runProcess(executable: "/usr/bin/zip", arguments: ["-q", "-r", url.path, "."], currentDirectory: workDir)
        guard output.status == 0, fileManager.fileExists(atPath: url.path) else {
            fatalError("Fixture zip failed: \(output.stderr)")
        }
    }

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <numFmts count="0"/>
    <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
    <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
    <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
    <cellXfs count="8">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    </cellXfs>
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
    </styleSheet>
    """

    private static func write(_ string: String, to url: URL) throws {
        try string.data(using: .utf8)!.write(to: url, options: .atomic)
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
