import Foundation
@testable import SheetMusicCore
@testable import SheetMusicMSCX

/// Pieces written for the bar repair's tests (F4): one staff of the values, chords, dots, ledger
/// notes, triplets and two-voice bars the repair reads. **Provenance:** authored for this fork and
/// owned by FretCodex, like `FretCodexFixtures`; nothing here comes from `Resources/`.
enum FretCodexBarRepairFixtures {
    /// A natural (or sharp) note's MuseScore tonal pitch class.
    static func tpc(_ midi: Int) -> Int {
        [14, 21, 16, 23, 18, 13, 20, 15, 22, 17, 24, 19][midi % 12]
    }

    static func chord(_ pitches: [Int], _ type: String, dots: Int = 0) -> String {
        let notes = pitches.map { "<Note><pitch>\($0)</pitch><tpc>\(tpc($0))</tpc></Note>" }.joined()
        let dotsXML = dots > 0 ? "<dots>\(dots)</dots>" : ""
        return "<Chord>\(dotsXML)<durationType>\(type)</durationType>\(notes)</Chord>"
    }

    static func rest(_ type: String) -> String {
        "<Rest><durationType>\(type)</durationType></Rest>"
    }

    static func measureRest(_ n: Int, _ d: Int) -> String {
        "<Rest><durationType>measure</durationType><duration>\(n)/\(d)</duration></Rest>"
    }

    static func tuplet(_ chords: [String], base: String, actual: Int = 3, normal: Int = 2) -> String {
        "<Tuplet><normalNotes>\(normal)</normalNotes><actualNotes>\(actual)</actualNotes><baseNote>\(base)</baseNote></Tuplet>"
            + chords.joined() + "<endTuplet/>"
    }

    /// A one-staff score; each measure is its voices' contents.
    static func score(_ measures: [[String]], time: (Int, Int) = (4, 4), clef: String? = nil) throws -> Score {
        var body = ""
        for (i, voices) in measures.enumerated() {
            body += "<Measure>"
            for (v, content) in voices.enumerated() {
                var lead = ""
                if i == 0, v == 0 {
                    if let clef { lead += "<Clef><concertClefType>\(clef)</concertClefType><transposingClefType>\(clef)</transposingClefType></Clef>" }
                    lead += "<TimeSig><sigN>\(time.0)</sigN><sigD>\(time.1)</sigD></TimeSig>"
                }
                body += "<voice>\(lead)\(content)</voice>"
            }
            body += "</Measure>"
        }
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <museScore version="4.60"><Score><Division>480</Division>
        <Part id="1"><Staff id="1"><StaffType group="pitched"><name>stdNormal</name></StaffType></Staff>
        <trackName>Piano</trackName><Instrument id="piano"><longName>Piano</longName><trackName>Piano</trackName>
        <instrumentId>keyboard.piano</instrumentId></Instrument></Part>
        <Staff id="1">\(body)</Staff></Score></museScore>
        """
        return try MSCXParser.parse(Data(xml.utf8))
    }

    /// Twelve bars of 4/4 in the treble clef.
    static func study() throws -> Score {
        func c(_ p: [Int], _ t: String, dots: Int = 0) -> String { chord(p, t, dots: dots) }
        func r(_ t: String) -> String { rest(t) }
        return try score([
            [c([72], "quarter") + c([74], "eighth") + c([76], "eighth") + c([77], "quarter", dots: 1) + c([79], "eighth")],
            [c([69], "16th") + c([71], "16th") + c([72], "16th") + c([74], "16th") + c([76], "half") + r("quarter")],
            [c([60, 64, 67], "quarter") + c([62, 64], "quarter") + c([65, 69, 72], "half")],
            [tuplet([c([76], "eighth"), c([77], "eighth"), c([79], "eighth")], base: "eighth") + c([81], "quarter") + c([71], "half")],
            [c([93], "quarter") + c([98], "quarter") + c([96], "quarter") + c([95], "quarter")],
            [c([72], "whole")],
            [c([67], "half", dots: 1) + c([69], "quarter")],
            [c([76], "half") + c([74], "half"), c([60], "quarter") + c([62], "quarter") + c([64], "half")],
            [c([72], "eighth") + c([74], "eighth") + c([76], "eighth") + c([77], "eighth") + c([79], "quarter", dots: 1) + c([81], "eighth")],
            [c([72, 76], "quarter", dots: 1) + c([74], "eighth") + r("half")],
            [c([72], "eighth", dots: 1) + c([74], "16th") + c([76], "quarter") + c([77], "half")],
            [measureRest(4, 4)],
        ])
    }

    /// Eight bars of 2/4 with triplets on the beat.
    static func triplets() throws -> Score {
        func c(_ p: [Int], _ t: String, dots: Int = 0) -> String { chord(p, t, dots: dots) }
        let t = { (p: [Int]) in tuplet(p.map { c([$0], "eighth") }, base: "eighth") }
        return try score([
            [t([72, 74, 76]) + c([77], "quarter")],
            [c([79], "quarter") + t([81, 79, 77])],
            [c([76], "eighth") + c([74], "eighth") + c([72], "quarter")],
            [t([71, 72, 74]) + t([76, 77, 79])],
            [c([81], "half")],
            [c([79], "eighth") + c([77], "eighth") + c([76], "eighth") + c([74], "eighth")],
            [t([72, 71, 69]) + c([67], "quarter")],
            [c([72], "half")],
        ], time: (2, 4))
    }
}

/// A small deterministic generator, for the property and shuffle tests.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
