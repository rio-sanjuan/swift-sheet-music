import Foundation
import SheetMusicCore
import SheetMusicXMLTools

extension Part {
    /// Decode the per-`<Part>` declaration. Top-level `<Staff>` measures
    /// are paired in afterwards by `assembleParts`.
    /// `fallbackIndex` (1-based) is the position of this `<Part>` in
    /// document order; it backstops missing/empty `id` attributes
    /// with a sequential integer so the decoded `Part.id` is always
    /// non-empty (matches the encoder's id-synthesis convention).
    static func decodePairing(
        _ node: XMLTreeNode, fallbackIndex: Int,
    ) throws -> MSCXStaffPairing {
        let raw = node.attributes["id"] ?? ""
        let id = raw.isEmpty ? String(fallbackIndex) : raw
        let declaredRaw = node.all("Staff").map { Staff.declared($0) }
        // Resolve <linkedTo> score-global staff ids into indices
        // within this part (linked pairs are always same-part in
        // MuseScore). Unresolvable targets are silently dropped —
        // linkage only gates playback dedupe, never rendering.
        let declared: [(mscxID: String?, staff: Staff)] = declaredRaw.map { entry in
            var staff = entry.staff
            if let linkID = entry.linkedToID,
               let target = declaredRaw.firstIndex(where: { $0.mscxID == linkID }) {
                staff.linkedToStaffOffset = target
            }
            return (entry.mscxID, staff)
        }
        guard let instrNode = node.first("Instrument") else {
            throw SheetMusicError.malformedScore(reason: "Part missing <Instrument>")
        }
        let instrument = try Instrument.decode(instrNode)
        return MSCXStaffPairing(
            partID: id,
            trackName: node.first("trackName")?.text,
            instrument: instrument,
            declared: declared,
        )
    }
}
