import Foundation
@testable import SheetMusicCore
@testable import SheetMusicMSCX
@testable import SheetMusicXMLTools
import Testing

/// FretCodex fork, delta F2 (SM-4): a voice-level spanner's end side keeps its `<prev><location>` through a
/// decode → encode round trip, so MuseScore can pair it with its begin side again. It used to come back as a bare
/// `<prev/>`, which MuseScore never pairs: the volta (or hairpin, ottava, …) was dropped on load. The fixture is
/// written for the fork in the shape MuseScore 4 writes and is owned by FretCodex (see `FretCodexFixtures`).
@Suite("FretCodex F2 — MSCX volta end sides")
struct FretCodexMSCXVoltaTests {
    /// Four 4/4 bars: a repeat whose first ending is bar 2 and whose second ending is bar 3 — the score's last
    /// bar, so its end side sits after the last chord with `<fractions>-1/1</fractions>`, as MuseScore writes a
    /// spanner ending on the score's final tick. Bar 1 carries a hairpin ending half-way through bar 2.
    static let endings = """
    <?xml version="1.0" encoding="UTF-8"?><museScore version="4.60"><Score><Division>480</Division>
    <Part><Staff id="1"/><Instrument/></Part><Staff id="1">
    <Measure><startRepeat/><voice><TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
    <Chord><durationType>whole</durationType><Note><pitch>60</pitch><tpc>14</tpc></Note></Chord></voice></Measure>
    <Measure><voice>
    <Spanner type="HairPin"><HairPin><subtype>0</subtype></HairPin>\
    <next><location><measures>1</measures><fractions>1/2</fractions></location></next></Spanner>
    <Spanner type="Volta"><Volta><beginText>1.</beginText><endings>1</endings></Volta>\
    <next><location><measures>1</measures></location></next></Spanner>
    <Chord><durationType>whole</durationType><Note><pitch>62</pitch><tpc>16</tpc></Note></Chord></voice>\
    <endRepeat>2</endRepeat></Measure>
    <Measure><voice>
    <Spanner type="Volta"><prev><location><measures>-1</measures></location></prev></Spanner>
    <Spanner type="Volta"><Volta><beginText>2.</beginText><endings>2</endings></Volta>\
    <next><location><fractions>1/1</fractions></location></next></Spanner>
    <Chord><durationType>half</durationType><Note><pitch>64</pitch><tpc>18</tpc></Note></Chord>
    <Spanner type="HairPin"><prev><location><measures>-1</measures><fractions>-1/2</fractions></location></prev>\
    </Spanner>
    <Chord><durationType>half</durationType><Note><pitch>65</pitch><tpc>13</tpc></Note></Chord>
    <Spanner type="Volta"><prev><location><fractions>-1/1</fractions></location></prev></Spanner>
    </voice></Measure>
    </Staff></Score></museScore>
    """

    /// The `<Spanner>` nodes in each measure's first voice, in order.
    static func spannerNodes(_ bytes: Data) throws -> [[XMLTreeNode]] {
        let staff = try #require(XMLTreeParser.parse(bytes).first("Score")?.first("Staff"))
        return staff.all("Measure").map { measure in
            measure.first("voice")?.all("Spanner") ?? []
        }
    }

    static func isEndSide(_ node: XMLTreeNode) -> Bool {
        node.children.contains { $0.name == "prev" }
    }

    /// The end sides — `<Spanner>`s holding a `<prev>` — and their location, as `type measures fractions`.
    static func endSides(_ bytes: Data) throws -> [[String]] {
        try spannerNodes(bytes).map { nodes in
            nodes.compactMap { node in
                guard let prev = node.first("prev") else { return nil }
                let location = prev.first("location")
                return [
                    node.attributes["type"] ?? "?",
                    location?.first("measures")?.text ?? "-",
                    location?.first("fractions")?.text ?? "-",
                ].joined(separator: " ")
            }
        }
    }

    static func spanners(_ score: Score) -> [[Spanner]] {
        score.parts[0].staves[0].measures.map { measure in
            measure.voices[0].elements.compactMap { element in
                if case let .spanner(spanner) = element { return spanner }
                return nil
            }
        }
    }

    static func voiceElements(_ score: Score) -> [[[VoiceElement]]] {
        score.parts[0].staves[0].measures.map { $0.voices.map(\.elements.values) }
    }

