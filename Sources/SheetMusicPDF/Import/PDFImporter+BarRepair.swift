#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Foundation
import SheetMusicCore

// THE BAR REPAIR (FretCodex fork, F4; `PDFImportOptions.omrBarRepair`). On a page the raster
// fallback read, a bar's rhythm, chords and voices are rebuilt from the evidence recognition
// found, by passes each behind a bit of `BarRepairPasses`. Reached only from `buildOneMeasure`,
// and only when the option is on and the page is a raster page, so a vector page — and any
// page with the option off — reads exactly as before.

extension PDFImporter {
    /// Everything `buildOneMeasure` knows about one bar, for the repair.
    struct RepairBar {
        var importMeasure: ImportMeasure
        /// The page's text — an OCR layer a scanned PDF keeps (`applyRasterFallback`): tuplet
        /// numerals and lyrics, read as the legacy chain reads them.
        var texts: [TextGlyph] = []
        var nextStaffTopY: CGFloat?
        var paths: [PathSegment]
        var tieMarks: TieMarks
        var graceSizeThreshold: CGFloat
        var clef: Clef
        var key: KeySignature
        var ts: TimeSignature
        var emitClef: Clef?
        var emitKey: KeySignature?
        var emitTime: TimeSignature?
        var pageIndex: Int
        var measureIndex: Int
        var location: String
        var options: PDFImportOptions
        var slot: Int
        var measureIndexOffset: Int
        var geometry: PDFGeometryCollector?
        /// Whether the time signature in force was read from two stacked digits.
        var meterFromDigits: Bool

        var passes: BarRepairPasses { options.omrBarRepairPasses }
        var spatium: CGFloat { staffSpatium(importMeasure.staffYLines) }
        var stemHeadEndTolerance: CGFloat {
            options.omrStemHeadEndTolerance.map { CGFloat($0) } ?? stemHeadEndToleranceInSpaces
        }
    }

