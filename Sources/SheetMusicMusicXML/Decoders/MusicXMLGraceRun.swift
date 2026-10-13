import SheetMusicCore
import SheetMusicFoundation

/// One voice's grace notes waiting for the chord they belong to — MuseScore's grace chord list (`gcl`) and its
/// grace-after count (`gac`), `MusicXmlParserPass2::measure` / `note` (`importmusicxmlpass2.cpp`). Kept per
/// MusicXML voice of a staff; MuseScore keeps one list per measure and marks attaching it to a chord of another
/// voice a TODO.
///
/// - A grace waits; a `<chord/>` grace joins the grace chord before it.
/// - The next ordinary chord of the voice takes them as `graceNotesBefore`, in document order — except that a run
///   ending a slur or trill (`MusicXMLNoteDecoder.Grace.endsSlurOrTrill`) up to that grace belongs to the previous
///   chord, as grace notes AFTER it (`addGraceChordsAfter`), when the voice's previous chord or rest is a chord.
/// - A rest takes none: they wait for the chord after it.
/// - At the end of the measure, graces still waiting become grace notes after the voice's last chord, as
///   MuseScore converts its remainder; with no chord to take them they are dropped, as there.
///
/// Becoming an after-grace is MuseScore's `Chord::toGraceAfter`: an appoggiatura becomes `grace8after`, `grace16` /
/// `grace32` their `…after` forms, and an acciaccatura or `grace4`, which have none, stay as they are — so they land
/// in the previous chord's `graceNotesBefore`, where MuseScore's own `graceNotesBefore()` filter puts them.
struct MusicXMLGraceRun {
    private var graces: [GraceChord] = []
    /// How many of `graces`, from the front, belong after the previous chord.
    private var afterCount = 0

    var isEmpty: Bool {
        graces.isEmpty
    }

    mutating func add(_ grace: MusicXMLNoteDecoder.Grace) {
        if grace.isChordTone, let last = graces.indices.last {
            graces[last].notes = ChordNotes(Array(graces[last].notes) + [grace.note])
        } else {
            graces.append(GraceChord(
                graceType: grace.graceType, duration: grace.duration, notes: ChordNotes([grace.note]),
            ))
        }
        if grace.endsSlurOrTrill { afterCount = graces.count }
    }

    /// Hand the run to `principal`, the ordinary chord being appended to `elements` — the voice so far — and the
    /// after-run to the voice's previous chord, then empty the run.
    mutating func attach(to principal: inout Chord, previousIn elements: inout [VoiceElement]) {
        var before = graces
        if afterCount > 0,
           let previous = elements.lastIndex(where: Self.isChordOrRest),
           case let .chord(chord) = elements[previous], !chord.notes.isEmpty
        {
            elements[previous] = .chord(Self.appendingAfter(Array(graces.prefix(afterCount)), to: chord))
            before = Array(graces.dropFirst(afterCount))
        }
        principal.graceNotesBefore = IdentifiedArray(principal.graceNotesBefore.values + before)
        self = MusicXMLGraceRun()
    }

    /// End of the measure: the graces still waiting become grace notes after the voice's last chord.
    mutating func flush(into elements: inout [VoiceElement]) {
        defer { self = MusicXMLGraceRun() }
        guard let last = elements.lastIndex(where: { element in
            if case let .chord(chord) = element { return !chord.notes.isEmpty }
            return false
        }), case let .chord(chord) = elements[last]
        else { return }
        elements[last] = .chord(Self.appendingAfter(graces, to: chord))
    }

    private static func isChordOrRest(_ element: VoiceElement) -> Bool {
        if case .chord = element { return true }
        return false
    }

    /// `chord` with `graces` attached as grace notes after it (`Chord::toGraceAfter`, then `Chord::add`).
    private static func appendingAfter(_ graces: [GraceChord], to chord: Chord) -> Chord {
        var chord = chord
        var after = chord.graceNotesAfter.values
        var before = chord.graceNotesBefore.values
        for var grace in graces {
            grace.graceType = graceAfter(grace.graceType)
            if grace.graceType.isAfter {
                after.append(grace)
            } else {
                before.append(grace)
            }
        }
        chord.graceNotesAfter = IdentifiedArray(after)
        chord.graceNotesBefore = IdentifiedArray(before)
        return chord
    }

    /// MuseScore's `Chord::toGraceAfter`.
    private static func graceAfter(_ type: GraceType) -> GraceType {
        switch type {
        case .appoggiatura: .grace8after
        case .grace16: .grace16after
        case .grace32: .grace32after
        default: type
        }
    }
}
