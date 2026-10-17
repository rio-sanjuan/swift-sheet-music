#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Foundation
import SheetMusicCore

// Part-shape derivation and per-system part → global-slot mapping for the
// assembler. Split out of PDFImporter+Assemble.swift to keep both files
// under the 400-line cap. `PartShape` is module-internal (not fileprivate)
// so PDFImporter+Assemble.swift can use it.

extension PDFImporter {
    // MARK: - Part shape

    /// Map of `referenceSystem.parts[i]` → flat staff-slot indices, plus
    /// the assembled `Part` list with placeholder instruments.
    struct PartShape {
        var parts: [Part]
        var slotsByPartIndex: [Int: [Int]]
        var totalStaffSlots: Int
        /// Whether a system coupled unlike the reference fills the slots
        /// staff by staff (`staffSlots`, `PDFImportOptions.omrCouplesByStaves`).
        var couplesByStaves = false
    }

    /// Total staff count across all parts in a system.
    static func totalStaves(_ system: ImportSystem) -> Int {
        system.parts.reduce(0) { $0 + $1.staves.count }
    }

    /// Median staff line-spacing (one spatium) across a system's staves,
    /// used as the row-grouping tolerance for `removeColonAnnotations`.
    /// Falls back to a nominal value when the system has no measurable staff.
    static func referenceLineSpacing(_ system: ImportSystem) -> CGFloat {
        let spacings = system.parts
            .flatMap(\.staves)
            .compactMap { staff -> CGFloat? in
                guard let lo = staff.staff.yLines.first,
                      let hi = staff.staff.yLines.last, hi > lo
                else { return nil }
                return (hi - lo) / 4
            }
            .sorted()
        guard !spacings.isEmpty else { return 8 }
        return spacings[spacings.count / 2]
    }

    static func partShape(from referenceSystem: ImportSystem, couplesByStaves: Bool = false) -> PartShape {
        var parts: [Part] = []
        var slotsByPartIndex: [Int: [Int]] = [:]
        var nextSlot = 0
        for (partIdx, partProto) in referenceSystem.parts.enumerated() {
            let staffCount = partProto.staves.count
            let part = Part(
                id: "P\(partIdx + 1)",
                trackName: nil,
                instrument: Instrument(id: "voice"),
                staves: IdentifiedArray(Array(
                    repeating: SheetMusicCore.Staff(staffType: "stdNormal", group: "pitched"),
                    count: staffCount,
                )),
            )
            parts.append(part)
            var slots: [Int] = []
            for _ in 0 ..< staffCount {
                slots.append(nextSlot)
                nextSlot += 1
            }
            slotsByPartIndex[partIdx] = slots
        }
        return PartShape(
            parts: parts,
            slotsByPartIndex: slotsByPartIndex,
            totalStaffSlots: nextSlot,
            couplesByStaves: couplesByStaves,
        )
    }

    /// The system the part shape is taken from: the first with the most
    /// staves; by staves (`PDFImportOptions.omrCouplesByStaves`), the first
    /// of those coupled as most of them are.
    ///
    /// A raster page's coupling rests on a brace glyph the detector sees on
    /// one system and misses on the next, so the richest systems need not
    /// agree on it, and the first of them is as likely the odd one out as
    /// any. The coupling most of them read is the likelier one.
    static func referenceSystem(_ systems: [ImportSystem], couplesByStaves: Bool) -> ImportSystem? {
        // `max(by:)` keeps the first of equals.
        guard let richest = systems.max(by: { totalStaves($0) < totalStaves($1) }) else { return nil }
        guard couplesByStaves else { return richest }
        let candidates = systems.filter { totalStaves($0) == totalStaves(richest) }
        var counts: [[Int]: Int] = [:]
        for system in candidates {
            counts[system.parts.map(\.staves.count), default: 0] += 1
        }
        let most = counts.values.max() ?? 0
        return candidates.first { counts[$0.parts.map(\.staves.count)] == most }
    }

    /// For each of `system.parts`, the global staff slots its staves fill, in
    /// order — `zip` with its staves stops at the shorter.
    ///
    /// By part, the default: the slots of the reference part `partSlotMapping`
    /// maps it to. A system coupled unlike the reference loses staves that
    /// way: two single-staff parts where the reference has one two-staff part
    /// put the second staff's music in a part that isn't there, and one part
    /// of two staves where the reference has two of one each drops its second
    /// staff. By staves (`shape.couplesByStaves`), a system coupled unlike the
    /// reference, with no more staves than it has slots, fills the slots
    /// staff by staff from the top — as `partSlotMapping` fills parts.
    static func staffSlots(system: ImportSystem, shape: PartShape) -> [[Int]] {
        let refForSystemPart = partSlotMapping(system: system, shape: shape)
        let byPart = system.parts.indices.map { shape.slotsByPartIndex[refForSystemPart[$0]] ?? [] }
        guard shape.couplesByStaves,
              system.parts.map(\.staves.count) != shape.parts.map(\.staves.count),
              totalStaves(system) <= shape.totalStaffSlots
        else { return byPart }
        var next = 0
        return system.parts.map { part in
            defer { next += part.staves.count }
            return Array(next ..< next + part.staves.count)
        }
    }

    // MARK: - Part → global-slot mapping

