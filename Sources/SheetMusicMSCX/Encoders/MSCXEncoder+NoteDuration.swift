import SheetMusicCore
import SheetMusicFoundation
import SheetMusicXMLTools

extension NoteDuration {
    /// The most augmentation dots a `<dots>` value carries: MuseScore's
    /// `MAX_DOTS` (`engraving/dom/note.h:53`). Its reader clamps anything
    /// larger (`TDuration::setDots`, `dom/durationtype.cpp`), so a fifth dot
    /// would load as a shorter note than the file claims — the encoder never
    /// writes one.
    static let mscxMaxDots = 4

    /// MuseScore `<durationType>` text for the named cases.
    /// Inverse of `init?(mscxName:)`. `.fraction` returns nil — the
    /// caller emits `measure` + `<duration>` instead, or attempts
    /// `decomposed()` first.
    var mscxName: String? {
        switch self {
        case .whole: "whole"
        case .half: "half"
        case .quarter: "quarter"
        case .eighth: "eighth"
        case .sixteenth: "16th"
        case .thirtySecond: "32nd"
        case .sixtyFourth: "64th"
        case .oneTwentyEighth: "128th"
        case .twoFiftySixth: "256th"
        case .fraction: nil
        case .measure: nil
        }
    }

    /// Try to express this duration as a named base + 0–4 dots
    /// (`mscxMaxDots`). Returns nil for `.measure` and for `.fraction`
    /// values that don't match any such combination (rare but possible —
    /// e.g., a 5/64 duration produced by an exotic tuplet ratio, or a
    /// five-dot value).
    ///
    /// The search order cannot change an existing answer by reaching
    /// four dots: `base · (2 − 2⁻ᵈ)` lies in `[base, 2·base)`, so no two
    /// bases share a value and each value has at most one spelling.
    func decomposed() -> (name: String, dots: Int)? {
        if case .measure = self { return nil }
        let target = asFraction
        let bases: [NoteDuration] = [
            .whole, .half, .quarter, .eighth, .sixteenth,
            .thirtySecond, .sixtyFourth, .oneTwentyEighth, .twoFiftySixth,
        ]
        for base in bases {
            // mscxName is non-nil for every element of `bases`.
            guard let name = base.mscxName else { continue }
            for dots in 0 ... Self.mscxMaxDots where base.dotted(dots).asFraction == target {
                return (name, dots)
            }
        }
        return nil
    }

    /// Throw unless a `<Chord>` — an ordinary chord or a grace — can carry this
    /// duration: a named base with at most `mscxMaxDots` dots.
    ///
    /// A `<Rest>` has a second form, `<durationType>measure</durationType>` +
    /// `<duration>`, which `appendDurationXML` falls back to. A `<Chord>` has
    /// not: both MuseScore and `Chord.decode` (`mscx.chord.invalidDurationType`)
    /// reject a chord written that way, and since the decoder throws, ONE such
    /// chord made the whole file unreadable. Refusing to write it is the only
    /// faithful answer short of splitting the chord into tied ones, which would
    /// change the score's structure behind the caller's back.
    ///
    /// `.measure` is refused too — a chord carries no "fills the bar" marker
    /// in MSCX, and this check has no bar length to resolve one against.
    func requireChordSpelling(location: String) throws {
        if case .measure = self {
            throw Self.chordDurationNotRepresentable(
                "a .measure duration on a \(location) has no note value to write",
                location: location,
            )
        }
        guard decomposed() == nil else { return }
        let length = asFraction
        throw Self.chordDurationNotRepresentable(
            "duration \(length.numerator)/\(length.denominator) on a \(location) is not a note value "
                + "with at most \(Self.mscxMaxDots) dots; MSCX has no other <Chord> spelling",
            location: location,
        )
    }

    private static func chordDurationNotRepresentable(
        _ message: String, location: String,
    ) -> SheetMusicError {
        .malformedScore(ScoreFault(
            code: "mscx.encoder.chordDurationNotRepresentable",
            message: message,
            location: location,
        ))
    }

    /// Append `<durationType>` (and optionally `<dots>` or
    /// `<duration>`) children to `children`.
    ///
    /// Prefers a named base + dots when possible (the form Chord
    /// requires); falls back to `<durationType>measure</durationType>`
    /// + `<duration>N/D</duration>` only for `.fraction` values that
    /// cannot be decomposed (Rest accepts this form; Chord does not —
    /// the voice encoder checks `requireChordSpelling` before it gets
    /// here, so no chord it writes takes the fallback).
    ///
    /// Element order matches MuseScore Studio's writer: `<dots>`
    /// precedes `<durationType>`. Emitting them in the reverse
    /// order (durationType first) makes MuseScore's loader read the
    /// duration without dots — the chord renders as a dotted half
    /// but plays back as a plain half, with the missing 1/4 padded
    /// out as an extra rest.
    func appendDurationXML(to children: inout [XMLTreeNode]) {
        if case .measure = self {
            preconditionFailure(
                "appendDurationXML: .measure must be written via "
                    + "the appendDurationXML(to:in:) overload that "
                    + "carries the effective measure duration",
            )
        }
        if let parts = decomposed() {
            if parts.dots > 0 {
                children.append(XMLTreeNode(name: "dots", text: String(parts.dots)))
            }
            children.append(XMLTreeNode(name: "durationType", text: parts.name))
            return
        }
        if case let .fraction(f) = self {
            children.append(XMLTreeNode(name: "durationType", text: "measure"))
            children.append(XMLTreeNode(
                name: "duration",
                text: "\(f.numerator)/\(f.denominator)",
            ))
        }
    }
}
