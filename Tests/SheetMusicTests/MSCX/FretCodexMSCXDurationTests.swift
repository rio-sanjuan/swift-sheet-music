import Foundation
@testable import SheetMusicCore
@testable import SheetMusicMSCX
@testable import SheetMusicXMLTools
import Testing

/// FretCodex fork, delta F2: what the MSCX encoder writes for a chord's duration. A `<Chord>` has exactly one
/// spelling — a note value with up to MuseScore's four dots — so the encoder writes that or refuses; it never writes
/// a chord its own decoder (or MuseScore) rejects, which used to make the whole file unreadable (SM-2), and a
/// whole-bar `.measure` chord is written as its bar's note value instead of trapping (SM-1). Scores are built in
/// code; nothing here comes from `Tests/SheetMusicTests/Resources/` (see `FretCodexFixtures`).
@Suite("FretCodex F2 — MSCX chord durations")
struct FretCodexMSCXDurationTests {
    /// One part, one staff, one bar of `measureLength` holding `elements`.
    static func score(_ elements: [VoiceElement], measureLength: Fraction? = nil) -> Score {
        let staff = Staff(
            staffType: "stdNormal", group: "pitched", defaultClefType: nil,
            measures: [Measure(voices: [Voice(elements: elements)], actualLength: measureLength)],
        )
        return Score(division: 480, parts: [
            Part(id: "1", trackName: "Guitar", instrument: Instrument(id: "guitar"), staves: [staff]),
        ])
    }

    static func chord(_ duration: NoteDuration, graces: [GraceChord] = []) -> VoiceElement {
        .chord(Chord(duration: duration, notes: ChordNotes([Note(pitch: 60, tpc: 14)]), graceNotesBefore: graces))
    }

    static func firstChord(_ score: Score) -> Chord? {
        for element in score.parts[0].staves[0].measures[0].voices[0].elements {
            if case let .chord(chord) = element { return chord }
        }
        return nil
    }

    /// The fault code an encode threw, or `nil` when it did not throw.
    static func faultCode(encoding score: Score) -> String? {
        do {
            _ = try MSCXEncoder.encode(score)
            return nil
        } catch let SheetMusicError.malformedScore(fault) {
            return fault.code
        } catch {
            return "\(error)"
        }
    }

    /// Whether `length` is `base · (2 − 2⁻ᵈ)` for a base from a whole to a 256th and `d` ≤ 4 — worked out here
    /// from the definition, not from the encoder's own search.
    static func isNoteValueWithAtMostFourDots(_ length: Fraction) -> Bool {
        for exponent in 0 ... 8 {
            for dots in 0 ... 4 {
                let value = Fraction(numerator: (1 << (dots + 1)) - 1, denominator: 1 << (exponent + dots))
                if value == length { return true }
            }
        }
        return false
    }

    // MARK: - SM-1: a whole-bar chord

