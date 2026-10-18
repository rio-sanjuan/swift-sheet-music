#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Foundation
import SheetMusicCore

// P5, ONE VOICE RULE (F4, `BarRepairPasses.voiceRule`). Upstream makes a bar two-voice when any two
// onsets stand under 3 pt apart — on a photo, a third to two-thirds of a staff space — and then
// splits it twice, differently: by the elements' mean y to reconcile, by the staff midline to emit.
// Here a bar is two-voice only on two-voice evidence, in staff spaces, and the one split it makes
// serves the repair, the voices and the geometry side-car.

extension PDFImporter {
    /// One split of a bar's elements into voices: each element's (voice, position in it).
    struct VoiceSplit {
        var voiceCount: Int
        var placements: [(voice: Int, position: Int)]

        /// Element indices of each voice, in position order.
        var groups: [[Int]] {
            (0 ..< voiceCount).map { v in
                placements.indices.filter { placements[$0].voice == v }
                    .sorted { placements[$0].position < placements[$1].position }
            }.filter { !$0.isEmpty }
        }
    }

    /// Upstream's split, as `assignVoices` makes it.
    static func legacySplit(_ elements: [RhythmElement], staffMidY: CGFloat) -> VoiceSplit {
        VoiceSplit(
            voiceCount: elements.isEmpty ? 0 : (hasCoincidentOnset(elements) ? 2 : 1),
            placements: voiceAssignment(elements: elements, staffMidY: staffMidY),
        )
    }

    /// Up- and down-stemmed notes whose heads stand within this many staff spaces in x sound
    /// together: two voices.
    static let voiceOverlapInSpaces: CGFloat = 1.0
    /// A rest this far off the staff's middle line, beside a note, is a second voice's.
    static let displacedRestInSpaces: CGFloat = 2.0

    /// P5's split: two voices only when two notes with stems in opposite directions stand
    /// together (a column split by P4 into two stems, or heads overlapping in x), or a rest is
    /// pushed off the staff's middle beside a note. Then stems up are voice 1 and down voice 2,
    /// rests and stemless notes by the staff's middle line; otherwise one voice in x order.
    static func ruleSplit(_ elements: [RhythmElement], bar: BarEvidence, staffMidY: CGFloat) -> VoiceSplit {
        guard !elements.isEmpty else { return VoiceSplit(voiceCount: 0, placements: []) }
        let sp = bar.spatium
        let notes = elements.indices.filter { !elements[$0].isRest }
        var twoVoice = false
        outer: for a in notes {
            for b in notes where b > a {
                let dx = abs(elements[a].x - elements[b].x)
                guard let ua = direction(elements[a]), let ub = direction(elements[b]), ua != ub else { continue }
                if dx <= voiceOverlapInSpaces * sp {
                    twoVoice = true
                    break outer
                }
            }
        }
        if !twoVoice {
            twoVoice = elements.contains { rest in
                rest.isRest && abs(rest.y - staffMidY) >= displacedRestInSpaces * sp
                    && notes.contains { abs(elements[$0].x - rest.x) <= 3 * sp }
            }
        }
        guard twoVoice else {
            let order = elements.indices.sorted { (elements[$0].x, $0) < (elements[$1].x, $1) }
            var placements = [(voice: Int, position: Int)](repeating: (0, 0), count: elements.count)
            for (position, i) in order.enumerated() {
                placements[i] = (0, position)
            }
            return VoiceSplit(voiceCount: 1, placements: placements)
        }
        var counts = [0, 0]
        var placements = [(voice: Int, position: Int)](repeating: (0, 0), count: elements.count)
        let order = elements.indices.sorted { (elements[$0].x, $0) < (elements[$1].x, $1) }
        for i in order {
            let e = elements[i]
            let upper: Bool = if let up = direction(e), !e.isRest { up } else { e.y > staffMidY }
            let v = upper ? 0 : 1
            placements[i] = (v, counts[v])
            counts[v] += 1
        }
        return VoiceSplit(voiceCount: 2, placements: placements)
    }

    /// A note's stem direction (true: up), nil for a rest or a note with no stem found.
    private static func direction(_ e: RhythmElement) -> Bool? {
        guard !e.isRest, e.evidence?.virtualStem != true else { return nil }
        switch e.stemDirection {
        case .up: return true
        case .down: return false
        case .none: return nil
        }
    }

    /// The voices `split` makes of `elements`, with each voice's tuplets — `assignVoices`, given
    /// the split.
    static func voices(_ elements: [RhythmElement], split: VoiceSplit) -> [Voice] {
        guard !elements.isEmpty else { return [] }
        return (0 ..< split.voiceCount).map { v in
            let members = elements.indices.filter { split.placements[$0].voice == v }
                .sorted { split.placements[$0].position < split.placements[$1].position }
            return Voice(
                elements: members.map { .chord(elements[$0].chord) },
                tuplets: tuplets(from: members.map { elements[$0].tupletRatio }),
            )
        }
    }
}
