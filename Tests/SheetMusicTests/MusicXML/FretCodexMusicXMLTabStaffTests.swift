import Foundation
@testable import SheetMusicCore
@testable import SheetMusicMusicXML
import Testing

/// FretCodex fork, delta F1: the staff side of MusicXML tablature — the TAB clef's staff, octave clefs, the capo, and
/// a guitar written as standard + tab, compared with a hand-authored MSCX of the same music. Fixtures are authored for
/// the fork and owned by FretCodex (see `FretCodexFixtures`).
@Suite("FretCodex F1 — MusicXML tab staves")
struct FretCodexMusicXMLTabStaffTests {
    typealias F = FretCodexFixtures

    /// The guitar riff as ONE part with two staves: staff 1 treble-8vb, staff 2 TAB. Written an octave above sounding
    /// (`<octave-change>-1`), so the written E3 is the open low E string.
    static let guitarAndTab = F.document(measures: """
    <measure number="1">
      <attributes>
        <divisions>480</divisions>
        <key><fifths>1</fifths></key>
        <time><beats>4</beats><beat-type>4</beat-type></time>
        <staves>2</staves>
        <clef number="1"><sign>G</sign><line>2</line><clef-octave-change>-1</clef-octave-change></clef>
        <clef number="2"><sign>TAB</sign><line>5</line></clef>
        <staff-details number="2"><staff-lines>6</staff-lines>\(F.standardTuning)</staff-details>
        <transpose><diatonic>0</diatonic><chromatic>0</chromatic><octave-change>-1</octave-change></transpose>
      </attributes>
      \(F.note("E", 3, staff: 1))
      \(F.note("F", 3, alter: 1, staff: 1))
      \(F.note("G", 3, staff: 1))
      \(F.note("B", 3, staff: 1))
      <backup><duration>1920</duration></backup>
      \(F.note("E", 3, voice: 5, staff: 2, technical: F.tab(string: 6, fret: 0)))
      \(F.note("F", 3, alter: 1, voice: 5, staff: 2, technical: F.tab(string: 6, fret: 2)))
      \(F.note("G", 3, voice: 5, staff: 2, technical: F.tab(string: 6, fret: 3)))
      \(F.note("B", 3, voice: 5, staff: 2, technical: F.tab(string: 5, fret: 2)))
    </measure>
    """)

    /// The same riff as MuseScore models it: one part, a standard staff and a tab staff linked to it, sounding
    /// pitches, a guitar transposition, the tuning on the instrument.
    static let guitarAndTabMSCX = """
    <?xml version="1.0" encoding="UTF-8"?>
    <museScore version="4.60"><Score><Division>480</Division>
    <Part>
      <Staff id="1"><StaffType group="pitched"><name>stdNormal</name></StaffType><defaultClef>G8vb</defaultClef></Staff>
      <Staff id="2"><StaffType group="tablature"><name>tab6StrCommon</name><lines>6</lines></StaffType>
        <defaultClef>TAB</defaultClef><linkedTo>1</linkedTo></Staff>
      <Instrument id="guitar-steel"><longName>Guitar</longName><trackName>Guitar</trackName>
        <transposeDiatonic>-7</transposeDiatonic><transposeChromatic>-12</transposeChromatic>
        <StringData><frets>19</frets><string>40</string><string>45</string><string>50</string>
        <string>55</string><string>59</string><string>64</string></StringData></Instrument>
    </Part>
    <Staff id="1"><Measure><voice>
      <KeySig><concertKey>1</concertKey></KeySig><TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
      \(notesMSCX(withTab: false))
    </voice></Measure></Staff>
    <Staff id="2"><Measure><voice>
      <KeySig><concertKey>1</concertKey></KeySig><TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
      \(notesMSCX(withTab: true))
    </voice></Measure></Staff>
    </Score></museScore>
    """

    /// E2 F♯2 G2 B2 (sounding), on the sixth string frets 0 2 3 and the fifth string fret 2.
    static func notesMSCX(withTab: Bool) -> String {
        [(40, 18, 5, 0), (42, 20, 5, 2), (43, 15, 5, 3), (47, 19, 4, 2)].map { pitch, tpc, string, fret in
            let tab = withTab ? "<fret>\(fret)</fret><string>\(string)</string>" : ""
            return "<Chord><durationType>quarter</durationType>"
                + "<Note><pitch>\(pitch)</pitch><tpc>\(tpc)</tpc>\(tab)</Note></Chord>"
        }.joined()
    }