    @Test("a whole-bar chord is written as its bar's note value and reads back as that value")
    func wholeBarChord() throws {
        let cases: [(bar: Fraction, written: String, dots: String?)] = [
            (Fraction(numerator: 4, denominator: 4), "whole", nil),
            (Fraction(numerator: 3, denominator: 4), "half", "1"),
            (Fraction(numerator: 7, denominator: 8), "half", "2"),
            (Fraction(numerator: 1, denominator: 4), "quarter", nil), // a one-beat pickup
        ]
        for (bar, written, dots) in cases {
            let bytes = try MSCXEncoder.encode(Self.score([Self.chord(.measure)], measureLength: bar))
            let chord = try #require(XMLTreeParser.parse(bytes).first("Score")?.first("Staff")?.first("Measure")?
                .first("voice")?.first("Chord"), "\(bar)")
            #expect(chord.first("durationType")?.text == written, "\(bar)")
            #expect(chord.first("dots")?.text == dots, "\(bar)")
            #expect(chord.all("duration").isEmpty, "\(bar)")
            let decoded = try MSCXParser.parse(bytes)
            #expect(Self.firstChord(decoded)?.duration == NoteDuration.measure.resolved(in: bar), "\(bar)")
            #expect(Self.firstChord(decoded)?.notes.map(\.pitch) == [60], "\(bar)")
        }
    }

    @Test("a whole-bar chord in a bar no single note value fills throws instead of trapping")
    func wholeBarChordWithoutANoteValue() {
        #expect(Self.faultCode(encoding: Self.score(
            [Self.chord(.measure)], measureLength: Fraction(numerator: 5, denominator: 4),
        )) == "mscx.encoder.chordDurationNotRepresentable")
    }

    @Test("a whole-bar chord tied into the next bar keeps the tie")
    func wholeBarChordTie() throws {
        let staff = Staff(
            staffType: "stdNormal", group: "pitched", defaultClefType: nil,
            measures: [
                Measure(voices: [Voice(elements: [.chord(Chord(
                    duration: .measure, notes: ChordNotes([Note(pitch: 60, tpc: 14, tieForward: 1)]),
                ))])], actualLength: Fraction(numerator: 3, denominator: 4)),
                Measure(voices: [Voice(elements: [.chord(Chord(
                    duration: .half, notes: ChordNotes([Note(pitch: 60, tpc: 14, tieBack: 1)]),
                ))])], actualLength: Fraction(numerator: 3, denominator: 4)),
            ],
        )
        let score = Score(division: 480, parts: [
            Part(id: "1", trackName: "Guitar", instrument: Instrument(id: "guitar"), staves: [staff]),
        ])
        let decoded = try MSCXParser.parse(MSCXEncoder.encode(score))
        let notes = decoded.parts[0].staves[0].measures.compactMap { measure -> Note? in
            guard case let .chord(chord) = measure.voices[0].elements.values.first else { return nil }
            return chord.notes.first
        }
        #expect(notes.map { $0.tieForward != nil } == [true, false])
        #expect(notes.map { $0.tieBack != nil } == [false, true])
    }

    // MARK: - SM-2: dots

    @Test("a four-dot chord writes <dots>4</dots> and reads back")
    func fourDots() throws {
        let duration = NoteDuration.half.dotted(4) // 31/32
        let bytes = try MSCXEncoder.encode(Self.score([Self.chord(duration)]))
        let xml = try #require(String(bytes: bytes, encoding: .utf8))
        #expect(xml.contains("<dots>4</dots>"))
        #expect(xml.contains("<durationType>half</durationType>"))
        #expect(!xml.contains("<durationType>measure</durationType>"))
        let decoded = try MSCXParser.parse(bytes)
        #expect(Self.firstChord(decoded)?.duration == duration)
    }

    @Test("a four-dot rest keeps its length instead of becoming a measure rest")
    func fourDotRest() throws {
        let duration = NoteDuration.quarter.dotted(4)
        let bytes = try MSCXEncoder.encode(Self.score([.rest(duration: duration)]))
        let decoded = try MSCXParser.parse(bytes)
        #expect(Self.firstChord(decoded)?.duration == duration)
    }

    @Test("a chord or grace needing five dots, or no note value at all, throws instead of writing an unreadable file")
    func unrepresentableThrows() {
        let code = "mscx.encoder.chordDurationNotRepresentable"
        #expect(Self.faultCode(encoding: Self.score([Self.chord(.half.dotted(5))])) == code)
        #expect(Self.faultCode(encoding: Self.score([Self.chord(.fraction(Fraction(numerator: 5, denominator: 64)))]))
            == code)
        let grace = GraceChord(
            graceType: .acciaccatura, duration: .eighth.dotted(5), notes: ChordNotes([Note(pitch: 62, tpc: 16)]),
        )
        #expect(Self.faultCode(encoding: Self.score([Self.chord(.quarter, graces: [grace])])) == code)
    }

    @Test("every fraction a chord or grace encodes with decodes back to the same length; the rest throw")
    func everyAcceptedFractionRoundTrips() throws {
        var accepted = 0
        for exponent in 0 ... 12 {
            let denominator = 1 << exponent
            for numerator in stride(from: 1, to: 2 * denominator, by: 2) {
                let length = Fraction(numerator: numerator, denominator: denominator)
                let expected = Self.isNoteValueWithAtMostFourDots(length)
                for asGrace in [false, true] {
                    let voice = asGrace
                        ? Voice(elements: [Self.chord(.quarter, graces: [GraceChord(
                            graceType: .appoggiatura, duration: .fraction(length),
                            notes: ChordNotes([Note(pitch: 62, tpc: 16)]),
                        )])])
                        : Voice(elements: [Self.chord(.fraction(length))])
                    guard let node = try? voice.encode() else {
                        #expect(!expected, "\(length) refused, but it is a note value")
                        continue
                    }
                    #expect(expected, "\(length) encoded, but it is not a note value")
                    let bytes = XMLTreeSerializer.serialize(XMLTreeNode(name: "root", children: [node]))
                    let decoded = try Voice.decode(#require(try XMLTreeParser.parse(bytes).first("voice")))
                    guard case let .chord(chord) = try #require(decoded.elements.values.first) else {
                        Issue.record("\(length): no chord decoded")
                        continue
                    }
                    let written = asGrace ? chord.graceNotesBefore.values.first?.duration : chord.duration
                    #expect(written?.asFraction == length, "\(length) decoded as \(String(describing: written))")
                    accepted += 1
                }
            }
        }
        // 9 bases × 5 dot counts, as chords and as graces.
        #expect(accepted == 2 * 9 * 5)
    }
}
