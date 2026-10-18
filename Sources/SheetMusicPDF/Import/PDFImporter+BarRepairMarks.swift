#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Foundation
import SheetMusicCore

// THE BAR REPAIR'S INK PASSES (F4): P1 dots by column, P2 flags in spaces, P3 beam rescue. Each
// reads only ink in the bar and changes a value only where the ink says so; none is reverted.

extension PDFImporter {
    // MARK: - P1: dots by column

    /// A dot's owner: the nearest head to its left with dx 0.5–1.6 sp and |dy| ≤ 0.75 sp.
    static let dotOwnerDXInSpaces: ClosedRange<CGFloat> = 0.5 ... 1.6
    static let dotOwnerDYInSpaces: CGFloat = 0.75
    /// Dots within this many spaces in x are one column.
    static let dotColumnInSpaces: CGFloat = 0.3

    /// P1. Each dot glyph is owned by one head — the nearest to its left in the window, staccatos
    /// excluded — and an element has as many dots as it owns dot COLUMNS (at most 2), never one
    /// per glyph: a dotted chord's dots stand in a column, one per head. Elements left with an
    /// unowned dot in a looser window, or a dot nearer another element's head, are marked for P6.
    static func applyDotColumns(_ elements: inout [RhythmElement], bar: BarEvidence, apply: Bool) {
        let sp = bar.spatium
        let glyphs = bar.glyphs
        var headOwner: [(head: Int, element: Int)] = []
        for (e, element) in elements.enumerated() {
            for h in element.evidence?.heads ?? [] { headOwner.append((h, e)) }
        }
        headOwner.sort { headKey(glyphs[$0.head], $0.head) < headKey(glyphs[$1.head], $1.head) }
        let dots = glyphs.indices.filter {
            if case .augmentationDot = glyphs[$0].semantic {
                return !isStaccatoOfSomeNotehead(glyphs[$0], in: glyphs)
            }
            return false
        }
        var owned: [Int: [Int]] = [:] // element → dot glyphs
        var unowned: [Int] = []
        for d in dots {
            let dot = glyphs[d].geometry.origin
            var best: (key: (CGFloat, CGFloat, CGFloat, Int), element: Int)?
            for (h, e) in headOwner {
                let head = glyphs[h].geometry.origin
                let dx = (dot.x - head.x) / sp
                let dy = abs(dot.y - head.y) / sp
                guard dotOwnerDXInSpaces.contains(dx), dy <= dotOwnerDYInSpaces else { continue }
                let key = (dx * dx + dy * dy, head.x, head.y, h)
                if best == nil || key < best!.key { best = (key, e) }
            }
            if let best { owned[best.element, default: []].append(d) } else { unowned.append(d) }
        }
        for e in elements.indices {
            guard var evidence = elements[e].evidence else { continue }
            let mine = (owned[e] ?? []).map { glyphs[$0].geometry.origin.x }.sorted()
            var columns = 0
            var last = -CGFloat.greatestFiniteMagnitude
            for x in mine where x - last > dotColumnInSpaces * sp {
                columns += 1
                last = x
            }
            // Relaxed window for P6: an unowned dot 0.3–1.6 head widths right, within 0.9 sp.
            evidence.dotAdd = unowned.contains { d in
                evidence.heads.contains { h in
                    let head = glyphs[h].geometry
                    let width = head.advance > 0 ? head.advance : 1.18 * sp
                    let dx = (glyphs[d].geometry.origin.x - head.origin.x) / width
                    return dx >= 0.3 && dx <= 1.6 && abs(glyphs[d].geometry.origin.y - head.origin.y) <= 0.9 * sp
                }
            }
            if apply {
                evidence.dots = min(columns, 2)
                // A dot this element owns that another element's head could also own.
                evidence.dotRemove = (owned[e] ?? []).contains { d in
                    let dot = glyphs[d].geometry.origin
                    return headOwner.contains { h, other in
                        guard other != e else { return false }
                        let head = glyphs[h].geometry.origin
                        return dotOwnerDXInSpaces.contains((dot.x - head.x) / sp)
                            && abs(dot.y - head.y) / sp <= dotOwnerDYInSpaces
                    }
                }
            } else {
                evidence.dotRemove = false
            }
            elements[e].evidence = evidence
            if apply { refreshDuration(&elements[e]) }
        }
    }

