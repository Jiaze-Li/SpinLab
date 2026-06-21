import Foundation
import CoreGraphics

/// Local LaTeX-backed axis label renderer.
///
/// Labels prefixed with "latex:" are compiled via a local LaTeX installation
/// (latexmk preferred, pdflatex fallback), rasterised to a CGImage, and drawn
/// into the chart CGContext at the requested size and orientation.
///
/// Results are cached by latex source string to avoid recompilation on every
/// redraw.  When LaTeX is unavailable every call returns nil / false and callers
/// fall back to MathMarkupRenderer or plain text.
final class LatexAxisLabelRenderer {

    static let shared = LatexAxisLabelRenderer()

    // MARK: - Prefix helpers

    static let latexPrefix = "latex:"

    static func isLatexLabel(_ text: String) -> Bool {
        text.hasPrefix(latexPrefix)
    }

    static func extractLatex(_ text: String) -> String {
        String(text.dropFirst(latexPrefix.count))
    }

    // MARK: - Orientation

    enum Orientation {
        case horizontal
        case rotated90
    }

    // MARK: - Backend status

    enum BackendStatus: Equatable {
        case latexmk(path: String)
        case pdflatex(path: String)
        case unavailable

        var isAvailable: Bool {
            if case .unavailable = self { return false }
            return true
        }

        var executablePath: String? {
            switch self {
            case .latexmk(let p): return p
            case .pdflatex(let p): return p
            case .unavailable: return nil
            }
        }
    }

    // MARK: - Cache

    struct CacheKey: Hashable {
        let latex: String
        let colorHex: String
    }

    private var cache: [CacheKey: (image: CGImage, naturalSize: CGSize)] = [:]
    private var _backendStatus: BackendStatus?

    // MARK: - Backend detection

    var backendStatus: BackendStatus {
        if let s = _backendStatus { return s }
        let s = Self.detectBackend()
        _backendStatus = s
        return s
    }

    static func detectBackend() -> BackendStatus {
        // MacTeX installs to /Library/TeX/texbin; Homebrew to /usr/local/bin or /opt/homebrew/bin.
        let searchDirs = ["/Library/TeX/texbin", "/usr/local/bin", "/opt/homebrew/bin"]
        for dir in searchDirs {
            let lm = "\(dir)/latexmk"
            if FileManager.default.isExecutableFile(atPath: lm) { return .latexmk(path: lm) }
        }
        if let p = which("latexmk") { return .latexmk(path: p) }
        for dir in searchDirs {
            let pl = "\(dir)/pdflatex"
            if FileManager.default.isExecutableFile(atPath: pl) { return .pdflatex(path: pl) }
        }
        if let p = which("pdflatex") { return .pdflatex(path: p) }
        return .unavailable
    }

    private static func which(_ command: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [command]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let path = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    // MARK: - Public API

    /// Returns the rendered label size (in chart points) at the given font size, or nil when LaTeX is unavailable.
    ///
    /// Sizing convention for rotated Y-axis labels:
    ///   horizontal footprint in left margin = returned size.height   (PDF height rotates to become width)
    ///   vertical footprint along axis       = returned size.width
    func labelSize(latex: String, fontSize: CGFloat) -> CGSize? {
        let key = CacheKey(latex: latex, colorHex: "000000ff")
        let natural: CGSize
        if let cached = cache[key] {
            natural = cached.naturalSize
        } else {
            guard let compiled = compile(latex: latex, colorHex: "000000ff") else {
                print("[LatexAxisLabelRenderer] LaTeX not available — falling back to MathMarkupRenderer")
                return nil
            }
            cache[key] = compiled
            natural = compiled.naturalSize
        }
        // LaTeX compiled at 12pt; scale to chart target fontSize.
        let scale = fontSize / 12.0
        return CGSize(width: natural.width * scale, height: natural.height * scale)
    }

    /// Draws the latex label into ctx at center, with optional 90° rotation for Y-axis labels.
    /// Returns false when LaTeX is unavailable so the caller can fall back.
    @discardableResult
    func draw(
        ctx: CGContext,
        latex: String,
        fontSize: CGFloat,
        color: CGColor,
        at center: CGPoint,
        orientation: Orientation
    ) -> Bool {
        let colorHex = hexString(color)
        let key = CacheKey(latex: latex, colorHex: colorHex)
        let entry: (image: CGImage, naturalSize: CGSize)
        if let cached = cache[key] {
            entry = cached
        } else {
            guard let compiled = compile(latex: latex, colorHex: colorHex) else {
                print("[LatexAxisLabelRenderer] LaTeX not available — falling back to MathMarkupRenderer")
                return false
            }
            cache[key] = compiled
            entry = compiled
        }
        let scale = fontSize / 12.0
        let drawSize = CGSize(
            width:  entry.naturalSize.width  * scale,
            height: entry.naturalSize.height * scale
        )
        ctx.saveGState()
        switch orientation {
        case .horizontal:
            let origin = CGPoint(
                x: center.x - drawSize.width  / 2,
                y: center.y - drawSize.height / 2
            )
            ctx.draw(entry.image, in: CGRect(origin: origin, size: drawSize))
        case .rotated90:
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: .pi / 2)
            let origin = CGPoint(x: -drawSize.width / 2, y: -drawSize.height / 2)
            ctx.draw(entry.image, in: CGRect(origin: origin, size: drawSize))
        }
        ctx.restoreGState()
        return true
    }

