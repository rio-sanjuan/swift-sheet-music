#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Foundation
import SheetMusicCore

/// One rasterized page → the `buildScore` inputs for it.
///
/// This is the product path. `OMRHybridFrontEnd` in the tests keeps its
/// bisect modes as substitutions around this call, so there is exactly one
/// implementation and one set of numbers.
enum RasterFrontEnd {
    static func page(
        bitmap: GrayBitmap, pageIndex: Int, detector: any OMRGlyphDetecting,
        diagnostics: (@Sendable (PDFImportDiagnostic) -> Void)?, keepsBeamsOutOfLines: Bool = false,
    ) throws -> (walked: WalkedContent, pageSize: CGSize) {
        // keepDeskewed: the detector consumes the deskewed grayscale. It is
        // opt-in because a page is ~18MB and holding one per page multiplies a
        // sweep's peak RSS by the page count — so the analysis dies here, with
        // this function's frame.
        let analysis = RasterPage.analyze(
            bitmap, pageIndex: pageIndex, keepDeskewed: true, keepsBeamsOutOfLines: keepsBeamsOutOfLines,
        )
        return try assembled(
            analysis: analysis, pageIndex: pageIndex, detector: detector,
            diagnostics: diagnostics,
        )
    }

    /// The assembly step alone, for a caller that already holds the raster
    /// analysis. REQUIRES `analysis.deskewed != nil` (built via
    /// `RasterPage.analyze(_:pageIndex:keepDeskewed: true)`) — throws
    /// otherwise, rather than handing the detector an analysis it will
    /// silently do nothing with.
    ///
    /// The eval harness computes `RasterPageAnalysis` once per page (with
    /// `keepDeskewed: true`) because its bisect modes need it too, and
    /// re-running `RasterPage.analyze` here would pay for a second
    /// classical-CV pass over the same bitmap for no reason — this is the
    /// seam `.full` and `.detectorGlyphs` route through so their numbers
    /// and the product path's stay one computation, not two that happen to
    /// agree today.
    ///
    /// The `deskewed` check exists because `assembled` is `internal`, so
    /// it is reachable by every future caller in this module — not just
    /// `page` above and today's eval harness. `OMRGlyphDetector.glyphs`
    /// returns `[]` with NO inference and, if `diagnostics` is `nil`, no
    /// diagnostic either when handed an analysis without `deskewed` — the
    /// exact "many successful-looking rows, zero notes, no error" failure
    /// a previous task's fix round removed from the harness. Enforcing it
    /// here closes the same hole at the interface, not just at today's one
    /// call site.
    static func assembled(
        analysis: RasterPageAnalysis, pageIndex: Int, detector: any OMRGlyphDetecting,
        diagnostics: (@Sendable (PDFImportDiagnostic) -> Void)?,
    ) throws -> (walked: WalkedContent, pageSize: CGSize) {
        guard analysis.deskewed != nil else {
            throw SheetMusicError.malformedScore(ScoreFault(
                code: "omr.rasterFrontEnd.missingDeskewed",
                message: "RasterFrontEnd.assembled: analysis for page \(pageIndex) has no "
                    + "deskewed bitmap — build it with "
                    + "RasterPage.analyze(_:pageIndex:keepDeskewed: true), or the detector "
                    + "silently returns no glyphs with no diagnostic",
            ))
        }
        let detected = try detector.glyphs(
            pageIndex: pageIndex, analysis: analysis, diagnostics: diagnostics,
        )
        // FretCodex fork, F7: the detector's tuplet numerals go to the page's texts
        // (`tupletNumeralsAsText`). Otherwise texts and curves stay empty: no OCR, no curve
        // detector, so a raster page carries no title, lyrics, tempo text or ties.
        let (glyphs, texts) = Self.tupletNumeralsAsText(detected, pageIndex: pageIndex)
        let walked = WalkedContent(glyphs: glyphs, texts: texts, paths: analysis.paths, curves: [])
        return (walked, analysis.pageSizePt)
    }
}

extension RasterFrontEnd {
    /// The font name a detected tuplet numeral carries as text (`TextGlyph.isDetectedNumeral`).
    static let tupletNumeralFont = "OMR-tuplet"

    /// FretCodex fork, F7: `detected` with each tuplet numeral the detector read (`tuplet3`…
    /// `tuplet9`) taken out of the glyphs and given to the page's texts as the digit it is, at its
    /// origin and size. A vector page carries the numeral as text, so `detectTupletMarks` anchors
    /// it to its beam or bracket from there, as it does a vector page's.
    static func tupletNumeralsAsText(
        _ detected: [ClassifiedGlyph], pageIndex: Int,
    ) -> (glyphs: [ClassifiedGlyph], texts: [TextGlyph]) {
        var glyphs: [ClassifiedGlyph] = []
        var numerals: [(digit: Int, geometry: GlyphGeometry)] = []
        for glyph in detected {
            if case let .tupletDigit(digit) = glyph.semantic {
                numerals.append((digit, glyph.geometry))
            } else {
                glyphs.append(glyph)
            }
        }
        // F8: one numeral to a place. The detector can read one numeral twice — as two classes
        // at once (a 3 and a 9), or as one class a point apart across a tile seam — and a second
        // mark at the same place finds its notes taken or names the wrong ratio. Of numerals
        // closer than half their size, the commoner digit is kept, then the first read.
        let commonness = [3, 6, 5, 7, 9]
        let ordered = numerals.indices.sorted { a, b in
            let ra = commonness.firstIndex(of: numerals[a].digit) ?? commonness.count
            let rb = commonness.firstIndex(of: numerals[b].digit) ?? commonness.count
            return ra != rb ? ra < rb : a < b
        }.map { numerals[$0] }
        var kept: [(digit: Int, geometry: GlyphGeometry)] = []
        for numeral in ordered {
            let o = numeral.geometry.origin, reach = 0.5 * numeral.geometry.renderedSize
            guard !kept.contains(where: { abs($0.geometry.origin.x - o.x) < reach && abs($0.geometry.origin.y - o.y) < reach })
            else { continue }
            kept.append(numeral)
        }
        let texts = kept.map { numeral in
            TextGlyph(
                text: String(numeral.digit), fontName: tupletNumeralFont,
                fontSize: numeral.geometry.renderedSize, renderedSize: numeral.geometry.renderedSize,
                origin: numeral.geometry.origin, bbox: .zero, pageIndex: pageIndex,
            )
        }
        return (glyphs, texts)
    }
}

extension TextGlyph {
    /// FretCodex fork, F8: whether the detector read this text, a tuplet numeral on a raster page
    /// (`RasterFrontEnd.tupletNumeralsAsText`), rather than a PDF's text layer carrying it.
    var isDetectedNumeral: Bool { fontName == RasterFrontEnd.tupletNumeralFont }
}
