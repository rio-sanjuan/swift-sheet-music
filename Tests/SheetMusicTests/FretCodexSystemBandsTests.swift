#if SHEET_MUSIC_HAS_APPLE_PLATFORM_TEST_SUPPORT
    import CoreGraphics
    import Foundation
    @testable import SheetMusicPDF
    import Testing

    /// FretCodex fork: `PDFImportOptions.omrSystemBands`. A raster page joins a system's staves only
    /// by a vertical run that covers them; a host that has found the systems on the picture says
    /// where they lie instead.
    @Suite("FretCodex — systems where the host says they are")
    struct FretCodexSystemBandsTests {
        static func staff(_ top: CGFloat) -> SheetMusicPDF.Staff {
            SheetMusicPDF.Staff(pageIndex: 0, yLines: (0 ..< 5).map { top - CGFloat($0) * 5 }, xRange: 50 ... 550, barlineCandidates: [])
        }

        /// Two songs' systems of three staves — a voice, then a piano's two hands — top to bottom.
        static let staves = [700, 650, 610, 500, 450, 410].map(staff)

        @Test func stavesInOneBandAreOneSystemAndAStaffInNoneIsItsOwn() {
            let systems = PDFImporter.bandedSystems(Self.staves, bands: [595 ... 705, 395 ... 505])
            #expect(systems.map(\.count) == [3, 3])
            // A band that misses the last staff leaves it a system of its own.
            #expect(PDFImporter.bandedSystems(Self.staves, bands: [595 ... 705, 440 ... 505]).map(\.count) == [3, 2, 1])
        }

        @Test func withoutBandsSystemsAreFoundAsBefore() {
            #expect(PDFImportOptions().omrSystemBands == nil)
            // No vertical run joins these staves, and no ensemble size is known: the gaps alone
            // decide, as upstream does.
            let systems = PDFImporter.layoutSystems(staves: Self.staves, paths: [], classified: [], pageIndex: 0)
            let banded = PDFImporter.layoutSystems(staves: Self.staves, paths: [], classified: [], pageIndex: 0,
                                                   systemBands: [595 ... 705, 395 ... 505])
            #expect(banded.count == 2)
            #expect(!systems.isEmpty)
        }
    }
#endif
