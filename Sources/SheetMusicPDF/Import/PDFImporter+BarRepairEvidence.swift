#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Foundation
import SheetMusicCore

// THE BAR REPAIR'S EVIDENCE (F4). `decodeRhythmWithEvidence` decodes a bar as `decodeRhythm` does
// — with every pass off its elements are `decodeRhythm`'s exactly — and keeps beside each element
// how its value was read (head kind, beam or flag level, dots, stem) and, per stem, what the beam
// lines say: the full beams and stubs over it, its beam group, and the lines the raster found at
// its bare end. The passes (PDFImporter+BarRepairMarks, +Chords, +Voices, +Search) read these.

/// What the beam lines say about one stem of a bar.
struct StemEvidence: Equatable {
    var index: Int
    var x: CGFloat
    var loY: CGFloat
    var hiY: CGFloat
    /// The end beams and flags attach to — away from the head — and whether it is the top end.
    var bareEndY: CGFloat?
    var up: Bool?
    /// Full beams over it (spanning two stems or more) and stubs it owns.
    var fullCount = 0
    var stubCount = 0
    /// Its beam group — the smallest stem index in it — and the group's size.
    var groupRoot: Int
    var groupSize = 1
    /// The level `computeBeamLevels` gives it (upstream's).
    var level = 0
    /// Distinct beam lines (0.35 sp apart) covering its x within 0.5 sp, their middle −0.9…+2.9 sp
    /// from the bare end toward the head — counted over every beam overlapping the bar.
    var levelHint = 0
    /// A beam line ends no more than 3 sp short of it, on the line through its bare end.
    var extrapolated = false
    /// Kept by the beam rescue: refused by the head-end gate, a beam reaching its far end.
    var rescued = false

    /// A stub owned by a stem no full beam reaches: the primary beam was lost, the note has at
    /// least two levels.
    var stubImpliesPrimary: Bool { stubCount > 0 && fullCount == 0 }
}

/// How one element's value was read, and what else the ink allows.
struct ElementEvidence {
    /// The value its head kind gives (quarter for black, half, whole).
    var base: NoteDuration
    var filled: Bool
    /// Halvings from beams or a flag.
    var level = 0
    var levelFromFlag = false
    var dots = 0
    /// Its stem in `BarEvidence.stems`; nil with no stem.
    var stem: Int?
    /// A column with no stem found, read as one chord (P4); it takes no beam and no flag.
    var virtualStem = false
    var stemUp: Bool?
    /// Its heads, as indices into the bar's x-sorted glyphs.
    var heads: [Int] = []
    /// A head of the other fill within 0.3 sp of one of its heads, or a flag beside a hollow
    /// head: the other kind is an alternative.
    var otherFill = false
    /// A dot glyph no head owns, in the relaxed window of one of its heads (P6 may add a dot).
    var dotAdd = false
    /// One of its dots is nearer another element's head (P6 may remove it).
    var dotRemove = false
    /// A flag within 1 sp of the bare end that P2 did not apply (P6 may apply it).
    var looseFlagLevel: Int?
    /// A flag P2 found at the stem of a hollow head (which it does not shorten): the level the
    /// head's black alternative takes.
    var flagBesideHollow = 0

    /// The value the components give.
    var duration: NoteDuration {
        let d = PDFImporter.durationForBeamLevels(level, base: base)
        return dots > 0 ? d.dotted(dots) : d
    }
}

/// What a bar's evidence builder found.
struct BarEvidence {
    var stems: [StemEvidence] = []
    /// The bar's glyphs, x-sorted as the decode saw them, and which of them are graces.
    var glyphs: [ClassifiedGlyph] = []
    var graces: Set<Int> = []
    var spatium: CGFloat = 8
    var staffYLines: [CGFloat] = []
    /// The stem paths, by `StemEvidence.index`.
    var stemPaths: [PathSegment] = []
    /// Every beam overlapping the bar in x and in the staff's band.
    var beams: [PathSegment] = []
}

