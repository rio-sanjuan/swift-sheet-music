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
        // A whole or double-whole head has no stem by nature: it never takes one, so a stem
        // beside it — another voice's — cannot pull it into its chord.
        let nearest: [Int: Int?] = Dictionary(uniqueKeysWithValues: heads.map { h in
            (h, isStemlessHead(c.glyphs[h].semantic) ? nil : nearestStem(
                toX: c.glyphs[h].geometry.origin.x, noteY: c.glyphs[h].geometry.origin.y,
                stems: c.stems, spatium: sp,
            )?.index)
        })
        columns = joiningMirroredSeconds(columns, c, nearest: nearest, anySecond: passes.contains(.mirroredChords))
        for column in columns {
            for chord in chordsOfColumn(column, c, nearest: nearest, passes: passes) {
                // On a stem, a head read as whole never sets the value: the stem says it is not one.
                let candidates = chord.stem == nil ? chord.heads
                    : chord.heads.filter { !isStemlessHead(c.glyphs[$0].semantic) }
                let lead = (candidates.isEmpty ? chord.heads : candidates)
                    .min { headKey(c.glyphs[$0], $0) < headKey(c.glyphs[$1], $1) } ?? chord.heads[0]
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
    /// within 1.35 sp in x and on that column's stem (or, with no stem, beside a column with none),
    /// is that column's mirrored head.
    ///
    /// With `anySecond` (`.mirroredChords`, F6), a stemmed column on the column before's stem joins
    /// it when one of its heads is a second from one of that column's: a chord's displaced head
    /// stands across the stem with the heads above it a third or more from those left behind.
    static func joiningMirroredSeconds(_ columns: [[Int]], _ c: ChordContext, nearest: [Int: Int?], anySecond: Bool = false) -> [[Int]] {
        let sp = c.spatium
        var out: [[Int]] = []
        for column in columns {
            guard let previous = out.last else { out.append(column); continue }
            let previousStems = Set(previous.compactMap { nearest[$0] ?? nil })
            func second(_ h: Int) -> Bool {
                let g = c.glyphs[h].geometry.origin
                return previous.contains { p in
                    let q = c.glyphs[p].geometry.origin
                    let dy = abs(g.y - q.y)
                    return g.x - q.x <= chordMateWindowInSpaces * sp && dy >= 0.25 * sp && dy <= 0.75 * sp
                }
            }
            if anySecond, !previousStems.isEmpty,
               column.allSatisfy({ h in (nearest[h] ?? nil).map(previousStems.contains) ?? false }), column.contains(where: second) {
                out[out.count - 1] += column
                continue
            }
            let mirrored = column.allSatisfy { h in
                let g = c.glyphs[h].geometry.origin
                let ownStem = nearest[h] ?? nil
                // On the column's own stem — or, stemless, beside a column with none: a head with
                // no stem beside a stemmed note a second away is as likely a second voice.
                if let ownStem { guard previousStems.contains(ownStem) else { return false } }
                else { guard previousStems.isEmpty else { return false } }
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

    /// A whole, double-whole or x-whole head: one written with no stem.
    static func isStemlessHead(_ s: SMuFLSemantic) -> Bool {
        switch s {
        case .noteheadWhole, .noteheadDoubleWhole, .noteheadXWhole: true
        default: false
        }
    }

    /// The chords a column of heads makes, each with its stem (nil: none found). Its whole notes
    /// are a chord of their own, on no stem: a whole note under another voice's quarter is a
    /// second voice, never that quarter's head.
    static func chordsOfColumn(
        _ column: [Int], _ c: ChordContext, nearest: [Int: Int?], passes: BarRepairPasses,
    ) -> [(heads: [Int], stem: Int?)] {
        let wholes = column.filter { isStemlessHead(c.glyphs[$0].semantic) }
        if !wholes.isEmpty {
            let rest = column.filter { !isStemlessHead(c.glyphs[$0].semantic) }
            // Unless a found stem runs along every head, the whole-classified ones ON it (within
            // a quarter space of its span, where a chord's end head sits): then the "whole" is a
            // misread head of that chord — no stemmed chord has a whole — and joins it.
            if !rest.isEmpty, let stem = stemAlongEvery(rest, wholes: wholes, c) { return [(column, stem)] }
            return [(wholes, nil)] + (rest.isEmpty ? [] : stemmedChordsOfColumn(rest, c, nearest: nearest, passes: passes))
        }
        return stemmedChordsOfColumn(column, c, nearest: nearest, passes: passes)
    }

    /// A stem along every head of `heads` (as `stemmedChordsOfColumn`'s spanning test) with each
    /// of `wholes` within a quarter space of its span.
    private static func stemAlongEvery(_ heads: [Int], wholes: [Int], _ c: ChordContext) -> Int? {
        let sp = c.spatium
        let window = stemAttachWindow(spatium: sp)
        func along(_ s: PathSegment, _ h: Int, slack: CGFloat) -> Bool {
            let o = c.glyphs[h].geometry.origin
            return abs(s.rect.midX - o.x) <= window && o.y >= s.rect.minY - slack * sp && o.y <= s.rect.maxY + slack * sp
        }
        return c.stems.indices.first { si in
            heads.allSatisfy { along(c.stems[si], $0, slack: 0.75) } && wholes.allSatisfy { along(c.stems[si], $0, slack: 0.25) }
        }
    }

    private static func stemmedChordsOfColumn(
        _ column: [Int], _ c: ChordContext, nearest: [Int: Int?], passes: BarRepairPasses,
    ) -> [(heads: [Int], stem: Int?)] {
        let sp = c.spatium
        let window = stemAttachWindow(spatium: sp)
        // The heads' own stems, in index order.
        let owned = Array(Set(column.compactMap { nearest[$0] ?? nil })).sorted()
        // Two stems, one up from the upper heads and one down from the lower ones: two chords,
        // one a voice — a crash over a kick, or two voices a second or a third apart. Checked
        // before a stem along every head, which a second voice's head half a space off its end
        // would pass.
        if owned.count >= 2 {
            func heads(_ si: Int) -> [CGFloat] { column.filter { nearest[$0] == si }.map { c.glyphs[$0].geometry.origin.y } }
            func up(_ si: Int) -> Bool { c.stems[si].rect.midY > (heads(si).reduce(0, +) / CGFloat(max(1, heads(si).count))) }
            let ups = owned.filter(up), downs = owned.filter { !up($0) }
            let lowestUp = ups.flatMap(heads).min(), highestDown = downs.flatMap(heads).max()
            if let lowestUp, let highestDown, lowestUp > highestDown {
                return grouped(column, owned: owned, c, nearest: nearest)
            }
        }
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
        return grouped(column, owned: owned, c, nearest: nearest)
    }

    /// A column's heads on their own stems; a stemless head joins the stem nearest it in y.
    static func grouped(
        _ column: [Int], owned: [Int], _ c: ChordContext, nearest: [Int: Int?],
    ) -> [(heads: [Int], stem: Int?)] {
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
        return owned.map { (groups[$0] ?? [], $0) }.filter { !$0.heads.isEmpty }
    }
}