    @Test("a TAB clef makes a tablature staff shaped like MSCX's: group, tab<N>StrCommon, line count, clef 'TAB'")
    func tabStaffMatchesMSCX() throws {
        let musicXML = try F.parse(Self.guitarAndTab)
        let mscx = try F.parseMSCX(Self.guitarAndTabMSCX)
        for (produced, reference) in zip(musicXML.parts[0].staves, mscx.parts[0].staves) {
            #expect(produced.staffType == reference.staffType)
            #expect(produced.group == reference.group)
            #expect(produced.lineCount == reference.lineCount)
        }
        let tabStaff = musicXML.parts[0].staves[1]
        #expect(tabStaff.group == "tablature")
        #expect(tabStaff.staffType == "tab6StrCommon")
        // MSCX names the clef in `defaultClef`; MusicXML in the opening `.clef`. `NotatedClef` still collapses it.
        #expect(mscx.parts[0].staves[1].defaultClefType == "TAB")
        let clef = try #require(F.firstClef(musicXML, staff: 1))
        #expect(clef.concertClefType == "TAB")
        #expect(NotatedClef(rawType: clef.concertClefType) == .treble)
    }

    @Test("a 4-line TAB staff is tab4StrCommon; an unusual count falls back to tab6StrCommon")
    func tabPresetFollowsLineCount() throws {
        func staff(lines: Int) throws -> Staff {
            try F.parse(F.document(measures: """
            <measure number="1"><attributes><divisions>480</divisions><clef><sign>TAB</sign></clef>
            <staff-details><staff-lines>\(lines)</staff-lines></staff-details></attributes>\(F.note("E", 2))</measure>
            """)).parts[0].staves[0]
        }
        let bass = try staff(lines: 4)
        #expect(bass.staffType == "tab4StrCommon")
        #expect(bass.lineCount == 4)
        let threeLine = try staff(lines: 3)
        #expect(threeLine.staffType == "tab6StrCommon")
        #expect(threeLine.lineCount == 3)
    }

    @Test("guitar standard + tab decode to the same sounding pitches, tuning and tab positions as the MSCX")
    func guitarAndTabMatchMSCX() throws {
        let musicXML = try F.parse(Self.guitarAndTab)
        let mscx = try F.parseMSCX(Self.guitarAndTabMSCX)
        let instrument = musicXML.parts[0].instrument
        #expect(instrument.transposeDiatonic == mscx.parts[0].instrument.transposeDiatonic)
        #expect(instrument.transposeChromatic == mscx.parts[0].instrument.transposeChromatic)
        #expect(instrument.stringData?.strings == mscx.parts[0].instrument.stringData?.strings)
        for staff in 0 ..< 2 {
            let produced = F.notes(musicXML, staff: staff).map { [$0.pitch, $0.tpc] }
            let reference = F.notes(mscx, staff: staff).map { [$0.pitch, $0.tpc] }
            #expect(produced == reference)
        }
        let producedTab = F.notes(musicXML, staff: 1).map { [$0.string, $0.fret] }
        let referenceTab = F.notes(mscx, staff: 1).map { [$0.string, $0.fret] }
        #expect(producedTab == referenceTab)
    }

    /// The pairing rule FRETCODEX.md gives consumers: within a part, a `tablature` staff pairs with the part's pitched
    /// staff — MSCX also says so in `<linkedTo>`, MusicXML has no such markup. Chords pair by position.
    @Test("one part, two staves: the consumer pairs the pitched staff with the tab staff by part and position")
    func pairingWithinOnePart() throws {
        let score = try F.parse(Self.guitarAndTab)
        let part = score.parts[0]
        let pitched = try #require(part.staves.firstIndex { $0.group == "pitched" })
        let tab = try #require(part.staves.firstIndex { $0.group == "tablature" })
        #expect((pitched, tab) == (0, 1))
        #expect(part.staves[tab].preservedMarkup.isEmpty) // no <linkedTo>: nothing in MusicXML says it
        let merged = zip(F.notes(score, staff: pitched), F.notes(score, staff: tab)).map { standard, tabNote in
            Note(pitch: standard.pitch, tpc: standard.tpc, fret: tabNote.fret, string: tabNote.string)
        }
        #expect(merged.map(\.pitch) == [40, 42, 43, 47])
        #expect(merged.map(\.string) == [5, 5, 5, 4])
        #expect(merged.map(\.fret) == [0, 2, 3, 2])
    }