extension PDFImporter {
    /// `decodeRhythm`, keeping its evidence. `passes` may add rescued stems (`.beamRescue`) and
    /// group heads into column chords (`.columnChords`); the value passes run after it.
    static func decodeRhythmWithEvidence(
        measure: ImportMeasure,
        decoded: [DecodedPitch],
        paths: [PathSegment],
        tieMarks: TieMarks,
        graceSizeThreshold: CGFloat,
        stemHeadEndTolerance: CGFloat,
        passes: BarRepairPasses,
    ) -> (elements: [RhythmElement], bar: BarEvidence) {
        var pitchByGlyph: [ClassifiedGlyph: DecodedPitch] = [:]
        for dp in decoded {
            pitchByGlyph[dp.glyph] = dp
        }
        let glyphs = measure.glyphs.sorted { $0.geometry.origin.x < $1.geometry.origin.x }
        let spatium = staffSpatium(measure.staffYLines)
        let yBand = staffBeamBand(measure.staffYLines)
        var stems = paths.filter {
            isStem(in: measure, $0, noteheads: glyphs, spatium: spatium, headEndTolerance: stemHeadEndTolerance)
                && segmentOverlapsBand($0, yBand)
        }
        let legacyStemCount = stems.count
        let beams = paths.filter {
            $0.kind == .beam && measure.xRange.contains($0.rect.midX) && segmentOverlapsBand($0, yBand)
        }
        let overlapping = paths.filter {
            $0.kind == .beam && $0.rect.maxX >= measure.xRange.lowerBound
                && $0.rect.minX <= measure.xRange.upperBound && segmentOverlapsBand($0, yBand)
        }
        if passes.contains(.beamRescue) {
            stems += rescuedStems(
                measure: measure, paths: paths, stems: stems, glyphs: glyphs, beams: overlapping,
                spatium: spatium, yBand: yBand,
            )
        }
        let graceIndices = graceNoteheadIndices(glyphs: glyphs, threshold: graceSizeThreshold)
        let noteheadOrigins = glyphs.filter { isNotehead($0.semantic) }.map(\.geometry.origin)
        let levelByStem = computeBeamLevels(
            stems: stems, beams: beams, noteheadOrigins: noteheadOrigins, spatium: spatium,
        )
        var bar = BarEvidence(
            stems: stemEvidence(
                stems: stems, beams: beams, overlapping: overlapping, noteheadOrigins: noteheadOrigins,
                levels: levelByStem, spatium: spatium,
            ),
            glyphs: glyphs, graces: graceIndices, spatium: spatium, staffYLines: measure.staffYLines,
            stemPaths: stems, beams: overlapping,
        )
        for i in legacyStemCount ..< stems.count {
            bar.stems[i].rescued = true
        }
        let context = ChordContext(
            glyphs: glyphs, stems: stems, levelByStem: levelByStem, flagBand: yBand,
            pitchByGlyph: pitchByGlyph, tieMarks: tieMarks, spatium: spatium,
        )
        var elements: [RhythmElement] = []
        if passes.contains(.columnChords) {
            elements = columnChordElements(context, graces: graceIndices, bar: bar, passes: passes)
        } else {
            var consumed = graceIndices
            for (i, g) in glyphs.enumerated() where !consumed.contains(i) {
                switch g.semantic {
                case let .rest(dur):
                    elements.append(makeRest(glyph: g, duration: dur, spatium: spatium))
                    consumed.insert(i)
                case .noteheadBlack, .noteheadHalf,
                     .noteheadWhole, .noteheadDoubleWhole,
                     .noteheadXBlack, .noteheadXHalf, .noteheadXWhole:
                    let cluster = stemCluster(startingAt: i, in: glyphs, stems: stems, spatium: spatium)
                    consumed.formUnion(cluster.indices)
                    elements.append(chordElement(
                        lead: i, cluster: cluster.indices, stemIndex: cluster.stemIndex, context,
                    ))
                default:
                    continue
                }
            }
        }
        for i in elements.indices where !elements[i].isRest {
            markOtherFill(&elements[i], glyphs: glyphs, spatium: spatium)
        }
        let graces = buildGraceChords(
            indices: graceIndices, glyphs: glyphs, pitchByGlyph: pitchByGlyph, tieMarks: tieMarks,
        )
        let sorted = elements.sorted { $0.x < $1.x }
        return (attachGraces(graces, to: sorted), bar)
    }

