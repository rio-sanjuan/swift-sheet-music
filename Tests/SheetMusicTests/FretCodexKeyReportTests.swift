#if SHEET_MUSIC_HAS_APPLE_PLATFORM_TEST_SUPPORT
    import CoreGraphics
    import Foundation
    import SheetMusicCore
    @testable import SheetMusicPDF
    import Testing

    /// FretCodex fork: `PDFImportOptions.omrReportsKeyReadings`. The score holds a key signature only
    /// where the key changes; the report says what each system read, and what courtesy key it ends
    /// with.
    @Suite("FretCodex — every system's key reading reported")
    struct FretCodexKeyReportTests {
        static let yLines: [CGFloat] = [490, 495, 500, 505, 510]
        static let sharpLadder = [8, 5, 9, 6, 3, 7, 4]

        static func glyph(_ semantic: SMuFLSemantic, x: CGFloat, sa: Int) -> ClassifiedGlyph {
            ClassifiedGlyph(
                geometry: GlyphGeometry(origin: CGPoint(x: x, y: 490 + CGFloat(sa) * 2.5), advance: 5, pageIndex: 0, fontSize: 20),
                semantic: semantic,
            )
        }

        static func sharps(_ count: Int, from x: CGFloat) -> [ClassifiedGlyph] {
            (0 ..< count).map { glyph(.accidentalSharp, x: x + CGFloat($0) * 6, sa: sharpLadder[$0]) }
        }

        /// Two bars: a treble clef and `start` sharps, a note; a note, and `courtesy` sharps after it.
        static func staff(start: Int, courtesy: Int) -> ImportStaff {
            func measure(_ range: ClosedRange<CGFloat>, _ glyphs: [ClassifiedGlyph]) -> ImportMeasure {
                ImportMeasure(xRange: range, glyphs: glyphs, leadingBarline: nil, trailingBarline: nil, staffYLines: yLines)
            }
            return ImportStaff(
                staff: SheetMusicPDF.Staff(pageIndex: 0, yLines: yLines, xRange: 50 ... 550, barlineCandidates: []),
                measures: [
                    measure(50 ... 300, [glyph(.clefG, x: 60, sa: 2)] + sharps(start, from: 80) + [glyph(.noteheadBlack, x: 200, sa: 4)]),
                    measure(300 ... 550, [glyph(.noteheadBlack, x: 350, sa: 4)] + sharps(courtesy, from: 500)),
                ],
            )
        }

        static func reports(_ staff: ImportStaff, reporting: Bool = true) -> [String] {
            var said: [PDFImportDiagnostic] = []
            _ = PDFImporter.scoreStateEvents(
                staff: staff, texts: [], diagnostics: { said.append($0) }, location: "page 0, system 1",
                reportsKeys: reporting,
            )
            return said.filter { $0.message.hasPrefix("key signature read") }.map { "\($0.location): \($0.message)" }
        }

        @Test func eachSystemSaysWhatItReadAndWhatItAnnounces() {
            #expect(Self.reports(Self.staff(start: 2, courtesy: 3)) == [
                "page 0, system 1, measure 0: key signature read at this system's start: 2",
                "page 0, system 1, measure 1: key signature read at this system's end: 3",
            ])
            #expect(Self.reports(Self.staff(start: 0, courtesy: 0)) == [
                "page 0, system 1, measure 0: key signature read at this system's start: none",
            ])
        }

        /// Past the system's final barline, the courtesy is a cell of its own, dropped as
        /// content-free; its glyphs ride with the last measure and are read there.
        @Test func aCourtesyPastTheFinalBarlineIsRead() {
            var staff = Self.staff(start: 2, courtesy: 0)
            staff.measures[1].droppedTrailingGlyphs = Self.sharps(3, from: 560)
            #expect(Self.reports(staff) == [
                "page 0, system 1, measure 0: key signature read at this system's start: 2",
                "page 0, system 1, measure 1: key signature read at this system's end: 3",
            ])
            // And nothing else reads them: the bars' keys are as before.
            let events = PDFImporter.scoreStateEvents(staff: staff, texts: [], reportsKeys: true)
            #expect(events.compactMap { if case let .keySignature(key, atMeasureIndex: _) = $0 { key.concertKey } else { nil } } == [2])
        }

        @Test func nothingIsSaidUnlessAsked() {
            #expect(Self.reports(Self.staff(start: 2, courtesy: 3), reporting: false).isEmpty)
            #expect(!PDFImportOptions().omrReportsKeyReadings)
        }

        /// The courtesy is read for the report only: the key in force is the one the bars read.
        @Test func aCourtesyChangesNoKey() {
            let events = PDFImporter.scoreStateEvents(staff: Self.staff(start: 2, courtesy: 3), texts: [], reportsKeys: true)
            let keys: [Int] = events.compactMap {
                if case let .keySignature(key, atMeasureIndex: _) = $0 { key.concertKey } else { nil }
            }
            #expect(keys == [2])
        }
    }
#endif
