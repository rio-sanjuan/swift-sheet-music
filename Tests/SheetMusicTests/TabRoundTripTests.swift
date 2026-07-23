import Foundation
@testable import SheetMusicCore
@testable import SheetMusicMSCX
@testable import SheetMusicXMLTools
import Testing

/// Encode → decode equality for the tablature additions, plus the
/// "non-tab output is unchanged" guarantee.
struct TabRoundTripTests {
    // MARK: - Note fret/string

    @Test func noteFretStringRoundTrips() throws {
        let note = Note(pitch: 64, tpc: 18, fret: 5, string: 1)
        let encoded = note.encode()
        let decoded = try Note.decode(encoded)
        #expect(decoded.fret == 5)
        #expect(decoded.string == 1)
    }

    @Test func fretElementOrderMatchesMuseScore() throws {
        // <fret>/<string> sit between <tpc> and <head> (TWrite Pid order).
        let note = Note(pitch: 64, tpc: 18, headType: "cross", fret: 5, string: 1)
        let names = note.encode().children.map(\.name)
        let tpcIdx = try #require(names.firstIndex(of: "tpc"))
        let fretIdx = try #require(names.firstIndex(of: "fret"))
        let stringIdx = try #require(names.firstIndex(of: "string"))
        let headIdx = try #require(names.firstIndex(of: "head"))
        #expect(tpcIdx < fretIdx)
        #expect(fretIdx < stringIdx)
        #expect(stringIdx < headIdx)
    }

    @Test func nonTabNoteEmitsNoTabElements() throws {
        let names = Note(pitch: 60, tpc: 14).encode().children.map(\.name)
        #expect(!names.contains("fret"))
        #expect(!names.contains("string"))
    }

    // MARK: - StaffType properties

    @Test func tabCommonStaffTypeRoundTrips() throws {
        let staff = Staff(
            staffType: "tab6StrCommon",
            group: "tablature",
            typeProperties: StaffTypeProperties(
                lines: 6,
                lineDistanceSp: 1.5,
                genKeysig: false,
                tab: TabStaffStyle(),
            ),
        )
        let encoded = staff.encodeDeclaration(staffID: "2")
        let decoded = Staff.declared(encoded).staff
        #expect(decoded.typeProperties == staff.typeProperties)
        #expect(decoded.staffType == "tab6StrCommon")
        #expect(decoded.group == "tablature")
    }

    @Test func tabSimpleStaffTypeRoundTrips() throws {
        let staff = Staff(
            staffType: "tab6StrSimple",
            group: "tablature",
            typeProperties: StaffTypeProperties(
                lines: 6,
                lineDistanceSp: 1.5,
                genTimesig: false,
                genKeysig: false,
                stemless: true,
                tab: TabStaffStyle(
                    showBackTied: false,
                    minimStyle: .none,
                    showRests: false,
                    showTabFingering: false,
                ),
            ),
        )
        let encoded = staff.encodeDeclaration(staffID: "2")
        let decoded = Staff.declared(encoded).staff
        #expect(decoded.typeProperties == staff.typeProperties)
    }

    @Test func upsideDownLinesThroughRoundTrip() throws {
        let staff = Staff(
            staffType: "custom",
            group: "tablature",
            typeProperties: StaffTypeProperties(
                lines: 4,
                lineDistanceSp: 1.5,
                genKeysig: false,
                tab: TabStaffStyle(
                    onLines: false,
                    linesThrough: true,
                    upsideDown: true,
                    stemsThrough: true,
                    minimStyle: .slashed,
                ),
            ),
        )
        let decoded = Staff.declared(staff.encodeDeclaration(staffID: "2")).staff
        #expect(decoded.typeProperties == staff.typeProperties)
    }

    @Test func standardStaffDeclarationIsByteStable() throws {
        // A default pitched staff must serialize exactly as before the
        // tab work: <StaffType group="pitched"><name>stdNormal</name>.
        let staff = Staff()
        let encoded = staff.encodeDeclaration(staffID: "1")
        let staffType = try #require(encoded.children.first { $0.name == "StaffType" })
        #expect(staffType.children.map(\.name) == ["name"])
        #expect(!encoded.children.contains { $0.name == "linkedTo" })
    }

    // MARK: - StringData

    @Test func stringDataRoundTrips() throws {
        let instrument = Instrument(
            id: "guitar",
            stringData: StringData(
                frets: 22,
                strings: [
                    .init(pitch: 67, open: true),
                    .init(pitch: 50), .init(pitch: 55),
                    .init(pitch: 59), .init(pitch: 62),
                ],
            ),
        )
        let decoded = try Instrument.decode(instrument.encode())
        #expect(decoded.stringData == instrument.stringData)
    }

    @Test func nonFrettedInstrumentEmitsNoStringData() throws {
        let names = Instrument(id: "piano").encode().children.map(\.name)
        #expect(!names.contains("StringData"))
    }

    // MARK: - Full linked standard+tab score

    private func makeLinkedTabScore() -> Score {
        let stdChord = Chord(duration: .quarter, notes: [Note(pitch: 64, tpc: 18)])
        let tabChord = Chord(
            duration: .quarter,
            notes: [Note(pitch: 64, tpc: 18, fret: 0, string: 0)],
        )
        let standard = Staff(
            measures: [Measure(voices: [Voice(elements: [
                .timeSignature(TimeSignature(numerator: 4, denominator: 4)),
                .chord(stdChord), .rest(duration: .quarter),
                .rest(duration: .half),
            ])])],
        )
        let tab = Staff(
            staffType: "tab6StrCommon",
            group: "tablature",
            typeProperties: StaffTypeProperties(
                lines: 6, lineDistanceSp: 1.5, genKeysig: false,
                tab: TabStaffStyle(),
            ),
            linkedToStaffOffset: 0,
            defaultClefType: "TAB",
            measures: [Measure(voices: [Voice(elements: [
                .timeSignature(TimeSignature(numerator: 4, denominator: 4)),
                .chord(tabChord), .rest(duration: .quarter),
                .rest(duration: .half),
            ])])],
        )
        let part = Part(
            id: "1",
            instrument: Instrument(
                id: "guitar",
                channels: [InstrumentChannel(program: 24)],
                stringData: StringData(
                    frets: 19,
                    strings: [40, 45, 50, 55, 59, 64].map { .init(pitch: $0) },
                ),
            ),
            staves: [standard, tab],
        )
        return Score(division: 480, parts: [part])
    }

    @Test func linkedTabScoreRoundTrips() throws {
        let original = makeLinkedTabScore()
        let encoded = try MSCXEncoder.encode(original)
        let reparsed = try MSCXParser.parse(encoded)
        let part = reparsed.parts[0]
        #expect(part.staves.count == 2)
        #expect(part.staves[1].isTablature)
        #expect(part.staves[1].linkedToStaffOffset == 0)
        #expect(part.staves[1].typeProperties == original.parts[0].staves[1].typeProperties)
        #expect(part.instrument.stringData == original.parts[0].instrument.stringData)
        // The tab note's voicing survives the trip.
        guard case let .chord(chord) = part.staves[1].measures[0].voices[0].elements[1] else {
            Issue.record("expected chord at element 1")
            return
        }
        #expect(chord.notes[0].fret == 0)
        #expect(chord.notes[0].string == 0)
        #expect(chord.notes[0].pitch == 64)
    }
}
