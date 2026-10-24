#if SHEET_MUSIC_HAS_APPLE_PLATFORM_TEST_SUPPORT
    import CoreGraphics
    import Foundation
    import SheetMusicLayoutApple
    @testable import SheetMusicCore
    @testable import SheetMusicMSCX
    @testable import SheetMusicPDF
    import Testing

    /// FretCodex fork, F7: `.numeralRevert`, on raster-like pages that keep some of their tuplet
    /// numerals — those a detector read — and not the rest.
    @MainActor
    @Suite("FretCodex — the raster bar repair (F7): numerals set aside")
    struct FretCodexNumeralRevertTests {
        typealias T = FretCodexBarRepairTests

        /// `data` read raster-like, keeping the numerals `keeps` chooses.
        static func rasterLike(_ data: Data, options: PDFImportOptions, keeps: ([TextGlyph]) -> [TextGlyph]) throws -> Score {
            let document = try PDFImporter.openDocument(data)
            let walk = try PDFImporter.walkDocument(document)
            var content = walk.content
            content.paths = content.paths.map {
                var path = $0
                path.detectedFromRaster = true
                return path
            }
            content.texts = keeps(content.texts)
            content.curves = []
            return try PDFImporter.buildScore(
                pageCount: document.pageCount, walked: content, pageSizes: walk.pageSizes,
                documentAttributes: walk.attributes, options: options,
                rasterPages: Set(0 ..< document.pageCount),
            )
        }

        /// Continuous triplets with some of their numerals read — every other one, or all — and
        /// a voice that has numerals on some of its groups: the search, one tuplet at most, could
        /// not finish the run the marks began. Read without them, the bar is the run F6 reads.
        @Test(.enabled(if: T.bravuraAvailable))
        func tripletsWithSomeNumeralsReadReadWholeAsTriplets() throws {
            guard #available(macOS 15.0, iOS 16.0, *) else { return }
            let data = try PDFExporter.export(score: FretCodexBarRepairF6Tests.tripletRuns())
            var without = BarRepairPasses.all
            without.remove(.numeralRevert)
            let everyOther = { (texts: [TextGlyph]) in texts.enumerated().filter { $0.offset % 2 == 0 }.map(\.element) }
            for keeps in [everyOther, { $0 }] {
                let before = FretCodexBarRepairF6Tests.tripletNotes(try Self.rasterLike(data, options: T.repairOn(without), keeps: keeps))
                let after = FretCodexBarRepairF6Tests.tripletNotes(try Self.rasterLike(data, options: T.repairOn(.all), keeps: keeps))
                #expect(before.eighths > 0, "\(before)")
                #expect(after.triplets == 27 && after.eighths == 0 && after.notes == 36, "\(after)")
            }
        }

        /// No numeral read, nothing to set aside: the page reads as F6 reads it.
        @Test(.enabled(if: T.bravuraAvailable))
        func withNoNumeralThePassChangesNothing() throws {
            guard #available(macOS 15.0, iOS 16.0, *) else { return }
            let data = try PDFExporter.export(score: FretCodexBarRepairF6Tests.tripletRuns())
            var without = BarRepairPasses.all
            without.remove(.numeralRevert)
            let none = { (_: [TextGlyph]) in [TextGlyph]() }
            #expect(try Self.rasterLike(data, options: T.repairOn(without), keeps: none)
                == Self.rasterLike(data, options: T.repairOn(.all), keeps: none))
        }
    }
#endif
