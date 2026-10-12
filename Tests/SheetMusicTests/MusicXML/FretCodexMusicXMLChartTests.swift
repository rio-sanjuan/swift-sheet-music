import Foundation
@testable import SheetMusicCore
@testable import SheetMusicMIDI
@testable import SheetMusicMSCX
@testable import SheetMusicMusicXML
import Testing

/// FretCodex fork, delta F1: the parts of a guitar chart MusicXML used to drop — tempo, chord symbols, endings and
/// short bars — decoded into the `Score` shape MSCX gives them. Fixtures are authored for the fork and owned by
/// FretCodex (see `FretCodexFixtures`).
@Suite("FretCodex F1 — MusicXML chart elements")
struct FretCodexMusicXMLChartTests {
    typealias F = FretCodexFixtures

    /// A 3/4 G-major tune: a one-beat pickup (`implicit`), ♩ = 90 with a G chord at the start, a repeated bar with
    /// first and second endings, and a final two-beat bar that completes the pickup.
    static let tune = F.document(measures: """
    <measure number="0" implicit="yes">
      <attributes><divisions>480</divisions><key><fifths>1</fifths></key>
        <time><beats>3</beats><beat-type>4</beat-type></time><clef><sign>G</sign><line>2</line></clef></attributes>
      <direction placement="above"><direction-type><words></words></direction-type><sound tempo="90"/></direction>
      \(F.note("D", 4))
    </measure>
    <measure number="1">
      <barline location="left"><bar-style>heavy-light</bar-style><repeat direction="forward"/></barline>
      <harmony><root><root-step>G</root-step></root><kind>major</kind></harmony>
      \(F.note("G", 4, type: "half", duration: 960))\(F.note("B", 4))
    </measure>
    <measure number="2">
      <barline location="left"><ending number="1" type="start">1.</ending></barline>
      <harmony><root><root-step>D</root-step></root><kind text="7">dominant</kind></harmony>
      \(F.note("A", 4, type: "half", dotted: true, duration: 1440))
      <barline location="right"><bar-style>light-heavy</bar-style><ending number="1" type="stop"/>\
      <repeat direction="backward"/></barline>
    </measure>
    <measure number="3">
      <barline location="left"><ending number="2" type="start">2.</ending></barline>
      \(F.note("G", 4, type: "half", dotted: true, duration: 1440))
      <barline location="right"><ending number="2" type="discontinue"/></barline>
    </measure>
    <measure number="4">
      \(F.note("G", 4, type: "half", duration: 960))
      <barline location="right"><bar-style>light-heavy</bar-style></barline>
    </measure>
    """)

    static func tempos(_ score: Score, measure: Int) -> [(MeasurePosition, Tempo)] {
        score.systemMeasures[measure].elements.compactMap { positioned in
            if case let .tempo(tempo) = positioned.element { return (positioned.position, tempo) }
            return nil
        }
    }

    static func harmonies(_ score: Score, measure: Int) -> [Harmony] {
        F.elements(score, measure: measure).compactMap { element in
            if case let .harmony(harmony) = element { return harmony }
            return nil
        }
    }

    static func voltas(_ score: Score, measure: Int) -> [Spanner] {
        F.elements(score, measure: measure).compactMap { element in
            if case let .spanner(spanner) = element, spanner.kind == .volta { return spanner }
            return nil
        }
    }

