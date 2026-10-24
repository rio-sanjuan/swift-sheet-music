import Foundation

/// The passes of the raster bar repair (`PDFImportOptions.omrBarRepair`), one bit each, so a host
/// can measure what each one does by leaving it out. FretCodex fork, F4.
///
/// Every pass acts on pages read through the raster fallback only, and only when `omrBarRepair`
/// is on; a vector page never reads these bits. `.all` is every pass the fork recommends.
public struct BarRepairPasses: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// P7. A notehead is captured by its staff out to 7 staff spaces from the outer line, not 5:
    /// a D7 sits 6 spaces above a treble staff. Clamped at the midpoint to a neighbouring staff
    /// as before.
    public static let ledgerBand = BarRepairPasses(rawValue: 1 << 0)
    /// P1. Dots counted by dot column, in staff spaces, each dot glyph used by one note.
    public static let dotColumns = BarRepairPasses(rawValue: 1 << 1)
    /// P2. A flag matched to a stem's bare end in staff spaces.
    public static let flagsInSpaces = BarRepairPasses(rawValue: 1 << 2)
    /// P3. A stemmed black note with no beam level takes the beam lines the raster found at its
    /// stem; a stem refused by the head-end gate is kept when a beam reaches its far end.
    public static let beamRescue = BarRepairPasses(rawValue: 1 << 3)
    /// P4. Heads are grouped into columns before any value is chosen: one column, one chord,
    /// unless two stems in opposite directions hold disjoint heads.
    public static let columnChords = BarRepairPasses(rawValue: 1 << 4)
    /// P5. A bar is two-voice only on two-voice evidence, in staff spaces; one split serves the
    /// repair, the voices and the geometry.
    public static let voiceRule = BarRepairPasses(rawValue: 1 << 5)
    /// P6. A voice that does not sum to the bar is repaired by the cheapest evidence-backed set of
    /// at most three changes, or left as read when none is unique.
    public static let repairSearch = BarRepairPasses(rawValue: 1 << 6)
    /// P6: three or more stems whose bare ends line up may be an unseen beam.
    public static let phantomGroups = BarRepairPasses(rawValue: 1 << 7)
    /// P6: a beam line ending just short of a stem, on its bare end's line, may reach it.
    public static let extrapolatedBeams = BarRepairPasses(rawValue: 1 << 8)
    /// P6: a beam stub owned by a stem with no full beam implies the primary beam.
    public static let stubImpliesPrimary = BarRepairPasses(rawValue: 1 << 9)
    /// P6: upstream's evidence-free one-note re-valuation, as the dearest last resort.
    public static let legacyFallback = BarRepairPasses(rawValue: 1 << 10)
    /// P6: an intact beam group of 3 or 6 equal notes, every stem with a line, may be a triplet
    /// or a sextuplet.
    public static let tupletGroups = BarRepairPasses(rawValue: 1 << 11)
    /// P6: change sets of three changes, not just one or two.
    public static let threeChanges = BarRepairPasses(rawValue: 1 << 12)
    /// P3-P5 are undone in a bar where they leave fewer voices summing to the bar, under a meter
    /// read from two stacked digits.
    public static let revertRule = BarRepairPasses(rawValue: 1 << 13)
    /// P4: a column of heads with no stem joins into one chord only when its heads are all black
    /// or all hollow.
    public static let headKindRule = BarRepairPasses(rawValue: 1 << 14)
    /// For measuring: the revert rule applied under any meter, not only one read from stacked
    /// digits. Never in `.all`.
    public static let revertEverywhere = BarRepairPasses(rawValue: 1 << 15)
    /// P6, with `.tupletGroups`: a "broken" group — a beamed 2 or 5 and the black, unflagged,
    /// undotted note beside it whose line was lost — may be a triplet or a sextuplet, at a cost
    /// above an intact group's. The third note's stem must point the group's way and its bare end
    /// sit on one of the group's beam lines carried on.
    public static let brokenTuplets = BarRepairPasses(rawValue: 1 << 16)
    /// A leading cell dropped as content-free and narrow — a clef's or a time signature's stroke
    /// taken for a barline — hands its time-signature glyphs, and only those, to the first bar
    /// kept, so a page's opening meter is not lost (FretCodex SM-38). Clef and key glyphs stay
    /// dropped: carrying them misread two held-out binder pages.
    public static let leadingTime = BarRepairPasses(rawValue: 1 << 17)
    /// For measuring: with `.repairSearch` off, a voice that does not sum is left as read —
    /// neither P6 nor upstream's repair — so P6's gain can be told from dropping upstream's.
    /// Never in `.all`.
    public static let leaveUnfit = BarRepairPasses(rawValue: 1 << 18)

    /// P6, with `.tupletGroups`: every intact beam group of a voice that could be a triplet (or
    /// a sextuplet), the same size, read as one together at a single tuplet's cost — a bar of
    /// triplet accompaniment is four groups, and the search takes one tuplet at most. FretCodex
    /// fork, F6.
    public static let tupletRuns = BarRepairPasses(rawValue: 1 << 19)
    /// P4: a stemmed column on the stem of the column before it joins that column's chord when any
    /// of its heads, not every one, is a second from that column's — a chord's displaced head
    /// carries the heads above it across the stem. FretCodex fork, F6.
    public static let mirroredChords = BarRepairPasses(rawValue: 1 << 20)
    /// P6: a bar the tuplet numerals on it leave with more voices unsummed than it has read without
    /// them is read without them. A page prints a run's first numerals and leaves the rest to be
    /// understood; read, those few mark some of a voice's groups and not the others, and the
    /// search, which takes one tuplet at most, cannot finish the run. FretCodex fork, F7.
    public static let numeralRevert = BarRepairPasses(rawValue: 1 << 21)
    /// Every pass the fork recommends: those that earned their place, each left out in turn,
    /// through FretCodex's PageReader (its ADR 0006, round 3). Measured and left out: P2
    /// (`.flagsInSpaces`, no page moved), `.headKindRule`, `.voiceRule`, `.revertRule`,
    /// `.phantomGroups` (each within noise or worse), `.legacyFallback` and `.threeChanges` (each
    /// cost note values on the phone level), and `.brokenTuplets` (under the drop rule's margin,
    /// and it can turn a straight bar into a triplet when a stray note leaves it a beat over).
    /// F6 adds `.tupletRuns` and `.mirroredChords`, measured on FretCodex's Lieder bench (its ADR
    /// 0006, round 4): on its confirm songs, read clean, values 0.816 → 0.847, and no page of its
    /// corpus or robustness pages moved but three whose triplets now read.
    public static let all: BarRepairPasses = [
        .ledgerBand, .dotColumns, .beamRescue, .columnChords, .repairSearch, .extrapolatedBeams,
        .stubImpliesPrimary, .tupletGroups, .leadingTime, .tupletRuns, .mirroredChords, .numeralRevert,
    ]

    /// Each bit's name, for a host that sets passes from text.
    public static let names: [(name: String, pass: BarRepairPasses)] = [
        ("ledgerBand", .ledgerBand), ("dotColumns", .dotColumns), ("flagsInSpaces", .flagsInSpaces),
        ("beamRescue", .beamRescue), ("columnChords", .columnChords), ("voiceRule", .voiceRule),
        ("repairSearch", .repairSearch), ("phantomGroups", .phantomGroups),
        ("extrapolatedBeams", .extrapolatedBeams), ("stubImpliesPrimary", .stubImpliesPrimary),
        ("legacyFallback", .legacyFallback), ("tupletGroups", .tupletGroups),
        ("threeChanges", .threeChanges), ("revertRule", .revertRule),
        ("headKindRule", .headKindRule), ("revertEverywhere", .revertEverywhere),
        ("brokenTuplets", .brokenTuplets), ("leadingTime", .leadingTime), ("leaveUnfit", .leaveUnfit),
        ("tupletRuns", .tupletRuns), ("mirroredChords", .mirroredChords), ("numeralRevert", .numeralRevert),
    ]
}