    /// What `assembleChord` reads with.
    struct ChordContext {
        var glyphs: [ClassifiedGlyph]
        var stems: [PathSegment]
        var levelByStem: [Int: Int]
        var flagBand: ClosedRange<CGFloat>?
        var pitchByGlyph: [ClassifiedGlyph: DecodedPitch]
        var tieMarks: TieMarks
        var spatium: CGFloat
    }

    /// `assembleChord`'s element for a cluster already chosen, with its evidence. With a stem it
    /// reads exactly as `assembleChord`; `virtual` marks a column chord with no stem found.
    static func chordElement(
        lead: Int, cluster: [Int], stemIndex: Int?, virtual: Bool = false, _ c: ChordContext,
    ) -> RhythmElement {
        let leadGlyph = c.glyphs[lead]
        let stem = stemIndex.map { c.stems[$0] }
        let (notes, noteRects) = buildChordNotes(
            clusterIndices: cluster, glyphs: c.glyphs, pitchByGlyph: c.pitchByGlyph,
            tieMarks: c.tieMarks, spatium: c.spatium,
        )
        let base = baseDuration(for: leadGlyph.semantic)
        var evidence = ElementEvidence(base: base, filled: isFilledNotehead(leadGlyph.semantic))
        evidence.stem = stemIndex
        evidence.virtualStem = virtual
        evidence.heads = cluster
        if base == .quarter, let si = stemIndex {
            evidence.level = c.levelByStem[si] ?? 0
        }
        if evidence.level == 0 {
            evidence.level = flagLevelAttached(
                glyphs: c.glyphs, stem: stem, lead: leadGlyph, flagBand: c.flagBand, spatium: c.spatium,
            )
            evidence.levelFromFlag = evidence.level > 0
        }
        evidence.dots = dotCountBeside(glyphs: c.glyphs, lead: leadGlyph)
        let dir = stem.map { s in
            stemDirection(of: s, noteheadYs: cluster.map { c.glyphs[$0].geometry.origin.y })
        }
        evidence.stemUp = dir.map { $0 == .up }
        return RhythmElement(
            chord: Chord(duration: evidence.duration, notes: ChordNotes(notes)),
            x: leadGlyph.geometry.origin.x,
            y: leadGlyph.geometry.origin.y,
            stemDirection: dir,
            beamGroup: nil,
            lowConfidenceDuration: evidence.levelFromFlag,
            noteheadIsFilled: isFilledNotehead(leadGlyph.semantic),
            noteRects: noteRects,
            onsetRect: PDFGeometryRects.union(noteRects),
            evidence: evidence,
        )
    }

    /// A head of the other fill within 0.3 sp of one of the element's heads — a black and a
    /// hollow detection at one spot, which upstream's pitch dedup silently settles by position.
    static func markOtherFill(_ element: inout RhythmElement, glyphs: [ClassifiedGlyph], spatium: CGFloat) {
        guard var evidence = element.evidence else { return }
        let reach = 0.3 * spatium
        for h in evidence.heads {
            let head = glyphs[h]
            let filled = isFilledNotehead(head.semantic)
            if glyphs.contains(where: { g in
                isNotehead(g.semantic) && isFilledNotehead(g.semantic) != filled
                    && abs(g.geometry.origin.x - head.geometry.origin.x) <= reach
                    && abs(g.geometry.origin.y - head.geometry.origin.y) <= reach
            }) {
                evidence.otherFill = true
            }
        }
        element.evidence = evidence
    }

