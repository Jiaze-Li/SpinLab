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

        init(_ header: String, _ value: String, style: String? = nil) {
            self.header = header
            self.value = value
            self.style = style
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
    /// mixed-sheet (invalid-profile) scenarios are covered by
    /// `buildForMixedSheetProfileInvariant(to:)` instead, since a stray
    /// cross-series row on a sheet other tests also depend on would poison
    /// that sheet's `RegistrySheetProfile.series` for everyone sharing this
    /// fixture (a mixed sheet's declared series is nil — see
    /// `RegistrySheetProfile`).
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

    /// A third fixture, purpose-built to exercise the `RegistrySheetProfile`
    /// "one sheet = one series" invariant: a routable sheet whose rows mix
    /// more than one series must fail closed (declared `series == nil`),
    /// and — critically — that invalidity must still block a *write* into
    /// an exact reserved row physically sitting on it, even though exact
    /// row identity normally takes routing priority.
    ///
    /// - NNO mixes its own series with a stray `QX1` row: `NNO4` (reserved),
    ///   `NNO7` (fully populated, for the exact-existing-populated-row
    ///   test), and `QX1` (reserved, the contaminating stray row). NNO's
    ///   profile is therefore invalid (`series == nil`) even though
    ///   `seriesObserved` still records both `NNO` and `QX`.
    /// - LSMO carries only `QX99` (reserved) — a clean, single-series `QX`
    ///   sheet, so an incoming QX batch has exactly one *valid* candidate
    ///   even though NNO also contains a QX row.
    /// - LNO, NCO, PLD-N样品 are empty; not used by these tests.
    static func buildForMixedSheetProfileInvariant(to url: URL) throws {
        var docs: [String: XMLDocument] = [:]

        docs["LNO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])
        docs["NCO"] = try sheetDoc(headers: materialSheetHeaders, rows: [])

        docs["NNO"] = try sheetDoc(headers: materialSheetHeaders, rows: [
            [FixtureCell("编号", "NNO4")],
            [
                FixtureCell("编号", "NNO7"),
                FixtureCell("靶", "NNO"),
                FixtureCell("日期", "2026.8.10"),
                FixtureCell("substrate", "STO(001)")
            ],
            // Stray cross-series row: makes NNO's profile invalid (mixed).
            [FixtureCell("编号", "QX1")]
        ])

        docs["LSMO"] = try sheetDoc(headers: materialSheetHeaders, rows: [
            [FixtureCell("编号", "QX99")]
        ])

        docs["PLD-N样品"] = try sheetDoc(headers: pldnHeaders, rows: [])

        let sheetOrder = ["LNO", "NCO", "NNO", "LSMO", "PLD-N样品"]
        try assemble(sheetOrder: sheetOrder, docs: docs, to: url)
    }

    // MARK: - Worksheet body

    private static func sheetDoc(headers: [String], rows: [[FixtureCell]]) throws -> XMLDocument {
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
                if let style = cell.style {
                    XLSXWorkbookKit.setCellStyle(doc: &doc, row: rowNumber, column: column, style: style)
                }
                XLSXWorkbookKit.setCellValue(doc: &doc, row: rowNumber, column: column, value: cell.value)
            }
        }

        return doc
    }

    // MARK: - Workbook assembly

    private static func assemble(sheetOrder: [String], docs: [String: XMLDocument], to url: URL) throws {
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

        let workbookXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>\(sheetsXML)</sheets></workbook>"
        try write(workbookXML, to: workDir.appending(path: "xl/workbook.xml"))

        let workbookRelsXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(relsXML)</Relationships>"
        try write(workbookRelsXML, to: workDir.appending(path: "xl/_rels/workbook.xml.rels"))

        try write(stylesXML, to: workDir.appending(path: "xl/styles.xml"))

        let contentTypesXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>\(overridesXML)</Types>"
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
