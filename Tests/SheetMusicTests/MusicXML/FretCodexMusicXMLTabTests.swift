import Foundation
@testable import SheetMusicCore
@testable import SheetMusicMusicXML
import Testing

/// FretCodex fork, delta F1: MusicXML tablature decodes into the `Score` shape MSCX gives a MuseScore guitar part —
/// `Note.string` / `Note.fret`, `Instrument.stringData`, a tablature `Staff`, octave clefs, capo. Fixtures are authored
/// for the fork and owned by FretCodex (see `FretCodexFixtures`).
@Suite("FretCodex F1 — MusicXML tablature")
struct FretCodexMusicXMLTabTests {
    typealias F = FretCodexFixtures

    /// One 6-line TAB staff tuned to `tuning`, holding `notes`.
    static func tabPart(tuning: String = F.standardTuning, notes: String, extraDetails: String = "") -> String {
        F.document(measures: """
        <measure number="1">
          <attributes>
            <divisions>480</divisions>
            <time><beats>4</beats><beat-type>4</beat-type></time>
            <clef><sign>TAB</sign><line>5</line></clef>
            <staff-details><staff-lines>6</staff-lines>\(tuning)\(extraDetails)</staff-details>
          </attributes>
          \(notes)
        </measure>
        """)
    }

    @Test("<string> n becomes Note.string n − 1 (0 = highest string); <fret> is kept")
    func stringAndFretWithIndexFlip() throws {
        let score = try F.parse(Self.tabPart(notes: """
        \(F.note("E", 4, technical: F.tab(string: 1, fret: 0)))
        \(F.note("G", 2, technical: F.tab(string: 6, fret: 3)))
        \(F.note("C", 4, technical: F.tab(string: 2, fret: 1)))
        \(F.note("E", 3, chord: true, technical: F.tab(string: 4, fret: 2)))
        \(F.note("A", 3))
        """))
        let notes = F.notes(score)
        #expect(notes.map(\.string) == [0, 5, 1, 3, nil])
        #expect(notes.map(\.fret) == [0, 3, 1, 2, nil])
        // The consumer rule: string s sounds strings[count − 1 − s] + fret.
        let strings = try #require(score.parts[0].instrument.stringData).strings
        for note in notes {
            guard let string = note.string, let fret = note.fret else { continue }
            #expect(strings[strings.count - 1 - string].pitch + fret == note.pitch)
        }
    }

    @Test("a string below 1 or a negative fret is dropped; a <technical> in a second <notations> is read")
    func malformedPositionsAreDropped() throws {
        let second = """
        <note><pitch><step>D</step><octave>3</octave></pitch><duration>480</duration><voice>1</voice>\
        <type>quarter</type><notations><fermata/></notations>\
        <notations><technical><string>4</string><fret>0</fret></technical></notations></note>
        """
        let score = try F.parse(Self.tabPart(notes: """
        \(F.note("E", 4, technical: "<string>0</string><fret>-1</fret>"))
        \(second)
        """))
        let notes = F.notes(score)
        #expect(notes.map(\.string) == [nil, 3])
        #expect(notes.map(\.fret) == [nil, 0])
    }

    @Test("standard tuning: <staff-tuning> line 1 is the lowest string, StringData low → high")
    func standardTuning() throws {
        let stringData = try #require(try F.parse(Self.tabPart(notes: F.note("E", 4))).parts[0].instrument.stringData)
        #expect(stringData.strings.map(\.pitch) == [40, 45, 50, 55, 59, 64])
        #expect(stringData.strings.allSatisfy { !$0.useFlat && !$0.isOpen })
        #expect(stringData.frets == 25)
    }

    @Test("drop D lowers only the lowest string")
    func dropDTuning() throws {
        let tuning = F.standardTuning.replacingOccurrences(
            of: F.tuning(line: 1, "E", 2), with: F.tuning(line: 1, "D", 2),
        )
        let stringData = try #require(try F.parse(Self.tabPart(tuning: tuning, notes: F.note("D", 2)))
            .parts[0].instrument.stringData)
        #expect(stringData.strings.map(\.pitch) == [38, 45, 50, 55, 59, 64])
        #expect(stringData.strings.allSatisfy { !$0.useFlat })
    }

    @Test("E♭ tuning keeps its flat spelling (useFlat)")
    func eFlatTuning() throws {
        let tuning = [("E", 2), ("A", 2), ("D", 3), ("G", 3), ("B", 3), ("E", 4)]
            .enumerated()
            .map { F.tuning(line: $0.offset + 1, $0.element.0, $0.element.1, alter: -1) }
            .joined()
        let stringData = try #require(try F.parse(Self.tabPart(tuning: tuning, notes: F.note("E", 4, alter: -1)))
            .parts[0].instrument.stringData)
        #expect(stringData.strings.map(\.pitch) == [39, 44, 49, 54, 58, 63])
        #expect(stringData.strings.allSatisfy { $0.useFlat })
    }

    @Test("a line without a tuning is a pitch-0 placeholder; staff-tuning without staff-lines sizes by its lines")
    func partialTuning() throws {
        let partial = try F.parse(Self.tabPart(tuning: F.tuning(line: 2, "A", 2), notes: F.note("A", 2)))
        #expect(partial.parts[0].instrument.stringData?.strings.map(\.pitch) == [0, 45, 0, 0, 0, 0])

        let unsized = try F.parse(F.document(measures: """
        <measure number="1"><attributes><divisions>480</divisions>
        <staff-details>\(F.tuning(line: 1, "B", 0))\(F.tuning(line: 4, "G", 2))</staff-details></attributes>
        \(F.note("B", 0))</measure>
        """))
        #expect(unsized.parts[0].instrument.stringData?.strings.map(\.pitch) == [23, 0, 0, 43])
    }

    @Test("a part without <staff-tuning> keeps stringData nil")
    func noTuning() throws {
        let score = try F.parse(F.document(measures: "<measure number=\"1\">\(F.note("C", 4))</measure>"))
        #expect(score.parts[0].instrument.stringData == nil)
    }
}
