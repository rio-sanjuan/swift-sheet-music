#if SHEET_MUSIC_HAS_APPLE_PLATFORM_TEST_SUPPORT
    import CoreGraphics
    import Foundation
    @testable import SheetMusicPDF
    import Testing

    /// FretCodex fork, F12: beams read net of a page's ink spread (`omrBeamInkSpread`).
    @Suite("FretCodex — beams on a page printed bolder than the engraving")
    struct FretCodexBeamInkSpreadTests {
        typealias T = RasterBeamTests

        /// Three beams `thickness` px thick across a 12 px staff space, over five staff lines
        /// `line` px thick — a photographed page's are bolder than the engraving's.
        static func page(thickness: Int, line: Int) -> GrayBitmap {
            var bmp = RasterTestBitmaps.blank(widthPx: 400, heightPx: 260, dpi: 300)
            for i in 0 ..< 5 {
                for x in 20 ..< 380 { RasterTestBitmaps.vLine(&bmp, x: x, y0: 160 + 12 * i, y1: 160 + 12 * i + line, thickness: 1) }
            }
            for (i, y) in [30, 70, 110].enumerated() {
                T.slopedBeam(&bmp, x0: 60 + 20 * i, x1: 300, y0: y, dy: 0, thickness: thickness)
            }
            return bmp
        }

        static func beams(_ bmp: GrayBitmap, spread: Bool) -> [PathSegment] {
            RasterPage.beamSegments(
                RasterPage.binarize(bmp), spacingPx: T.spacing, transform: T.transform(bmp), pageIndex: 0,
                measuresInkSpread: spread,
            )
        }

        @Test func boldBeamsLostOnTheLadderAreFoundNetOfTheSpread() {
            // 9 px is 0.75 spaces: past the single beam's rung (6 ± 2.5) and short of the
            // double's (15 ± 2.5).
            let bmp = Self.page(thickness: 9, line: 2)
            #expect(RasterPage.inkSpreadPx(RasterPage.binarize(bmp), spacingPx: T.spacing) == 3)
            #expect(Self.beams(bmp, spread: false).isEmpty)
            #expect(Self.beams(bmp, spread: true).count == 3)
        }

        @Test func anEngravedPageSpreadsNothingAndReadsAsBefore() {
            let bmp = Self.page(thickness: 6, line: 1)
            #expect(RasterPage.inkSpreadPx(RasterPage.binarize(bmp), spacingPx: T.spacing) == 0)
            let off = Self.beams(bmp, spread: false), on = Self.beams(bmp, spread: true)
            #expect(off.count == 3)
            #expect(on.map(\.rect) == off.map(\.rect))
        }

        @Test func aSpreadWithinTheLaddersToleranceIsNone() {
            // The single beam's rung takes 2.5 px either way at a 12 px space: a beam a pixel bold
            // stays on it, and counts for nothing; two pixels bolder is half the tolerance and more.
            #expect(RasterPage.inkSpreadPx(RasterPage.binarize(Self.page(thickness: 7, line: 1)), spacingPx: 12) == 0)
            #expect(RasterPage.inkSpreadPx(RasterPage.binarize(Self.page(thickness: 8, line: 1)), spacingPx: 12) == 2)
            // Thinner than engraved is not a spread.
            #expect(RasterPage.inkSpreadPx(RasterPage.binarize(Self.page(thickness: 5, line: 1)), spacingPx: 12) == 0)
        }

        @Test func noteheadsOutCountingTheBeamsAreNotTakenForThem() {
            // A page of few beams and many heads, whose middle columns run 0.95 spaces.
            var bmp = Self.page(thickness: 6, line: 1)
            for i in 0 ..< 40 {
                RasterTestBitmaps.vLine(&bmp, x: 10 + 9 * i, y0: 200, y1: 211, thickness: 6)
            }
            #expect(RasterPage.inkSpreadPx(RasterPage.binarize(bmp), spacingPx: T.spacing) == 0)
        }

        @Test func theOptionIsOffByDefault() {
            #expect(PDFImportOptions().omrBeamInkSpread == false)
        }
    }
#endif
