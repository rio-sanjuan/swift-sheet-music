#if SHEET_MUSIC_HAS_APPLE_PLATFORM_TEST_SUPPORT
    import CoreGraphics
    import Foundation
    @testable import SheetMusicCore
    @testable import SheetMusicPDF
    import Testing

    /// FretCodex fork, F8: a numeral the detector read is anchored as far from its staff and its
    /// beam as a photographed song page puts it; a PDF's own numeral as before; and one numeral
    /// read twice is one numeral.
    @Suite("FretCodex — detected tuplet numerals anchored")
    struct FretCodexTupletAnchoringTests {
        static let spatium: CGFloat = 5
        /// Lines at 100…120: the staff's top line is y 120 (y up).
        static let lines: [CGFloat] = [100, 105, 110, 115, 120]

        static func beam(y: CGFloat) -> PathSegment {
            PathSegment(
                kind: .beam, rect: CGRect(x: 50, y: y, width: 40, height: 2.5),
                lineWidth: 2.5, pageIndex: 0, quad: nil, detectedFromRaster: true,
            )
        }

        static func numeral(y: CGFloat, detected: Bool) -> TextGlyph {
            TextGlyph(
                text: "3", fontName: detected ? RasterFrontEnd.tupletNumeralFont : "Bravura Text",
                fontSize: 6, renderedSize: 6, origin: CGPoint(x: 68, y: y), bbox: .zero, pageIndex: 0,
            )
        }

        static func marks(_ numeral: TextGlyph, beamY: CGFloat) -> [PDFImporter.TupletMark] {
            PDFImporter.detectTupletMarks(
                texts: [numeral], paths: [beam(y: beamY)], staffYLines: lines, xRange: 0 ... 200, pageIndex: 0,
            )
        }

        @Test func aDetectedNumeralSixSpacesOutIsAnchoredAndAPDFsIsNot() {
            // A triplet over notes high above the staff: its beam 5 spaces up, the numeral 6.
            #expect(Self.marks(Self.numeral(y: 150, detected: true), beamY: 145).count == 1)
            #expect(Self.marks(Self.numeral(y: 150, detected: false), beamY: 145).isEmpty)
            // Past 7 spaces, nothing.
            #expect(Self.marks(Self.numeral(y: 158, detected: true), beamY: 155).isEmpty)
        }

        @Test func aDetectedNumeralFourSpacesFromItsBeamIsAnchored() {
            // Within the band either way; 4 spaces from the beam, past a PDF numeral's 3.
            #expect(Self.marks(Self.numeral(y: 134, detected: true), beamY: 114).count == 1)
            #expect(Self.marks(Self.numeral(y: 134, detected: false), beamY: 114).isEmpty)
        }

        @Test func oneNumeralReadTwiceIsOne() {
            func glyph(_ digit: Int, x: CGFloat) -> ClassifiedGlyph {
                ClassifiedGlyph(
                    geometry: GlyphGeometry(origin: CGPoint(x: x, y: 150), advance: 3.3, renderedSize: 6, pageIndex: 0, fontSize: 0),
                    semantic: .tupletDigit(digit),
                )
            }
            // A 9 and a 3 at one place, a second 3 a point away, and a 5 elsewhere.
            let (_, texts) = RasterFrontEnd.tupletNumeralsAsText(
                [glyph(9, x: 68), glyph(3, x: 68), glyph(3, x: 69), glyph(5, x: 120)], pageIndex: 0,
            )
            #expect(texts.map(\.text).sorted() == ["3", "5"])
            #expect(texts.first { $0.text == "3" }?.origin.x == 68)
        }
    }
#endif