    @Test("the tune: pickup, tempo, chord symbols, endings and playback order")
    func tune() throws {
        let score = try F.parse(Self.tune)
        let measures = score.parts[0].staves[0].measures
        #expect(measures.map(\.actualLength) == [
            Fraction(numerator: 1, denominator: 4), nil, nil, nil, Fraction(numerator: 2, denominator: 4),
        ])
        #expect(measures.map(\.irregular) == [true, false, false, false, false])
        #expect(score.displayedMeasureNumber(at: 1) == 1)

        let tempo = try #require(Self.tempos(score, measure: 0).first)
        #expect(tempo.0 == .start)
        #expect(tempo.1.beatsPerSecond == 1.5)
        #expect(tempo.1.beatNote == .quarter)

        #expect(Self.harmonies(score, measure: 1).map(\.rootTpc) == [15])
        #expect(Self.harmonies(score, measure: 1).map(\.name) == [""])
        #expect(Self.harmonies(score, measure: 2).map(\.name) == ["7"])

        #expect(Self.voltas(score, measure: 2).map(\.voltaEndings) == [[1]])
        #expect(Self.voltas(score, measure: 3).map(\.voltaEndings) == [[2]])
        #expect(Self.voltas(score, measure: 2).map(\.nextMeasuresOffset) == [1])

        let order = RepeatUnwinder.plan(navigation: ScoreNavigation(score: score)).map(\.measureIndex)
        #expect(order == [0, 1, 2, 1, 3, 4])
    }

    @Test("<sound tempo> is quarter notes per minute; a lone one is an invisible marking")
    func soundTempo() throws {
        let score = try F.parse(F.document(measures: """
        <measure number="1"><attributes><divisions>480</divisions></attributes>
        \(F.note("C", 4))<direction><direction-type><words></words></direction-type><sound tempo="72"/></direction>
        \(F.note("D", 4))<sound tempo="144"/>\(F.note("E", 4))</measure>
        """))
        let tempos = Self.tempos(score, measure: 0)
        #expect(tempos.map { $0.0 } == [
            MeasurePosition(numerator: 1, denominator: 4), MeasurePosition(numerator: 2, denominator: 4),
        ])
        #expect(tempos.map { $0.1.beatsPerSecond } == [1.2, 2.4])
        #expect(tempos.allSatisfy { !$0.1.visible })
    }

    @Test("<metronome> gives the beat note, and the tempo when <sound> is missing")
    func metronome() throws {
        func tempo(_ direction: String) throws -> Tempo? {
            try Self.tempos(F.parse(F.document(measures: """
            <measure number="1"><attributes><divisions>480</divisions></attributes>\(direction)\
            \(F.note("C", 4))</measure>
            """)), measure: 0).first?.1
        }
        let dotted = try #require(try tempo("""
        <direction><direction-type><metronome><beat-unit>quarter</beat-unit><beat-unit-dot/>\
        <per-minute>60</per-minute></metronome></direction-type></direction>
        """))
        #expect(dotted.beatsPerSecond == 1.5) // 60 dotted quarters = 90 quarters a minute
        #expect(dotted.beatNote == .quarter)
        #expect(dotted.beatDots == 1)
        #expect(dotted.visible)
        let both = try #require(try tempo("""
        <direction><direction-type><metronome><beat-unit>half</beat-unit><per-minute>50</per-minute></metronome>\
        </direction-type><sound tempo="100"/></direction>
        """))
        #expect(both.beatsPerSecond == 100.0 / 60)
        #expect(both.beatNote == .half)
        #expect(try tempo("<direction><direction-type><words>Swing</words></direction-type></direction>") == nil)
    }

    @Test("the same tempo in two parts is one tempo")
    func tempoAcrossParts() throws {
        let measure = """
        <measure number="1"><attributes><divisions>480</divisions></attributes>
        <direction><direction-type><words></words></direction-type><sound tempo="96"/></direction>\(F.note("C", 4))
        </measure>
        """
        let score = try F.parse(F.document([
            (id: "P1", name: "Guitar", measures: measure), (id: "P2", name: "Bass", measures: measure),
        ]))
        #expect(Self.tempos(score, measure: 0).count == 1)
    }

    @Test("chord symbols: root and bass tpc, MuseScore-form suffixes, printed kind text")
    func chordSymbols() throws {
        func harmony(_ body: String) throws -> Harmony? {
            try Self.harmonies(F.parse(F.document(measures: """
            <measure number="1"><attributes><divisions>480</divisions></attributes>
            <harmony>\(body)</harmony>\(F.note("C", 4))</measure>
            """)), measure: 0).first
        }
        let root = { (step: String, alter: Int) in
            "<root><root-step>\(step)</root-step><root-alter>\(alter)</root-alter></root>"
        }
        let cases: [(String, Int?, String, Int?)] = [
            (root("E", 0) + "<kind>minor-seventh</kind>", 18, "m7", nil),
            (root("B", -1) + "<kind>major-seventh</kind>", 12, "maj7", nil),
            (root("F", 1) + "<kind>half-diminished</kind>", 20, "m7b5", nil),
            (root("A", 0) + "<kind>suspended-fourth</kind>", 17, "sus4", nil),
            (root("C", 0) + "<kind text=\"min7\">minor-seventh</kind>", 14, "min7", nil),
            (root("D", 0) + "<kind>dominant</kind><bass><bass-step>F</bass-step><bass-alter>1</bass-alter></bass>",
             16, "7", 20),
            (root("G", 0) + "<kind>dominant</kind><degree><degree-value>9</degree-value>"
                + "<degree-alter>-1</degree-alter><degree-type>add</degree-type></degree>", 15, "7b9", nil),
            ("<root><root-step text=\"\">C</root-step></root><kind text=\"N.C.\">none</kind>", nil, "N.C.", nil),
        ]
        for (body, rootTpc, name, bassTpc) in cases {
            let decoded = try #require(try harmony(body), "\(body)")
            #expect(decoded.rootTpc == rootTpc, "\(body)")
            #expect(decoded.name == name, "\(body)")
            #expect(decoded.bassTpc == bassTpc, "\(body)")
        }
        #expect(try harmony("<kind>none</kind>") == nil) // nothing to show
    }

    @Test("a chord symbol equals the MSCX <Harmony> for the same chord")
    func chordSymbolMatchesMSCX() throws {
        let musicXML = try #require(Self.harmonies(F.parse(F.document(measures: """
        <measure number="1"><attributes><divisions>480</divisions></attributes><harmony><root><root-step>E</root-step>
        </root><kind>minor-seventh</kind></harmony>\(F.note("E", 4))</measure>
        """)), measure: 0).first)
        let mscx = try #require(Self.harmonies(F.parseMSCX("""
        <?xml version="1.0" encoding="UTF-8"?><museScore version="4.60"><Score><Division>480</Division>
        <Part><Staff id="1"/><Instrument/></Part><Staff id="1"><Measure><voice>
        <Harmony><root>18</root><name>m7</name></Harmony>
        <Chord><durationType>quarter</durationType><Note><pitch>64</pitch><tpc>18</tpc></Note></Chord>
        </voice></Measure></Staff></Score></museScore>
        """), measure: 0).first)
        #expect(musicXML == mscx)
    }

    @Test("a chord symbol sits before the chord at its time, or is jogged to a time between chords")
    func chordSymbolPlacement() throws {
        let score = try F.parse(F.document(measures: """
        <measure number="1"><attributes><divisions>480</divisions><time><beats>4</beats><beat-type>4</beat-type>
        </time></attributes>\(F.note("C", 4, type: "half", duration: 960))
        <harmony><root><root-step>F</root-step></root><kind>major</kind></harmony>\(F.note("F", 4, type: "half",
        duration: 960))<backup><duration>480</duration></backup>
        <harmony><root><root-step>G</root-step></root><kind>major</kind></harmony><forward><duration>480</duration>
        </forward></measure>
        """))
        let shape = F.elements(score).map { element -> String in
            switch element {
            case .chord: "chord"
            case let .harmony(harmony): "harmony \(harmony.rootTpc ?? -1)"
            case let .locationShift(delta): "shift \(delta.numerator)/\(delta.denominator)"
            default: "other"
            }
        }
        #expect(shape == [
            "other", "chord", "harmony 13", "chord", "shift -1/4", "harmony 15", "shift 1/4",
        ])
    }

    @Test("an ending's volta equals the MSCX <Spanner type=\"Volta\"> and spans until its stop")
    func endings() throws {
        let score = try F.parse(F.document(measures: """
        <measure number="1"><attributes><divisions>480</divisions></attributes>
        <barline location="left"><ending number="1, 2" type="start"/></barline>\(F.note("C", 4, type: "whole",
        duration: 1920))</measure>
        <measure number="2">\(F.note("C", 4, type: "whole", duration: 1920))
        <barline location="right"><ending number="1, 2" type="stop"/><repeat direction="backward"/></barline></measure>
        <measure number="3"><barline location="left"><ending number="x" type="start"/></barline>\(F.note("C", 4,
        type: "whole", duration: 1920))</measure>
        """))
        let volta = try #require(Self.voltas(score, measure: 0).first)
        #expect(volta.voltaEndings == [1, 2])
        #expect(volta.nextMeasuresOffset == 2)
        #expect(volta.beginText == "1, 2")
        #expect(Self.voltas(score, measure: 2).isEmpty) // "x" is not an ending number
        let mscx = try #require(Self.voltas(F.parseMSCX("""
        <?xml version="1.0" encoding="UTF-8"?><museScore version="4.60"><Score><Division>480</Division>
        <Part><Staff id="1"/><Instrument/></Part><Staff id="1"><Measure><voice>
        <Spanner type="Volta"><Volta><beginText>1, 2</beginText><endings>1, 2</endings></Volta>
        <next><location><measures>2</measures></location></next></Spanner>
        <Chord><durationType>whole</durationType><Note><pitch>60</pitch><tpc>14</tpc></Note></Chord>
        </voice></Measure></Staff></Score></museScore>
        """), measure: 0).first)
        #expect(volta == mscx)
    }

    @Test("a short first bar matches MSCX's <Measure len> + <irregular>; a full bar keeps nil")
    func pickupMatchesMSCX() throws {
        let musicXML = try F.parse(F.document(measures: """
        <measure number="0" implicit="yes"><attributes><divisions>480</divisions><time><beats>3</beats>\
        <beat-type>4</beat-type></time></attributes>\(F.note("D", 4))</measure>
        <measure number="1">\(F.note("G", 4, type: "half", dotted: true, duration: 1440))</measure>
        """))
        let mscx = try F.parseMSCX("""
        <?xml version="1.0" encoding="UTF-8"?><museScore version="4.60"><Score><Division>480</Division>
        <Part><Staff id="1"/><Instrument/></Part><Staff id="1"><Measure len="1/4"><irregular>1</irregular><voice>
        <TimeSig><sigN>3</sigN><sigD>4</sigD></TimeSig>
        <Chord><durationType>quarter</durationType><Note><pitch>62</pitch><tpc>16</tpc></Note></Chord></voice></Measure>
        <Measure><voice><Chord><durationType>half</durationType><dots>1</dots><Note><pitch>67</pitch><tpc>15</tpc>\
        </Note></Chord></voice></Measure></Staff></Score></museScore>
        """)
        let produced = musicXML.parts[0].staves[0].measures
        let reference = mscx.parts[0].staves[0].measures
        #expect(produced.map(\.actualLength) == reference.map(\.actualLength))
        #expect(produced.map(\.irregular) == reference.map(\.irregular))
    }

    @Test("the decoded tune survives MSCX encode → decode")
    func tuneRoundTripsThroughMSCX() throws {
        let score = try F.parse(Self.tune)
        let decoded = try MSCXParser.parse(MSCXEncoder.encode(score))
        #expect(decoded.parts[0].staves[0].measures.map(\.actualLength)
            == score.parts[0].staves[0].measures.map(\.actualLength))
        #expect(Self.harmonies(decoded, measure: 2) == Self.harmonies(score, measure: 2))
        #expect(Self.voltas(decoded, measure: 2) == Self.voltas(score, measure: 2))
        #expect(Self.tempos(decoded, measure: 0).map { $0.1.beatsPerSecond } == [1.5])
    }
}
