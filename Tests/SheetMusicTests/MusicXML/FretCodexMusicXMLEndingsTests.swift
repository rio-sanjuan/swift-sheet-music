import Foundation
@testable import SheetMusicCore
@testable import SheetMusicMIDI
@testable import SheetMusicMSCX
@testable import SheetMusicMusicXML
@testable import SheetMusicXMLTools
import Testing

/// FretCodex fork, delta F2 (SM-15): a MusicXML `<ending>` decodes into the volta PAIR an MSCX file holds — begin
/// side and end side — so MusicXML → `Score` → MSCX writes a volta MuseScore can pair, equal to what the
/// hand-written MSCX equivalent decodes to. F1 produced the begin side only. Fixtures are authored for the fork and
/// owned by FretCodex (see `FretCodexFixtures`).
@Suite("FretCodex F2 — MusicXML ending pairs")
struct FretCodexMusicXMLEndingsTests {
    typealias F = FretCodexFixtures

    /// Four 4/4 bars: a repeat, a first ending on bar 2, and a second ending over bars 3–4 that runs to the end of
    /// the piece (closed by `discontinue`), with a final bar line.
    static let musicXML = F.document(measures: """
    <measure number="1">
      <attributes><divisions>480</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes>
      <barline location="left"><repeat direction="forward"/></barline>
      \(F.note("C", 4, type: "whole", duration: 1920))
    </measure>
    <measure number="2">
      <barline location="left"><ending number="1" type="start">1.</ending></barline>
      \(F.note("D", 4, type: "whole", duration: 1920))
      <barline location="right"><ending number="1" type="stop"/><repeat direction="backward"/></barline>
    </measure>
    <measure number="3">
      <barline location="left"><ending number="2" type="start">2.</ending></barline>
      \(F.note("E", 4, type: "whole", duration: 1920))
    </measure>
    <measure number="4">
      \(F.note("F", 4, type: "whole", duration: 1920))
      <barline location="right"><bar-style>light-heavy</bar-style><ending number="2" type="discontinue"/></barline>
    </measure>
    """)

    /// The same four bars as MuseScore 4 writes them: each volta a begin side and an end side; the first ending's
    /// end side on bar 3's downbeat ahead of the second ending's begin side; the second ending ending on the score's
    /// last tick, so its `<next>` points into bar 4 at the bar's length and its end side follows bar 4's chord.
    static let mscx = """
    <?xml version="1.0" encoding="UTF-8"?><museScore version="4.60"><Score><Division>480</Division>
    <Part><Staff id="1"/><Instrument/></Part><Staff id="1">
    <Measure><startRepeat/><voice><TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
    <Chord><durationType>whole</durationType><Note><pitch>60</pitch><tpc>14</tpc></Note></Chord></voice></Measure>
    <Measure><voice>
    <Spanner type="Volta"><Volta><beginText>1.</beginText><endings>1</endings></Volta>\
    <next><location><measures>1</measures></location></next></Spanner>
    <Chord><durationType>whole</durationType><Note><pitch>62</pitch><tpc>16</tpc></Note></Chord></voice>\
    <endRepeat>2</endRepeat></Measure>
    <Measure><voice>
    <Spanner type="Volta"><prev><location><measures>-1</measures></location></prev></Spanner>
    <Spanner type="Volta"><Volta><beginText>2.</beginText><endings>2</endings></Volta>\
    <next><location><measures>1</measures><fractions>1/1</fractions></location></next></Spanner>
    <Chord><durationType>whole</durationType><Note><pitch>64</pitch><tpc>18</tpc></Note></Chord></voice></Measure>
    <Measure><voice>
    <Chord><durationType>whole</durationType><Note><pitch>65</pitch><tpc>13</tpc></Note></Chord>
    <Spanner type="Volta"><prev><location><measures>-1</measures><fractions>-1/1</fractions></location></prev>\
    </Spanner>
    <BarLine><subtype>end</subtype></BarLine></voice></Measure>
    </Staff></Score></museScore>
    """

