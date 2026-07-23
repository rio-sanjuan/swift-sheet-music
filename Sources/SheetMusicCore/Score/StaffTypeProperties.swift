import Foundation

/// Typed view of a `<StaffType>` element's children beyond the
/// name/group pair that `Staff.staffType` / `Staff.group` carry.
/// Defaults describe MuseScore's `stdNormal` preset (5-line pitched
/// staff), so a bare `StaffTypeProperties()` is a standard staff.
///
/// MuseScore emits most children only when they differ from these
/// defaults (e.g. `<lines>` only when ≠ 5, `<clef>` only when
/// `genClef` is false), and the encoder mirrors that.
///
/// C++: `mu::engraving::StaffType` (group-common subset; the
/// tablature-only properties live in `TabStaffStyle`).
public struct StaffTypeProperties: Sendable, Equatable {
    /// Number of staff lines (`<lines>`). 5 standard; tab presets
    /// use the string count (4/6); percussion presets use 1–3.
    public var lines: Int
    /// Distance between adjacent staff lines in spatium units
    /// (`<lineDistance>`). 1.0 standard; tab presets use 1.5 so
    /// fret marks fit between lines.
    public var lineDistanceSp: Double
    /// Whether a clef is engraved on this staff (`<clef>` element,
    /// written only when false).
    public var genClef: Bool
    /// Whether time signatures are engraved (`<timesig>`, written
    /// only when false — the tab "simple" presets suppress them).
    public var genTimesig: Bool
    /// Whether key signatures are engraved (`<keysig>`). MuseScore
    /// forces this false for tablature staves at read time; the
    /// element itself only appears on standard/percussion staves.
    public var genKeysig: Bool
    /// Whether barlines are engraved (`<barlines>`, written only
    /// when false).
    public var showBarlines: Bool
    /// Whether chords are engraved without stems (`<stemless>`;
    /// legacy alias `<slashStyle>`). The tab "simple" presets are
    /// stemless.
    public var stemless: Bool
    /// Tablature-only presentation properties. Non-nil iff the
    /// staff's group is "tablature".
    public var tab: TabStaffStyle?

    public init(
        lines: Int = 5,
        lineDistanceSp: Double = 1.0,
        genClef: Bool = true,
        genTimesig: Bool = true,
        genKeysig: Bool = true,
        showBarlines: Bool = true,
        stemless: Bool = false,
        tab: TabStaffStyle? = nil,
    ) {
        self.lines = lines
        self.lineDistanceSp = lineDistanceSp
        self.genClef = genClef
        self.genTimesig = genTimesig
        self.genKeysig = genKeysig
        self.showBarlines = showBarlines
        self.stemless = stemless
        self.tab = tab
    }
}
