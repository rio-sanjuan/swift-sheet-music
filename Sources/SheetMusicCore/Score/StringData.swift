import Foundation

/// String tunings for a fretted instrument. MuseScore stores this as
/// `<StringData>` inside `<Instrument>`:
///
/// ```xml
/// <StringData>
///   <frets>19</frets>
///   <string>40</string>          <!-- open-string MIDI pitch -->
///   <string open="1">45</string> <!-- unfretted drone string -->
/// </StringData>
/// ```
///
/// Strings are listed in document order, LOW to HIGH pitch (standard
/// guitar EADGBE = 40, 45, 50, 55, 59, 64). Note that `Note.string`
/// indexes tab lines top-down (0 = top line = highest string), so
/// string index `s` on an L-string instrument tunes to
/// `strings[L - 1 - s]`.
///
/// C++: `mu::engraving::StringData`.
public struct StringData: Sendable, Equatable {
    /// Number of frets on the fingerboard (`<frets>`). MuseScore
    /// defaults to 19; frets beyond this are out of range.
    public var frets: Int
    /// Open-string tunings in document order (low → high pitch).
    public var strings: [StringTuning]

    /// One string's tuning entry.
    public struct StringTuning: Sendable, Equatable {
        /// Open-string MIDI pitch.
        public var pitch: Int
        /// MuseScore `open="1"` — an unfretted (drone) string, e.g.
        /// a 5-string banjo's thumb string. Such strings sound only
        /// at fret 0.
        public var open: Bool

        public init(pitch: Int, open: Bool = false) {
            self.pitch = pitch
            self.open = open
        }
    }

    public init(frets: Int = 19, strings: [StringTuning] = []) {
        self.frets = frets
        self.strings = strings
    }
}
