#if SHEET_MUSIC_HAS_APPLE_PLATFORM_TEST_SUPPORT
    import Foundation
    @testable import SheetMusicPDF
    import Testing

    /// FretCodex fork: `PDFImportOptions.omrKeepsBeamsOutOfStaffLines`. A beam is a row inked most of
    /// the way along a run long enough for a staff line; left in, it adds a sixth line to a staff or
    /// joins two of its lines into one.
    @Suite("FretCodex — beams kept out of the raster staff lines")
    struct FretCodexOMRBeamLineTests {
        static let width = 1000, height = 300, spacing = 20

        /// Five lines two rows thick at rows 100, 120 … 180, across the page, and ink in `boxes`
        /// (columns, rows).
        static func mask(_ boxes: [(Range<Int>, Range<Int>)]) -> InkMask {
            var bits = [Bool](repeating: false, count: width * height)
            for line in 0 ..< 5 {
                for row in 100 + line * spacing ..< 102 + line * spacing {
                    for x in 0 ..< width {
                        bits[row * width + x] = true
                    }
                }
            }
            for (columns, rows) in boxes {
                for row in rows {
                    for x in columns {
                        bits[row * width + x] = true
                    }
                }
            }
            return InkMask(bits: bits, width: width, height: height)
        }

        /// The lines found, at 200 dpi: a 50-point line is 139 pixels.
        static func lines(_ mask: InkMask, keepingBeamsOut: Bool) -> Int {
            let transform = PageTransform(dpi: 200, widthPx: width, heightPx: height, deskewDegrees: 0)
            return RasterPage.staffLineSegments(
                mask, spacingPx: Double(spacing), transform: transform, pageIndex: 0,
                keepsBeamsOut: keepingBeamsOut,
            ).count
        }

        /// A beam half a space thick inside the second space, 20 spaces long: a sixth line.
        @Test func aBeamWithinASpaceIsNotALine() {
            let mask = Self.mask([(300 ..< 700, 125 ..< 135)])
            #expect(Self.lines(mask, keepingBeamsOut: false) == 6)
            #expect(Self.lines(mask, keepingBeamsOut: true) == 5)
        }

        /// A beam filling the first space from line to line: the two lines are one blob.
        @Test func aBeamAcrossASpaceKeepsBothLines() {
            let mask = Self.mask([(300 ..< 500, 102 ..< 120)])
            #expect(Self.lines(mask, keepingBeamsOut: false) == 4)
            #expect(Self.lines(mask, keepingBeamsOut: true) == 5)
        }

        /// A beam lying on a line, along most of it, leaves the line where it was.
        @Test func aLineABeamLiesOnIsKept() {
            let mask = Self.mask([(100 ..< 900, 140 ..< 150)])
            #expect(Self.lines(mask, keepingBeamsOut: true) == 5)
        }

        /// A line worn through in one row is one line, not two.
        @Test func aWornLineIsOneLine() {
            var mask = Self.mask([(0 ..< Self.width, 160 ..< 163)])
            for x in 0 ..< 700 {
                mask[x, 161] = false
            }
            #expect(Self.lines(mask, keepingBeamsOut: true) == 5)
        }
    }
#endif
