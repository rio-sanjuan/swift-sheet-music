import SheetMusicCore
import SheetMusicFoundation

/// What one part says about one `<measure>`, for sizing the bar across the score.
struct MusicXMLMeasureFacts {
    /// How far the part's notes, `<forward>`s and `<backup>`s reach (`MusicXMLMeasureCursor.length`).
    var contentLength: Fraction
    /// The time signature in force, `nil` when none has been read.
    var nominalLength: Fraction?
    /// `<divisions>` in force, for MuseScore's rounding tolerance.
    var divisionsPerQuarter: Int
    /// `<measure implicit="yes">`.
    var isImplicit: Bool
}

/// The bar sizes MuseScore's importer gives a MusicXML file, as `Measure.actualLength` / `Measure.irregular` hold
/// them for MSCX's `<Measure len="…">` / `<irregular>`. C++: `MusicXmlParserPass1::determineMeasureLength` and the
/// end of `MusicXmlParserPass1::measure` (`importmusicxmlpass1.cpp`), and `implicit` in `MusicXmlParserPass2::measure`.
///
/// - A bar is as long as the longest content any part gives it, rounded to a 1/128 the way MuseScore rounds it. When
///   that differs from the time signature in force — a pickup, the bar that completes it, an over-full bar — it
///   becomes `actualLength`; an empty bar, or one that fills its signature, keeps `nil`.
/// - `implicit="yes"` in any part makes the bar `irregular` (left out of the measure count). The two are independent,
///   as in MuseScore: a short bar that is not marked implicit is still numbered.
enum MusicXMLMeasureLength {
    /// One `(actualLength, irregular)` per measure index, over `factsByPart[part][measure]`.
    static func resolve(_ factsByPart: [[MusicXMLMeasureFacts]]) -> [(actualLength: Fraction?, irregular: Bool)] {
        let count = factsByPart.map(\.count).max() ?? 0
        return (0 ..< count).map { index in
            let entries = factsByPart.compactMap { $0.indices.contains(index) ? $0[index] : nil }
            let irregular = entries.contains(where: \.isImplicit)
            var content = Fraction(numerator: 0, denominator: 1)
            for entry in entries {
                let rounded = rounded(entry.contentLength, divisionsPerQuarter: entry.divisionsPerQuarter)
                if MeasurePosition(offset: content) < MeasurePosition(offset: rounded) { content = rounded }
            }
            let nominal = entries.lazy.compactMap(\.nominalLength).first ?? Fraction(numerator: 4, denominator: 4)
            guard content.numerator > 0, content != nominal else { return (nil, irregular) }
            return (content, irregular)
        }
    }

    /// `length` on a 1/128 grid: down when it overshoots a grid line by less than one division (a rounding error in
    /// the source), up otherwise.
    static func rounded(_ length: Fraction, divisionsPerQuarter: Int) -> Fraction {
        let scaled = length.numerator * 128
        guard scaled % length.denominator != 0 else { return length }
        let down = Fraction(numerator: scaled / length.denominator, denominator: 128)
        let overshoot = length - down
        let tolerance = Fraction(numerator: 1, denominator: 4 * max(1, divisionsPerQuarter))
        if MeasurePosition(offset: overshoot) < MeasurePosition(offset: tolerance) { return down }
        return down + Fraction(numerator: 1, denominator: 128)
    }
}