    // MARK: - Stems

    /// Per-stem beam evidence: upstream's level, the full beams and stubs, the beam group, and the
    /// lines at the bare end (`levelHint`, `extrapolated`).
    static func stemEvidence(
        stems: [PathSegment], beams: [PathSegment], overlapping: [PathSegment],
        noteheadOrigins: [CGPoint], levels: [Int: Int], spatium: CGFloat,
    ) -> [StemEvidence] {
        let infos: [StemInfo] = stems.enumerated().map { idx, stem in
            StemInfo(
                index: idx, x: stem.rect.midX, loY: stem.rect.minY, hiY: stem.rect.maxY,
                beamedEndY: beamedEnd(
                    loY: stem.rect.minY, hiY: stem.rect.maxY, stemX: stem.rect.midX,
                    noteheads: noteheadOrigins, spatium: spatium,
                ),
            )
        }
        let reach = BeamReach.forSpatium(spatium)
        var full: [PathSegment] = []
        var stubs: [PathSegment] = []
        for b in beams where b.kind == .beam {
            if infos.count(where: { fullBeamSpans(b, stem: $0, reach: reach) }) >= 2 {
                full.append(b)
            } else {
                stubs.append(b)
            }
        }
        var out = infos.map { s in
            StemEvidence(
                index: s.index, x: s.x, loY: s.loY, hiY: s.hiY, bareEndY: s.beamedEndY,
                up: s.beamedEndY.map { $0 == s.hiY }, groupRoot: s.index, level: levels[s.index] ?? 0,
            )
        }
        var uf = UnionFind(ids: infos.map(\.index))
        for beam in full {
            var members: [Int] = []
            for s in infos {
                if fullBeamSpans(beam, stem: s, reach: reach) {
                    out[s.index].fullCount += 1
                    members.append(s.index)
                } else if stemInBeamGroup(beam, stem: s, reach: reach) {
                    members.append(s.index)
                }
            }
            for k in members.indices.dropFirst() {
                uf.union(members[0], members[k])
            }
        }
        for stub in stubs {
            if let owner = stubOwner(stub, stems: infos, reach: reach) { out[owner].stubCount += 1 }
        }
        // Group roots: the smallest stem index of each component — never a Set's order.
        var rootOf: [Int] = infos.map { uf.find($0.index) }
        var smallest: [Int: Int] = [:]
        for s in infos {
            smallest[rootOf[s.index]] = min(smallest[rootOf[s.index]] ?? s.index, s.index)
        }
        rootOf = rootOf.map { smallest[$0] ?? $0 }
        for s in infos {
            out[s.index].groupRoot = rootOf[s.index]
            out[s.index].groupSize = rootOf.count { $0 == rootOf[s.index] }
            out[s.index].levelHint = levelHint(out[s.index], beams: overlapping, spatium: spatium)
            if out[s.index].levelHint == 0 {
                out[s.index].extrapolated = reachesByExtrapolation(out[s.index], beams: overlapping, spatium: spatium)
            }
        }
        return out
    }

    /// How deep a beam's middle at `x` sits below (toward the head of) a stem's bare end, in
    /// points; `extending` takes the beam's lines past its ends instead of clamping.
    static func beamDepth(_ beam: PathSegment, at x: CGFloat, stem s: StemEvidence, extending: Bool = false) -> CGFloat? {
        guard let bare = s.bareEndY, let up = s.up else { return nil }
        let mid: CGFloat
        if let q = beam.quad {
            mid = extending
                ? ((q.topSlope + q.botSlope) * x + q.topIntercept + q.botIntercept) / 2
                : (q.topY(at: x) + q.botY(at: x)) / 2
        } else {
            mid = beam.rect.midY
        }
        return up ? bare - mid : mid - bare
    }

