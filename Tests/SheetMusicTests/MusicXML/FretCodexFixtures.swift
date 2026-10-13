import Foundation
@testable import SheetMusicCore
@testable import SheetMusicMSCX
@testable import SheetMusicMusicXML

/// Builders and readers for the FretCodex fork's tests (deltas F1 and F2, `FRETCODEX.md`).
///
/// **Provenance.** Every MusicXML and MSCX snippet in the `FretCodex*Tests` files — under `MusicXML/` and `MSCX/` —
/// is authored for this fork and owned by FretCodex. None is copied or derived from `Tests/SheetMusicTests/Resources/`
/// (MuseScore's GPL-3.0 fixtures).
enum FretCodexFixtures {
    /// A `<score-partwise>` document of the given `<score-part>` / `<part>` pairs.
    static func document(_ parts: [(id: String, name: String, measures: String)]) -> String {
        let scoreParts = parts.map { part in
            "<score-part id=\"\(part.id)\"><part-name>\(part.name)</part-name></score-part>"
        }.joined()
        let bodies = parts.map { "<part id=\"\($0.id)\">\($0.measures)</part>" }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0">
          <part-list>\(scoreParts)</part-list>
          \(bodies)
        </score-partwise>
        """
    }

    /// One part, `P1` named "Guitar".
    static func document(measures: String) -> String {
        document([(id: "P1", name: "Guitar", measures: measures)])
    }

    static func parse(_ xml: String) throws -> Score {
        try MusicXMLParser.parse(Data(xml.utf8))
    }

    static func parseMSCX(_ xml: String) throws -> Score {
        try MSCXParser.parse(Data(xml.utf8))
    }

    /// A `<note>` at 480 divisions per quarter. `technical` is the `<technical>` body.
    static func note(
        _ step: String, _ octave: Int, alter: Int = 0,
        type: String = "quarter", dotted: Bool = false, duration: Int = 480,
        voice: Int = 1, staff: Int? = nil, chord: Bool = false,
        technical: String? = nil,
    ) -> String {
        let alterXML = alter == 0 ? "" : "<alter>\(alter)</alter>"
        let dotXML = dotted ? "<dot/>" : ""
        let staffXML = staff.map { "<staff>\($0)</staff>" } ?? ""
        let technicalXML = technical.map { "<notations><technical>\($0)</technical></notations>" } ?? ""
        return """
        <note>\(chord ? "<chord/>" : "")<pitch><step>\(step)</step>\(alterXML)<octave>\(octave)</octave></pitch>\
        <duration>\(duration)</duration><voice>\(voice)</voice><type>\(type)</type>\(dotXML)\
        \(staffXML)\(technicalXML)</note>
        """
    }

    /// `<technical>` body for MusicXML string `string` (1 = highest), fret `fret`.
    static func tab(string: Int, fret: Int) -> String {
        "<string>\(string)</string><fret>\(fret)</fret>"
    }

    /// `<staff-tuning>` for `line` (1 = bottom line, lowest string).
    static func tuning(line: Int, _ step: String, _ octave: Int, alter: Int = 0) -> String {
        let alterXML = alter == 0 ? "" : "<tuning-alter>\(alter)</tuning-alter>"
        return """
        <staff-tuning line="\(line)"><tuning-step>\(step)</tuning-step>\(alterXML)\
        <tuning-octave>\(octave)</tuning-octave></staff-tuning>
        """
    }

    /// Standard guitar tuning, lines 1–6 = E2 A2 D3 G3 B3 E4.
    static let standardTuning = [("E", 2), ("A", 2), ("D", 3), ("G", 3), ("B", 3), ("E", 4)]
        .enumerated()
        .map { tuning(line: $0.offset + 1, $0.element.0, $0.element.1) }
        .joined()

    /// Every chord's notes on one staff, measure by measure, in voice order.
    static func notes(_ score: Score, part: Int = 0, staff: Int = 0) -> [Note] {
        score.parts[part].staves[staff].measures.flatMap { measure in
            measure.voices.flatMap { voice in
                voice.elements.flatMap { element -> [Note] in
                    if case let .chord(chord) = element { return Array(chord.notes) }
                    return []
                }
            }
        }
    }

    /// The voice elements of one measure's first voice.
    static func elements(_ score: Score, part: Int = 0, staff: Int = 0, measure: Int = 0) -> [VoiceElement] {
        Array(score.parts[part].staves[staff].measures[measure].voices[0].elements)
    }

    /// The first clef in a staff's first measure.
    static func firstClef(_ score: Score, part: Int = 0, staff: Int = 0) -> Clef? {
        for element in elements(score, part: part, staff: staff) {
            if case let .clef(clef) = element { return clef }
        }
        return nil
    }
}
