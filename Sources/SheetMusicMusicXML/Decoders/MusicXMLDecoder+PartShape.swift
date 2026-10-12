import SheetMusicCore
import SheetMusicFoundation

/// The part- and score-level facts the measure walk collects but no single measure owns: tablature staves, the
/// instrument's tuning and transposition, and bar lengths.
extension Score {
    /// MuseScore's tablature staff type for a staff of `lineCount` lines — `tab<N>StrCommon`, the preset a
    /// MuseScore-built N-string tab staff carries, for the N that have one (4…10); otherwise `tab6StrCommon`, the
    /// default MuseScore's MusicXML importer applies to every TAB staff (`StaffTypes::TAB_DEFAULT`) before setting its
    /// line count.
    ///
    /// The staff carries no `staffTypePreservedMarkup`: a MusicXML file says nothing about fonts, stems or duration
    /// symbols, so a consumer reads those as the named preset's defaults.
    static func tabStaffType(lineCount: Int) -> String {
        (4 ... 10).contains(lineCount) ? "tab\(lineCount)StrCommon" : "tab6StrCommon"
    }

    /// `instrument` with the part's `<staff-tuning>` as `stringData` and its opening `<transpose>` as
    /// `transposeDiatonic` / `transposeChromatic` — where an MSCX `<Instrument>` keeps both.
    static func withPartAttributes(
        _ instrument: Instrument,
        from walker: MusicXMLMeasureWalker.PartResult,
    ) -> Instrument {
        var result = instrument
        if let stringData = walker.stringData {
            result.stringData = stringData
        }
        result.transposeDiatonic = walker.transposition.diatonic
        result.transposeChromatic = walker.transposition.chromatic
        return result
    }

    /// `parts` with each bar's `actualLength` / `irregular` (from `MusicXMLMeasureLength`) set on every staff, as
    /// MSCX writes `len` on every staff's `<Measure>` and `Score.blank` sets a pickup on every staff.
    static func sizingMeasures(
        _ parts: [Part],
        by sizes: [(actualLength: Fraction?, irregular: Bool)],
    ) -> [Part] {
        guard sizes.contains(where: { $0.actualLength != nil || $0.irregular }) else { return parts }
        return parts.map { part in
            var part = part
            for staffIndex in part.staves.indices {
                part.staves.updateValue(at: staffIndex) { staff in
                    for (index, size) in sizes.enumerated() where staff.measures.indices.contains(index) {
                        if let actualLength = size.actualLength {
                            staff.measures[index].actualLength = actualLength
                        }
                        if size.irregular {
                            staff.measures[index].irregular = true
                        }
                    }
                }
            }
            return part
        }
    }
}
