import SheetMusicCore
import SheetMusicFoundation
import SheetMusicXMLTools

extension MusicXMLNoteDecoder {
    /// A note's `<notations><technical><string>` / `<fret>` as `Note.string` / `Note.fret`.
    ///
    /// **String numbering.** MusicXML numbers strings from 1 at the HIGHEST string; `Note.string` is MuseScore's
    /// 0-based index from the highest string (the top tab line), so `string = n − 1`. Frets are kept as written. C++:
    /// `MusicXmlParserNotations::addTechnical` (`importmusicxmlpass2.cpp`), which does the same subtraction.
    ///
    /// **Every staff, not only TAB.** MuseScore sets the pair only on a tablature staff and turns a `<string>` on a
    /// standard staff into a string-number text. Here the pair is read wherever the file gives it: a standard staff
    /// linked to a tab carries the same `<fret>` / `<string>` in MSCX, and a standard-notation-only guitar part that
    /// spells its positions is still a tab a consumer can use. The two values are independent, as in MSCX.
    ///
    /// A `<note>` may hold several `<notations>`; the first `<string>` and first `<fret>` across all of their
    /// `<technical>` children win. A string below 1, a negative fret, or a non-integer is dropped (`nil`) — the
    /// parser policy for cosmetic values.
    static func decodeTabPosition(_ node: XMLTreeNode) -> (string: Int?, fret: Int?) {
        let technical = node.all("notations").flatMap { $0.all("technical") }
        let string = technical.lazy.compactMap { $0.first("string") }.first
            .flatMap { Int($0.text) }
            .flatMap { $0 >= 1 ? $0 - 1 : nil }
        let fret = technical.lazy.compactMap { $0.first("fret") }.first
            .flatMap { Int($0.text) }
            .flatMap { $0 >= 0 ? $0 : nil }
        return (string, fret)
    }
}
