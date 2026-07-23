import Foundation
import SheetMusicCore
import SheetMusicXMLTools

extension StaffTypeProperties {
    /// Decode the children of a `<StaffType group="…">` element into
    /// typed properties. MuseScore omits children matching preset
    /// defaults (e.g. `<lines>` only when ≠ 5, `<clef>` only when
    /// clef generation is off), so absence means "default".
    ///
    /// Policy per child:
    ///   * Layout-affecting values we honor → parsed below.
    ///   * Known cosmetic values (fonts we don't select, offsets,
    ///     colors, 4.6 fret-text-style plumbing) → silently skipped.
    ///   * Unknown children on a TABLATURE staff → warn
    ///     (`mscx.staffType.unsupportedTabProperty`) and drop; on
    ///     other groups unknown children stay silently skipped
    ///     (pre-existing permissive behavior).
    ///
    /// C++: `TRead::read(StaffType*)` (rw/read460/tread.cpp) and
    /// `TWrite::write(const StaffType*)` (rw/write/twrite.cpp).
    static func decode(_ node: XMLTreeNode, group: String) -> StaffTypeProperties {
        var props = StaffTypeProperties()
        let isTab = group == "tablature"
        var tab: TabStaffStyle? = isTab ? TabStaffStyle() : nil
        if isTab {
            // MuseScore forces key signature generation off for
            // tablature staves at read time (no element is written).
            props.genKeysig = false
        }

        // `<stemless>` (or its 2.x alias `<slashStyle>`) implies
        // `showBackTied = !stemless` unless an explicit
        // `<showBackTied>` follows — MuseScore 2.0.2 scores lack the
        // property and derived it from slashStyle. Mirror the
        // ordering-sensitive compat rule by tracking explicitness.
        var sawExplicitShowBackTied = false

        for child in node.children {
            switch child.name {
            case "lines":
                props.lines = Int(child.text) ?? props.lines
            case "lineDistance":
                props.lineDistanceSp = Double(child.text) ?? props.lineDistanceSp
            case "clef":
                props.genClef = boolText(child.text) ?? props.genClef
            case "timesig":
                props.genTimesig = boolText(child.text) ?? props.genTimesig
            case "keysig":
                props.genKeysig = boolText(child.text) ?? props.genKeysig
            case "barlines":
                props.showBarlines = boolText(child.text) ?? props.showBarlines
            case "stemless", "slashStyle":
                let value = boolText(child.text) ?? props.stemless
                props.stemless = value
                if !sawExplicitShowBackTied {
                    tab?.showBackTied = !value
                }
            case "showBackTied":
                sawExplicitShowBackTied = true
                tab?.showBackTied = boolText(child.text) ?? true
            case "name", "yoffset", "mag", "small", "stepOffset",
                 "invisible", "color", "noteheadScheme", "ledgerlines",
                 "fretPresetIdx", "fretUseTextStyle", "fretTextStyle":
                // Known cosmetic / handled elsewhere (name) / 4.6
                // fret-text-style plumbing — silently skipped.
                break
            default:
                if var tabStyle = tab, applyTabProperty(child, to: &tabStyle) {
                    tab = tabStyle
                } else if isTab {
                    mscxDecoderWarn(
                        code: "mscx.staffType.unsupportedTabProperty",
                        message: "Unknown <StaffType> child <\(child.name)> on tablature staff — dropped",
                    )
                }
            }
        }
        props.tab = tab
        return props
    }

    /// Apply one tab-block child to `tab`. Returns `false` when the
    /// element name isn't a tab property (caller then warns on
    /// tablature staves).
    private static func applyTabProperty(
        _ child: XMLTreeNode, to tab: inout TabStaffStyle,
    ) -> Bool {
        switch child.name {
        case "durations":
            tab.genDurations = boolText(child.text) ?? false
        case "durationFontName":
            tab.durationFontName = child.text
        case "durationFontSize":
            tab.durationFontSize = Double(child.text) ?? 15
        case "durationFontY":
            tab.durationFontY = Double(child.text) ?? 0
        case "fretFontName":
            tab.fretFontName = child.text
        case "fretFontSize":
            tab.fretFontSize = Double(child.text) ?? 9
        case "fretFontY":
            tab.fretFontY = Double(child.text) ?? 0
        case "symbolRepeat":
            tab.symbolRepeat = Int(child.text) ?? 0
        case "linesThrough":
            tab.linesThrough = boolText(child.text) ?? false
        case "minimStyle":
            if let raw = Int(child.text),
               let style = TabStaffStyle.MinimStyle(rawValue: raw) {
                tab.minimStyle = style
            } else {
                mscxDecoderWarn(
                    code: "mscx.staffType.unsupportedTabProperty",
                    message: "Unknown <minimStyle> '\(child.text)' — using default",
                )
            }
        case "onLines":
            tab.onLines = boolText(child.text) ?? true
        case "showRests":
            tab.showRests = boolText(child.text) ?? true
        case "stemsDown":
            tab.stemsDown = boolText(child.text) ?? true
        case "stemsThrough":
            tab.stemsThrough = boolText(child.text) ?? false
        case "upsideDown":
            tab.upsideDown = boolText(child.text) ?? false
        case "showTabFingering":
            tab.showTabFingering = boolText(child.text) ?? false
        case "useNumbers":
            tab.useNumbers = boolText(child.text) ?? true
        default:
            return false
        }
        return true
    }

    /// MuseScore serializes StaffType booleans as `0` / `1`; accept
    /// `true` / `false` spellings defensively.
    private static func boolText(_ text: String) -> Bool? {
        switch text {
        case "0", "false": false
        case "1", "true": true
        default: Int(text).map { $0 != 0 }
        }
    }
}
