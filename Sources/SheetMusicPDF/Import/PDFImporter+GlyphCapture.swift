#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Foundation

/// Which glyphs belong to which staff.
///
/// Split out of `PDFImporter+Layout` to keep that file under the 400-line
/// cap, the same way `systemBarlineUnion` was — these two functions are one
/// decision (a staff's vertical capture band, and the clamp that stops it
/// reaching a neighbour) and read better together than either did beside the
/// measure-splitting code.
extension PDFImporter {
    /// Vertical clamp bounds for a staff's glyph-capture band: the midpoint to
    /// the nearest staff below (`lower`) and above (`upper`). `±infinity` when
    /// there is no neighbour on that side. On a well-spaced ensemble the
    /// midpoint is farther than the ±3-line band, so clamping is a no-op; on a
    /// tight grand staff it stops the band from crossing into the sibling
    /// staff and double-capturing its noteheads.
    static func neighborBandClamp(
        top: CGFloat, bottom: CGFloat, bands: [(lo: CGFloat, hi: CGFloat)],
    ) -> (lower: CGFloat, upper: CGFloat) {
        var lower = -CGFloat.greatestFiniteMagnitude
        var upper = CGFloat.greatestFiniteMagnitude
        for b in bands {
            if b.hi < bottom - 0.5 {
                lower = max(lower, (bottom + b.hi) / 2)
            } else if b.lo > top + 0.5 {
                upper = min(upper, (top + b.lo) / 2)
            }
        }
        return (lower, upper)
    }

