#if SHEET_MUSIC_HAS_APPLE_PLATFORM_TEST_SUPPORT
    import CoreGraphics
    import Foundation
    @testable import SheetMusicCore
    @testable import SheetMusicPDF
    import Testing

    /// FretCodex fork, F11: the detector's score reaches a numeral it read; a weak one scales no
    /// notes under a beam far longer than its tuplet, and a weak 6 is set aside.
    @Suite("FretCodex — detected numerals' evidence")
    struct FretCodexNumeralEvidenceTests {
        static let spatium: CGFloat = 5
        /// Lines at 100…120: the staff's top line is y 120 (y up).
        static let lines: [CGFloat] = [100, 105, 110, 115, 120]

        static func beam(y: CGFloat) -> PathSegment {
            PathSegment(
                kind: .beam, rect: CGRect(x: 50, y: y, width: 40, height: 2.5),
                lineWidth: 2.5, pageIndex: 0, quad: nil, detectedFromRaster: true,
            )
        }

        /// A numeral the detector read with `score`, or a PDF's own when `score` is nil.
        static func numeral(_ digit: String = "3", y: CGFloat, score: Double?) -> TextGlyph {
            TextGlyph(
                text: digit, fontName: score == nil ? "Bravura Text" : RasterFrontEnd.tupletNumeralFont,
                fontSize: 6, renderedSize: 6, origin: CGPoint(x: 68, y: y), bbox: .zero, pageIndex: 0,
                detectorScore: score,
            )
        }

        static func marks(_ numeral: TextGlyph, beamY: CGFloat) -> [PDFImporter.TupletMark] {
            PDFImporter.detectTupletMarks(
                texts: [numeral], paths: [beam(y: beamY)], staffYLines: lines, xRange: 0 ... 200, pageIndex: 0,
            )
        }

        @Test func theDetectorsScoreReachesTheNumeral() {
            let glyph = ClassifiedGlyph(
                geometry: GlyphGeometry(origin: CGPoint(x: 68, y: 150), advance: 3.3, renderedSize: 6, pageIndex: 0, fontSize: 0),
                semantic: .tupletDigit(3), score: 0.42,
            )
            let (_, texts) = RasterFrontEnd.tupletNumeralsAsText([glyph], pageIndex: 0)
            #expect(texts.map(\.detectorScore) == [0.42])
        }

        @Test func aWeakNumeralIsMarkedWeak() {
            #expect(Self.marks(Self.numeral(y: 134, score: 0.33), beamY: 122).map(\.weak) == [true])
            #expect(Self.marks(Self.numeral(y: 134, score: 0.6), beamY: 122).map(\.weak) == [false])
            #expect(Self.marks(Self.numeral(y: 134, score: nil), beamY: 122).map(\.weak) == [false])
        }

        static func eighths(_ count: Int) -> [RhythmElement] {
            (0 ..< count).map {
                RhythmElement(chord: Chord(duration: .eighth, notes: [Note(pitch: 60, tpc: 14)]), x: 100 + CGFloat($0) * 10, y: 0)
            }
        }

        static func scaled(_ elements: [RhythmElement], weak: Bool) -> Int {
            let span = elements.first!.x ... elements.last!.x
            let mark = PDFImporter.TupletMark(
                xRange: span, normal: 2, actual: 3, digitCenterX: elements[1].x,
                digitOrigin: .zero, anchor: .beam, weak: weak,
            )
            return PDFImporter.applyTupletMarks(elements: elements, marks: [mark], spatium: spatium).count(where: \.inTuplet)
        }

        @Test func aWeakNumeralOverALongBeamScalesNothing() {
            // A beam over 8 eighths: a weak 3 under it is no evidence, a confident one finds its
            // triplet in it as before.
            #expect(Self.scaled(Self.eighths(8), weak: true) == 0)
            #expect(Self.scaled(Self.eighths(8), weak: false) == 3)
            // Over 3, or two triplets' 6 under one primary, a weak 3 is read.
            #expect(Self.scaled(Self.eighths(3), weak: true) == 3)
            #expect(Self.scaled(Self.eighths(6), weak: true) == 3)
        }

        @Test func aWeakSixIsSetAside() {
            #expect(Self.marks(Self.numeral("6", y: 134, score: 0.36), beamY: 122).isEmpty)
            #expect(Self.marks(Self.numeral("6", y: 134, score: 0.5), beamY: 122).map(\.actual) == [6])
            #expect(Self.marks(Self.numeral("6", y: 134, score: nil), beamY: 122).map(\.actual) == [6])
            // Other weak digits are kept.
            #expect(Self.marks(Self.numeral("5", y: 134, score: 0.36), beamY: 122).map(\.actual) == [5])
        }
    }
#endif
