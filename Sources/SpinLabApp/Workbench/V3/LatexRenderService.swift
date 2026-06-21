import Foundation
import CoreGraphics

// MARK: - Backend protocol

/// Low-level LaTeX compilation contract.
/// The real implementation runs latexmk / pdflatex as a subprocess.
/// Test implementations return fixed assets without touching the filesystem.
protocol LatexRenderBackend {
    var isAvailable: Bool { get }
    /// Compile a LaTeX formula body and return the rasterised image plus its natural size in PDF points.
    func compile(latex: String) -> (image: CGImage, naturalSize: CGSize)?
}

// MARK: - General rendering service

/// General LaTeX formula rendering service.
///
/// Owns: backend detection, .tex document generation, LaTeX subprocess invocation,
/// PDF rasterisation, and a result cache keyed by (latex, colorHex, pixelScale).
///
/// This type has no axis semantics.  Callers that need axis-specific logic
/// (label prefix detection, orientation, footprint conventions) use LatexAxisLabelRenderer.
final class LatexRenderService {

    static let shared = LatexRenderService()

    // MARK: - Types

    struct CacheKey: Hashable {
        let latex: String
        let colorHex: String
        let pixelScale: CGFloat
    }

    struct RenderedAsset {
        let image: CGImage
        let naturalSize: CGSize  // PDF points at 12pt LaTeX compile size
    }

    // MARK: - State

    private var cache: [CacheKey: RenderedAsset] = [:]
    let backend: LatexRenderBackend

    // MARK: - Init (injectable for tests)

    init(backend: LatexRenderBackend = LocalLatexBackend()) {
        self.backend = backend
    }

    // MARK: - Availability

    var isAvailable: Bool { backend.isAvailable }

    // MARK: - Measurement API (no axis semantics)

    /// Returns the rendered natural size of the formula at the given fontSize, or nil when unavailable.
    ///
    /// The formula is compiled at 12pt LaTeX size and the result is scaled by (fontSize / 12).
    func naturalSize(
        latex: String,
        fontSize: CGFloat,
        color: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    ) -> CGSize? {
        guard let asset = render(latex: latex, color: color) else { return nil }
        let scale = fontSize / 12.0
        return CGSize(width: asset.naturalSize.width * scale, height: asset.naturalSize.height * scale)
    }

    // MARK: - Render API (no axis semantics)

    /// Returns a rendered asset (CGImage + natural PDF size) from cache or by compiling.
    /// pixelScale controls rasterisation density (2.0 = retina quality).
    @discardableResult
    func render(
        latex: String,
        color: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        pixelScale: CGFloat = 2.0
    ) -> RenderedAsset? {
        let key = CacheKey(latex: latex, colorHex: hexString(color), pixelScale: pixelScale)
        if let cached = cache[key] { return cached }
        guard let (image, naturalSize) = backend.compile(latex: latex) else {
            print("[LatexRenderService] Backend unavailable — cannot compile formula")
            return nil
        }
        let asset = RenderedAsset(image: image, naturalSize: naturalSize)
        cache[key] = asset
        return asset
    }

    // MARK: - Helpers

    static func hexString(_ color: CGColor) -> String {
        let c = color.components ?? [0, 0, 0, 1]
        let r = Int((c[0] * 255).rounded())
        let g = c.count > 1 ? Int((c[1] * 255).rounded()) : r
        let b = c.count > 2 ? Int((c[2] * 255).rounded()) : r
        let a = c.count > 3 ? Int((c[3] * 255).rounded()) : 255
        return String(format: "%02x%02x%02x%02x", r, g, b, a)
    }

    private func hexString(_ color: CGColor) -> String { Self.hexString(color) }
}

// MARK: - Real backend (local LaTeX subprocess)

/// Invokes a local latexmk or pdflatex installation to compile LaTeX formulas.
final class LocalLatexBackend: LatexRenderBackend {

    enum Status: Equatable {
        case latexmk(path: String)
        case pdflatex(path: String)
        case unavailable

        var executablePath: String? {
            switch self {
            case .latexmk(let p): return p
            case .pdflatex(let p): return p
            case .unavailable: return nil
            }
        }
    }

    let status: Status

    init() { self.status = Self.detect() }

    /// Designated init for tests that need a known status without filesystem probing.
    init(status: Status) { self.status = status }

    var isAvailable: Bool { status != .unavailable }

    // MARK: - Backend detection

    static func detect() -> Status {
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

    // MARK: - LatexRenderBackend

    func compile(latex: String) -> (image: CGImage, naturalSize: CGSize)? {
        guard isAvailable else { return nil }
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LatexRender_\(UUID().uuidString)")
        guard (try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let texFile = tmpDir.appendingPathComponent("formula.tex")
        let pdfFile = tmpDir.appendingPathComponent("formula.pdf")
        guard (try? makeTexDocument(latex: latex).write(to: texFile, atomically: true, encoding: .utf8)) != nil else {
            return nil
        }
        guard runLatex(texFile: texFile, outputDir: tmpDir, pdfFile: pdfFile) else { return nil }
        return rasterizePDF(at: pdfFile)
    }

    // MARK: - Private

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
        guard let execPath = status.executablePath else { return false }
        let args: [String]
        switch status {
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

    private func rasterizePDF(at url: URL) -> (image: CGImage, naturalSize: CGSize)? {
        guard let data = try? Data(contentsOf: url) as CFData,
              let provider = CGDataProvider(data: data),
              let pdfDoc = CGPDFDocument(provider),
              let page = pdfDoc.page(at: 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        // Rasterise at 2× for retina quality; image is stored in the LatexRenderService cache.
        let rasterScale: CGFloat = 2.0
        let pixelW = Int((box.width  * rasterScale).rounded())
        let pixelH = Int((box.height * rasterScale).rounded())
        guard let ctx = CGContext(
            data: nil, width: pixelW, height: pixelH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).rawValue
        ) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0))
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(pixelW), height: CGFloat(pixelH)))
        ctx.scaleBy(x: rasterScale, y: rasterScale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(page)
        guard let image = ctx.makeImage() else { return nil }
        return (image, CGSize(width: box.width, height: box.height))
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
}
