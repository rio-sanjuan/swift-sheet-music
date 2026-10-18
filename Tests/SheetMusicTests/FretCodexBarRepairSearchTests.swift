#if SHEET_MUSIC_HAS_APPLE_PLATFORM_TEST_SUPPORT
    import CoreGraphics
    import Foundation
    @testable import SheetMusicCore
    @testable import SheetMusicPDF
    import Testing

    /// FretCodex fork, F4: P6 (the repair search).
    @Suite("FretCodex — the raster bar repair (F4): the repair search")
    struct FretCodexBarRepairSearchTests {
        // MARK: - P6: the repair search

        /// A voice of black notes, each `(x in spaces, value, levelHint, group)`.
        static func voice(_ notes: [(x: CGFloat, value: NoteDuration, hint: Int, group: Int?)], sp: CGFloat = 6,
                          lined: Bool = true) -> ([RhythmElement], BarEvidence) {
            var bar = BarEvidence()
            bar.spatium = sp
            var elements: [RhythmElement] = []
            for (i, n) in notes.enumerated() {
                let level = n.value == .eighth ? 1 : n.value == .sixteenth ? 2 : 0
                var stem = StemEvidence(index: i, x: n.x * sp + 7, loY: 100, hiY: 121, bareEndY: 121, up: true, groupRoot: n.group ?? i)
                stem.levelHint = n.hint
                stem.fullCount = n.group != nil && lined ? 1 : 0
                stem.groupSize = notes.filter { $0.group != nil && $0.group == n.group }.count
                if n.group == nil { stem.groupSize = 1 }
                bar.stems.append(stem)
                var ev = ElementEvidence(base: .quarter, filled: true)
                ev.level = level
                ev.stem = i
                ev.stemUp = true
                elements.append(RhythmElement(
                    chord: Chord(duration: n.value, notes: ChordNotes([Note(pitch: 60 + i, tpc: 14)])),
                    x: n.x * sp, y: 107, stemDirection: .up, beamGroup: nil, evidence: ev,
                ))
            }
            return (elements, bar)
        }

        static func repair(_ elements: [RhythmElement], _ bar: BarEvidence, _ ts: TimeSignature,
                           passes: BarRepairPasses = FretCodexBarRepairTests.every) -> ([RhythmElement], PDFImporter.SearchOutcome) {
            var out = elements
            let outcome = PDFImporter.repairVoice(Array(elements.indices), elements: &out, bar: bar, ts: ts, passes: passes)
            return (out, outcome)
        }

        static let twoFour = TimeSignature(numerator: 2, denominator: 4)

        @Test func aBeamedTripletOnABeatIsATripletNotASixteenth() {
            // Photo #2 bar 1: three beamed eighths, evenly spaced, then a quarter, in 2/4.
            let (elements, bar) = Self.voice([(0, .eighth, 1, 0), (2, .eighth, 1, 0), (4, .eighth, 1, 0), (8, .quarter, 0, nil)])
            let (out, outcome) = Self.repair(elements, bar, Self.twoFour)
            #expect(outcome == .repaired)
            let third = NoteDuration.fraction(Fraction(numerator: 1, denominator: 12))
            #expect(out.map(\.chord.duration) == [third, third, third, .quarter])
            #expect(out.prefix(3).allSatisfy { $0.tupletRatio.map { $0 == (2, 3) } ?? false })
            let voices = PDFImporter.voices(out, split: PDFImporter.VoiceSplit(voiceCount: 1, placements: out.indices.map { (0, $0) }))
            #expect(voices[0].tupletSpans.map { [$0.startIndex, $0.endIndex] } == [[0, 2]])
        }

        @Test func stemsWithNoBeamLineAreNoTuplet() {
            // Phone #8 bar 12: three beamed eighths whose beam the raster never saw, read as
            // quarters, then a quarter rest's worth — in 2/4 the voice is 1/4 over.
            var (elements, bar) = Self.voice([(0, .quarter, 0, 0), (2, .quarter, 0, 0), (4, .quarter, 0, 0)], lined: false)
            // Bare ends on one line, stems not the free length.
            for i in bar.stems.indices {
                bar.stems[i].bareEndY = 121 + CGFloat(i) * 0.2
                bar.stems[i].hiY = bar.stems[i].bareEndY!
            }
            let threeFour = TimeSignature(numerator: 3, denominator: 8)
            let (out, outcome) = Self.repair(elements, bar, threeFour, passes: FretCodexBarRepairTests.every.subtracting(.phantomGroups))
            #expect(out.allSatisfy { !$0.inTuplet })
            #expect(outcome != .repaired)
            for i in elements.indices {
                elements[i].y = 121 - 4.5 * 6
            }
            let (straight, phantom) = Self.repair(elements, bar, threeFour)
            #expect(phantom == .repaired)
            #expect(straight.map(\.chord.duration) == [.eighth, .eighth, .eighth])
        }

        @Test func inSixEightAThreeEighthGroupIsNeverScaled() {
            let (elements, bar) = Self.voice([(0, .eighth, 1, 0), (2, .eighth, 1, 0), (4, .eighth, 1, 0), (8, .quarter, 0, nil)])
            let (out, _) = Self.repair(elements, bar, TimeSignature(numerator: 6, denominator: 8))
            #expect(out.allSatisfy { !$0.inTuplet })
        }

        @Test func aStubOnAStemNoBeamReachesMakesASixteenth() {
            // Photo #2 bar 2, in 2/4: a dotted eighth, a sixteenth whose primary beam stops short
            // (only its stub reaches it), a quarter.
            var (elements, bar) = Self.voice([(0, .eighth, 1, 0), (3, .quarter, 1, nil), (6, .quarter, 0, nil)])
            elements[0].evidence?.dots = 1
            elements[0].chord.duration = NoteDuration.eighth.dotted(1)
            bar.stems[1].stubCount = 1
            bar.stems[1].fullCount = 0
            let (out, outcome) = Self.repair(elements, bar, Self.twoFour)
            #expect(outcome == .repaired)
            #expect(out[1].chord.duration == .sixteenth)
        }

        @Test func twoRepairsOfEqualCostAreRefused() {
            // Two eighths read as quarters, a line at each stem, in 3/8: either one alone closes the
            // bar. Upstream would take the first; with no upstream reading to break it, the tie is
            // refused.
            let (elements, bar) = Self.voice([(0, .quarter, 1, nil), (4, .quarter, 1, nil)])
            let units = PDFImporter.repairUnits([0, 1], elements: elements, bar: bar, ts: TimeSignature(numerator: 3, denominator: 8),
                                                passes: FretCodexBarRepairTests.every, barTicks: 288)
            #expect(units.count == 2 && units.allSatisfy { $0.cost == 1 && $0.delta == -96 })
            let refused = PDFImporter.searchRepair(units: units, legacy: [], need: -96, cap: 3, order: [0, 1], elements: elements,
                                                   barTicks: 288, ts: TimeSignature(numerator: 3, denominator: 8))
            #expect(refused != nil && refused?.chosen == nil)
            // Through the whole voice, upstream's own pick (the first) breaks the tie.
            let (out, outcome) = Self.repair(elements, bar, TimeSignature(numerator: 3, denominator: 8))
            #expect(outcome == .repaired)
            #expect(out.map(\.chord.duration) == [.eighth, .quarter])
        }

        @Test func aVoiceThatSumsIsUntouched() {
            let (elements, bar) = Self.voice([(0, .quarter, 2, nil), (4, .quarter, 0, nil)])
            let (out, outcome) = Self.repair(elements, bar, Self.twoFour)
            #expect(outcome == .sums)
            #expect(out.map(\.chord.duration) == elements.map(\.chord.duration))
        }

        @Test func noDotWithoutADotColumn() {
            // Phone #4 bar 6: a half and a quarter in 4/4, a quarter short: no dotted half.
            var (elements, bar) = Self.voice([(0, .half, 0, nil), (8, .quarter, 0, nil)])
            elements[0].evidence = ElementEvidence(base: .half, filled: false)
            elements[0].noteheadIsFilled = false
            bar.stems[0].levelHint = 0
            let (out, _) = Self.repair(elements, bar, TimeSignature(numerator: 4, denominator: 4))
            #expect(!out.contains { if case .fraction = $0.chord.duration { return true } else { return false } })
        }

        @Test func ticksAgreeWithFractions() {
            let values: [NoteDuration] = [.whole, .half, .quarter, .eighth, .sixteenth, .thirtySecond, .sixtyFourth]
            var all = values + values.flatMap { [$0.dotted(1), $0.dotted(2)] }
            for v in [NoteDuration.quarter, .eighth, .sixteenth, .thirtySecond] {
                let f = v.asFraction
                all.append(.fraction(Fraction(numerator: f.numerator * 2, denominator: f.denominator * 3)))
                all.append(.fraction(Fraction(numerator: f.numerator * 4, denominator: f.denominator * 6)))
            }
            for d in all {
                let t = PDFImporter.ticks(d, bar: 0)
                #expect(t != nil, "\(d)")
                if let t { #expect(Fraction(numerator: t, denominator: repairTicksPerWhole) == d.asFraction) }
            }
        }

        @Test func theSearchMakesAtMostThreeChanges() {
            // Four eighths read as quarters, each with its line, in 2/4 plus a half: closing it needs
            // four changes — none is made.
            let (elements, bar) = Self.voice((0 ..< 4).map { (CGFloat($0) * 3, .quarter, 1, nil) })
            let (out, outcome) = Self.repair(elements, bar, TimeSignature(numerator: 2, denominator: 4),
                                             passes: FretCodexBarRepairTests.every.subtracting([.legacyFallback, .phantomGroups]))
            #expect(outcome != .repaired, "\(out.map(\.chord.duration))")
            #expect(out.map(\.chord.duration) == elements.map(\.chord.duration))
        }

        /// The search against brute force: every combination of at most `cap` alternatives, one per
        /// element, on 500 random small voices.
        @Test func theSearchEqualsBruteForce() {
            var rng = SplitMix(seed: 7)
            for _ in 0 ..< 500 {
                let n = 2 + Int(rng.next() % 5)
                var units: [PDFImporter.RepairUnit] = []
                for m in 0 ..< n {
                    for _ in 0 ..< Int(rng.next() % 4) {
                        let delta = (Int(rng.next() % 9) - 4) * 48
                        guard delta != 0 else { continue }
                        units.append(PDFImporter.RepairUnit(kind: .evidence, members: [m], durations: [.eighth],
                                                            cost: 1 + Int(rng.next() % 3), ratio: nil, delta: delta))
                    }
                }
                let need = (Int(rng.next() % 9) - 4) * 48
                guard need != 0 else { continue }
                let elements = (0 ..< n).map { m in
                    RhythmElement(chord: Chord(duration: .quarter, notes: ChordNotes([Note(pitch: 60, tpc: 14)])),
                                  x: CGFloat(m * 10), y: 0, stemDirection: nil, beamGroup: nil)
                }
                let found = PDFImporter.searchRepair(units: units, legacy: [], need: need, cap: 3, order: Array(0 ..< n),
                                                     elements: elements, barTicks: 768, ts: TimeSignature(numerator: 4, denominator: 4))
                // Brute force: the cheapest (cost, count) over every disjoint subset of size ≤ 3.
                var best: (Int, Int)?
                func walk(_ start: Int, _ chosen: [PDFImporter.RepairUnit]) {
                    if !chosen.isEmpty, chosen.map(\.delta).reduce(0, +) == need {
                        let key = (chosen.map(\.cost).reduce(0, +), chosen.count)
                        if best == nil || key < best! { best = key }
                    }
                    guard chosen.count < 3 else { return }
                    for k in start ..< units.count where !chosen.contains(where: { $0.members == units[k].members }) {
                        walk(k + 1, chosen + [units[k]])
                    }
                }
                walk(0, [])
                #expect((found != nil) == (best != nil))
                if let chosen = found?.chosen, let best {
                    #expect((chosen.map(\.cost).reduce(0, +), chosen.count) == best)
                }
            }
        }
    }

#endif