    /// Set an element's value from its evidence's components.
    static func refreshDuration(_ element: inout RhythmElement) {
        guard let evidence = element.evidence, !element.isRest, !element.inTuplet else { return }
        element.chord.duration = evidence.duration
    }

    // MARK: - P2: flags in spaces

    /// Where a flag's origin may sit from its stem's bare end, in staff spaces: x from the stem,
    /// positive to the right, and y along the stem.
    static let flagDXInSpaces: ClosedRange<CGFloat> = -0.5 ... 0.5
    static let flagDYInSpaces: CGFloat = 1.5

    /// P2. A stemmed note with no beam level takes the highest flag at its stem's bare end, in
    /// staff spaces, of the stem's orientation. A flag never shortens a hollow head: it is
    /// evidence the head is black (P6's alternative). A flag just outside the window is kept for
    /// P6.
    static func applyFlagsInSpaces(
        _ elements: inout [RhythmElement], bar: BarEvidence, flagBand: ClosedRange<CGFloat>?, apply: Bool,
    ) {
        let sp = bar.spatium
        let flags = bar.glyphs.filter { g in
            flagLevel(g.semantic) != nil && (flagBand?.contains(g.geometry.origin.y) ?? true)
        }
        for e in elements.indices {
            guard var evidence = elements[e].evidence, let si = evidence.stem, !evidence.virtualStem,
                  !(evidence.level > 0 && !evidence.levelFromFlag)
            else { continue }
            let stem = bar.stems[si]
            let up = evidence.stemUp ?? (stem.up ?? true)
            let bare = up ? stem.hiY : stem.loY
            var level = 0
            var loose = 0
            for f in flags {
                let isUp: Bool
                switch f.semantic {
                case .flag8thUp, .flag16thUp, .flag32ndUp, .flag64thUp: isUp = true
                default: isUp = false
                }
                guard isUp == up, let lvl = flagLevel(f.semantic) else { continue }
                let dx = (f.geometry.origin.x - stem.x) / sp
                let dy = (f.geometry.origin.y - bare) / sp
                if flagDXInSpaces.contains(dx), abs(dy) <= flagDYInSpaces {
                    level = max(level, lvl)
                } else if abs(dx) <= 1, abs(dy) <= 1 + flagDYInSpaces {
                    loose = max(loose, lvl)
                }
            }
            if level == 0, loose > 0 { evidence.looseFlagLevel = loose }
            if apply {
                if evidence.filled {
                    evidence.level = level
                    evidence.levelFromFlag = level > 0
                } else {
                    evidence.level = 0
                    evidence.levelFromFlag = false
                    if level > 0 {
                        evidence.otherFill = true
                        evidence.flagBesideHollow = level
                    }
                }
                elements[e].lowConfidenceDuration = evidence.levelFromFlag
            }
            elements[e].evidence = evidence
            if apply { refreshDuration(&elements[e]) }
        }
    }

    // MARK: - P3: beam rescue

    /// P3. A black, stemmed note read with no beam and no flag takes the beam lines the raster
    /// found at its stem's bare end (`StemEvidence.levelHint`) — a beam whose middle falls in the
    /// next bar, or one that missed the group test, still counts at this stem.
    static func applyBeamRescue(_ elements: inout [RhythmElement], bar: BarEvidence) {
        for e in elements.indices {
            guard var evidence = elements[e].evidence, evidence.filled, evidence.base == .quarter,
                  let si = evidence.stem, !evidence.virtualStem, evidence.level == 0
            else { continue }
            let hint = bar.stems[si].levelHint
            guard hint >= 1 else { continue }
            evidence.level = hint
            evidence.levelFromFlag = false
            elements[e].evidence = evidence
            elements[e].lowConfidenceDuration = false
            refreshDuration(&elements[e])
        }
    }
}
