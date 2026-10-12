import SheetMusicCore
import SheetMusicFoundation
import SheetMusicXMLTools

/// The time position inside one `<measure>` of one part, as MusicXML's `<duration>`, `<backup>` and `<forward>` move
/// it, and the furthest it reached — the measure's content length. A fraction of a whole note, like
/// `MeasurePosition`. C++: the `mTime` / `mDura` pair of `MusicXmlParserPass1::measure` (`importmusicxmlpass1.cpp`).
///
/// The walker still assigns notes to voices by document order; this cursor exists to place what has no note of its
/// own (tempo, chord symbols) and to measure the bar.
struct MusicXMLMeasureCursor {
    private(set) var time = Fraction(numerator: 0, denominator: 1)
    /// The furthest `time` reached: the content length of the measure in this part.
    private(set) var length = Fraction(numerator: 0, denominator: 1)

    /// Move past `note`: a `<chord/>` tone or a `<grace>` note takes no time; anything else advances by the length
    /// MuseScore's `MusicXmlNoteDuration::checkTiming` settles on — the TYPED length (`<type>`, dots, tuplet) when
    /// there is one, which is also the duration the note decoder stores, else `<duration>`; and `<duration>` for a
    /// `whole`-typed rest, Sibelius's spelling of a whole-measure rest in any metre.
    mutating func advance(overNote note: XMLTreeNode, divisions: DivisionsContext) {
        let isChordTone = note.children.contains { $0.name == "chord" }
        let isGrace = note.children.contains { $0.name == "grace" }
        guard !isChordTone, !isGrace else { return }
        let isRest = note.children.contains { $0.name == "rest" }
        if isRest, note.first("type")?.text == "whole", let duration = Self.divisions(note), duration > 0 {
            move(by: divisions.fractionOfWhole(duration))
        } else if let length = MusicXMLDuration.decode(note: note, divisions: divisions) {
            move(by: length.resolved(in: time).asFraction)
        }
    }

    /// `<backup>`: back by its duration, never before the downbeat.
    mutating func backup(_ node: XMLTreeNode, divisions: DivisionsContext) {
        guard let duration = Self.divisions(node), duration > 0 else { return }
        let target = time - divisions.fractionOfWhole(duration)
        time = target.numerator < 0 ? Fraction(numerator: 0, denominator: 1) : target
    }

    /// `<forward>`: on by its duration.
    mutating func forward(_ node: XMLTreeNode, divisions: DivisionsContext) {
        guard let duration = Self.divisions(node), duration > 0 else { return }
        move(by: divisions.fractionOfWhole(duration))
    }

    /// Where a `<direction>` or `<harmony>` at the cursor lands: `time` plus its `<offset>` (divisions), never before
    /// the downbeat.
    func position(of node: XMLTreeNode, divisions: DivisionsContext) -> Fraction {
        guard let offset = node.first("offset").flatMap({ Double($0.text) }).map({ Int($0) }), offset != 0 else {
            return time
        }
        let target = time + divisions.fractionOfWhole(offset)
        return target.numerator < 0 ? Fraction(numerator: 0, denominator: 1) : target
    }

    private mutating func move(by delta: Fraction) {
        time += delta
        if MeasurePosition(offset: length) < MeasurePosition(offset: time) { length = time }
    }

    private static func divisions(_ node: XMLTreeNode) -> Int? {
        node.first("duration").flatMap { Int($0.text) }
    }
}