    /// The taxonomy's own count of beam lines at a stem (ADR 0006, round 3): lines covering its x
    /// within 0.5 sp whose middle is −0.9…+2.9 sp from its bare end, 0.35 sp apart.
    static func levelHint(_ s: StemEvidence, beams: [PathSegment], spatium sp: CGFloat) -> Int {
        let depths = beams.compactMap { beam -> CGFloat? in
            let lo = beam.quad?.xRange.lowerBound ?? beam.rect.minX
            let hi = beam.quad?.xRange.upperBound ?? beam.rect.maxX
            guard s.x >= lo - 0.5 * sp, s.x <= hi + 0.5 * sp,
                  let depth = beamDepth(beam, at: s.x, stem: s),
                  depth >= -0.9 * sp, depth <= 2.9 * sp
            else { return nil }
            return depth
        }.sorted()
        var count = 0
        var last = -CGFloat.greatestFiniteMagnitude
        for depth in depths where depth - last > 0.35 * sp {
            count += 1
            last = depth
        }
        return count
    }

    /// A beam line ending no more than 3 sp short of the stem, whose line carried on reaches the
    /// stem's bare end (−0.9…+2.9 sp, as `levelHint`).
    static func reachesByExtrapolation(_ s: StemEvidence, beams: [PathSegment], spatium sp: CGFloat) -> Bool {
        beams.contains { beam in
            let lo = beam.quad?.xRange.lowerBound ?? beam.rect.minX
            let hi = beam.quad?.xRange.upperBound ?? beam.rect.maxX
            let short = s.x < lo ? lo - s.x : s.x - hi
            guard short > 0.5 * sp, short <= 3 * sp,
                  let depth = beamDepth(beam, at: s.x, stem: s, extending: true)
            else { return false }
            return depth >= -0.9 * sp && depth <= 2.9 * sp
        }
    }

    /// P3's stem rescue: a vertical in the bar, beside a head, that the head-end gate refused,
    /// kept when a beam line reaches its far end — the end away from the head — within 0.6 sp.
    static func rescuedStems(
        measure: ImportMeasure, paths: [PathSegment], stems: [PathSegment], glyphs: [ClassifiedGlyph],
        beams: [PathSegment], spatium sp: CGFloat, yBand: ClosedRange<CGFloat>?,
    ) -> [PathSegment] {
        let heads = glyphs.filter { isNotehead($0.semantic) }
        let window = stemAttachWindow(spatium: sp)
        return paths.filter { path in
            guard path.kind == .vertical, segmentOverlapsBand(path, yBand), !stems.contains(path),
                  path.rect.height >= 2 * sp,
                  isStem(in: measure, path, noteheads: glyphs, spatium: sp, headEndTolerance: .greatestFiniteMagnitude)
            else { return false }
            let x = path.rect.midX
            // The head beside it, by the nearer end.
            guard let head = heads.filter({ abs($0.geometry.origin.x - x) <= window })
                .min(by: { a, b in
                    min(abs(a.geometry.origin.y - path.rect.minY), abs(a.geometry.origin.y - path.rect.maxY))
                        < min(abs(b.geometry.origin.y - path.rect.minY), abs(b.geometry.origin.y - path.rect.maxY))
                })
            else { return false }
            let y = head.geometry.origin.y
            // The head must still be along the stem, within a space and a half of an end.
            guard min(abs(y - path.rect.minY), abs(y - path.rect.maxY)) <= 1.5 * sp else { return false }
            let farEnd = abs(path.rect.maxY - y) >= abs(path.rect.minY - y) ? path.rect.maxY : path.rect.minY
            return beams.contains { beam in
                let lo = beam.quad?.xRange.lowerBound ?? beam.rect.minX
                let hi = beam.quad?.xRange.upperBound ?? beam.rect.maxX
                guard x >= lo - 0.5 * sp, x <= hi + 0.5 * sp else { return false }
                let mid = beam.quad.map { ($0.topY(at: x) + $0.botY(at: x)) / 2 } ?? beam.rect.midY
                return abs(mid - farEnd) <= 0.6 * sp
            }
        }
    }
}
