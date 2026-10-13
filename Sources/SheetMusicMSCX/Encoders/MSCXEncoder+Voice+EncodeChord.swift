import SheetMusicCore
import SheetMusicFoundation
import SheetMusicXMLTools

extension Voice {
    /// Build the `<Chord>` / `<Rest>` element for one chord case of the
    /// element switch. Factored out of `encode(element:…)` so that
    /// dispatch fits within the function-body-length budget; carries
    /// the same `staffGroup` / `voiceIndex` threading needed for
    /// percussion-v3 stem direction and default note head emission.
    func encodeChord(
        chord: Chord,
        eid: EID,
        activeTuplets: [TupletSpan],
        previousChordDuration: Fraction?,
        isFirstChordOfVoice: Bool,
        isLastChordOfVoice: Bool,
        prevVoiceTotal: Fraction?,
        voiceBarLength: Fraction,
        effectiveDuration: Fraction,
        injectedTremolo: Tremolo?,
        previousChordNotes: ChordNotes? = nil,
        forwardTiePartnerNotes: ChordNotes? = nil,
        previousChordTrailingBendGrace: Int? = nil,
        slurEndMarkers: [XMLTreeNode] = [],
        options: MSCXEncoderOptions,
        staffGroup: String,
        voiceIndex: Int,
    ) throws -> XMLTreeNode {
        // Copy-and-mutate rather than rebuilding from an explicit field
        // list: `Chord` is a value type, so every field survives by
        // construction and a future field added to `Chord` can't be
        // silently dropped here the way an explicit-list rebuild once was.
        var unscaledChord = chord
        // A whole-bar CHORD (`.measure` with notes) has no marker form in
        // MSCX: MuseScore's `V_MEASURE` is a rest-only duration type, and a
        // chord that fills a bar is stored as the bar's own note value — a
        // whole in 4/4, a dotted half in 3/4, a quarter in a one-beat pickup.
        // So that is what is written, in the decoder's spelling
        // (`NoteDuration.resolved(in:)`); it reads back as that concrete
        // value, not as `.measure`. A rest keeps the marker, which
        // `encodeAsRest(…, in:)` writes with the bar's length.
        let written = chord.notes.isEmpty ? chord.duration : chord.duration.resolved(in: effectiveDuration)
        unscaledChord.duration = try unscaledDuration(written, in: activeTuplets)
        // A `<Rest>` can fall back to `measure` + `<duration>`; a `<Chord>`
        // cannot, and one written that way makes the file unreadable — so
        // refuse here, before anything is written. For a whole-bar chord
        // that is a bar no single note value fills (5/4, 7/16, 4/2):
        // MuseScore would split it into tied chords, which is a structural
        // edit this encoder does not make on the caller's behalf.
        if !unscaledChord.notes.isEmpty {
            let isWholeBar = chord.duration == .measure
            try unscaledChord.duration.requireChordSpelling(
                location: isWholeBar
                    ? "whole-bar chord in a \(effectiveDuration.numerator)/\(effectiveDuration.denominator) bar"
                    : "chord",
            )
        }
        let tieForward = forwardTieLocation(
            chord: chord,
            isLastChordOfVoice: isLastChordOfVoice,
            voiceBarLength: voiceBarLength,
        )
        let tieBack = backwardTieLocation(
            chord: chord,
            isFirstChordOfVoice: isFirstChordOfVoice,
            previousChordDuration: previousChordDuration,
            prevVoiceTotal: prevVoiceTotal,
        )
        // The same two deltas without the "does this chord carry a tie?"
        // guard: a guitar bend needs them on chords that carry no tie at all.
        let bendForward = forwardTieDelta(
            chord: chord,
            isLastChordOfVoice: isLastChordOfVoice,
            voiceBarLength: voiceBarLength,
        )
        let bendBackward = backwardTieDelta(
            isFirstChordOfVoice: isFirstChordOfVoice,
            previousChordDuration: previousChordDuration,
            prevVoiceTotal: prevVoiceTotal,
        )
        return unscaledChord.notes.isEmpty
            ? unscaledChord.encodeAsRest(
                eid: eid,
                slurEndMarkers: slurEndMarkers,
                options: options, in: effectiveDuration,
            )
            : unscaledChord.encodeAsChord(
                eid: eid,
                tieForwardLocation: tieForward,
                tieBackLocation: tieBack,
                tieForwardPartnerNotes: forwardTiePartnerNotes,
                tieBackPartnerNotes: previousChordNotes,
                bendNeighbourForward: bendForward,
                bendNeighbourBackward: bendBackward,
                previousChordTrailingBendGrace: previousChordTrailingBendGrace,
                slurEndMarkers: slurEndMarkers,
                options: options,
                staffGroup: staffGroup,
                voiceIndex: voiceIndex,
                injectedTremolo: injectedTremolo,
            )
    }
}
