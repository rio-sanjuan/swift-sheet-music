import Foundation
@testable import SheetMusicCore
@testable import SheetMusicMSCX
@testable import SheetMusicMusicXML
import Testing

/// FretCodex fork, delta F2 (SM-9): a MusicXML `<grace>` note decodes into the grace chord MSCX holds — on the
/// chord it decorates, taking no time — instead of an ordinary chord of its full `<type>` that pushed the rest of
/// the bar, and the chord symbols placed by time, out of line. Fixtures are authored for the fork and owned by
/// FretCodex (see `FretCodexFixtures`).
@Suite("FretCodex F2 — MusicXML grace notes")
struct FretCodexMusicXMLGraceTests {
    typealias F = FretCodexFixtures

    /// A `<grace>` note: `slash` for an acciaccatura, `notations` any extra `<notations>` body.
    static func grace(
        _ step: String, _ octave: Int, type: String = "eighth", slash: Bool = false, chord: Bool = false,
        technical: String? = nil, notations: String = "",
    ) -> String {
        let technicalXML = technical.map { "<technical>\($0)</technical>" } ?? ""
        let notationsXML = technicalXML.isEmpty && notations.isEmpty
            ? "" : "<notations>\(technicalXML)\(notations)</notations>"
        return """
        <note><grace\(slash ? " slash=\"yes\"" : "")/>\(chord ? "<chord/>" : "")<pitch><step>\(step)</step>\
        <octave>\(octave)</octave></pitch><voice>1</voice><type>\(type)</type>\(notationsXML)</note>
        """
    }

    static func harmony(_ step: String) -> String {
        "<harmony><root><root-step>\(step)</root-step></root><kind>major</kind></harmony>"
    }

    /// Two 4/4 guitar bars with string and fret on every note.
    /// Bar 1: chord symbol C; an acciaccatura before E; F; chord symbol G on beat 3; a two-note 16th grace before
    /// G; B. Bar 2: C, slurred to an eighth grace after it; an acciaccatura before E; G for a half, with an eighth
    /// grace after it that no chord follows.
    static let bars = F.document(measures: """
    <measure number="1"><attributes><divisions>480</divisions><time><beats>4</beats><beat-type>4</beat-type></time>\
    </attributes>
    \(harmony("C"))
    \(grace("D", 4, slash: true, technical: F.tab(string: 2, fret: 3)))
    \(F.note("E", 4, technical: F.tab(string: 1, fret: 0)))
    \(F.note("F", 4, technical: F.tab(string: 1, fret: 1)))
    \(harmony("G"))
    \(grace("A", 4, type: "16th", technical: F.tab(string: 1, fret: 5)))
    \(grace("C", 5, type: "16th", chord: true, technical: F.tab(string: 1, fret: 8)))
    \(F.note("G", 4, technical: F.tab(string: 1, fret: 3)))
    \(F.note("B", 4, technical: F.tab(string: 1, fret: 7)))
    </measure>
    <measure number="2">
    <note><pitch><step>C</step><octave>5</octave></pitch><duration>480</duration><voice>1</voice><type>quarter</type>\
    <notations><technical>\(F.tab(string: 1, fret: 8))</technical><slur type="start"/></notations></note>
    \(grace("B", 4, technical: F.tab(string: 1, fret: 7), notations: "<slur type=\"stop\"/>"))
    \(grace("D", 5, slash: true, technical: F.tab(string: 1, fret: 10)))
    \(F.note("E", 5, technical: F.tab(string: 1, fret: 12)))
    \(F.note("G", 4, type: "half", duration: 960, technical: F.tab(string: 1, fret: 3)))
    \(grace("A", 4, technical: F.tab(string: 1, fret: 5)))
    </measure>
    """)

    /// The same two bars as MuseScore writes them: every grace a `<Chord>` with its grace tag, ahead of the chord
    /// it belongs to — after-graces included.
    static let mscx = """
    <?xml version="1.0" encoding="UTF-8"?><museScore version="4.60"><Score><Division>480</Division>
    <Part><Staff id="1"/><Instrument/></Part><Staff id="1">
    <Measure><voice><TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
    <Chord><durationType>eighth</durationType><acciaccatura/>\(note(62, 16, string: 1, fret: 3))</Chord>
    <Chord><durationType>quarter</durationType>\(note(64, 18, string: 0, fret: 0))</Chord>
    <Chord><durationType>quarter</durationType>\(note(65, 13, string: 0, fret: 1))</Chord>
    <Chord><durationType>16th</durationType><grace16/>\(note(69, 17, string: 0, fret: 5))\
    \(note(72, 14, string: 0, fret: 8))</Chord>
    <Chord><durationType>quarter</durationType>\(note(67, 15, string: 0, fret: 3))</Chord>
    <Chord><durationType>quarter</durationType>\(note(71, 19, string: 0, fret: 7))</Chord>
    </voice></Measure>
    <Measure><voice>
    <Chord><durationType>eighth</durationType><grace8after/>\(note(71, 19, string: 0, fret: 7))</Chord>
    <Chord><durationType>quarter</durationType>\(note(72, 14, string: 0, fret: 8))</Chord>
    <Chord><durationType>eighth</durationType><acciaccatura/>\(note(74, 16, string: 0, fret: 10))</Chord>
    <Chord><durationType>quarter</durationType>\(note(76, 18, string: 0, fret: 12))</Chord>
    <Chord><durationType>eighth</durationType><grace8after/>\(note(69, 17, string: 0, fret: 5))</Chord>
    <Chord><durationType>half</durationType>\(note(67, 15, string: 0, fret: 3))</Chord>
    </voice></Measure>
    </Staff></Score></museScore>
    """

