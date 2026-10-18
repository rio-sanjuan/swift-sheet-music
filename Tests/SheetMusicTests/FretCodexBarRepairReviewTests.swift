#if SHEET_MUSIC_HAS_APPLE_PLATFORM_TEST_SUPPORT
    import CoreGraphics
    import Foundation
    @testable import SheetMusicCore
    @testable import SheetMusicPDF
    import Testing

    /// FretCodex fork, F4: the risks round 3's skeptical review found in the bar repair, each on
    /// the bar it named. Every test here failed on `f4/bar-repair` at `7f65e307`.
    @Suite("FretCodex — the raster bar repair (F4): the review's cases")
    struct FretCodexBarRepairReviewTests {
        typealias Search = FretCodexBarRepairSearchTests

        static let fourFour = TimeSignature(numerator: 4, denominator: 4)
        static let every = FretCodexBarRepairTests.every
        /// The broken-tuplet bit, by name (it is measured, not in `.all`).
        static let broken = BarRepairPasses.names.first { $0.name == "brokenTuplets" }?.pass ?? []

        // MARK: - P6: the broken-tuplet unit

        /// A 4/4 bar of half, eighth, eighth, quarter with a stray black blob read as a quarter
        /// before it: the voice is a quarter over. The quarter after the beamed pair is no triplet
        /// member — its stem carries no line and nothing ties it to the pair's beam — so the bar
        /// stays as read, unfit, as upstream leaves it.
        @Test func aQuarterBesideABeamedPairIsNoBrokenTriplet() {
            var (elements, bar) = Search.voice([
                (0, .quarter, 0, nil), (3, .half, 0, nil), (8, .eighth, 1, 9), (10, .eighth, 1, 9), (12, .quarter, 0, nil),
            ])
            elements[1].evidence = ElementEvidence(base: .half, filled: false)
            elements[1].evidence?.stem = 1
            elements[1].noteheadIsFilled = false
            let (read, outcome) = Search.repair(elements, bar, Self.fourFour, passes: .all)
            #expect(outcome != .repaired, "\(read.map(\.chord.duration))")
            // Every pass, the broken unit and the evidence-free fallback among them: still no triplet.
            #expect(Search.repair(elements, bar, Self.fourFour, passes: Self.every).0.allSatisfy { !$0.inTuplet })
            // Its stem lined up with the pair's beam carried on is still not enough under `.all`.
            bar.stems[4].bareEndY = bar.stems[3].bareEndY
            let (out, _) = Search.repair(elements, bar, Self.fourFour, passes: .all)
            #expect(out.allSatisfy { !$0.inTuplet })
        }

        /// The same pair with the third member's stem on the pair's beam line carried on, black,
        /// unflagged, its line lost: with `.brokenTuplets` on, a triplet; with a stem the other
        /// way, a flag, or a dot, never.
        @Test func aBrokenTripletNeedsItsThirdStemOnTheGroupsBeam() {
            var b = RepairBarBuilder(sp: 6)
            let sp: CGFloat = 6
            let e1 = b.note(x: 40, step: 2)
            let e2 = b.note(x: 40 + 2 * sp, step: 2)
            b.beam(from: 40 + 1.18 * sp, e1, to: 40 + 3.18 * sp, e2)
            b.note(x: 40 + 4 * sp, step: 2)
            b.note(x: 40 + 8 * sp, step: 2)
            // 2/4: [8 8] q q reads 3/4 — a quarter over; [8 8 8]3 q is the bar.
            let (elements, bar) = b.decode()
            #expect(elements.map(\.chord.duration) == [.eighth, .eighth, .quarter, .quarter])
            let twoFour = TimeSignature(numerator: 2, denominator: 4)
            let (on, outcome) = Search.repair(elements, bar, twoFour, passes: .all.union(Self.broken))
            #expect(outcome == .repaired)
            #expect(on.prefix(3).allSatisfy { $0.inTuplet })
            let (off, _) = Search.repair(elements, bar, twoFour, passes: .all.subtracting(Self.broken))
            #expect(off.allSatisfy { !$0.inTuplet })
            // The third note's stem down: no member of an up-stemmed group.
            var down = RepairBarBuilder(sp: 6)
            let d1 = down.note(x: 40, step: 2)
            let d2 = down.note(x: 40 + 2 * sp, step: 2)
            down.beam(from: 40 + 1.18 * sp, d1, to: 40 + 3.18 * sp, d2)
            down.note(x: 40 + 4 * sp, step: 9, up: false)
            down.note(x: 40 + 8 * sp, step: 2)
            let (de, dbar) = down.decode()
            let (dout, _) = Search.repair(de, dbar, twoFour, passes: .all.union(Self.broken))
            #expect(dout.allSatisfy { !$0.inTuplet })
        }

        // MARK: - P6: a beam level raised only to the stem's own lines

        /// A beamed eighth whose stem a neighbour's beam crosses halfway along: the lines counted
        /// at it say two, the lines hung from its bare end one. In a voice a sixteenth over, the
        /// eighth is not made a sixteenth.
        @Test func aNeighboursLineIsNoSecondBeamForABeamedEighth() {
            var (elements, bar) = Search.voice([
                (0, .eighth, 1, 0), (2, .eighth, 1, 0), (5, .quarter, 0, nil), (9, .sixteenth, 2, nil),
            ])
            elements[3].evidence?.level = 2
            bar.stems[0].levelHint = 2
            bar.stems[0].anchoredLevel = 1
            let (out, outcome) = Search.repair(elements, bar, TimeSignature(numerator: 2, denominator: 4), passes: .all)
            #expect(out[0].chord.duration == .eighth)
            #expect(outcome != .repaired)
            // Lines hung from the bare end still raise it.
            bar.stems[0].anchoredLevel = 2
            let (raised, _) = Search.repair(elements, bar, TimeSignature(numerator: 2, denominator: 4), passes: .all)
            #expect(raised[0].chord.duration == .sixteenth)
        }

        // MARK: - P6: meters

        /// 3/8 is compound: its one beamed group of three eighths is never a triplet.
        @Test func inThreeEightAGroupOfThreeIsNeverATriplet() {
            let (elements, bar) = Search.voice([(0, .eighth, 1, 0), (2, .eighth, 1, 0), (4, .eighth, 1, 0), (7, .eighth, 0, nil)])
            let (out, _) = Search.repair(elements, bar, TimeSignature(numerator: 3, denominator: 8), passes: .all)
            #expect(out.allSatisfy { !$0.inTuplet })
        }

        /// In 2/2 an eighth triplet on the second quarter is on its own span: it may be read.
        @Test func inCutTimeATripletOnTheSecondQuarterIsRead() {
            let (elements, bar) = Search.voice([
                (0, .quarter, 0, nil), (4, .eighth, 1, 9), (6, .eighth, 1, 9), (8, .eighth, 1, 9), (12, .quarter, 0, nil),
                (16, .quarter, 0, nil),
            ])
            let (out, outcome) = Search.repair(elements, bar, TimeSignature(numerator: 2, denominator: 2), passes: .all)
            #expect(outcome == .repaired)
            #expect(out[1 ... 3].allSatisfy { $0.inTuplet })
        }

        /// A sextuplet of sixteenths, read straight, beside a quarter in 2/4: 6:4.
        @Test func aBeamedSixIsReadAsASextuplet() {
            let notes: [(x: CGFloat, value: NoteDuration, hint: Int, group: Int?)] =
                (0 ..< 6).map { (CGFloat($0) * 1.6, .sixteenth, 2, 0) } + [(11, .quarter, 0, nil)]
            let (elements, bar) = Search.voice(notes)
            let (out, outcome) = Search.repair(elements, bar, TimeSignature(numerator: 2, denominator: 4))
            #expect(outcome == .repaired)
            let sixth = NoteDuration.fraction(Fraction(numerator: 1, denominator: 24))
            #expect(out.prefix(6).allSatisfy { $0.chord.duration == sixth && $0.tupletRatio.map { $0 == (4, 6) } ?? false })
            // Six straight sixteenths in a bar that sums are left alone.
            let straight = Search.voice((0 ..< 6).map { (CGFloat($0) * 1.6, .sixteenth, 2, 0) }
                + [(11, .eighth, 1, nil), (13, .quarter, 0, nil)])
            #expect(Search.repair(straight.0, straight.1, TimeSignature(numerator: 3, denominator: 4)).1 == .sums)
        }

        /// A meter with no denominator never reaches `Fraction`, which would trap.
        @Test func anInvalidMeterIsLeftAsRead() {
            let (elements, bar) = Search.voice([(0, .quarter, 1, nil), (4, .quarter, 0, nil)])
            let (out, outcome) = Search.repair(elements, bar, TimeSignature(numerator: 4, denominator: 0))
            #expect(outcome != .repaired)
            #expect(out.map(\.chord.duration) == elements.map(\.chord.duration))
        }

        // MARK: - P4: a whole note is no stem's

        /// Voice 1 quarters E5 F5 G5 A5, stems up; voice 2 a whole C4 under the first. The whole
        /// note stays its own chord, a whole, whatever leads the column.
        @Test(arguments: [0.0, -0.3, 0.3] as [CGFloat])
        func aWholeNoteUnderAQuarterStaysAWhole(dx: CGFloat) {
            let sp: CGFloat = 6
            var b = RepairBarBuilder(sp: sp)
            for (k, step) in [7, 8, 9, 10].enumerated() { b.note(x: 40 + CGFloat(k) * 5 * sp, step: CGFloat(step)) }
            b.glyph(.noteheadWhole, x: 40 + dx * sp, y: b.y(-2))
            let (elements, _) = b.decode([.columnChords])
            let whole = elements.filter { $0.chord.notes.values.contains { $0.pitch == 60 } }
            #expect(whole.count == 1)
            #expect(whole.first?.chord.duration == .whole)
            #expect(whole.first?.chord.notes.count == 1)
            #expect(elements.count == 5)
        }

        // MARK: - P1: double dots and staccatos

        /// A double-dotted quarter: its second dot sits 2.33 spaces from the head's origin, past the
        /// owner window, chained 0.65 spaces right of the first.
        @Test(arguments: FretCodexBarRepairMarksTests.spatia)
        func aDoubleDotIsTwoDots(sp: CGFloat) {
            var b = RepairBarBuilder(sp: sp)
            b.note(x: 20, step: 3)
            b.glyph(.augmentationDot, x: 20 + 1.68 * sp, y: b.y(3))
            b.glyph(.augmentationDot, x: 20 + 2.33 * sp, y: b.y(3))
            #expect(FretCodexBarRepairMarksTests.dotted(b) == [2])
        }

        /// A staccato the warp moved off its own head's centre — so upstream's staccato test misses
        /// it — sits over the next note's head, in the dot window of the note before: it is that
        /// note's staccato, not the earlier note's dot.
        @Test(arguments: FretCodexBarRepairMarksTests.spatia)
        func aStaccatoOverTheNextHeadIsNoDot(sp: CGFloat) {
            var b = RepairBarBuilder(sp: sp)
            b.note(x: 20, step: 4, up: false)
            b.note(x: 20 + 1.6 * sp, step: 2, up: false)
            // Over the second head, a space above it: dx −0.1 head widths fails the staccato test.
            b.glyph(.augmentationDot, x: 20 + 1.6 * sp - 0.12 * sp, y: b.y(2) + 1.0 * sp)
            #expect(FretCodexBarRepairMarksTests.dotted(b) == [0, 0])
        }

        // MARK: - P7: far heads only from this page, never another system's

        /// FretCodex reads a photo as one PDF page per system, all laid out alike: a stemmed head on
        /// page 1 must not pull page 0's sharp, 6 spaces off its staff, into page 0.
        @Test func aFarHeadOnAnotherPageCapturesNothingHere() {
            let sp: CGFloat = 6
            let staff = FretCodexBarRepairMarksTests.staff(100, sp: sp)
            let y = 100 + 4 * sp + 6 * sp
            let sharp = ClassifiedGlyph(geometry: GlyphGeometry(origin: CGPoint(x: 50 - 1.5 * sp, y: y), advance: sp, pageIndex: 0),
                                        semantic: .accidentalSharp)
            let headElsewhere = ClassifiedGlyph(geometry: GlyphGeometry(origin: CGPoint(x: 50, y: y), advance: 6, pageIndex: 1),
                                                semantic: .noteheadBlack)
            let stem = PathSegment(kind: .vertical, rect: CGRect(x: 50, y: y - 3.5 * sp, width: 0, height: 3.5 * sp),
                                   lineWidth: 0.1 * sp, pageIndex: 0, quad: nil, detectedFromRaster: true)
            let captured = PDFImporter.filterGlyphs(classified: [sharp, headElsewhere], staff: staff, lo: 0, hi: 400,
                                                    noteheadBandSpaces: 7, verticals: [stem])
            #expect(captured.isEmpty)
        }

        /// Two systems 10 spaces apart: a voice-2 head 4 spaces under the upper staff, stem down —
        /// toward the lower staff, 6 spaces above it. The far band stops at the midpoint to every
        /// staff on the page, not only the system's, so only the upper staff takes it.
        @Test func aHeadBetweenTwoSystemsIsTheNearerStaffs() {
            let sp: CGFloat = 6
            let lower = SheetMusicPDF.Staff(pageIndex: 0, yLines: (0 ..< 5).map { 100 + CGFloat($0) * sp }, xRange: 0 ... 400,
                                            barlineCandidates: [])
            let upperBottom = 100 + 4 * sp + 10 * sp
            let upper = SheetMusicPDF.Staff(pageIndex: 0, yLines: (0 ..< 5).map { upperBottom + CGFloat($0) * sp }, xRange: 0 ... 400,
                                            barlineCandidates: [])
            let headY = upperBottom - 4 * sp
            let head = ClassifiedGlyph(geometry: GlyphGeometry(origin: CGPoint(x: 50, y: headY), advance: 1.18 * sp, pageIndex: 0),
                                       semantic: .noteheadBlack)
            let stem = PathSegment(kind: .vertical, rect: CGRect(x: 50, y: headY - 3.5 * sp, width: 0, height: 3.5 * sp),
                                   lineWidth: 0.1 * sp, pageIndex: 0, quad: nil, detectedFromRaster: true)
            let systems = PDFImporter.layoutSystems(staves: [lower, upper], paths: [stem], classified: [head], pageIndex: 0,
                                                    ensembleSize: 1, noteheadBandSpaces: 7)
            #expect(systems.count == 2)
            let takers = systems.map { system in
                system.parts.flatMap(\.staves).flatMap(\.measures).flatMap(\.glyphs).count { isNoteheadForTest($0.semantic) }
            }
            #expect(takers.reduce(0, +) == 1, "\(takers)")
        }

        func isNoteheadForTest(_ s: SMuFLSemantic) -> Bool {
            if case .noteheadBlack = s { return true }
            return false
        }
    }
#endif
