#if SHEET_MUSIC_HAS_APPLE_PLATFORM_TEST_SUPPORT
    import CoreGraphics
    import Foundation
    @testable import SheetMusicCore
    @testable import SheetMusicPDF
    import Testing

    /// FretCodex fork, F7: a tuplet numeral the detector reads goes to a raster page's texts.
    @Suite("FretCodex — a detected tuplet numeral read as text")
    struct FretCodexOMRTupletNumeralTests {
        static func glyph(_ semantic: SMuFLSemantic, x: CGFloat, size: CGFloat) -> ClassifiedGlyph {
            ClassifiedGlyph(
                geometry: GlyphGeometry(
                    origin: CGPoint(x: x, y: 700), advance: size * 0.55,
                    renderedSize: size, pageIndex: 2, fontSize: 0,
                ),
                semantic: semantic,
            )
        }

        @Test func aNumeralBecomesItsDigitAndEverythingElseStaysAGlyph() {
            let detected = [
                Self.glyph(.noteheadBlack, x: 100, size: 20),
                Self.glyph(.tupletDigit(3), x: 118, size: 6),
                Self.glyph(.noteheadBlack, x: 120, size: 20),
                Self.glyph(.tupletDigit(6), x: 160, size: 7),
            ]
            let (glyphs, texts) = RasterFrontEnd.tupletNumeralsAsText(detected, pageIndex: 2)
            #expect(glyphs.map(\.semantic) == [.noteheadBlack, .noteheadBlack])
            #expect(texts.map(\.text) == ["3", "6"])
            #expect(texts.map(\.origin) == [CGPoint(x: 118, y: 700), CGPoint(x: 160, y: 700)])
            // The size `digitExtent` and the tuplet anchoring measure by.
            #expect(texts.map(\.renderedSize) == [6, 7])
            #expect(texts.allSatisfy { $0.pageIndex == 2 })
        }

        /// Reads a notehead and a triplet's numeral on whatever page it is asked for.
        struct NumeralDetector: OMRGlyphDetecting {
            func glyphs(
                pageIndex: Int, analysis _: RasterPageAnalysis,
                diagnostics _: (@Sendable (PDFImportDiagnostic) -> Void)?,
            ) throws -> [ClassifiedGlyph] {
                [
                    FretCodexOMRTupletNumeralTests.glyph(.noteheadBlack, x: 100, size: 20),
                    FretCodexOMRTupletNumeralTests.glyph(.tupletDigit(3), x: 118, size: 6),
                ].map { glyph in
                    var glyph = glyph
                    glyph.geometry.pageIndex = pageIndex
                    return glyph
                }
            }
        }

        /// The fallback once merged a raster page's glyphs and paths and left its texts behind, so
        /// no numeral the detector read ever reached `detectTupletMarks`.
        @Test func theRasterFallbackKeepsTheNumeralsItRead() throws {
            let document = try PDFImporter.openDocument(
                PDFImporterRasterFallbackTests.imageOnlyPDF(PDFImporterRasterFallbackTests.staffBitmap()),
            )
            var walked = WalkedContent(glyphs: [], texts: [], paths: [], curves: [])
            var pageSizes: [Int: CGSize] = [:]
            var options = PDFImportOptions()
            options.omrRenderDPI = PDFImporterRasterFallbackTests.renderDPI
            let pages = PDFImporter.applyRasterFallback(
                to: &walked, pageSizes: &pageSizes, document: document,
                detector: NumeralDetector(), options: options,
            )
            #expect(pages == [0])
            #expect(walked.glyphs.map(\.semantic) == [.noteheadBlack])
            #expect(walked.texts.map(\.text) == ["3"])
        }

        @Test func everyNumeralClassIsInTheDetectorsVocabulary() {
            for digit in [3, 5, 6, 7, 9] {
                #expect(OMRGlyphVocabulary.semantic(forClassName: "tuplet\(digit)") == .tupletDigit(digit))
            }
        }
    }
#endif
