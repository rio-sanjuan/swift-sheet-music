#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Foundation
import SheetMusicCore

// P4, COLUMN CHORDS (F4, `BarRepairPasses.columnChords`). Upstream starts a chord from a head with
// a stem and admits a mate only on the lead's own stem, so a column of heads whose stem the raster
// missed, or whose mate snapped to a neighbouring stroke, splits into successive notes or into two
// voices. Here a bar's heads are grouped into columns first — by x, with a mirrored second joined
// across the stem — and each column becomes one chord, unless two stems in opposite directions
// hold disjoint heads (a drum crash over a kick), which stay two.

extension PDFImporter {
    /// Heads within this many staff spaces in x, chained, are one column.
    static let columnLinkInSpaces: CGFloat = 0.6

    static func columnChordElements(
        _ c: ChordContext, graces: Set<Int>, bar: BarEvidence, passes: BarRepairPasses,
    ) -> [RhythmElement] {
        let sp = c.spatium
        var elements: [RhythmElement] = []
        var heads: [Int] = []
        for (i, g) in c.glyphs.enumerated() where !graces.contains(i) {
            if case let .rest(dur) = g.semantic {
                elements.append(makeRest(glyph: g, duration: dur, spatium: sp))
            } else if isNotehead(g.semantic) {
                heads.append(i)
            }
        }
        heads.sort { headKey(c.glyphs[$0], $0) < headKey(c.glyphs[$1], $1) }
        // Single linkage in x.
        var columns: [[Int]] = []
        for h in heads {
            if let last = columns.last?.last,
               c.glyphs[h].geometry.origin.x - c.glyphs[last].geometry.origin.x <= columnLinkInSpaces * sp
            {
                columns[columns.count - 1].append(h)
            } else {
                columns.append([h])
            }
        }
        let nearest: [Int: Int?] = Dictionary(uniqueKeysWithValues: heads.map { h in
            (h, nearestStem(
                toX: c.glyphs[h].geometry.origin.x, noteY: c.glyphs[h].geometry.origin.y,
                stems: c.stems, spatium: sp,
            )?.index)
        })
        columns = joiningMirroredSeconds(columns, c, nearest: nearest)
        for column in columns {
            for chord in chordsOfColumn(column, c, nearest: nearest, passes: passes) {
                let lead = chord.heads.min { headKey(c.glyphs[$0], $0) < headKey(c.glyphs[$1], $1) } ?? chord.heads[0]
                elements.append(chordElement(
                    lead: lead, cluster: chord.heads.sorted(), stemIndex: chord.stem,
                    virtual: chord.stem == nil && chord.heads.count > 1, c,
                ))
            }
        }
        return elements
    }

    /// A head's total sort key: x, y, kind, index.
    static func headKey(_ g: ClassifiedGlyph, _ i: Int) -> (CGFloat, CGFloat, Int, Int) {
        (g.geometry.origin.x, g.geometry.origin.y, isFilledNotehead(g.semantic) ? 0 : 1, i)
    }

    /// A column whose every head is a second (0.25–0.75 sp) from a head of the column before it,
    /// within 1.35 sp in x and on no stem of its own but that column's, is that column's mirrored
    /// head.
    static func joiningMirroredSeconds(_ columns: [[Int]], _ c: ChordContext, nearest: [Int: Int?]) -> [[Int]] {
        let sp = c.spatium
        var out: [[Int]] = []
        for column in columns {
            guard let previous = out.last else { out.append(column); continue }
            let previousStems = Set(previous.compactMap { nearest[$0] ?? nil })
            let mirrored = column.allSatisfy { h in
                let g = c.glyphs[h].geometry.origin
                let ownStem = nearest[h] ?? nil
                guard ownStem == nil || previousStems.contains(ownStem!) else { return false }
                return previous.contains { p in
                    let q = c.glyphs[p].geometry.origin
                    let dy = abs(g.y - q.y)
                    return g.x - q.x <= chordMateWindowInSpaces * sp && dy >= 0.25 * sp && dy <= 0.75 * sp
                }
            }
            if mirrored {
                out[out.count - 1] += column
            } else {
                out.append(column)
            }
        }
        return out
    }

    /// The chords a column of heads makes, each with its stem (nil: none found).
    static func chordsOfColumn(
        _ column: [Int], _ c: ChordContext, nearest: [Int: Int?], passes: BarRepairPasses,
    ) -> [(heads: [Int], stem: Int?)] {
        let sp = c.spatium
        let window = stemAttachWindow(spatium: sp)
        let ys = column.map { c.glyphs[$0].geometry.origin.y }
        // One found stem along every head: one chord.
        let spanning = c.stems.indices.filter { si in
            let s = c.stems[si]
            return column.allSatisfy { h in
                let o = c.glyphs[h].geometry.origin
                return abs(s.rect.midX - o.x) <= window
                    && o.y >= s.rect.minY - 0.75 * sp && o.y <= s.rect.maxY + 0.75 * sp
            }
        }
        let byCost = spanning.min { a, b in
            let ca = column.map { stemCost(c.stems[a], x: c.glyphs[$0].geometry.origin.x, noteY: c.glyphs[$0].geometry.origin.y) }.reduce(0, +)
            let cb = column.map { stemCost(c.stems[b], x: c.glyphs[$0].geometry.origin.x, noteY: c.glyphs[$0].geometry.origin.y) }.reduce(0, +)
            return (ca, a) < (cb, b)
        }
        if let stem = byCost { return [(column, stem)] }
        // The heads' own stems, in index order.
        let owned = Array(Set(column.compactMap { nearest[$0] ?? nil })).sorted()
        if owned.isEmpty {
            // No stem: one chord on a virtual stem — but a black and a hollow head with no stem
            // to share are two notes.
            let filled = column.filter { isFilledNotehead(c.glyphs[$0].semantic) }
            let hollow = column.filter { !isFilledNotehead(c.glyphs[$0].semantic) }
            if passes.contains(.headKindRule), !filled.isEmpty, !hollow.isEmpty {
                return [(filled, nil), (hollow, nil)]
            }
            return [(column, nil)]
        }
        // Heads on their stems; a stemless head joins the stem whose span reaches it, else the
        // one nearest in y.
        var groups: [Int: [Int]] = [:]
        for h in column {
            if let own = nearest[h] ?? nil {
                groups[own, default: []].append(h)
                continue
            }
            let y = c.glyphs[h].geometry.origin.y
            let target = owned.min { a, b in
                (stemYDistance(c.stems[a], noteY: y), a) < (stemYDistance(c.stems[b], noteY: y), b)
            }!
            groups[target, default: []].append(h)
        }
        _ = ys
        return owned.map { (groups[$0] ?? [], $0) }.filter { !$0.heads.isEmpty }
    }
}