    @Test("two parts — standard and TAB — keep one staff each; the TAB part is the tablature one")
    func standardAndTabAsTwoParts() throws {
        let attributes = { (clef: String, details: String) in
            """
            <attributes><divisions>480</divisions><time><beats>4</beats><beat-type>4</beat-type></time>\(clef)\
            \(details)<transpose><diatonic>0</diatonic><chromatic>0</chromatic><octave-change>-1</octave-change>\
            </transpose></attributes>
            """
        }
        let octaveClef = "<clef><sign>G</sign><line>2</line><clef-octave-change>-1</clef-octave-change></clef>"
        let standard = attributes(octaveClef, "") + F.note("E", 3)
        let tabDetails = "<staff-details><staff-lines>6</staff-lines>\(F.standardTuning)</staff-details>"
        let tab = attributes("<clef><sign>TAB</sign></clef>", tabDetails)
            + F.note("E", 3, technical: F.tab(string: 6, fret: 0))
        let score = try F.parse(F.document([
            (id: "P1", name: "Guitar", measures: "<measure number=\"1\">\(standard)</measure>"),
            (id: "P2", name: "Guitar", measures: "<measure number=\"1\">\(tab)</measure>"),
        ]))
        #expect(score.parts.map { $0.staves.map(\.group) } == [["pitched"], ["tablature"]])
        #expect(score.parts[0].instrument.stringData == nil)
        #expect(score.parts[1].instrument.stringData?.strings.count == 6)
        #expect(F.notes(score, part: 0).map(\.pitch) == F.notes(score, part: 1).map(\.pitch))
    }

    @Test("<clef-octave-change> names MuseScore's octave clef")
    func octaveClefs() throws {
        func clef(_ sign: String, _ line: Int, octave: Int) throws -> String? {
            try F.firstClef(F.parse(F.document(measures: """
            <measure number="1"><attributes><divisions>480</divisions><clef><sign>\(sign)</sign><line>\(line)</line>\
            <clef-octave-change>\(octave)</clef-octave-change></clef></attributes>\(F.note("C", 4))</measure>
            """)))?.concertClefType
        }
        #expect(try clef("G", 2, octave: -1) == "G8vb")
        #expect(try clef("G", 2, octave: 1) == "G8va")
        #expect(try clef("G", 2, octave: -2) == "G15mb")
        #expect(try clef("F", 4, octave: -1) == "F8vb")
        #expect(try clef("C", 4, octave: -1) == "C4_8VB")
        #expect(try clef("C", 3, octave: -1) == "C3") // MuseScore has no octave alto clef: the change is ignored
        #expect(try clef("G", 2, octave: 0) == "G")
        let guitarClef = try #require(try clef("G", 2, octave: -1))
        #expect(NotatedClef(rawType: guitarClef) == .treble8vb)
    }

    @Test("<capo> becomes a .capo element on its staff; pitches are left as written")
    func capo() throws {
        let score = try F.parse(F.document(measures: """
        <measure number="1"><attributes><divisions>480</divisions>
        <time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>TAB</sign></clef>
        <staff-details><staff-lines>6</staff-lines>\(F.standardTuning)<capo>2</capo></staff-details></attributes>
        \(F.note("F", 4, alter: 1, technical: F.tab(string: 1, fret: 0)))</measure>
        <measure number="2"><attributes><staff-details><capo>2</capo></staff-details></attributes>
        \(F.note("F", 4, alter: 1, technical: F.tab(string: 1, fret: 0)))</measure>
        <measure number="3"><attributes><staff-details><capo>0</capo></staff-details></attributes>
        \(F.note("E", 4, technical: F.tab(string: 1, fret: 0)))</measure>
        """))
        let capos = (0 ..< 3).map { measure in
            F.elements(score, measure: measure).compactMap { element -> Capo? in
                if case let .capo(capo) = element { return capo }
                return nil
            }
        }
        #expect(capos[0] == [Capo(fretPosition: 2, text: "Capo 2")])
        #expect(capos[1].isEmpty) // restated, not changed
        #expect(capos[2] == [Capo(fretPosition: 0, text: "No capo")])
        #expect(F.notes(score).map(\.pitch) == [66, 66, 64])
    }
}
