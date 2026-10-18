#if SHEET_MUSIC_HAS_APPLE_PLATFORM_TEST_SUPPORT
    import CoreGraphics
    import Foundation
    @testable import SheetMusicCore
    @testable import SheetMusicPDF
    import Testing

    /// FretCodex fork, F4: the bar repair's pieces, on bars built by hand at three staff sizes.
    @Suite("FretCodex — the raster bar repair (F4): passes")
    struct FretCodexBarRepairUnitTests {
        // MARK: - P0: the tuplet-keeping prepend

        static func triplet() -> Voice {
            let third = NoteDuration.fraction(Fraction(numerator: 1, denominator: 12))
            let notes = [60, 62, 64].map { Chord(duration: third, notes: ChordNotes([Note(pitch: $0, tpc: 14)])) }
            let rest = Chord(duration: .quarter, notes: [])
            return Voice(
                elements: notes.map { .chord($0) } + [.chord(rest)],
                tuplets: [Tuplet(normalNotes: 2, actualNotes: 3, startIndex: 0, endIndex: 2)],
            )
        }

        @Test func aVoiceZeroTripletKeepsItsTupletPastClefKeyAndTime() throws {
            let (voices, leading) = PDFImporter.prependingScoreStateKeepingTuplets(
                [Self.triplet()], clef: Clef(concertClefType: "F"), key: KeySignature(concertKey: 2),
                time: TimeSignature(numerator: 2, denominator: 4),
            )
            #expect(leading == 3)
            var voice = voices[0]
            #expect(voice.tuplets.count == 1)
            #expect(voice.tupletSpans.first.map { ($0.startIndex, $0.endIndex) } ?? (0, 0) == (3, 5))
            var ids = EIDAllocator()
            voice.assignMissingIDs(using: &ids)
            let span = try #require(voice.tupletSpans.first)
            #expect(span.isResolved && span.startIndex == 3 && span.endIndex == 5)
            #expect(span.normalNotes == 2 && span.actualNotes == 3)
        }

        @Test func upstreamsPrependIsUnchanged() {
            let (voices, leading) = PDFImporter.prependingScoreState(
                [Self.triplet()], clef: Clef(concertClefType: "F"), key: nil, time: nil,
            )
            #expect(leading == 1)
            #expect(voices[0].tuplets.isEmpty, "upstream drops them: SM-29")
            let (same, _) = PDFImporter.prependingScoreStateKeepingTuplets([Self.triplet()], clef: nil, key: nil, time: nil)
            #expect(same == [Self.triplet()])
        }
    }
#endif