    /// One bar on the repair's branch. With no pass on it is the legacy chain exactly; otherwise
    /// P4, P1, P2, P3, P5 and P6 in that order (P7 acted when the bar's glyphs were captured).
    static func buildRepairedMeasure(_ bar: RepairBar) -> Measure {
        let measure = bar.importMeasure
        let passes = bar.passes
        let decoded = decodePitches(measure: measure, activeClef: bar.clef, activeKey: bar.key)
        let staffMidY = staffMidline(measure.staffYLines)
        let yBand = staffBeamBand(measure.staffYLines)
        let barTicks = ticks(Fraction(numerator: bar.ts.numerator, denominator: bar.ts.denominator)) ?? 0
        // The revert rule's referee: a meter read from two stacked digits.
        let referee = passes.contains(.revertRule) && (bar.meterFromDigits || passes.contains(.revertEverywhere))
        func fits(_ elements: [RhythmElement], _ split: VoiceSplit) -> Int {
            split.groups.count { group in
                if group.count == 1, elements[group[0]].isRest, elements[group[0]].chord.duration == .whole {
                    return true
                }
                let sum = group.compactMap { ticks(elements[$0].chord.duration, bar: barTicks) }.reduce(0, +)
                return sum == barTicks
            }
        }
        func keeps(_ new: [RhythmElement], over old: [RhythmElement]) -> Bool {
            !referee || fits(new, legacySplit(new, staffMidY: staffMidY))
                >= fits(old, legacySplit(old, staffMidY: staffMidY))
        }
        func decode(columns: Bool, text: Bool = true) -> ([RhythmElement], BarEvidence) {
            var chosen = passes.subtracting(.columnChords)
            if columns { chosen.insert(.columnChords) }
            var (elements, evidence) = decodeRhythmWithEvidence(
                measure: measure, decoded: decoded, paths: bar.paths, tieMarks: bar.tieMarks,
                graceSizeThreshold: bar.graceSizeThreshold, stemHeadEndTolerance: bar.stemHeadEndTolerance,
                passes: chosen,
            )
            if !passes.isEmpty {
                // P1 and P2 follow the ink alone; off, they still mark P6's alternatives.
                applyDotColumns(&elements, bar: evidence, apply: passes.contains(.dotColumns))
                applyFlagsInSpaces(&elements, bar: evidence, flagBand: yBand, apply: passes.contains(.flagsInSpaces))
            }
            return (text ? readingText(bar, elements) : elements, evidence)
        }
        if passes.isEmpty {
            let (elements, evidence) = decode(columns: false)
            if let probe = bar.options.barRepairProbe {
                probeBar(evidence, location: bar.location + ", slot \(bar.slot)", probe: probe)
            }
            return legacyTail(bar, elements: elements, staffMidY: staffMidY)
        }
        // One reading of the bar through P4…P6: its elements, voices, and the voices left unsummed.
        func reading(text: Bool) -> (reconciled: [RhythmElement], split: VoiceSplit, evidence: BarEvidence, unfit: [String]) {
            var (elements, evidence) = decode(columns: false, text: text)
            if let probe = bar.options.barRepairProbe {
                probeBar(evidence, location: bar.location + ", slot \(bar.slot)", probe: probe)
            }
            // P4, reverted where it leaves fewer voices summing under a stacked-digit meter.
            if passes.contains(.columnChords) {
                let (columned, columnedEvidence) = decode(columns: true, text: text)
                if keeps(columned, over: elements) { (elements, evidence) = (columned, columnedEvidence) }
            }
            // P3.
            if passes.contains(.beamRescue) {
                var rescued = elements
                applyBeamRescue(&rescued, bar: evidence)
                if keeps(rescued, over: elements) { elements = rescued }
            }
            // P5.
            var split = legacySplit(elements, staffMidY: staffMidY)
            var ownSplit = false
            if passes.contains(.voiceRule) {
                let rule = ruleSplit(elements, bar: evidence, staffMidY: staffMidY)
                if !referee || fits(elements, rule) >= fits(elements, split) {
                    split = rule
                    ownSplit = true
                }
            }
            // P6, or upstream's repair on the split chosen.
            var reconciled = elements
            var unfit: [String] = []
            if passes.contains(.repairSearch) {
                for (v, group) in split.groups.enumerated() {
                    let probe = bar.options.barRepairProbe.map { sink in { (line: String) in sink(line + " | \(bar.location), voice \(v + 1)") } }
                    let outcome = repairVoice(group, elements: &reconciled, bar: evidence, ts: bar.ts, passes: passes, probe: probe)
                    probe?("OUTCOME \(outcome)")
                    if case let .unfit(why) = outcome {
                        unfit.append("bar repair: voice \(v + 1) does not sum to the bar, left as read (\(why))")
                    }
                }
            } else if passes.contains(.leaveUnfit) {
                // Measuring only: no repair of any kind.
            } else if ownSplit {
                let barLength = Fraction(numerator: bar.ts.numerator, denominator: bar.ts.denominator)
                for group in split.groups {
                    reconcileVoiceGroup(
                        indices: group, barLength: barLength, spatium: bar.spatium, elements: &reconciled,
                        diagnostics: bar.options.diagnostics, location: bar.location,
                    )
                }
            } else {
                reconciled = reconcileMeasureDurations(
                    elements: elements, timeSignature: bar.ts, spatium: bar.spatium,
                    diagnostics: bar.options.diagnostics, location: bar.location,
                )
                split = legacySplit(reconciled, staffMidY: staffMidY)
            }
            return (reconciled, split, evidence, unfit)
        }
        var (reconciled, split, evidence, unfit) = reading(text: true)
        // `.numeralRevert`: numerals that leave more voices unsummed than the bar read without them
        // are set aside — read on some of a voice's groups and not the rest, they mark a run the
        // search would have read whole.
        if passes.contains(.numeralRevert), !unfit.isEmpty, !bar.texts.isEmpty {
            let plain = reading(text: false)
            if plain.unfit.count < unfit.count { (reconciled, split, evidence, unfit) = plain }
        }
        for message in unfit {
            bar.options.diagnostics?(PDFImportDiagnostic(
                severity: .warning, location: bar.location, message: message, context: "slot \(bar.slot)",
            ))
        }
        if let probe = bar.options.barRepairProbe {
            for (i, e) in reconciled.enumerated() {
                let pitches = e.chord.notes.values.map { String($0.pitch) }.joined(separator: "+")
                let stem = e.evidence?.stem.map { s in
                    let f = evidence.stems[s]
                    return "\(s) hint \(f.levelHint) full \(f.fullCount) stub \(f.stubCount) root \(f.groupRoot)/\(f.groupSize)"
                } ?? (e.evidence?.virtualStem == true ? "virtual" : "-")
                probe("ELEMENT v\(split.placements[i].voice + 1) x \(String(format: "%.2f", e.x / bar.spatium)) "
                    + "y \(String(format: "%.2f", (e.y - staffMidY) / bar.spatium)) \(pitches.isEmpty ? "rest" : pitches) "
                    + "\(e.chord.duration) dir \(e.stemDirection.map { "\($0)" } ?? "-") stem \(stem) | \(bar.location)")
            }
        }
        let voiceList = voices(reconciled, split: split)
        let (finalVoices, leadingCount) = prependingScoreStateKeepingTuplets(
            voiceList, clef: bar.emitClef, key: bar.emitKey, time: bar.emitTime,
        )
        recordGeometry(
            bar.geometry, reconciled: reconciled, staffMidY: staffMidY,
            leadingCount: leadingCount, importMeasure: measure, slot: bar.slot,
            measureIndex: bar.measureIndexOffset + bar.measureIndex, pageIndex: bar.pageIndex,
            placements: split.placements,
        )
        return Measure(voices: finalVoices)
    }