    @Test("an end side's <prev> location is decoded")
    func decodesEndSides() throws {
        let score = try FretCodexFixtures.parseMSCX(Self.endings)
        let ends = Self.spanners(score).map { $0.filter { !$0.visible } }
        #expect(ends.map { $0.map(\.prevMeasuresOffset) } == [[], [], [-1, -1, 0]])
        #expect(ends.map { $0.map(\.prevFractionsOffset) } == [
            [], [], [nil, Fraction(numerator: -1, denominator: 2), Fraction(numerator: -1, denominator: 1)],
        ])
        #expect(ends[2].map(\.kind) == [.volta, .hairpin, .volta])
        // Begin sides have no `<prev>`.
        let begins = Self.spanners(score).flatMap { $0.filter(\.visible) }
        #expect(begins.count == 3)
        #expect(begins.allSatisfy { $0.prevMeasuresOffset == 0 && $0.prevFractionsOffset == nil })
    }

    @Test("decode → encode → decode keeps both sides of each ending and their <location>")
    func roundTrip() throws {
        let source = Data(Self.endings.utf8)
        let decoded = try MSCXParser.parse(source)
        let encoded = try MSCXEncoder.encode(decoded)
        let again = try MSCXParser.parse(encoded)
        #expect(Self.spanners(again) == Self.spanners(decoded))
        #expect(Self.voiceElements(again) == Self.voiceElements(decoded))

        // The encoded file carries the end sides' <prev><location> exactly as the source spelled them.
        #expect(try Self.endSides(encoded) == [
            [], [], ["Volta -1 -", "HairPin -1 -1/2", "Volta - -1/1"],
        ])
        #expect(try Self.endSides(encoded) == Self.endSides(source))
        let sourceEnds = try Self.spannerNodes(source).map { $0.filter(Self.isEndSide) }
        let encodedEnds = try Self.spannerNodes(encoded).map { $0.filter(Self.isEndSide) }
        #expect(encodedEnds == sourceEnds)
        // And a second pass writes the same bytes.
        #expect(try MSCXEncoder.encode(again) == encoded)
    }

    @Test("an end side built in code writes the same <Spanner> as a preserved-markup end side, and only once")
    func builtEndSideMatchesPreservedWorkaround() throws {
        func score(endSide: VoiceElement) -> Score {
            let chord = VoiceElement.chord(Chord(duration: .whole, notes: ChordNotes([Note(pitch: 60, tpc: 14)])))
            let begin = Spanner(
                kind: .volta, rawType: "Volta", nextMeasuresOffset: 1, voltaEndings: [1], beginText: "1.",
            )
            let staff = Staff(
                staffType: "stdNormal", group: "pitched", defaultClefType: nil,
                measures: [
                    Measure(voices: [Voice(elements: [.spanner(begin), chord])]),
                    Measure(voices: [Voice(elements: [endSide, chord])]),
                ],
            )
            return Score(division: 480, parts: [
                Part(id: "1", trackName: "Guitar", instrument: Instrument(id: "guitar"), staves: [staff]),
            ])
        }
        let built = try MSCXEncoder.encode(score(endSide: .spanner(Spanner(
            kind: .volta, rawType: "Volta", prevMeasuresOffset: -1, visible: false,
        ))))
        let preserved = try MSCXEncoder.encode(score(endSide: .preserved(PreservedXML(
            name: "Spanner", attributes: ["type": "Volta"],
            children: [PreservedXML(name: "prev", children: [PreservedXML(name: "location", children: [
                PreservedXML(name: "measures", text: "-1"),
            ])])],
        ))))
        #expect(try Self.endSides(built) == [[], ["Volta -1 -"]])
        #expect(try Self.endSides(preserved) == [[], ["Volta -1 -"]])
        #expect(try Self.spannerNodes(built) == Self.spannerNodes(preserved))
        // Both read back as the same modeled end side.
        #expect(try Self.spanners(MSCXParser.parse(built)) == Self.spanners(MSCXParser.parse(preserved)))
    }

    @Test("an end side with no location still writes the bare <prev/>")
    func bareEndSide() throws {
        let node = Spanner(kind: .volta, rawType: "Volta", visible: false).encode()
        #expect(node == XMLTreeNode(name: "Spanner", attributes: ["type": "Volta"], children: [
            XMLTreeNode(name: "prev"),
        ]))
    }
}