    static func note(_ pitch: Int, _ tpc: Int, string: Int, fret: Int) -> String {
        "<Note><pitch>\(pitch)</pitch><tpc>\(tpc)</tpc><fret>\(fret)</fret><string>\(string)</string></Note>"
    }

    static func chords(_ score: Score, measure: Int) -> [Chord] {
        F.elements(score, measure: measure).compactMap { element in
            if case let .chord(chord) = element { return chord }
            return nil
        }
    }

    /// Each chord's onset in its bar, from the voice's own durations.
    static func onsets(_ score: Score, measure: Int) -> [Fraction] {
        var cursor = Fraction(numerator: 0, denominator: 1)
        return chords(score, measure: measure).map { chord in
            defer { cursor += chord.duration.asFraction }
            return cursor
        }
    }

    @Test("graces take no time: the bar's chords and chord symbols keep their onsets")
    func gracesTakeNoTime() throws {
        let score = try F.parse(Self.bars)
        #expect(Self.chords(score, measure: 0).map { $0.notes.map(\.pitch) } == [[64], [65], [67], [71]])
        #expect(Self.onsets(score, measure: 0) == [0, 1, 2, 3].map { Fraction(numerator: $0, denominator: 4) })
        #expect(Self.chords(score, measure: 1).map { $0.notes.map(\.pitch) } == [[72], [76], [67]])
        #expect(Self.onsets(score, measure: 1) == [0, 1, 2].map { Fraction(numerator: $0, denominator: 4) })
        // Each chord symbol sits immediately before the chord at its time, with no jog: G is on beat 3.
        let shape = F.elements(score).compactMap { element -> String? in
            switch element {
            case let .chord(chord): "chord \(chord.notes.first?.pitch ?? 0)"
            case let .harmony(harmony): "harmony \(harmony.rootTpc ?? 0)"
            case .locationShift: "shift"
            default: nil
            }
        }
        #expect(shape == ["harmony 14", "chord 64", "chord 65", "harmony 15", "chord 67", "chord 71"])
        let length = score.parts[0].staves[0].measures.map(\.actualLength)
        #expect(length == [nil, nil])
    }

    @Test("graces are the grace chords the equivalent MSCX decodes to: kind, value, notes, string and fret")
    func gracesMatchMSCX() throws {
        let fromMusicXML = try F.parse(Self.bars)
        let fromMSCX = try F.parseMSCX(Self.mscx)
        for measure in 0 ..< 2 {
            let produced = Self.chords(fromMusicXML, measure: measure)
            let reference = Self.chords(fromMSCX, measure: measure)
            #expect(produced.map(\.graceNotesBefore.values) == reference.map(\.graceNotesBefore.values))
            #expect(produced.map(\.graceNotesAfter.values) == reference.map(\.graceNotesAfter.values))
            #expect(produced.map(\.duration) == reference.map(\.duration))
            #expect(produced.map(\.notes) == reference.map(\.notes))
        }
        let first = try #require(Self.chords(fromMusicXML, measure: 0).first?.graceNotesBefore.values.first)
        #expect(first.graceType == .acciaccatura)
        #expect(first.duration == .eighth)
        #expect(first.notes.map(\.string) == [1])
        #expect(first.notes.map(\.fret) == [3])
        let sixteenths = try #require(Self.chords(fromMusicXML, measure: 0)[2].graceNotesBefore.values.first)
        #expect(sixteenths.graceType == .grace16)
        #expect(sixteenths.duration == .sixteenth)
        #expect(sixteenths.notes.map(\.pitch) == [69, 72])
        let bar2 = Self.chords(fromMusicXML, measure: 1)
        #expect(bar2.map { $0.graceNotesAfter.values.map(\.graceType) } == [[.grace8after], [], [.grace8after]])
        #expect(bar2.map { $0.graceNotesBefore.values.map(\.graceType) } == [[], [.acciaccatura], []])
    }

    @Test("a grace before a rest waits for the chord after it; a grace rest is ignored")
    func graceBeforeARest() throws {
        let score = try F.parse(F.document(measures: """
        <measure number="1"><attributes><divisions>480</divisions></attributes>
        \(Self.grace("D", 4))<note><rest/><duration>480</duration><voice>1</voice><type>quarter</type></note>
        <note><grace/><rest/><voice>1</voice><type>eighth</type></note>
        \(F.note("E", 4, type: "half", dotted: true, duration: 1440))
        </measure>
        """))
        let elements = F.elements(score)
        #expect(elements.count == 2)
        guard case let .chord(rest) = elements[0], case let .chord(chord) = elements[1] else {
            Issue.record("expected a rest and a chord, got \(elements)")
            return
        }
        #expect(rest.notes.isEmpty && rest.graceNotesBefore.isEmpty)
        #expect(chord.graceNotesBefore.values.map { $0.notes.map(\.pitch) } == [[62]])
    }

    @Test("the graces survive MusicXML → MSCX → decode")
    func gracesRoundTripThroughMSCX() throws {
        let score = try F.parse(Self.bars)
        let decoded = try MSCXParser.parse(MSCXEncoder.encode(score))
        for measure in 0 ..< 2 {
            let before = Self.chords(score, measure: measure)
            let after = Self.chords(decoded, measure: measure)
            #expect(after.map(\.graceNotesBefore.values) == before.map(\.graceNotesBefore.values))
            #expect(after.map(\.graceNotesAfter.values) == before.map(\.graceNotesAfter.values))
            #expect(Self.onsets(decoded, measure: measure) == Self.onsets(score, measure: measure))
        }
    }
}
