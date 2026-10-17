#if SHEET_MUSIC_HAS_APPLE_PLATFORM_TEST_SUPPORT
    import CoreGraphics
    import Foundation
    @testable import SheetMusicCore
    @testable import SheetMusicPDF
    import Testing

    /// FretCodex fork: `PDFImportOptions.omrStemHeadEndTolerance`, `isStem`'s notehead-end gate set
    /// for one parse.
    @Suite("FretCodex — the raster stem gate, for one parse")
    struct FretCodexOMRStemToleranceTests {
        static let spatium: CGFloat = 5
        static let staffYLines: [CGFloat] = [100, 105, 110, 115, 120]

        static let head = ClassifiedGlyph(
            geometry: GlyphGeometry(
                origin: CGPoint(x: 50, y: 110), advance: spatium * 1.2,
                renderedSize: spatium * 4, pageIndex: 0, fontSize: 0,
            ),
            semantic: .noteheadBlack,
        )

        /// A raster stem beside the head whose nearer end stops 0.6 of a space short of it.
        static let stem = PathSegment(
            kind: .vertical,
            rect: CGRect(x: 50 + spatium * 1.2, y: 110 + 0.6 * spatium, width: 0, height: spatium * 3),
            lineWidth: 0.7, pageIndex: 0, quad: nil, detectedFromRaster: true,
        )

        static func isStem(tolerance: CGFloat?) -> Bool {
            let measure = ImportMeasure(xRange: 0 ... 200, glyphs: [head], staffYLines: staffYLines)
            if let tolerance {
                return PDFImporter.isStem(
                    in: measure, stem, noteheads: [head], spatium: spatium, headEndTolerance: tolerance,
                )
            }
            return PDFImporter.isStem(in: measure, stem, noteheads: [head], spatium: spatium)
        }

        @Test func theMeasuredGateRefusesAStemEndingAwayFromItsHead() {
            #expect(!Self.isStem(tolerance: nil))
            #expect(PDFImportOptions().omrStemHeadEndTolerance == nil)
        }

        @Test func aWiderGateForOneParseAdmitsIt() {
            #expect(Self.isStem(tolerance: 0.75))
            #expect(!Self.isStem(tolerance: 0.5))
        }
    }
#endif
