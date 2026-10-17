#if SHEET_MUSIC_HAS_APPLE_PLATFORM_TEST_SUPPORT
    import CoreGraphics
    import Foundation
    @testable import SheetMusicPDF
    import Testing

    /// FretCodex fork: `PDFImportOptions.omrCouplesByStaves`. A raster system's staves are coupled
    /// into parts by a brace the detector sees in one system and misses in the next; one coupled
    /// unlike the reference loses a staff when it is mapped part by part.
    @Suite("FretCodex — systems coupled unlike the reference")
    struct FretCodexCouplingTests {
        static func staff(_ top: CGFloat) -> ImportStaff {
            ImportStaff(
                staff: SheetMusicPDF.Staff(
                    pageIndex: 0, yLines: (0 ..< 5).map { top - CGFloat($0) * 5 }, xRange: 50 ... 550,
                    barlineCandidates: [],
                ),
                measures: [],
            )
        }

        /// A grand staff: one part of two staves when the brace was read, else two parts of one.
        static func system(braced: Bool) -> ImportSystem {
            let treble = staff(700), bass = staff(650)
            return ImportSystem(
                pageIndex: 0, yRange: 600 ... 720,
                parts: braced ? [ImportPart(staves: [treble, bass])]
                    : [ImportPart(staves: [treble]), ImportPart(staves: [bass])],
            )
        }

        static let systems = [system(braced: true), system(braced: false), system(braced: false)]

        @Test func partByPartASystemCoupledUnlikeTheFirstLosesAStaff() throws {
            let reference = try #require(PDFImporter.referenceSystem(Self.systems, couplesByStaves: false))
            #expect(reference.parts.count == 1)
            let shape = PDFImporter.partShape(from: reference)
            // The second part has no slots: its staff is dropped.
            #expect(PDFImporter.staffSlots(system: Self.systems[1], shape: shape) == [[0, 1], []])
        }

        @Test func byStavesTheCommonestCouplingIsTheReferenceAndNoStaffIsLost() throws {
            let reference = try #require(PDFImporter.referenceSystem(Self.systems, couplesByStaves: true))
            #expect(reference.parts.count == 2)
            let shape = PDFImporter.partShape(from: reference, couplesByStaves: true)
            #expect(PDFImporter.staffSlots(system: Self.systems[0], shape: shape) == [[0, 1]])
            #expect(PDFImporter.staffSlots(system: Self.systems[1], shape: shape) == [[0], [1]])
            #expect(!PDFImportOptions().omrCouplesByStaves)
        }
    }
#endif