    // MARK: - Private compilation

    private func compile(latex: String, colorHex: String) -> (image: CGImage, naturalSize: CGSize)? {
        guard backendStatus.isAvailable else { return nil }
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LatexAxisLabel_\(UUID().uuidString)")
        guard (try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let texFile = tmpDir.appendingPathComponent("label.tex")
        let pdfFile = tmpDir.appendingPathComponent("label.pdf")
        guard (try? makeTexDocument(latex: latex).write(to: texFile, atomically: true, encoding: .utf8)) != nil else {
            return nil
        }
        guard runLatex(texFile: texFile, outputDir: tmpDir, pdfFile: pdfFile) else { return nil }
        return loadPDF(from: pdfFile)
    }

    private func makeTexDocument(latex: String) -> String {
        """
        \\documentclass[12pt,preview,border=2pt]{standalone}
        \\usepackage{amsmath}
        \\usepackage{amssymb}
        \\begin{document}
        $\\displaystyle \(latex)$
        \\end{document}
        """
    }

    private func runLatex(texFile: URL, outputDir: URL, pdfFile: URL) -> Bool {
        guard let execPath = backendStatus.executablePath else { return false }
        let args: [String]
        switch backendStatus {
        case .latexmk:
            args = ["-pdf", "-interaction=nonstopmode",
                    "-output-directory=\(outputDir.path)", texFile.path]
        case .pdflatex:
            args = ["-interaction=nonstopmode",
                    "-output-directory=\(outputDir.path)", texFile.path]
        case .unavailable:
            return false
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: execPath)
        proc.arguments = args
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        proc.currentDirectoryURL = outputDir
        guard (try? proc.run()) != nil else { return false }
        proc.waitUntilExit()
        return proc.terminationStatus == 0 &&
               FileManager.default.fileExists(atPath: pdfFile.path)
    }

    private func loadPDF(from url: URL) -> (image: CGImage, naturalSize: CGSize)? {
        guard let data = try? Data(contentsOf: url) as CFData,
              let provider = CGDataProvider(data: data),
              let pdfDoc = CGPDFDocument(provider),
              let page = pdfDoc.page(at: 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        // Rasterise at 2× for retina quality; image stored in cache, drawn scaled at use time.
        let renderScale: CGFloat = 2.0
        let pixelW = Int((box.width  * renderScale).rounded())
        let pixelH = Int((box.height * renderScale).rounded())
        guard let ctx = CGContext(
            data: nil, width: pixelW, height: pixelH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).rawValue
        ) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0))
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(pixelW), height: CGFloat(pixelH)))
        ctx.scaleBy(x: renderScale, y: renderScale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(page)
        guard let image = ctx.makeImage() else { return nil }
        return (image, CGSize(width: box.width, height: box.height))
    }

    private func hexString(_ color: CGColor) -> String {
        let c = color.components ?? [0, 0, 0, 1]
        let r = Int((c[0] * 255).rounded())
        let g = c.count > 1 ? Int((c[1] * 255).rounded()) : r
        let b = c.count > 2 ? Int((c[2] * 255).rounded()) : r
        let a = c.count > 3 ? Int((c[3] * 255).rounded()) : 255
        return String(format: "%02x%02x%02x%02x", r, g, b, a)
    }
}