    /// The legacy chain's text steps on a bar's elements: tuplet numerals read before lyrics, so a
    /// numeral is no syllable, and both before any repair, so it sees the tuplets the page wrote.
    /// A page with no text — every page FretCodex's `PageReader` makes — is unchanged.
    static func readingText(_ bar: RepairBar, _ elements: [RhythmElement]) -> [RhythmElement] {
        guard !bar.texts.isEmpty else { return elements }
        let measure = bar.importMeasure
        let marks = detectTupletMarks(
            texts: bar.texts, paths: bar.paths, staffYLines: measure.staffYLines, xRange: measure.xRange,
            pageIndex: bar.pageIndex,
        )
        let withLyrics = attachLyrics(
            elements: elements, texts: bar.texts, staffYLines: measure.staffYLines, pageIndex: bar.pageIndex,
            xRange: measure.xRange, nextStaffTopY: bar.nextStaffTopY, excludingOrigins: marks.map(\.digitOrigin),
        )
        return applyTupletMarks(elements: withLyrics, marks: marks, spatium: bar.spatium)
    }

    /// The legacy chain after the rhythm decode and its text: upstream's repair, voices and prepend.
    private static func legacyTail(_ bar: RepairBar, elements rhythm: [RhythmElement], staffMidY: CGFloat) -> Measure {
        let measure = bar.importMeasure
        let reconciled = reconcileMeasureDurations(
            elements: rhythm, timeSignature: bar.ts, spatium: bar.spatium,
            diagnostics: bar.options.diagnostics, location: bar.location,
        )
        let voices = assignVoices(
            elements: reconciled, measureXRange: measure.xRange, timeSignature: bar.ts,
            staffMidY: staffMidY, diagnostics: bar.options.diagnostics, location: bar.location,
        )
        let (finalVoices, leadingCount) = prependingScoreState(
            voices, clef: bar.emitClef, key: bar.emitKey, time: bar.emitTime,
        )
        recordGeometry(
            bar.geometry, reconciled: reconciled, staffMidY: staffMidY,
            leadingCount: leadingCount, importMeasure: measure, slot: bar.slot,
            measureIndex: bar.measureIndexOffset + bar.measureIndex, pageIndex: bar.pageIndex,
        )
        return Measure(voices: finalVoices)
    }
}
