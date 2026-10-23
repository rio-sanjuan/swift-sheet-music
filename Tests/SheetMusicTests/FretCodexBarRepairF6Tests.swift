#if SHEET_MUSIC_HAS_APPLE_PLATFORM_TEST_SUPPORT
    import CoreGraphics
    import Foundation
    import SheetMusicLayoutApple
    @testable import SheetMusicCore
    @testable import SheetMusicMSCX
    @testable import SheetMusicPDF
    import Testing

    /// FretCodex fork, F6: `.tupletRuns` and `.mirroredChords`, read on raster-like pages (vector
    /// exports with their text taken out, as a photo has none: no tuplet numeral to go by).
    @MainActor
    @Suite("FretCodex — the raster bar repair (F6): triplet runs and mirrored chords")
    struct FretCodexBarRepairF6Tests {
        typealias T = FretCodexBarRepairTests

        /// Continuous triplet eighths in 3/4, beamed in threes: a song's accompaniment.
        static func tripletRuns() throws -> Score {
            let c = { (p: Int) in FretCodexBarRepairFixtures.chord([p], "eighth") }
            let t = { (p: [Int]) in FretCodexBarRepairFixtures.tuplet(p.map(c), base: "eighth") }
            let bar = { (root: Int) in [t([root, root + 4, root + 7]) + t([root + 12, root + 7, root + 4]) + t([root, root + 4, root + 7])] }
            return try FretCodexBarRepairFixtures.score([bar(60), bar(62), bar(64), bar(62)], time: (3, 4))
        }

        /// Half-note chords with a second in them — G4, A4, C5 — whose A4 is set across the stem.
        static func secondChords() throws -> Score {
            let chord = { (p: [Int]) in FretCodexBarRepairFixtures.chord(p, "half") }
            return try FretCodexBarRepairFixtures.score([
                [chord([67, 69, 72]) + chord([65, 67, 71])],
                [chord([64, 65, 69]) + chord([67, 69, 72])],
            ], time: (4, 4))
        }

        /// The notes of `score`'s first staff read as triplet eighths — a twelfth of a whole — and
        /// all its notes.
        static func tripletNotes(_ score: Score) -> (triplets: Int, eighths: Int, notes: Int) {
            guard let staff = score.parts.values.first?.staves.values.first else { return (0, 0, 0) }
            var triplets = 0, eighths = 0, notes = 0
            for measure in staff.measures {
                for voice in measure.voices {
                    for element in voice.elements.values {
                        guard case let .chord(chord) = element else { continue }
                        notes += chord.notes.count
                        if case let .fraction(f) = chord.duration, f.numerator == 1, f.denominator == 12 { triplets += chord.notes.count }
                        if chord.duration == .eighth { eighths += chord.notes.count }
                    }
                }
            }
            return (triplets, eighths, notes)
        }

        @Test(.enabled(if: T.bravuraAvailable))
        func continuousTripletsWithNoNumeralReadAsTriplets() throws {
            guard #available(macOS 15.0, iOS 16.0, *) else { return }
            let data = try PDFExporter.export(score: Self.tripletRuns())
            var without = BarRepairPasses.all
            without.remove(.tupletRuns)
            let before = Self.tripletNotes(try T.rasterLike(data, options: T.repairOn(without)))
            let after = Self.tripletNotes(try T.rasterLike(data, options: T.repairOn(.all)))
            #expect(after.notes == 36)
            // One triplet a voice at most: a bar of three groups is left as read, overfull eighths;
            // with the runs, every one of those eighths is a triplet's. (The page's fourth bar, at
            // the end of its line, is read without its beams either way — as quarters.)
            #expect(before.triplets == 0 && before.eighths >= 27, "\(before)")
            #expect(after.triplets == before.eighths && after.eighths == 0, "\(after)")
        }

        @Test(.enabled(if: T.bravuraAvailable))
        func aChordWhoseSecondIsSetAcrossTheStemStaysOneChord() throws {
            guard #available(macOS 15.0, iOS 16.0, *) else { return }
            let data = try PDFExporter.export(score: Self.secondChords())
            let read = T.describe(try T.rasterLike(data, options: T.repairOn(.all)))
            #expect(read.count == 2)
            // Two chords a bar, three notes each, every one a half.
            for bar in read {
                let chords = bar.split(separator: " ").filter { $0.contains(":") }
                #expect(chords.count == 2, "\(bar)")
                #expect(chords.allSatisfy { $0.split(separator: "+").count == 3 }, "\(bar)")
            }
        }

        @Test func theNewPassesAreInAll() {
            #expect(BarRepairPasses.all.contains(.tupletRuns))
            #expect(BarRepairPasses.all.contains(.mirroredChords))
        }
    }
#endif