    /// For each `system.parts` index, the reference part index whose global
    /// slots it should fill.
    ///
    /// - **Full system** (part count == reference part count): the identity
    ///   map (`i → i`) — the overwhelmingly common case (the curated corpus
    ///   only produces full systems, so this branch is a pure no-op there).
    /// - **Under-full system** (fewer parts than the reference — MuseScore's
    ///   hide-empty-staves omitted a resting part's staff for this system):
    ///   the identity PREFIX (`i → i`). Hide-empty-staves never reorders the
    ///   surviving staves, so a system's parts are an order-preserving SUBSET
    ///   of the global part list; but WHICH parts are hidden is not
    ///   recoverable from geometry, because the survivors are re-justified
    ///   over the page — their normalized vertical positions carry no slot
    ///   information. (A previous nearest-normalized-y matching here actively
    ///   misrouted bottom parts whenever the reference carried an extra
    ///   bottom staff — e.g. a percussion staff detected on a single page —
    ///   because re-justification always pins the system's bottom part to the
    ///   reference's bottom slot.) In this corpus the hidden staves are
    ///   overwhelmingly the BOTTOM slots (percussion / aux parts under the
    ///   vocals), so the top-aligned prefix is the best order-preserving
    ///   assignment; refining the subset choice by per-slot clef/key
    ///   continuity is the planned next step for the remaining cases.
    static func partSlotMapping(
        system: ImportSystem, shape: PartShape,
    ) -> [Int] {
        _ = shape // subset choice by clef/key continuity: planned follow-up
        return Array(0 ..< system.parts.count)
    }

    // MARK: - F8va clef resolution (pre-pass)

    /// For every staff SLOT whose content reads under an ambiguous E065
    /// (F8va) clef, decide F8va-vs-plain-F ONCE from the slot's whole-part
    /// note population (aggregated across every system the slot appears in),
    /// and return only the slots that should be DOWNGRADED to plain F.
    ///
    /// Mirrors `appendSystem`'s slot routing (`partSlotMapping` +
    /// `shape.slotsByPartIndex`) so the aggregation lands in the same slots
    /// the measures will. Returns an empty map when no slot uses F8va — the
    /// common case, leaving the assembly path untouched.
    ///
    /// Alongside each F8va slot's own candidate pitches, the whole-part
    /// register profile of the nearest PITCHED slot above is aggregated and
    /// fed to `disambiguateF8vaClef` as the ensemble-voicing reference (see
    /// its doc comment for the invariant).
    static func resolveF8vaSlots(
        systems: [ImportSystem], shape: PartShape,
    ) -> [Int: Clef] {
        var pitchesBySlot: [Int: [Int]] = [:]
        for system in systems {
            let slotsForPart = staffSlots(system: system, shape: shape)
            for (partIdx, importPart) in system.parts.enumerated() {
                for (slot, importStaff) in zip(slotsForPart[partIdx], importPart.staves) {
                    guard staffInitialClefIsF8va(importStaff) else { continue }
                    pitchesBySlot[slot, default: []]
                        .append(contentsOf: f8vaCandidatePitches(staff: importStaff))
                }
            }
        }
        guard !pitchesBySlot.isEmpty else { return [:] }
        let reference = collectRegisterProfiles(
            systems: systems, shape: shape, f8vaSlots: Set(pitchesBySlot.keys),
        )
        var overrides: [Int: Clef] = [:]
        for (slot, pitches) in pitchesBySlot {
            let resolved = disambiguateF8vaClef(
                Clef(concertClefType: "F8va"), f8vaPitches: pitches,
                upperNeighborPitches: upperNeighborProfile(
                    of: slot,
                    profiles: reference.profiles,
                    excludedSlots: reference.excluded,
                ),
            )
            if resolved.concertClefType != "F8va" {
                overrides[slot] = resolved
            }
        }
        return overrides
    }

    /// Whole-part own-clef register profiles for every staff slot that can
    /// serve as an ensemble-voicing reference. F8va slots themselves are
    /// excluded up front (an unresolved slot cannot anchor another slot's
    /// resolution), and a slot that reads as percussion in ANY system is
    /// excluded from then on (drum-slot positions are not a register).
    private static func collectRegisterProfiles(
        systems: [ImportSystem], shape: PartShape, f8vaSlots: Set<Int>,
    ) -> (profiles: [Int: [Int]], excluded: Set<Int>) {
        var profiles: [Int: [Int]] = [:]
        var excluded = f8vaSlots
        for system in systems {
            let slotsForPart = staffSlots(system: system, shape: shape)
            for (partIdx, importPart) in system.parts.enumerated() {
                for (slot, importStaff) in zip(slotsForPart[partIdx], importPart.staves) {
                    guard !excluded.contains(slot) else { continue }
                    guard let pitches = registerProfilePitches(staff: importStaff)
                    else {
                        excluded.insert(slot)
                        profiles[slot] = nil
                        continue
                    }
                    profiles[slot, default: []].append(contentsOf: pitches)
                }
            }
        }
        return (profiles, excluded)
    }

    /// The register profile of the nearest pitched staff slot ABOVE `slot`
    /// (global slots are ordered top-to-bottom). Skips excluded slots
    /// (percussion / other F8va slots) and slots too sparse to define a
    /// tessitura; returns nil when no qualifying neighbor exists.
    private static func upperNeighborProfile(
        of slot: Int, profiles: [Int: [Int]], excludedSlots: Set<Int>,
    ) -> [Int]? {
        var candidate = slot - 1
        while candidate >= 0 {
            if !excludedSlots.contains(candidate),
               let profile = profiles[candidate], profile.count >= 8
            {
                return profile
            }
            candidate -= 1
        }
        return nil
    }
}
