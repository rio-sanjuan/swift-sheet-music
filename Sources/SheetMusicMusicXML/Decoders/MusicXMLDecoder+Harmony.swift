import SheetMusicCore
import SheetMusicFoundation
import SheetMusicXMLTools

/// Decodes a `<harmony>` chord symbol into the `Harmony` an MSCX `<Harmony>` gives: `rootTpc` / `bassTpc` as tonal
/// pitch classes and `name` as the quality SUFFIX only ("m7", "7", "maj7", "" for a major triad), so the root letter
/// plus `name` (plus "/" and the bass) reads as the chord symbol. C++: `MusicXmlParserPass2::harmony` and
/// `ParsedChord::fromXml` (`importmusicxmlpass2.cpp`, `chordlist.cpp`).
///
/// **Suffix.** `<kind text="…">` is what the source printed and wins when present; otherwise the suffix is spelled
/// from the `<kind>` value the way MuseScore's `fromXml` spells it (`use-symbols="yes"` selecting its `^ - + o 0`
/// forms). `<degree>`s are appended in MuseScore's form (`b9`, `#11`, `add9`, `no3`), parenthesised under
/// `parentheses-degrees="yes"` or where MuseScore forces it, and skipped when `print-object="no"` — MusicXML's way of
/// saying the kind's text already shows them. Not modeled: MuseScore's chord-list lookup that can respell the result
/// (`maj7` vs `Maj7`), its degree merges (`add9` on a sixth → `69`), `<function>` / `<numeral>` symbols, `<inversion>`
/// and `<frame>` diagrams.
///
/// **No root.** `<kind>none</kind>` or `<root-step text="">` leaves `rootTpc` nil and `name` the kind's text ("N.C.");
/// a symbol with neither a root nor any text is dropped.
enum MusicXMLHarmonyDecoder {
    struct Decoded {
        let harmony: Harmony
        /// 0-based staff from `<staff>`, `nil` for the part's first staff. (`<offset>` is read by the walker's
        /// cursor.)
        let staffIndex: Int?
    }

    static func decode(_ node: XMLTreeNode) -> Decoded? {
        let kindNode = node.first("kind")
        let kind = kindNode?.text ?? "major"
        let kindText = kindNode?.attributes["text"]
        let rootTpc = kind == "none" ? nil : node.first("root").flatMap(rootTpc(_:))
        let name: String = if rootTpc == nil {
            kindText ?? ""
        } else {
            suffix(kind: kind, kindNode: kindNode, degrees: node.all("degree"))
        }
        guard rootTpc != nil || !name.isEmpty else { return nil }
        let bassTpc = node.first("bass").flatMap { bass -> Int? in
            guard let step = bass.first("bass-step")?.text else { return nil }
            return PitchDecoder.tpc(step: step, alter: alter(bass.first("bass-alter")))
        }
        let harmony = Harmony(
            name: name,
            rootTpc: rootTpc,
            bassTpc: rootTpc == nil ? nil : bassTpc,
            visible: node.attributes["print-object"] != "no",
        )
        return Decoded(
            harmony: harmony,
            staffIndex: node.first("staff").flatMap { Int($0.text) }.map { $0 - 1 },
        )
    }

    private static func rootTpc(_ root: XMLTreeNode) -> Int? {
        // `<root-step text="">` hides the root: MuseScore reads it as no root at all.
        guard let stepNode = root.first("root-step"), stepNode.attributes["text"]?.isEmpty != true else { return nil }
        return PitchDecoder.tpc(step: stepNode.text, alter: alter(root.first("root-alter")))
    }

    private static func alter(_ node: XMLTreeNode?) -> Int {
        node.flatMap { Double($0.text) }.map { Int($0) } ?? 0
    }

    /// The quality suffix: the kind's printed text, or its spelled form, then the printed degrees.
    private static func suffix(kind: String, kindNode: XMLTreeNode?, degrees: [XMLTreeNode]) -> String {
        let symbols = kindNode?.attributes["use-symbols"] == "yes"
        let spelled = spelledKind(kind, symbols: symbols)
        let printedText = kindNode?.attributes["text"]
        let base = printedText ?? spelled.name
        // The kind's own modifiers (`sus4`, the `maj7` of `major-minor`) are part of a printed text already.
        var modifiers = printedText == nil ? spelled.modifiers : []
        for degree in degrees where degree.attributes["print-object"] != "no" {
            if let modifier = degreeModifier(degree) { modifiers.append(modifier) }
        }
        guard !modifiers.isEmpty else { return base }
        // MuseScore brackets the degrees when asked, or when a bare triad starts its alterations with a ♭ / ♯ (so
        // "C(b5)" does not read as a chord named "Cb5").
        let forced = !spelled.hasExtension && (modifiers[0].hasPrefix("b") || modifiers[0].hasPrefix("#"))
        let parenthesised = kindNode?.attributes["parentheses-degrees"] == "yes" || forced
        let joined = modifiers.joined()
        return parenthesised ? base + "(" + joined + ")" : base + joined
    }

    /// `<degree>` as MuseScore's modifier text: an added or altered degree is `add` / `b` / `#` + value, a subtracted
    /// one `no` + value. `nil` when the value or type is unusable.
    private static func degreeModifier(_ degree: XMLTreeNode) -> String? {
        guard let value = degree.first("degree-value").flatMap({ Int($0.text) }), (1 ... 13).contains(value) else {
            return nil
        }
        let degreeAlter = alter(degree.first("degree-alter"))
        switch degree.first("degree-type")?.text {
        case "add", "alter":
            switch degreeAlter {
            case -1: return "b\(value)"
            case 1: return "#\(value)"
            case 0: return "add\(value)"
            default: return nil
            }
        case "subtract": return "no\(value)"
        default: return nil
        }
    }
}
