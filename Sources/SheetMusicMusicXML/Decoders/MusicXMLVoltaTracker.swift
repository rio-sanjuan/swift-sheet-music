import SheetMusicCore
import SheetMusicFoundation

/// Pairs a part's `<ending type="start">` with the `stop` / `discontinue` that closes it and produces the volta
/// `Spanner` the MSCX side holds: `kind: .volta`, `voltaEndings` from the `number` list, `nextMeasuresOffset` = the
/// measures the bracket covers (1 for a one-bar ending), `beginText` the printed label (the ending's text, else its
/// number — MuseScore's `Volta::setText`). C++: `MusicXmlParserPass2::doEnding` (`importmusicxmlpass2.cpp`).
///
/// The spanner is placed on the part's FIRST staff, in the starting measure's first voice, ahead of its first chord —
/// where MuseScore writes a volta's begin side (the part's first track; annotations, then spanner starts, then the
/// chord). Only the begin side is produced: the end-side `<prev>` placeholder an MSCX file also carries holds nothing
/// `nextMeasuresOffset` does not, and navigation (`ScoreNavigation`) reads the begin side alone.
///
/// A `number` that is not a list of positive integers ("1, 2" and "1 2" are; MuseScore's TODO "1 - 3" is not) makes
/// no volta, as in MuseScore. A start that is never closed is closed at the bar before the next start, or at the
/// part's last bar.
struct MusicXMLVoltaTracker {
    private struct Open {
        let measureIndex: Int
        let endings: [Int]
        let text: String
        let visible: Bool
    }

    private var open: Open?
    /// Finished voltas, keyed by the measure they start in.
    private(set) var placements: [(measureIndex: Int, spanner: Spanner)] = []

    mutating func consume(_ ending: MusicXMLBarlineDecoder.Ending, measureIndex: Int) {
        switch ending.type {
        case "start":
            guard let endings = Self.endingNumbers(ending.number) else { return }
            if open != nil { close(atMeasure: measureIndex - 1) }
            open = Open(
                measureIndex: measureIndex,
                endings: endings,
                text: ending.text.isEmpty ? ending.number : ending.text,
                visible: ending.printObject,
            )
        case "stop", "discontinue":
            close(atMeasure: measureIndex)
        default:
            return
        }
    }

    /// Close a volta still open when the part ends.
    mutating func finish(lastMeasureIndex: Int) {
        close(atMeasure: lastMeasureIndex)
    }

    private mutating func close(atMeasure endIndex: Int) {
        guard let open else { return }
        self.open = nil
        placements.append((open.measureIndex, Spanner(
            kind: .volta,
            rawType: Spanner.Kind.volta.rawValue,
            nextMeasuresOffset: max(1, endIndex - open.measureIndex + 1),
            voltaEndings: open.endings,
            visible: open.visible,
            beginText: open.text,
        )))
    }

    /// "1", "1, 2", "1 2" → `[1]`, `[1, 2]`; `nil` when any entry is not a positive integer or there are none.
    private static func endingNumbers(_ number: String) -> [Int]? {
        let entries = number.split(whereSeparator: { $0 == "," || $0 == " " })
        let values = entries.compactMap { Int($0) }.filter { $0 > 0 }
        guard !values.isEmpty, values.count == entries.count else { return nil }
        return values
    }

    /// Insert each finished volta into `staffMeasures` (the part's first staff), first voice, before the first
    /// chord, rest or cursor jog — after the clef / key / time / capo the measure opens with and any chord symbol at
    /// the downbeat. Runs before identifiers are assigned, so the voice is rebuilt rather than spliced.
    func apply(to staffMeasures: inout [Measure]) {
        for (measureIndex, spanner) in placements where staffMeasures.indices.contains(measureIndex) {
            var measure = staffMeasures[measureIndex]
            if measure.voices.isEmpty { measure.voices = [Voice(elements: [])] }
            var elements = measure.voices[0].elements.values
            let index = elements.firstIndex { element in
                switch element {
                case .chord, .locationShift: true
                default: false
                }
            } ?? elements.endIndex
            elements.insert(.spanner(spanner), at: index)
            measure.voices[0].elements = IdentifiedArray(elements)
            staffMeasures[measureIndex] = measure
        }
    }
}
