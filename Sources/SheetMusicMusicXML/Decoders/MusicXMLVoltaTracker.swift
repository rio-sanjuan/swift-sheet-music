import SheetMusicCore
import SheetMusicFoundation

/// Pairs a part's `<ending type="start">` with the `stop` / `discontinue` that closes it and produces the volta pair
/// the MSCX side holds — a begin side and an end side, the two `<Spanner type="Volta">` halves MuseScore writes.
/// C++: `MusicXmlParserPass2::doEnding` (`importmusicxmlpass2.cpp`).
///
/// - The **begin side** is `kind: .volta`, `voltaEndings` from the `number` list, `beginText` the printed label (the
///   ending's text, else its number — MuseScore's `Volta::setText`), and the `<next>` offsets MuseScore's writer
///   gives a volta ending at the close of the last bar it covers (`Spanner.offsets(from:to:in:)`): the next bar's
///   downbeat, `nextMeasuresOffset` = the bars covered (1 for a one-bar ending) — or, when that last bar is the
///   score's last, the end of that bar: one bar fewer and `nextFractionsOffset` = the bar's length.
/// - The **end side** is the invisible `.volta` `Spanner` whose `prevMeasuresOffset` / `prevFractionsOffset` are the
///   begin side's offsets negated: MuseScore pairs the two halves by those locations and drops a volta whose end
///   side is missing or points elsewhere, so an MSCX file encoded from this score needs both.
///
/// Both sides go on the part's FIRST staff, in its first voice — the part's first track, where MuseScore writes a
/// volta. A side at a bar's downbeat goes ahead of the bar's first chord, rest or cursor jog, after the clef / key /
/// time / capo the bar opens with and any chord symbol at the downbeat (per segment MuseScore writes annotations,
/// then spanner ends and starts, then the chord); an end side there precedes a begin side, since MuseScore visits
/// spanners in start-tick order. An end side on the score's last tick goes after the last bar's content, ahead of a
/// trailing bar line — MuseScore writes it at the bar's end-bar-line segment.
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

    /// A closed ending: the bars `startMeasure ... lastMeasure` it covers.
    private struct Finished {
        let startMeasure: Int
        let lastMeasure: Int
        let endings: [Int]
        let text: String
        let visible: Bool
    }

    private var open: Open?
    /// Closed endings, in the order they closed — which is also start order.
    private var finished: [Finished] = []

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
        finished.append(Finished(
            startMeasure: open.measureIndex,
            lastMeasure: open.measureIndex + max(1, endIndex - open.measureIndex + 1) - 1,
            endings: open.endings,
            text: open.text,
            visible: open.visible,
        ))
    }

    /// "1", "1, 2", "1 2" → `[1]`, `[1, 2]`; `nil` when any entry is not a positive integer or there are none.
    private static func endingNumbers(_ number: String) -> [Int]? {
        let entries = number.split(whereSeparator: { $0 == "," || $0 == " " })
        let values = entries.compactMap { Int($0) }.filter { $0 > 0 }
        guard !values.isEmpty, values.count == entries.count else { return nil }
        return values
    }

    /// Where a volta side goes in its bar.
    private enum Slot {
        /// Ahead of the bar's first chord, rest or cursor jog.
        case downbeat
        /// After the bar's content, ahead of a trailing bar line.
        case barEnd
    }

    /// One side of a closed ending, and where it goes.
    private struct Side {
        let measure: Int
        let slot: Slot
        let isEnd: Bool
        let spanner: Spanner
    }

    /// Both sides of every closed ending. Needs the bar lengths, which is why it runs once the score's bars are
    /// sized (`Score.sizingMeasures`).
    private func sides(durations: [Fraction]) -> [Side] {
        let measureCount = durations.count
        var result: [Side] = []
        for volta in finished where volta.startMeasure < measureCount {
            let lastMeasure = min(volta.lastMeasure, measureCount - 1)
            var begin = Spanner(
                kind: .volta,
                rawType: Spanner.Kind.volta.rawValue,
                voltaEndings: volta.endings,
                visible: volta.visible,
                beginText: volta.text,
            )
            var end = Spanner(kind: .volta, rawType: Spanner.Kind.volta.rawValue, visible: false)
            if lastMeasure + 1 < measureCount {
                // Ends on the next bar's downbeat, which is where the end side is written.
                begin.nextMeasuresOffset = lastMeasure + 1 - volta.startMeasure
                end.prevMeasuresOffset = -begin.nextMeasuresOffset
                result.append(Side(measure: lastMeasure + 1, slot: .downbeat, isEnd: true, spanner: end))
            } else {
                // Ends on the score's last tick: MuseScore's `tick2measure` keeps that tick in the last bar, at
                // the bar's length, and writes the end side at the bar's end.
                let length = durations[lastMeasure]
                begin.nextMeasuresOffset = lastMeasure - volta.startMeasure
                begin.nextFractionsOffset = length
                end.prevMeasuresOffset = -begin.nextMeasuresOffset
                end.prevFractionsOffset = Fraction(numerator: -length.numerator, denominator: length.denominator)
                result.append(Side(measure: lastMeasure, slot: .barEnd, isEnd: true, spanner: end))
            }
            result.append(Side(measure: volta.startMeasure, slot: .downbeat, isEnd: false, spanner: begin))
        }
        return result
    }

    /// Insert both sides of each closed ending into `part`'s first staff, first voice (see the type's doc for the
    /// slots). Runs before identifiers are assigned, so a voice is rebuilt rather than spliced.
    func apply(to part: Part) -> Part {
        guard !finished.isEmpty, !part.staves.isEmpty else { return part }
        var part = part
        part.staves.updateValue(at: 0) { staff in
            let placed = sides(durations: staff.measures.effectiveMeasureDurations())
            for measureIndex in staff.measures.indices {
                let here = placed.filter { $0.measure == measureIndex }
                guard !here.isEmpty else { continue }
                // End sides first at a downbeat: a spanner ending here started earlier than one starting here.
                let downbeat = here.filter { $0.slot == .downbeat && $0.isEnd }
                    + here.filter { $0.slot == .downbeat && !$0.isEnd }
                staff.measures[measureIndex] = Self.inserting(
                    downbeat: downbeat.map(\.spanner),
                    barEnd: here.filter { $0.slot == .barEnd }.map(\.spanner),
                    into: staff.measures[measureIndex],
                )
            }
        }
        return part
    }

    private static func inserting(downbeat: [Spanner], barEnd: [Spanner], into measure: Measure) -> Measure {
        var measure = measure
        if measure.voices.isEmpty { measure.voices = [Voice(elements: [])] }
        var elements = measure.voices[0].elements.values
        let downbeatIndex = elements.firstIndex { element in
            switch element {
            case .chord, .locationShift: true
            default: false
            }
        } ?? elements.endIndex
        var barEndIndex = elements.endIndex
        while barEndIndex > downbeatIndex, case .barLine = elements[barEndIndex - 1] {
            barEndIndex -= 1
        }
        // The later index first, so the earlier one still names the same place.
        elements.insert(contentsOf: barEnd.map(VoiceElement.spanner), at: barEndIndex)
        elements.insert(contentsOf: downbeat.map(VoiceElement.spanner), at: downbeatIndex)
        measure.voices[0].elements = IdentifiedArray(elements)
        return measure
    }
}
