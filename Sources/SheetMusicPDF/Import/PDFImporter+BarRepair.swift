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
        let referee = passes.contains(.revertRule) && bar.meterFromDigits
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
        func decode(columns: Bool) -> ([RhythmElement], BarEvidence) {
            var chosen = passes.subtracting(.columnChords)
            if columns { chosen.insert(.columnChords) }
            var (elements, evidence) = decodeRhythmWithEvidence(
                measure: measure, decoded: decoded, paths: bar.paths, tieMarks: bar.tieMarks,
                graceSizeThreshold: bar.graceSizeThreshold, stemHeadEndTolerance: bar.stemHeadEndTolerance,
                passes: chosen,
            )
            guard !passes.isEmpty else { return (elements, evidence) }
            // P1 and P2 follow the ink alone; off, they still mark P6's alternatives.
            applyDotColumns(&elements, bar: evidence, apply: passes.contains(.dotColumns))
            applyFlagsInSpaces(&elements, bar: evidence, flagBand: yBand, apply: passes.contains(.flagsInSpaces))
            return (elements, evidence)
        }
        var (elements, evidence) = decode(columns: false)
        if let probe = bar.options.barRepairProbe {
            probeBar(evidence, location: bar.location + ", slot \(bar.slot)", probe: probe)
        }
        if passes.isEmpty {
            return legacyTail(bar, elements: elements, staffMidY: staffMidY)
        }
        // P4, reverted where it leaves fewer voices summing under a stacked-digit meter.
        if passes.contains(.columnChords) {
            let (columned, columnedEvidence) = decode(columns: true)
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
        if passes.contains(.repairSearch) {
            for (v, group) in split.groups.enumerated() {
                let outcome = repairVoice(group, elements: &reconciled, bar: evidence, ts: bar.ts, passes: passes)
                if case let .unfit(why) = outcome {
                    bar.options.diagnostics?(PDFImportDiagnostic(
                        severity: .warning, location: bar.location,
                        message: "bar repair: voice \(v + 1) does not sum to the bar, left as read (\(why))",
                        context: "slot \(bar.slot)",
                    ))
                }
            }
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
        if let probe = bar.options.barRepairProbe {
            for (i, e) in reconciled.enumerated() {
                let pitches = e.chord.notes.values.map { String($0.pitch) }.joined(separator: "+")
                let stem = e.evidence?.stem.map { String($0) } ?? (e.evidence?.virtualStem == true ? "virtual" : "-")
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

    /// The legacy chain after the rhythm decode: upstream's repair, voices and prepend.
    private static func legacyTail(_ bar: RepairBar, elements rhythm: [RhythmElement], staffMidY: CGFloat) -> Measure {
        let measure = bar.importMeasure
        // A raster page carries no text, so no tuplet mark and no lyric: the legacy chain's
        // `detectTupletMarks` / `attachLyrics` / `applyTupletMarks` are no-ops here.
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