    static func filterGlyphs(
        classified: [ClassifiedGlyph], staff: Staff, lo: CGFloat, hi: CGFloat,
        clamp: (lower: CGFloat, upper: CGFloat) = (
            -CGFloat.greatestFiniteMagnitude, CGFloat.greatestFiniteMagnitude,
        ),
        noteheadBandSpaces: CGFloat? = nil,
        verticals: [PathSegment] = [],
        farClamp: (lower: CGFloat, upper: CGFloat) = (
            -CGFloat.greatestFiniteMagnitude, CGFloat.greatestFiniteMagnitude,
        ),
    ) -> [ClassifiedGlyph] {
        // Vertical capture band around the staff. A fixed ±30pt band
        // bled into the NEIGHBOURING staff on dense vocal scores where
        // staves sit only ~27pt apart center-to-center — every notehead of
        // the staff above/below was double-counted and decoded with the
        // wrong clef anchor (observed: parts 1-4 inflated to 450-566 notes
        // with impossible pitches up to MIDI 104). Scale the band to the
        // staff's own line spacing instead.
        //
        // FIVE spaces, not three. Three is inside the range real music
        // writes: a piano bass octave's lower note sits further out and, with
        // no neighbour to claim it either, was dropped outright — measured on
        // `疑事無功_piano`, 25 of one page's 271 noteheads were captured by NO
        // staff, all 3.0–4.5 spaces past the nearest band. The symptom looked
        // like a chord bug (octave dyads arriving as `[47]` instead of
        // `[35, 47]`) and was not one.
        //
        // Widening is safe for a reason that post-dates the narrowing:
        // `clamp` cuts the band at the MIDPOINT to an adjacent staff, so this
        // number can no longer reach a neighbour. It binds only where there
        // IS no neighbour — a system's outermost staff — and there the
        // nearest ink is the next system, further off than the gap inside one
        // (~8.9 spaces vs ~6.7 on that score). Corpus: 38 scores better, 1
        // worse, net +154 metric points — see the commit for the breakdown.
        let bottom = staff.yLines.first ?? 0
        let top = staff.yLines.last ?? 0
        let lineSpacing = staff.yLines.count >= 2
            ? (top - bottom) / CGFloat(staff.yLines.count - 1)
            : 5
        let band = max(lineSpacing * 5, 6)
        // Flag glyphs (E240–E24F) carry NO pitch — they only subdivide a
        // note's duration — so a wider capture band cannot corrupt pitch.
        // Drum flags in particular render ~10–13pt (≈0.75 staff-height)
        // beyond the outer lines, PAST the ±3-line pitch band, and were being
        // dropped: bare stems then read as quarters (地球儀 drums 16→q:19,
        // 君と kick 8→q). Admit flags out to ~6 line-spacings (still short of
        // the ~3-staff-height neighbour spacing); applyFlags' own staff-band
        // + x-gate contain any bleed this admits.
        let flagBand = max(lineSpacing * 6, 12)
        // The bar repair's ledger band (F4, `BarRepairPasses.ledgerBand`), raster pages only: a
        // notehead is captured out to `noteheadBandSpaces` from the outer line, with the
        // accidental before it and the dot after it. Five spaces stops a space short of a D7 (6
        // spaces over a treble staff). Past the five, a head must hang on a stem running back
        // toward the staff — a ledger note's — so a stray detection there (a tab staff's figure,
        // a title's letter in a system's opening) is not taken, nor does it end the opening
        // where the clef, key and time are read. Still clamped at the midpoint to a neighbouring
        // staff, so no head is captured twice — and past the five spaces at the midpoint to every
        // staff on the page (`farClamp`), not only the system's: another system's voice-2 note on a
        // stem toward this staff is that system's. Only heads on this page, near this cell, are
        // far heads a sign may stand beside: FretCodex reads a photo as one PDF page per system,
        // each laid out alike.
        let headBand = noteheadBandSpaces.map { max(lineSpacing * $0, 6) } ?? band
        let middle = (top + bottom) / 2
        func outside(_ g: ClassifiedGlyph) -> Bool {
            g.geometry.origin.y > top + band || g.geometry.origin.y < bottom - band
        }
        func onAStemTowardTheStaff(_ g: ClassifiedGlyph) -> Bool {
            let o = g.geometry.origin
            return verticals.contains { v in
                guard abs(v.rect.midX - o.x) <= stemAttachWindow(spatium: lineSpacing) else { return false }
                let (near, far) = abs(v.rect.maxY - o.y) < abs(v.rect.minY - o.y)
                    ? (v.rect.maxY, v.rect.minY) : (v.rect.minY, v.rect.maxY)
                return abs(near - o.y) <= 0.75 * lineSpacing && abs(far - middle) < abs(near - middle)
            }
        }
        let farHeads = noteheadBandSpaces == nil ? [] : classified.filter {
            $0.geometry.pageIndex == staff.pageIndex
                && $0.geometry.origin.x >= lo - 3 * lineSpacing && $0.geometry.origin.x <= hi + 3 * lineSpacing
                && isNotehead($0.semantic) && outside($0) && onAStemTowardTheStaff($0)
        }
        func besideAFarHead(_ g: ClassifiedGlyph) -> Bool {
            farHeads.contains { h in
                let dx = g.geometry.origin.x - h.geometry.origin.x
                return abs(g.geometry.origin.y - h.geometry.origin.y) <= 0.75 * lineSpacing
                    && dx >= -3 * lineSpacing && dx <= 2.5 * lineSpacing
            }
        }
        return classified.filter {
            guard $0.geometry.pageIndex == staff.pageIndex,
                  lo <= $0.geometry.origin.x,
                  $0.geometry.origin.x < hi
            else { return false }
            // Flags carry no pitch (they only subdivide a note's duration) and
            // render far from the staff, so their wide band must NOT be clamped
            // — clamping cut legitimate drum flags on tightly-spaced staves and
            // dropped their duration. Only the pitch-bearing band is clamped at
            // the midpoint to an adjacent staff, so a tight grand staff's
            // sibling noteheads aren't double-captured.
            if isFlag($0.semantic) {
                return (bottom - flagBand) <= $0.geometry.origin.y
                    && $0.geometry.origin.y <= (top + flagBand)
            }
            var reach = band
            var far = false
            if noteheadBandSpaces != nil, outside($0) {
                if isNotehead($0.semantic) {
                    guard onAStemTowardTheStaff($0) else { return false }
                    reach = headBand
                    far = true
                } else if belongsToAHead($0.semantic), besideAFarHead($0) {
                    reach = headBand
                    far = true
                }
            }
            let low = max(bottom - reach, clamp.lower, far ? farClamp.lower : -CGFloat.greatestFiniteMagnitude)
            let high = min(top + reach, clamp.upper, far ? farClamp.upper : CGFloat.greatestFiniteMagnitude)
            return low <= $0.geometry.origin.y && $0.geometry.origin.y <= high
        }
    }

    /// A notehead, or the accidental or augmentation dot written beside one.
    static func belongsToAHead(_ s: SMuFLSemantic) -> Bool {
        if isNotehead(s) || accidentalAlteration(s) != nil { return true }
        if case .augmentationDot = s { return true }
        return false
    }
}
