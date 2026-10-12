import Foundation
@testable import SheetMusicCore
@testable import SheetMusicMSCX
@testable import SheetMusicMusicXML
import Testing

/// FretCodex fork, delta F1: `<transpose>` makes a MusicXML part store CONCERT pitch, as MSCX does — `Note.pitch` /
/// `Note.tpc` sound, `Instrument.transposeDiatonic` / `transposeChromatic` carry the interval, keys are concert.
/// Fixtures are authored for the fork and owned by FretCodex (see `FretCodexFixtures`).
@Suite("FretCodex F1 — MusicXML <transpose>")
struct FretCodexMusicXMLTransposeTests {
    typealias F = FretCodexFixtures

    /// A one-staff part with `transpose` in its first `<attributes>`, written key `fifths`, holding `notes`.
    static func part(transpose: String, fifths: Int = 0, notes: String) -> String {
        F.document(measures: """
        <measure number="1"><attributes><divisions>480</divisions><key><fifths>\(fifths)</fifths></key>
        <time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>G</sign><line>2</line></clef>
        <transpose>\(transpose)</transpose></attributes>\(notes)</measure>
        """)
    }

    @Test("a guitar written an octave up (<octave-change>-1) stores the sounding octave and a -7 / -12 instrument")
    func guitarOctave() throws {
        let score = try F.parse(Self.part(
            transpose: "<diatonic>0</diatonic><chromatic>0</chromatic><octave-change>-1</octave-change>",
            notes: F.note("E", 3) + F.note("G", 3, alter: 1) + F.note("B", 4, alter: -1),
        ))
        #expect(F.notes(score).map(\.pitch) == [40, 44, 58])
        #expect(F.notes(score).map(\.tpc) == [18, 22, 12]) // an octave leaves the spelling alone
        #expect(score.parts[0].instrument.transposeDiatonic == -7)
        #expect(score.parts[0].instrument.transposeChromatic == -12)
    }

    @Test("a B♭ clarinet: written E4 in D major is concert D4 in C major, and re-encodes to the written tpc2")
    func bFlatClarinet() throws {
        let score = try F.parse(Self.part(
            transpose: "<diatonic>-1</diatonic><chromatic>-2</chromatic>", fifths: 2,
            notes: F.note("E", 4) + F.note("F", 4, alter: 1),
        ))
        #expect(F.notes(score).map(\.pitch) == [62, 64])
        #expect(F.notes(score).map(\.tpc) == [16, 18]) // D, E
        let key = F.elements(score).compactMap { element -> KeySignature? in
            if case let .keySignature(key) = element { return key }
            return nil
        }
        #expect(key.map(\.concertKey) == [0]) // emitted: the written key is D even though the concert key is C
        let mscx = try #require(String(data: MSCXEncoder.encode(score), encoding: .utf8))
        #expect(mscx.contains("<tpc2>18</tpc2>")) // written E
        #expect(mscx.contains("<actualKey>2</actualKey>"))
        let roundTripped = try MSCXParser.parse(MSCXEncoder.encode(score))
        #expect(F.notes(roundTripped).map { [$0.pitch, $0.tpc] } == F.notes(score).map { [$0.pitch, $0.tpc] })
    }

    @Test("a written C major on a B♭ part is concert B♭ major, and is not dropped as an empty key")
    func writtenCMajorOnBFlatPart() throws {
        let score = try F.parse(Self.part(
            transpose: "<diatonic>-1</diatonic><chromatic>-2</chromatic>", notes: F.note("C", 5),
        ))
        let keys = F.elements(score).compactMap { element -> Int? in
            if case let .keySignature(key) = element { return key.concertKey }
            return nil
        }
        #expect(keys == [-2])
        #expect(F.notes(score).map(\.tpc) == [12]) // B♭
    }

    @Test("<chromatic> alone gets MuseScore's diatonic step count")
    func chromaticOnly() throws {
        let score = try F.parse(Self.part(transpose: "<chromatic>-2</chromatic>", notes: F.note("D", 4)))
        #expect(score.parts[0].instrument.transposeDiatonic == -1)
        #expect(score.parts[0].instrument.transposeChromatic == -2)
        #expect(F.notes(score).map(\.tpc) == [14]) // written D sounds C, not B♯
    }

    @Test("a part without <transpose> keeps written pitch and a concert-pitch instrument")
    func noTranspose() throws {
        let score = try F.parse(F.document(measures: "<measure number=\"1\">\(F.note("E", 3))</measure>"))
        #expect(F.notes(score).map(\.pitch) == [52])
        #expect(!score.parts[0].instrument.isTransposing)
    }

    @Test("a later <transpose> applies to the notes after it; the instrument keeps the opening one")
    func midPartChange() throws {
        let score = try F.parse(F.document(measures: """
        <measure number="1"><attributes><divisions>480</divisions>
        <transpose><diatonic>0</diatonic><chromatic>0</chromatic><octave-change>-1</octave-change></transpose>
        </attributes>\(F.note("E", 3))</measure>
        <measure number="2"><attributes><transpose><diatonic>0</diatonic><chromatic>0</chromatic></transpose>
        </attributes>\(F.note("E", 3))</measure>
        """))
        #expect(F.notes(score).map(\.pitch) == [40, 52])
        #expect(score.parts[0].instrument.transposeChromatic == -12)
    }
}
