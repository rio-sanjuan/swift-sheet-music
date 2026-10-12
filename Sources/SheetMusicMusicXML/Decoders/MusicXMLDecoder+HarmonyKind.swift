import SheetMusicCore
import SheetMusicFoundation

extension MusicXMLHarmonyDecoder {
    /// A `<kind>` value spelled as MuseScore spells it when the source gives no `text` (`ParsedChord::fromXml`,
    /// `chordlist.cpp`): a quality — written out (`m`, `maj`, `aug`, `dim`, `m7b5`) or, under `use-symbols="yes"`, as
    /// MuseScore's symbol characters (`-`, `^`, `+`, `o`, `0`) — followed by the extension, with the quality left
    /// implied for a major triad, a major sixth and the dominants. So `major` → "", `minor-seventh` → "m7",
    /// `dominant` → "7", `major-seventh` → "maj7", `dominant-ninth` → "9", `suspended-fourth` → "sus4",
    /// `power` → "5". A kind MuseScore has no spelling for (`Neapolitan`, `other`, …) spells as "".
    ///
    /// `modifiers` are the ones the kind itself implies (`sus4`, the `maj7` of `major-minor`), ahead of any
    /// `<degree>`; `hasExtension` feeds MuseScore's rule for bracketing degrees.
    static func spelledKind(_ kind: String, symbols: Bool) -> (name: String, modifiers: [String], hasExtension: Bool) {
        let quality = Quality(kind: kind, symbols: symbols)
        let extensionValue = extensionNumber(kind: kind) ?? quality.impliedExtension
        let extensionText = extensionValue.map(String.init) ?? ""
        let name = quality.isImplied ? extensionText : quality.text(symbols: symbols) + extensionText
        return (name, quality.modifiers, extensionValue != nil)
    }

    /// The extension a `<kind>` names, if it names one.
    private static func extensionNumber(kind: String) -> Int? {
        if kind.contains("seventh") { return 7 }
        if kind.contains("ninth") { return 9 }
        if kind.contains("11th") { return 11 }
        if kind.contains("13th") { return 13 }
        if kind.contains("sixth") { return 6 }
        return nil
    }

    private struct Quality {
        enum Base { case major, minor, augmented, diminished, halfDiminished, dominant, unnamed }

        var base: Base
        var isImplied = false
        var impliedExtension: Int?
        var modifiers: [String] = []

        init(kind: String, symbols: Bool) {
            switch kind {
            case "major-minor":
                base = .minor
                modifiers = ["maj7"]
            case "major", "major-sixth", "pedal":
                base = .major
                isImplied = true
            case "suspended-fourth", "suspended-second":
                base = .major
                isImplied = true
                modifiers = [kind == "suspended-fourth" ? "sus4" : "sus2"]
            case "power":
                base = .major
                isImplied = true
                impliedExtension = 5
            case "augmented", "augmented-seventh": base = .augmented
            case "half-diminished":
                base = .halfDiminished
                impliedExtension = symbols ? 7 : nil
            case "diminished", "diminished-seventh": base = .diminished
            case _ where kind.contains("major"): base = .major
            case _ where kind.contains("minor"): base = .minor
            case _ where kind.contains("dominant"):
                base = .dominant
                isImplied = true
                impliedExtension = 7
            default:
                base = .unnamed
            }
        }

        func text(symbols: Bool) -> String {
            switch base {
            case .major: symbols ? "^" : "maj"
            case .minor: symbols ? "-" : "m"
            case .augmented: symbols ? "+" : "aug"
            case .diminished: symbols ? "o" : "dim"
            case .halfDiminished: symbols ? "0" : "m7b5"
            case .dominant, .unnamed: ""
            }
        }
    }
}
