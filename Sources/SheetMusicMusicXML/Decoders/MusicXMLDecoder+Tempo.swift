import SheetMusicCore
import SheetMusicFoundation
import SheetMusicXMLTools

/// Decodes the tempo a `<direction>` (or a measure-level `<sound>`) sets into the `Tempo` an MSCX `<Tempo>` gives.
/// C++: `MusicXmlParserDirection::direction` / `metronome` and the measure-level `<sound tempo>` handling in
/// `MusicXmlParserPass2::measure` (`importmusicxmlpass2.cpp`).
///
/// - `beatsPerSecond` is quarter-normalised, as MSCX's `<tempo>` is: `<sound tempo>` is already quarter notes per
///   minute (÷ 60); without one, a `<metronome>`'s `<per-minute>` is converted from its beat unit
///   (`4 × beat × per-minute` quarters per minute — MuseScore's fallback for exporters that omit `<sound>`).
/// - `beatNote` / `beatDots` come from the metronome's first `<beat-unit>` and its `<beat-unit-dot>`s, else a quarter.
/// - `visible` follows MuseScore: a bare `<sound tempo>` makes an invisible marking; a printed `<metronome>` or
///   `<words>` makes a visible one. The marking's words themselves are not modeled by `Tempo`.
///
/// Nothing when neither source gives a positive tempo.
enum MusicXMLTempoDecoder {
    static func decode(direction: XMLTreeNode) -> Tempo? {
        let directionTypes = direction.all("direction-type")
        let metronome = directionTypes.lazy.compactMap { $0.first("metronome") }.first
        let hasWords = directionTypes.contains { type in type.all("words").contains { !$0.text.isEmpty } }
        let printsMetronome = metronome.map { $0.attributes["print-object"] != "no" } ?? false
        return tempo(
            soundTempo: direction.first("sound").flatMap(soundTempo(_:)),
            metronome: metronome,
            visible: printsMetronome || hasWords,
        )
    }

    /// A `<sound tempo>` standing directly in a `<measure>`: an invisible marking, as MuseScore makes it.
    static func decode(sound: XMLTreeNode) -> Tempo? {
        tempo(soundTempo: soundTempo(sound), metronome: nil, visible: false)
    }

    private static func tempo(soundTempo: Double?, metronome: XMLTreeNode?, visible: Bool) -> Tempo? {
        let beat = metronome.flatMap(beatUnit(_:))
        let quarterBPM = soundTempo ?? metronome.flatMap { node -> Double? in
            guard let beat, let perMinute = node.first("per-minute").flatMap({ Double($0.text) }) else { return nil }
            let length = beat.note.dotted(beat.dots).asFraction
            return 4 * Double(length.numerator) / Double(length.denominator) * perMinute
        }
        guard let quarterBPM, quarterBPM > 0 else { return nil }
        return Tempo(
            beatsPerSecond: quarterBPM / 60,
            visible: visible,
            beatNote: beat?.note ?? .quarter,
            beatDots: beat?.dots ?? 0,
        )
    }

    private static func soundTempo(_ sound: XMLTreeNode) -> Double? {
        sound.attributes["tempo"].flatMap { Double($0) }.flatMap { $0 > 0 ? $0 : nil }
    }

    /// The metronome's first `<beat-unit>` and the `<beat-unit-dot>`s that follow it (before any second unit).
    private static func beatUnit(_ metronome: XMLTreeNode) -> (note: NoteDuration, dots: Int)? {
        guard let index = metronome.children.firstIndex(where: { $0.name == "beat-unit" }),
              let note = NoteDuration(mscxName: metronome.children[index].text)
        else { return nil }
        let dots = metronome.children[(index + 1)...].prefix { $0.name == "beat-unit-dot" }.count
        return (note, dots)
    }
}
