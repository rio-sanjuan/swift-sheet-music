import SheetMusicCore
import SheetMusicFoundation
import SheetMusicXMLTools

/// A part's `<attributes><transpose>`: the interval MusicXML ADDS to a written pitch to get the sounding one, with
/// `<octave-change>` folded into both counts. Same sign convention as `Instrument.transposeDiatonic` /
/// `transposeChromatic` (written → sounding; a guitar is `-7` / `-12`, a B♭ clarinet `-1` / `-2`).
///
/// MuseScore stores CONCERT pitch — `<pitch>` and `<tpc>` sound, `<tpc2>` is written — so the decoder runs every
/// `<pitch>` through `sounding(midi:tpc:)` and every `<key>` through `concertKey(writtenFifths:)` while a
/// transposition is in force. C++: `MusicXmlParserPass1::transpose` and `xmlSetPitch`
/// (`importmusicxmlpass1.cpp` / `importmusicxmlpass2.cpp`), which store the interval on the instrument and add its
/// chromatic part to each written pitch.
struct MusicXMLTransposition: Equatable {
    var diatonic: Int
    var chromatic: Int

    static let none = MusicXMLTransposition(diatonic: 0, chromatic: 0)

    var isNone: Bool {
        diatonic == 0 && chromatic == 0
    }

    /// Line-of-fifths shift from a WRITTEN spelling to the concert one: `7 × chromatic − 12 × diatonic`. The exact
    /// inverse of `Instrument.writtenFifthsOffset`, which the MSCX encoder adds to `<tpc>` to write `<tpc2>`, so a
    /// decoded note re-encodes to the `<tpc2>` its MusicXML spelled. An octave contributes nothing (`7·12 − 12·7`).
    var concertFifthsShift: Int {
        7 * chromatic - 12 * diatonic
    }

    /// Decode one `<transpose>`. Absent or unreadable children count as 0; a decimal (MusicXML 4 allows microtonal
    /// `<chromatic>`) is truncated toward zero, as `PitchDecoder` does for `<alter>`. `<double/>` is not modeled.
    ///
    /// A `<chromatic>` without a `<diatonic>` gets the diatonic step count of the plain interval it spans — MuseScore's
    /// `chromatic2diatonic`, applied (as there) only when the folded diatonic count is still 0.
    static func decode(_ node: XMLTreeNode) -> MusicXMLTransposition {
        func value(_ name: String) -> Int {
            node.first(name).flatMap { Double($0.text) }.map { Int($0) } ?? 0
        }
        let octaves = value("octave-change")
        var result = MusicXMLTransposition(
            diatonic: value("diatonic") + 7 * octaves,
            chromatic: value("chromatic") + 12 * octaves,
        )
        if result.diatonic == 0, result.chromatic != 0 {
            result.diatonic = diatonicSteps(spanning: result.chromatic)
        }
        return result
    }

    /// The sounding `(midi, tpc)` of a written `(midi, tpc)`: the pitch moves by `chromatic` (clamped to MIDI's
    /// `0…127`, as MuseScore does) and the spelling by `concertFifthsShift`, respelled enharmonically back into the
    /// double-flat … double-sharp range (`-1…33`) when the shift pushes it out.
    func sounding(midi: Int, tpc: Int) -> (midi: Int, tpc: Int) {
        guard !isNone else { return (midi, tpc) }
        var concertTpc = tpc + concertFifthsShift
        while concertTpc > 33 {
            concertTpc -= 12
        }
        while concertTpc < -1 {
            concertTpc += 12
        }
        return (min(127, max(0, midi + chromatic)), concertTpc)
    }

    /// The concert key of a WRITTEN `<key><fifths>`, respelled into `-7…+7` the way the MSCX side reads a written
    /// key back (`Score.respelledKey`).
    func concertKey(writtenFifths: Int) -> Int {
        isNone ? writtenFifths : Score.respelledKey(writtenFifths + concertFifthsShift)
    }

    /// Diatonic steps of the smallest interval `semitones` spans — a minor or major second is 1 step, a tritone 3, a
    /// perfect fifth 4 — with whole octaves counting 7 and the sign kept.
    private static func diatonicSteps(spanning semitones: Int) -> Int {
        let stepsBySemitone = [0, 1, 1, 2, 2, 3, 3, 4, 5, 5, 6, 6]
        let magnitude = abs(semitones)
        let steps = stepsBySemitone[magnitude % 12] + 7 * (magnitude / 12)
        return semitones < 0 ? -steps : steps
    }
}
