#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Foundation
import SheetMusicCore

// THE BAR REPAIR'S INK PASSES (F4): P1 dots by column, P2 flags in spaces, P3 beam rescue. Each
// reads only ink in the bar and changes a value only where the ink says so; none is reverted.

extension PDFImporter {
    // MARK: - P1: dots by column

    /// A dot's owner: the nearest head to its left with dx 0.8–2.2 sp and |dy| ≤ 0.75 sp. The x
    /// window is set from the dots of bench pages 80–159 (round-3 probe): measured from the head's
    /// origin they sit 1.2–1.9 sp right (mode 1.6), 878 of 878 inside — upstream's 0.5–1.35 head
    /// widths stops at 1.6 and misses half of them. In y: 0 for a note in a space, ±0.4–0.6 for one
    /// on a line.
    static let dotOwnerDXInSpaces: ClosedRange<CGFloat> = 0.8 ... 2.2
    static let dotOwnerDYInSpaces: CGFloat = 0.75
    /// P6's looser window for a dot no head owns.
    static let dotLooseDXInSpaces: ClosedRange<CGFloat> = 0.5 ... 2.6
    static let dotLooseDYInSpaces: CGFloat = 0.9
    /// Dots within this many spaces in x are one column.
    static let dotColumnInSpaces: CGFloat = 0.3
    /// A double dot's second stands this far right of its first, at its height: MuseScore puts
    /// it 0.65 sp on (2.33 sp from the head's origin, past the owner window).
    static let secondDotDXInSpaces: ClosedRange<CGFloat> = 0.4 ... 0.9
    static let secondDotDYInSpaces: CGFloat = 0.2
    /// A dot over or under a LATER note's head — x from 0.3 sp before its origin to 1.2 after, y
    /// 0.35–1.3 sp off it — is that note's staccato, wherever the warp moved it: never an earlier
    /// note's augmentation dot. A dot of its own stands right of its head, past the next head's
    /// reach.
    static let staccatoOverDXInSpaces: ClosedRange<CGFloat> = -0.3 ... 1.2
    static let staccatoOverDYInSpaces: ClosedRange<CGFloat> = 0.35 ... 1.3

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
        /// Whether `dot` stands over or under a head of an element other than `e`, right of `x`.
        func staccatoOfALaterHead(_ dot: CGPoint, owner e: Int, x: CGFloat) -> Bool {
            headOwner.contains { h, other in
                guard other != e else { return false }
                let head = glyphs[h].geometry.origin
                guard head.x > x + 0.5 * sp else { return false }
                return staccatoOverDXInSpaces.contains((dot.x - head.x) / sp)
                    && staccatoOverDYInSpaces.contains(abs(dot.y - head.y) / sp)
            }
        }
        for d in dots {
            let dot = glyphs[d].geometry.origin
            var best: (key: (CGFloat, CGFloat, CGFloat, Int), element: Int)?
            var staccato = false
            for (h, e) in headOwner {
                let head = glyphs[h].geometry.origin
                let dx = (dot.x - head.x) / sp
                let dy = abs(dot.y - head.y) / sp
                guard dotOwnerDXInSpaces.contains(dx), dy <= dotOwnerDYInSpaces else { continue }
                if staccatoOfALaterHead(dot, owner: e, x: head.x) {
                    staccato = true
                    continue
                }
                let key = (dx * dx + dy * dy, head.x, head.y, h)
                if best == nil || key < best!.key { best = (key, e) }
            }
            if let best { owned[best.element, default: []].append(d) } else if !staccato { unowned.append(d) }
        }
        // A double dot's second, past the owner window, chained from the first.
        for e in owned.keys.sorted() {
            guard let last = owned[e]?.max(by: { glyphs[$0].geometry.origin.x < glyphs[$1].geometry.origin.x }) else { continue }
            let first = glyphs[last].geometry.origin
            if let second = unowned.first(where: { d in
                let o = glyphs[d].geometry.origin
                return secondDotDXInSpaces.contains((o.x - first.x) / sp) && abs(o.y - first.y) <= secondDotDYInSpaces * sp
            }) {
                owned[e, default: []].append(second)
                unowned.removeAll { $0 == second }
            }
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
            // Relaxed window for P6: an unowned dot a little further off.
            evidence.dotAdd = unowned.contains { d in
                evidence.heads.contains { h in
                    let head = glyphs[h].geometry.origin
                    let dot = glyphs[d].geometry.origin
                    return dotLooseDXInSpaces.contains((dot.x - head.x) / sp)
                        && abs(dot.y - head.y) <= dotLooseDYInSpaces * sp
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
    /// positive to the right, and y along the stem. Checked on the flags of bench pages 80–159
    /// (round-3 probe): a flag of its stem's way sits −0.25…0 sp from the stem in x (all 681), and
    /// −0.4…0 sp (up) or −0.1…+0.5 sp (down) from the bare end in y; the next flag is 1.1 sp off.
    /// Upstream's windows, already in spaces, hold them all, so they stay — a 64th's flag needs the
    /// 1.5 in y.
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
    /// hung from its stem's bare end (`StemEvidence.anchoredLevel`) — a beam whose middle falls in the
    /// next bar, or one that missed the group test, still counts at this stem.
    static func applyBeamRescue(_ elements: inout [RhythmElement], bar: BarEvidence) {
        for e in elements.indices {
            guard var evidence = elements[e].evidence, evidence.filled, evidence.base == .quarter,
                  let si = evidence.stem, !evidence.virtualStem, evidence.level == 0
            else { continue }
            let hint = bar.stems[si].anchoredLevel
            guard hint >= 1 else { continue }
            evidence.level = hint
            evidence.levelFromFlag = false
            elements[e].evidence = evidence
            elements[e].lowConfidenceDuration = false
            refreshDuration(&elements[e])
        }
    }
}
