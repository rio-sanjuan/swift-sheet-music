import SheetMusicCore
import SheetMusicFoundation
import SheetMusicXMLTools

/// The fretted-instrument parts of `<attributes><staff-details>`: `<staff-tuning>` becomes the part's `StringData`
/// and `<capo>` a `.capo` voice element. (`<staff-lines>` is `AttributesDecoder.decodeStaffLines`'s.) C++:
/// `MusicXmlParserPass2::staffDetails` / `staffTuning` (`importmusicxmlpass2.cpp`).
///
/// `number` selects the staff as `decodeStaffLines` does: absent means staff 1, out of range falls back to staff 1.
enum MusicXMLStaffDetailsDecoder {
    /// Record each staff's tuning into `previous.stringDataByStaff` and return the capo emissions.
    static func decode(
        _ node: XMLTreeNode,
        previous: inout MusicXMLAttributesSnapshot,
        staffCount: Int,
    ) -> [AttributesDecoder.Emission] {
        var output: [AttributesDecoder.Emission] = []
        for details in node.all("staff-details") {
            let number = details.attributes["number"].flatMap { Int($0) } ?? 1
            let staffIndex = (1 ... max(1, staffCount)).contains(number) ? number - 1 : 0
            if previous.stringDataByStaff[staffIndex] == nil,
               let tuning = stringData(details, lineCount: previous.lineCountByStaff[staffIndex])
            {
                previous.stringDataByStaff[staffIndex] = tuning
            }
            if let fret = details.first("capo").flatMap({ Int($0.text) }), fret >= 0,
               previous.capoByStaff[staffIndex] != fret
            {
                previous.capoByStaff[staffIndex] = fret
                output.append(AttributesDecoder.Emission(staffIndex: staffIndex, element: .capo(capo(atFret: fret))))
            }
        }
        return output
    }

    /// The tuning one `<staff-details>` spells, or `nil` when it has no readable `<staff-tuning>`.
    ///
    /// **Order.** `<staff-tuning line="1">` is the BOTTOM line of the staff, the lowest string, and
    /// `StringData.strings` is listed low → high, so line `L` is `strings[L − 1]` — MuseScore's own mapping.
    /// `Note.string` then counts from the other end: string `s` is tuned to `strings[count − 1 − s]`.
    ///
    /// **Size.** One string per staff line (`lineCount`, from `<staff-lines>`), or — when the staff never said — as
    /// many as the highest tuned line. A line without a `<staff-tuning>` is pitch 0, the placeholder MuseScore and the
    /// MSCX decoder both use, since the list is positional; a `line` outside the staff is ignored.
    ///
    /// **Pitches are as written** in `<staff-tuning>`; `<transpose>` is not applied. MuseScore's exporter writes the
    /// sounding tuning (E2 … E4 for a guitar) — the same concert pitches an MSCX `<StringData>` holds.
    ///
    /// **Spelling.** A string tuned with a negative `<tuning-alter>` is `useFlat`, so an E♭ tuning stays E♭ A♭ D♭ G♭
    /// B♭ E♭ rather than reading back as sharps; MuseScore's importer leaves `useFlat` unset.
    ///
    /// **Frets** are 25, MuseScore's value when the instrument brings no fret count of its own: MusicXML has no element
    /// for it.
    static func stringData(_ details: XMLTreeNode, lineCount: Int?) -> StringData? {
        var tuned: [Int: InstrumentString] = [:]
        for tuning in details.all("staff-tuning") {
            guard let line = tuning.attributes["line"].flatMap({ Int($0) }), line >= 1,
                  let step = tuning.first("tuning-step")?.text,
                  let octave = tuning.first("tuning-octave").flatMap({ Int($0.text) })
            else { continue }
            let alter = tuning.first("tuning-alter").flatMap { Double($0.text) }.map { Int($0) } ?? 0
            guard let pitch = PitchDecoder.midi(step: step, alter: alter, octave: octave),
                  (0 ... 127).contains(pitch)
            else { continue }
            tuned[line] = InstrumentString(pitch: pitch, useFlat: alter < 0)
        }
        guard let highestLine = tuned.keys.max() else { return nil }
        let count = lineCount ?? highestLine
        let strings = (1 ... count).map { tuned[$0] ?? InstrumentString(pitch: 0) }
        return StringData(frets: 25, strings: strings)
    }

    /// A capo at `fret`, with the text MuseScore generates for it (`Capo::generateText`): "Capo N", or "No capo" for
    /// fret 0. Pitches are not touched — see `FRETCODEX.md` for how this differs from an MSCX capo.
    private static func capo(atFret fret: Int) -> Capo {
        Capo(fretPosition: fret, text: fret > 0 ? "Capo \(fret)" : "No capo")
    }
}
