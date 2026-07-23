import Foundation
import SheetMusicCore
import SheetMusicXMLTools

extension StaffTypeProperties {
    /// Children of the `<StaffType>` element, in MuseScore's writer
    /// order. Mirrors `TWrite::write(const StaffType*)`
    /// (rw/write/twrite.cpp): common properties are emitted only when
    /// they differ from the `stdNormal` defaults, so a default
    /// pitched staff still serializes as just `<name>` — byte-stable
    /// with the pre-tab encoder. Tablature staves append the tab
    /// block, which MuseScore writes unconditionally.
    ///
    /// MuseScore 4.6+ ignores `<fretFontName>` (replaced by preset
    /// indices) and skips it harmlessly; ≤4.5 honors it.
    func mscxChildren(staffTypeName: String) -> [XMLTreeNode] {
        var children: [XMLTreeNode] = [
            XMLTreeNode(name: "name", text: staffTypeName),
        ]
        if lines != 5 {
            children.append(XMLTreeNode(name: "lines", text: String(lines)))
        }
        if lineDistanceSp != 1.0 {
            children.append(XMLTreeNode(
                name: "lineDistance", text: formatted(lineDistanceSp),
            ))
        }
        if !genClef {
            children.append(XMLTreeNode(name: "clef", text: "0"))
        }
        if stemless {
            children.append(XMLTreeNode(name: "stemless", text: "1"))
        }
        if !showBarlines {
            children.append(XMLTreeNode(name: "barlines", text: "0"))
        }
        if !genTimesig {
            children.append(XMLTreeNode(name: "timesig", text: "0"))
        }
        if let tab {
            // MuseScore emits `<keysig>` only for standard/percussion
            // groups (tab forces it false at read time), so nothing
            // to write here even when `genKeysig` is false.
            children.append(contentsOf: tabChildren(tab))
        } else if !genKeysig {
            children.append(XMLTreeNode(name: "keysig", text: "0"))
        }
        return children
    }

    private func tabChildren(_ tab: TabStaffStyle) -> [XMLTreeNode] {
        var children: [XMLTreeNode] = [
            XMLTreeNode(name: "durations", text: bool(tab.genDurations)),
            XMLTreeNode(
                name: "durationFontName", text: tab.durationFontName,
            ),
            XMLTreeNode(
                name: "durationFontSize", text: formatted(tab.durationFontSize),
            ),
            XMLTreeNode(
                name: "durationFontY", text: formatted(tab.durationFontY),
            ),
        ]
        if tab.symbolRepeat != 0 {
            children.append(XMLTreeNode(
                name: "symbolRepeat", text: String(tab.symbolRepeat),
            ))
        }
        children.append(contentsOf: [
            XMLTreeNode(name: "fretFontName", text: tab.fretFontName),
            XMLTreeNode(name: "fretFontSize", text: formatted(tab.fretFontSize)),
            XMLTreeNode(name: "fretFontY", text: formatted(tab.fretFontY)),
            XMLTreeNode(name: "linesThrough", text: bool(tab.linesThrough)),
            XMLTreeNode(
                name: "minimStyle", text: String(tab.minimStyle.rawValue),
            ),
            XMLTreeNode(name: "onLines", text: bool(tab.onLines)),
            XMLTreeNode(name: "showRests", text: bool(tab.showRests)),
            XMLTreeNode(name: "stemsDown", text: bool(tab.stemsDown)),
            XMLTreeNode(name: "stemsThrough", text: bool(tab.stemsThrough)),
            XMLTreeNode(name: "upsideDown", text: bool(tab.upsideDown)),
        ])
        if tab.showTabFingering {
            children.append(XMLTreeNode(name: "showTabFingering", text: "1"))
        }
        children.append(XMLTreeNode(name: "useNumbers", text: bool(tab.useNumbers)))
        // MuseScore writes showBackTied only when it differs from
        // !stemless (the 2.0.2-compat derivation).
        if tab.showBackTied != !stemless {
            children.append(XMLTreeNode(
                name: "showBackTied", text: bool(tab.showBackTied),
            ))
        }
        return children
    }

    private func bool(_ value: Bool) -> String {
        value ? "1" : "0"
    }

    /// MuseScore writes doubles without a trailing `.0` for whole
    /// values (`<lineDistance>1.5</lineDistance>` but
    /// `<fretFontSize>9</fretFontSize>`).
    private func formatted(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15
            ? String(Int(value))
            : String(value)
    }
}