    /// Each bar's first voice, as the volta sides, chords and bar lines it holds, in order.
    static func shape(_ score: Score) -> [[String]] {
        score.parts[0].staves[0].measures.map { measure in
            measure.voices[0].elements.compactMap { element -> String? in
                switch element {
                case .chord: "chord"
                case let .barLine(line): "barLine \(line.subtype ?? "-")"
                case let .spanner(spanner) where spanner.kind == .volta:
                    spanner.visible
                        ? "begin \(spanner.voltaEndings) \(spanner.nextMeasuresOffset) "
                        + "\(spanner.nextFractionsOffset.map { "\($0.numerator)/\($0.denominator)" } ?? "-")"
                        : "end \(spanner.prevMeasuresOffset) "
                        + "\(spanner.prevFractionsOffset.map { "\($0.numerator)/\($0.denominator)" } ?? "-")"
                default: nil
                }
            }
        }
    }

    static func voltas(_ score: Score) -> [[Spanner]] {
        score.parts[0].staves[0].measures.map { measure in
            measure.voices[0].elements.compactMap { element in
                if case let .spanner(spanner) = element, spanner.kind == .volta { return spanner }
                return nil
            }
        }
    }

    @Test("endings decode to the volta pairs the equivalent MSCX decodes to")
    func pairsMatchMSCX() throws {
        let fromMusicXML = try F.parse(Self.musicXML)
        let fromMSCX = try F.parseMSCX(Self.mscx)
        #expect(Self.shape(fromMusicXML) == [
            ["chord"],
            ["begin [1] 1 -", "chord"],
            ["end -1 -", "begin [2] 1 1/1", "chord"],
            ["chord", "end -1 -1/1", "barLine end"],
        ])
        #expect(Self.shape(fromMusicXML) == Self.shape(fromMSCX))
        #expect(Self.voltas(fromMusicXML) == Self.voltas(fromMSCX))
    }

    @Test("MusicXML → MSCX → decode keeps both sides of each ending and writes their <prev> location")
    func encodesPairs() throws {
        let fromMusicXML = try F.parse(Self.musicXML)
        let bytes = try MSCXEncoder.encode(fromMusicXML)
        let decoded = try MSCXParser.parse(bytes)
        let reference = try F.parseMSCX(Self.mscx)
        #expect(Self.voltas(decoded) == Self.voltas(reference))

        let staff = try #require(XMLTreeParser.parse(bytes).first("Score")?.first("Staff"))
        let prevs = staff.all("Measure").map { measure in
            (measure.first("voice")?.all("Spanner") ?? []).compactMap { spanner -> String? in
                guard let location = spanner.first("prev")?.first("location") else { return nil }
                return "\(location.first("measures")?.text ?? "-") \(location.first("fractions")?.text ?? "-")"
            }
        }
        #expect(prevs == [[], [], ["-1 -"], ["-1 -1/1"]])
    }

    @Test("an ending that runs to the end of the piece is skipped whole on the repeat")
    func finalEndingPlayback() throws {
        // |: C | D |1. E | F :|  — a first ending over the last two bars, now written as MuseScore writes a volta
        // that ends on the score's last tick (`<next>` one bar on, at that bar's length). The repeat list closes it
        // at the bar its `<next>` names, as MuseScore's `Spanner::endMeasure()` does, so the second time through
        // both bars are skipped and the piece ends after D.
        let score = try F.parse(F.document(measures: """
        <measure number="1"><attributes><divisions>480</divisions></attributes>
        <barline location="left"><repeat direction="forward"/></barline>\(F.note("C", 4, type: "whole",
        duration: 1920))</measure>
        <measure number="2">\(F.note("D", 4, type: "whole", duration: 1920))</measure>
        <measure number="3"><barline location="left"><ending number="1" type="start"/></barline>\(F.note("E", 4,
        type: "whole", duration: 1920))</measure>
        <measure number="4">\(F.note("F", 4, type: "whole", duration: 1920))
        <barline location="right"><ending number="1" type="stop"/><repeat direction="backward"/></barline></measure>
        """))
        #expect(Self.shape(score)[2] == ["begin [1] 1 1/1", "chord"])
        #expect(Self.shape(score)[3] == ["chord", "end -1 -1/1"])
        let order = RepeatUnwinder.plan(navigation: ScoreNavigation(score: score)).map(\.measureIndex)
        #expect(order == [0, 1, 2, 3, 0, 1])
    }
}
