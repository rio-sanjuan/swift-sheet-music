#if SHEET_MUSIC_HAS_APPLE_PLATFORM_TEST_SUPPORT
    import CoreGraphics
    import Foundation
    @testable import SheetMusicCore
    @testable import SheetMusicPDF
    import Testing

    /// FretCodex fork, F4: P4 (column chords) and P5 (the voice rule).
    @Suite("FretCodex — the raster bar repair (F4): chords and voices")
    struct FretCodexBarRepairChordsTests {
        // MARK: - P4: column chords

        static func columns(_ b: RepairBarBuilder, headKind: Bool = true) -> [RhythmElement] {
            b.decode(headKind ? [.columnChords, .headKindRule] : [.columnChords]).0
        }

        static func pitches(_ elements: [RhythmElement]) -> [[Int]] {
            elements.map { $0.chord.notes.values.map(\.pitch) }
        }

        @Test func aStemlessColumnIsOneChord() {
            var b = RepairBarBuilder(sp: 6)
            // E5 G5 B5 with no stem found (phone #1 bar 9).
            for step: CGFloat in [7, 9, 11] { b.note(x: 40, step: step, stem: false) }
            #expect(b.legacy().count == 3, "upstream: three notes, one after another")
            let chords = Self.columns(b)
            #expect(Self.pitches(chords) == [[76, 79, 83]])
            #expect(chords[0].evidence?.virtualStem == true)
        }

        @Test func fourHeadsOnOneDownStemAreOneChordInOneVoice() {
            let sp: CGFloat = 6
            var b = RepairBarBuilder(sp: sp)
            // F#5 A5 C#6 E6 on one down stem (photo #1 bar 11): a short stroke beside the top two
            // takes them from the lead's stem upstream.
            for step: CGFloat in [8, 10, 12, 14] { b.glyph(.noteheadBlack, x: 40, y: b.y(step)) }
            b.paths.append(PathSegment(kind: .vertical, rect: CGRect(x: 40, y: b.y(8) - 3.5 * sp, width: 0, height: b.y(14) - b.y(8) + 3.5 * sp),
                                       lineWidth: 0.6, pageIndex: 0, quad: nil, detectedFromRaster: true))
            b.paths.append(PathSegment(kind: .vertical, rect: CGRect(x: 40 + 0.3 * sp, y: b.y(12), width: 0, height: b.y(14) - b.y(12) + 2.6 * sp),
                                       lineWidth: 0.6, pageIndex: 0, quad: nil, detectedFromRaster: true))
            let chords = Self.columns(b)
            #expect(chords.count == 1)
            #expect(chords.first?.chord.notes.count == 4)
            let split = PDFImporter.ruleSplit(chords, bar: b.decode([.columnChords]).1, staffMidY: b.y(4))
            #expect(split.voiceCount == 1)
        }

        @Test func fourHeadsOnOneUpStemKeepEveryHead() {
            let sp: CGFloat = 6
            var b = RepairBarBuilder(sp: sp)
            // D4 F4 A4 C5 on one up stem (phone #16 bar 5), a stray stroke by the lower two.
            for step: CGFloat in [-1, 1, 3, 5] { b.glyph(.noteheadBlack, x: 40, y: b.y(step)) }
            b.paths.append(PathSegment(kind: .vertical, rect: CGRect(x: 40 + 1.18 * sp, y: b.y(-1), width: 0, height: b.y(5) - b.y(-1) + 3.5 * sp),
                                       lineWidth: 0.6, pageIndex: 0, quad: nil, detectedFromRaster: true))
            b.paths.append(PathSegment(kind: .vertical, rect: CGRect(x: 40 + 0.9 * sp, y: b.y(-1) - 2.6 * sp, width: 0, height: b.y(1) - b.y(-1) + 2.6 * sp),
                                       lineWidth: 0.6, pageIndex: 0, quad: nil, detectedFromRaster: true))
            #expect(Self.pitches(Self.columns(b)) == [[62, 65, 69, 72]])
        }

        @Test func aStemlessHollowHeadBesideBlackHeadsStaysApart() {
            var b = RepairBarBuilder(sp: 6)
            b.note(x: 40, step: 2, stem: false)
            b.note(x: 40, step: 4, stem: false)
            b.glyph(.noteheadWhole, x: 40.5, y: b.y(-2))
            #expect(Self.columns(b).count == 2)
            // A whole head is a chord of its own even without the head-kind rule (the review's
            // P4 case): no value both a whole and a black note's.
            #expect(Self.columns(b, headKind: false).count == 2)
        }

        @Test func aCrashOverAKickStaysTwoVoices() {
            let sp: CGFloat = 6
            var b = RepairBarBuilder(sp: sp)
            b.note(x: 40, step: 9, up: true)
            b.note(x: 40, step: 1, up: false)
            let (elements, bar) = b.decode([.columnChords])
            #expect(elements.count == 2)
            #expect(PDFImporter.ruleSplit(elements, bar: bar, staffMidY: b.y(4)).voiceCount == 2)
        }

        @Test func aSecondOnOneStemStaysOneVoice() {
            let sp: CGFloat = 6
            var b = RepairBarBuilder(sp: sp)
            b.note(x: 40, step: 2)
            b.glyph(.noteheadBlack, x: 40 + 1.2 * sp, y: b.y(3))
            b.note(x: 40 + 5 * sp, step: 4)
            let (elements, bar) = b.decode([.columnChords])
            #expect(Self.pitches(elements) == [[67, 69], [71]])
            #expect(PDFImporter.ruleSplit(elements, bar: bar, staffMidY: b.y(4)).voiceCount == 1)
            // Upstream calls a head 1.2 sp off two voices when it is under 3 points apart — not here.
            #expect(PDFImporter.legacySplit(elements, staffMidY: b.y(4)).voiceCount == 1)
        }

        @Test func theVoicesAndTheirPlacementsAgree() {
            var b = RepairBarBuilder(sp: 6)
            b.note(x: 40, step: 9, up: true)
            b.note(x: 40, step: 1, up: false)
            b.note(x: 80, step: 8, up: true)
            b.note(x: 80, step: 2, up: false)
            let (elements, bar) = b.decode([.columnChords])
            let split = PDFImporter.ruleSplit(elements, bar: bar, staffMidY: b.y(4))
            let voices = PDFImporter.voices(elements, split: split)
            for (i, p) in split.placements.enumerated() {
                guard case let .chord(chord) = voices[p.voice].elements.values[p.position] else { Issue.record("not a chord"); continue }
                #expect(chord == elements[i].chord)
            }
        }
    }
#endif
