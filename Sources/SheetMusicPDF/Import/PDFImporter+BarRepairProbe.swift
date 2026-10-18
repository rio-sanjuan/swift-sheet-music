#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Foundation
import SheetMusicCore

// THE BAR REPAIR'S PROBES (F4, test-only): the geometry its windows are set from, reported through
// `PDFImportOptions.barRepairProbe` — never read by the decode.

extension PDFImporter {
    /// Each flag of a bar against the nearest stem's bare end, and each dot against the nearest
    /// head to its left, in staff spaces.
    static func probeBar(_ bar: BarEvidence, location: String, probe: (String) -> Void) {
        let sp = bar.spatium
        let heads = bar.glyphs.enumerated().filter { isNotehead($0.element.semantic) && !bar.graces.contains($0.offset) }
        for g in bar.glyphs {
            if let level = flagLevel(g.semantic) {
                let up: Bool
                switch g.semantic {
                case .flag8thUp, .flag16thUp, .flag32ndUp, .flag64thUp: up = true
                default: up = false
                }
                let near = bar.stems.filter { $0.bareEndY != nil }
                    .min { abs($0.x - g.geometry.origin.x) < abs($1.x - g.geometry.origin.x) }
                let line = near.map { s in
                    String(
                        format: "FLAG level %d up %d stemUp %d dx %.3f dy %.3f stemLength %.2f",
                        level, up ? 1 : 0, s.up == true ? 1 : 0, (g.geometry.origin.x - s.x) / sp,
                        (g.geometry.origin.y - s.bareEndY!) / sp, (s.hiY - s.loY) / sp,
                    )
                } ?? "FLAG level \(level) up \(up ? 1 : 0) nostem"
                probe(line + " | " + location)
            }
            if case .augmentationDot = g.semantic {
                let near = heads.filter { $0.element.geometry.origin.x < g.geometry.origin.x }
                    .min { a, b in
                        hypot(a.element.geometry.origin.x - g.geometry.origin.x, a.element.geometry.origin.y - g.geometry.origin.y)
                            < hypot(b.element.geometry.origin.x - g.geometry.origin.x, b.element.geometry.origin.y - g.geometry.origin.y)
                    }
                if let head = near?.element {
                    probe(String(
                        format: "DOT dx %.3f dy %.3f headAdvance %.3f staccato %d | %@",
                        (g.geometry.origin.x - head.geometry.origin.x) / sp, (g.geometry.origin.y - head.geometry.origin.y) / sp,
                        head.geometry.advance / sp, isStaccatoOfSomeNotehead(g, in: bar.glyphs) ? 1 : 0, location,
                    ))
                }
            }
        }
    }

    /// Every notehead of a raster page against its nearest staff: how far past the outer line, in
    /// that staff's spaces, and whether any staff captured it.
    static func probeHeads(systems: [ImportSystem], classified: [ClassifiedGlyph], page: Int, probe: (String) -> Void) {
        let staves = systems.filter { $0.pageIndex == page }.flatMap { $0.parts.flatMap(\.staves) }
        let captured = Set(staves.flatMap { $0.measures.flatMap { $0.glyphs.map(\.geometry.origin) } }.map { "\($0.x),\($0.y)" })
        for g in classified where g.geometry.pageIndex == page && isNotehead(g.semantic) {
            let y = g.geometry.origin.y
            guard let staff = staves.min(by: { a, b in
                distance(y, to: a.staff.yLines) < distance(y, to: b.staff.yLines)
            }) else { continue }
            let sp = staffSpatium(staff.staff.yLines)
            let out = distance(y, to: staff.staff.yLines) / sp
            guard out > 3 else { continue }
            probe(String(
                format: "HEAD out %.3f above %d captured %d staves %d | page %d",
                out, y > (staff.staff.yLines.max() ?? 0) ? 1 : 0,
                captured.contains("\(g.geometry.origin.x),\(g.geometry.origin.y)") ? 1 : 0, staves.count, page,
            ))
        }
    }

    private static func distance(_ y: CGFloat, to lines: [CGFloat]) -> CGFloat {
        guard let lo = lines.min(), let hi = lines.max() else { return .greatestFiniteMagnitude }
        if y > hi { return y - hi }
        if y < lo { return lo - y }
        return 0
    }
}
