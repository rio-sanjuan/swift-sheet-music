import Foundation

/// Tablature-specific presentation properties of a `<StaffType
/// group="tablature">`. Defaults mirror MuseScore's `tab6StrCommon`
/// preset — the default tab staff type — so a bare `TabStaffStyle()`
/// reads as standard modern guitar tab.
///
/// C++: `mu::engraving::StaffType` (tablature-only subset).
public struct TabStaffStyle: Sendable, Equatable {
    /// Frets rendered as digits (`true`, modern) or letters
    /// (`false`, historic: fret 0 = "a", 1 = "b", …). MuseScore
    /// `<useNumbers>`.
    public var useNumbers: Bool
    /// Fret marks sit ON the string lines (`true`, modern) or in the
    /// spaces above them (`false`, historic French style).
    /// MuseScore `<onLines>`.
    public var onLines: Bool
    /// Staff lines are drawn through the fret marks (`true`) or
    /// wiped behind them (`false`, default). MuseScore `<linesThrough>`.
    public var linesThrough: Bool
    /// Reverse string order: top line = lowest string.
    /// MuseScore `<upsideDown>`.
    public var upsideDown: Bool
    /// Repeat the fret mark on a note tied *from* a previous note
    /// (`true`) or hide it (`false`). MuseScore `<showBackTied>`.
    public var showBackTied: Bool
    /// Stems point down / below the staff (`true`, default) or up /
    /// above it. MuseScore `<stemsDown>`.
    public var stemsDown: Bool
    /// Stems are drawn through the staff beside the fret column
    /// (`true`, "full" style) or detached beside the staff (`false`).
    /// MuseScore `<stemsThrough>`.
    public var stemsThrough: Bool
    /// How half notes are distinguished from quarters.
    /// MuseScore `<minimStyle>`.
    public var minimStyle: MinimStyle
    /// Rests are engraved on the tab staff. MuseScore `<showRests>`.
    public var showRests: Bool
    /// Historic styles draw duration symbols above the staff instead
    /// of stems. Parsed for round-trip; v1 renders stems regardless.
    /// MuseScore `<durations>` (genDurations).
    public var genDurations: Bool
    /// Show fingering marks on the tab staff. Parsed for round-trip;
    /// not rendered in v1. MuseScore `<showTabFingering>` — wire
    /// default is FALSE (element written only when true), so the
    /// model default follows the wire, not the Common preset (whose
    /// files carry an explicit `1`).
    public var showTabFingering: Bool
    /// When/whether a repeated duration symbol is re-engraved
    /// (historic styles): 0 never, 1 per system, 2 per measure,
    /// 3 always. Parsed for round-trip; not rendered in v1.
    /// MuseScore `<symbolRepeat>`.
    public var symbolRepeat: Int

    /// Fret mark font size in points (MuseScore reference spatium).
    /// MuseScore `<fretFontSize>`, preset default 9.
    public var fretFontSize: Double
    /// Fret mark font family. Parsed for round-trip; v1 renders
    /// system font. MuseScore `<fretFontName>` (≤4.5 spelling) —
    /// always written, so modeled non-optional with the stock face.
    public var fretFontName: String
    /// Vertical user offset of fret marks. Round-trip only.
    /// MuseScore `<fretFontY>`.
    public var fretFontY: Double
    /// Duration symbol font size (historic styles). Round-trip only.
    /// MuseScore `<durationFontSize>`, preset default 15.
    public var durationFontSize: Double
    /// Duration symbol font family. Round-trip only.
    /// MuseScore `<durationFontName>` — always written, so modeled
    /// non-optional with the stock face.
    public var durationFontName: String
    /// Vertical user offset of duration symbols. Round-trip only.
    /// MuseScore `<durationFontY>`.
    public var durationFontY: Double

    /// Half-note (minim) rendering on tab staves.
    /// C++: `mu::engraving::TablatureMinimStyle`.
    public enum MinimStyle: Int, Sendable, Equatable {
        /// Half notes get no stem at all.
        case none = 0
        /// Half notes get a shortened stem (Common preset).
        case shorter = 1
        /// Half notes get a stem with two slashes (Full preset).
        case slashed = 2
    }

    public init(
        useNumbers: Bool = true,
        onLines: Bool = true,
        linesThrough: Bool = false,
        upsideDown: Bool = false,
        showBackTied: Bool = true,
        stemsDown: Bool = true,
        stemsThrough: Bool = false,
        minimStyle: MinimStyle = .shorter,
        showRests: Bool = true,
        genDurations: Bool = false,
        showTabFingering: Bool = false,
        symbolRepeat: Int = 0,
        fretFontSize: Double = 9,
        fretFontName: String = "MuseScore Tab Sans",
        fretFontY: Double = 0,
        durationFontSize: Double = 15,
        durationFontName: String = "MuseScore Tab Modern",
        durationFontY: Double = 0,
    ) {
        self.useNumbers = useNumbers
        self.onLines = onLines
        self.linesThrough = linesThrough
        self.upsideDown = upsideDown
        self.showBackTied = showBackTied
        self.stemsDown = stemsDown
        self.stemsThrough = stemsThrough
        self.minimStyle = minimStyle
        self.showRests = showRests
        self.genDurations = genDurations
        self.showTabFingering = showTabFingering
        self.symbolRepeat = symbolRepeat
        self.fretFontSize = fretFontSize
        self.fretFontName = fretFontName
        self.fretFontY = fretFontY
        self.durationFontSize = durationFontSize
        self.durationFontName = durationFontName
        self.durationFontY = durationFontY
    }
}
