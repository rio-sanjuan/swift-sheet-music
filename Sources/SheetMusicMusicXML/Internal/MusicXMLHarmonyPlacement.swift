import SheetMusicCore
import SheetMusicFoundation

/// Places chord symbols into a voice by time, the way an MSCX voice holds them: a `.harmony` sits immediately before
/// the chord or rest that starts at its position. A symbol between onsets — a change under a held note — is wrapped
/// in a balanced `.locationShift` pair (jog back to it, then forward again), the MSCX `<location>` form; past the
/// last onset it is jogged from the voice's end.
enum MusicXMLHarmonyPlacement {
    /// `harmonies` in any order; equal positions keep their order. `measureLength` resolves `.measure` rests.
    static func inserting(
        _ harmonies: [(position: Fraction, harmony: Harmony)],
        into elements: [VoiceElement],
        measureLength: Fraction,
    ) -> [VoiceElement] {
        guard !harmonies.isEmpty else { return elements }
        // Onset of every chord / rest, and where the voice ends.
        var onsets: [(index: Int, onset: Fraction)] = []
        var cursor = Fraction(numerator: 0, denominator: 1)
        for (index, element) in elements.enumerated() {
            switch element {
            case let .chord(chord):
                onsets.append((index, cursor))
                cursor += chord.duration.resolved(in: measureLength).asFraction
            case let .locationShift(delta):
                cursor += delta
            default:
                continue
            }
        }
        var groups: [Int: [VoiceElement]] = [:]
        let sorted = harmonies.enumerated().sorted { lhs, rhs in
            let left = MeasurePosition(offset: lhs.element.position)
            let right = MeasurePosition(offset: rhs.element.position)
            return left == right ? lhs.offset < rhs.offset : left < right
        }
        for (_, entry) in sorted {
            let target = MeasurePosition(offset: entry.position)
            let anchor = onsets.first { !(MeasurePosition(offset: $0.onset) < target) }
            let index = anchor?.index ?? elements.endIndex
            let cursorThere = anchor?.onset ?? cursor
            let jog = entry.position - cursorThere
            if jog.numerator == 0 {
                groups[index, default: []].append(.harmony(entry.harmony))
            } else {
                groups[index, default: []] += [
                    .locationShift(delta: jog),
                    .harmony(entry.harmony),
                    .locationShift(delta: cursorThere - entry.position),
                ]
            }
        }
        var result: [VoiceElement] = []
        for (index, element) in elements.enumerated() {
            result += groups[index] ?? []
            result.append(element)
        }
        result += groups[elements.endIndex] ?? []
        return result
    }
}
