import SheetMusicCore
import SheetMusicFoundation
import SheetMusicXMLTools

/// A `<note>` carrying `<grace>`: decoded into the grace chord the MSCX side holds rather than an ordinary chord.
/// C++: `MusicXmlParserPass2::note`, `graceNoteType` and `createGraceChord` (`importmusicxmlpass2.cpp`).
///
/// A grace note takes no time: it is not a `VoiceElement`, so it neither advances a voice nor moves what follows it
/// (the measure cursor already skips it — `MusicXMLMeasureCursor.advance`). `MusicXMLGraceRun` collects a voice's
/// graces until the chord they belong to arrives.
///
/// What a grace keeps: the note itself — pitch at concert, spelling, accidental, ties, notehead parentheses, the
/// tablature `<string>` / `<fret>` — and a fermata, which MuseScore moves onto the principal chord's segment (it
/// is emitted ahead of that chord, as an ordinary note's is). What it drops, as `GraceChord` has nowhere to put it:
/// articulations, lyrics (MuseScore hands those to the principal chord), arpeggios, breath marks, and any
/// `steal-time-previous` / `steal-time-following` / `make-time` timing, which MuseScore's importer ignores too —
/// playback timing of a grace is `MidiRenderer`'s, from the grace type.
extension MusicXMLNoteDecoder {
    struct Grace {
        let graceType: GraceType
        /// The written value — the number of flags drawn; playback length comes from `graceType`.
        let duration: NoteDuration
        let note: Note
        /// `<chord/>`: another note of the grace chord just before it.
        let isChordTone: Bool
        /// Ends a slur or a trill's wavy line: MuseScore takes the run up to here as grace notes AFTER the
        /// previous chord (`Notations::mustStopGraceAFter`).
        let endsSlurOrTrill: Bool
        let fermata: Fermata?
    }

    /// MuseScore's `graceNoteType`: a slashed grace is an acciaccatura; otherwise the written value picks
    /// `grace4` / `grace16` / `grace32`, and anything else (an eighth, most often) is an appoggiatura.
    static func graceType(slash: Bool, value: NoteDuration) -> GraceType {
        if slash { return .acciaccatura }
        switch value {
        case .quarter: return .grace4
        case .sixteenth: return .grace16
        case .thirtySecond: return .grace32
        default: return .appoggiatura
        }
    }

    /// The grace a `<grace>` note decodes to. `<type>` and `<dot>`s give its written value — a grace has no
    /// `<duration>`, and a `<time-modification>` does not change how it is drawn; without a usable `<type>` it
    /// falls back to an eighth, the value of a plain acciaccatura or appoggiatura.
    static func decodeGrace(
        _ node: XMLTreeNode,
        isChordTone: Bool,
        drumTable: MusicXMLDrumTable,
        transposition: MusicXMLTransposition,
    ) throws -> Grace {
        let graceNode = node.first("grace")
        let value = node.first("type").flatMap { NoteDuration(mscxName: $0.text) } ?? .eighth
        let notations = node.first("notations")
        let endsSlur = notations?.all("slur").contains { $0.attributes["type"] == "stop" } ?? false
        let endsTrill = notations?.first("ornaments")?.all("wavy-line")
            .contains { $0.attributes["type"] == "stop" } ?? false
        return try Grace(
            graceType: graceType(slash: graceNode?.attributes["slash"] == "yes", value: value),
            duration: value.dotted(node.all("dot").count),
            note: decodePitchedNote(node, drumTable: drumTable, transposition: transposition),
            isChordTone: isChordTone,
            endsSlurOrTrill: endsSlur || endsTrill,
            fermata: decodeFermata(node),
        )
    }
}
