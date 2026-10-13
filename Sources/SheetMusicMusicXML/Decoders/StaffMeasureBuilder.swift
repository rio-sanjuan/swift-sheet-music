import SheetMusicCore
import SheetMusicFoundation

/// Accumulator for one staff's measure. Collects per-voice element buckets
/// where the "voice" key is an MSCX-style index derived from first-seen
/// MusicXML voice ids. MusicXML assigns global voice ids within a part
/// (e.g. 1 for right hand, 5 for left hand); MSCX uses positional voices
/// per `<voice>` block inside a measure. When a staff has only one MusicXML
/// voice id, everything — including attributes and barlines — ends up in a
/// single MSCX voice. Attributes always land in the first voice index.
struct StaffMeasureBuilder {
    private var voiceIndex: [String: Int] = [:]
    private var voices: [[VoiceElement]] = []
    private var defaultVoiceId: String?
    private var startRepeat = false
    private var endRepeatCount: Int?
    private var trailingBarline: BarLine?
    private var markers: [Marker] = []
    private var jumps: [Jump] = []
    /// System-level elements lifted out during decode (rehearsal marks
    /// and tempo changes; staff text / swing imports would feed into
    /// this once added). The caller pulls these
    /// out via `build()` and merges them into `Score.systemMeasures`.
    /// `originalStaff` is left nil here and stamped by the caller
    /// once the staff address is known.
    private var systemElements: [PositionedSystemElement] = []
    /// Chord symbols with their time in the measure, placed into the
    /// first voice by `build(measureLength:)`.
    private var harmonies: [(position: Fraction, harmony: Harmony)] = []
    /// Grace notes waiting for the chord they belong to, per MusicXML
    /// voice id. They are never voice elements, so they take no time.
    private var graceRuns: [String: MusicXMLGraceRun] = [:]

    /// Result of `build()`: the decoded `Measure` and the system
    /// elements that should be merged into the score-level
    /// `SystemMeasure` for this measure index.
    struct Built {
        let measure: Measure
        let systemElements: [PositionedSystemElement]
    }

    mutating func addMarkers(_ newMarkers: [Marker]) {
        markers.append(contentsOf: newMarkers)
    }

    mutating func addJumps(_ newJumps: [Jump]) {
        jumps.append(contentsOf: newJumps)
    }

    /// Record a rehearsal mark at the start of this measure.
    /// MusicXML's `<direction-type><rehearsal>` doesn't carry a
    /// fractional offset so the position defaults to
    /// `MeasurePosition.start`.
    mutating func addRehearsalMark(_ mark: RehearsalMark) {
        systemElements.append(PositionedSystemElement(
            position: .start,
            element: .rehearsalMark(mark),
        ))
    }

    /// Record a tempo change at `position` (a fraction of a whole note
    /// from the downbeat).
    mutating func addTempo(_ tempo: Tempo, at position: Fraction) {
        systemElements.append(PositionedSystemElement(
            position: MeasurePosition(offset: position),
            element: .tempo(tempo),
        ))
    }

    /// Record a chord symbol at `position`; `build(measureLength:)` puts
    /// it in the first voice before the chord that starts there.
    mutating func addHarmony(_ harmony: Harmony, at position: Fraction) {
        harmonies.append((position, harmony))
    }

    /// Append to the first voice index (MSCX attributes convention). Lazily
    /// creates the voice 0 bucket if no notes have been seen yet.
    mutating func appendAttribute(_ element: VoiceElement) {
        ensureFirstVoice()
        voices[0].append(element)
    }

    mutating func setDefaultVoice(_ voiceId: String) {
        defaultVoiceId = voiceId
    }

    /// Append a note-sourced element under the MSCX index corresponding to
    /// this MusicXML voice id. An ordinary chord takes the voice's waiting
    /// grace notes (`MusicXMLGraceRun`); a rest leaves them waiting.
    mutating func append(_ element: VoiceElement, toVoice voiceId: String) {
        let idx = internVoice(voiceId)
        if case var .chord(chord) = element, !chord.notes.isEmpty,
           var run = graceRuns.removeValue(forKey: voiceId), !run.isEmpty
        {
            run.attach(to: &chord, previousIn: &voices[idx])
            voices[idx].append(.chord(chord))
            return
        }
        voices[idx].append(element)
    }

    /// Hold a grace note for the next chord of its voice. A fermata on it
    /// goes into the voice now, ahead of that chord — MuseScore moves a
    /// grace's fermata onto its principal chord's segment.
    mutating func appendGrace(_ grace: MusicXMLNoteDecoder.Grace, toVoice voiceId: String) {
        let idx = internVoice(voiceId)
        graceRuns[voiceId, default: MusicXMLGraceRun()].add(grace)
        if let fermata = grace.fermata {
            voices[idx].append(.fermata(fermata))
        }
    }

    func elements(forVoice voiceId: String) -> [VoiceElement] {
        guard let idx = voiceIndex[voiceId] else { return [] }
        return voices[idx]
    }

    /// Positional voice index in the eventual built measure for the
    /// given MusicXML voice id. Returns `nil` before any append has
    /// claimed a slot for `voiceId`. Note that voice 0 may still be
    /// reassigned to the first real voice id (see `internVoice`); call
    /// this only after the relevant `append(_:toVoice:)`.
    func voicePositionIndex(forVoice voiceId: String) -> Int? {
        voiceIndex[voiceId]
    }

    /// Fold a `<chord/>` tone into the voice's last chord. Its articulations join the chord's, each kind once —
    /// a chord's tones commonly repeat the chord's marks, and MuseScore drops a duplicate the same way
    /// (`Chord::hasArticulation` in `addArticulationToChord`).
    mutating func foldIntoLastChord(
        voice voiceId: String, note: Note, duration: NoteDuration, articulations: [ChordArticulation] = [],
    ) {
        let idx = internVoice(voiceId)
        var elements = voices[idx]
        if let last = elements.last, case var .chord(chord) = last {
            chord.notes = ChordNotes(Array(chord.notes) + [note])
            let present = Set(chord.articulations.map(\.kind))
            chord.articulations += articulations.filter { !present.contains($0.kind) }
            elements[elements.count - 1] = .chord(chord)
        } else {
            elements.append(.chord(Chord(duration: duration, notes: [note], articulations: articulations)))
        }
        voices[idx] = elements
    }

    mutating func apply(barline: MusicXMLBarlineDecoder.Decoded) {
        switch barline.placement {
        case .start:
            if barline.startRepeat { startRepeat = true }
            if let line = barline.inline {
                appendToDefaultVoice(.barLine(line))
            }
        case .middle:
            if let line = barline.inline {
                appendToDefaultVoice(.barLine(line))
            }
        case .end:
            if let count = barline.endRepeatCount { endRepeatCount = count }
            if let line = barline.inline { trailingBarline = line }
        }
    }

    /// `measureLength` is the time signature in force; it resolves
    /// `.measure` rests when chord symbols are placed by time.
    func build(measureLength: Fraction = Fraction(numerator: 1, denominator: 1)) -> Built {
        var final = voices
        // Graces with no chord after them in the bar go after its last one.
        for (voiceId, run) in graceRuns.sorted(by: { $0.key < $1.key }) {
            guard let idx = voiceIndex[voiceId] else { continue }
            var run = run
            run.flush(into: &final[idx])
        }
        if !harmonies.isEmpty {
            if final.isEmpty { final.append([]) }
            final[0] = MusicXMLHarmonyPlacement.inserting(
                harmonies, into: final[0], measureLength: measureLength,
            )
        }
        if let trailing = trailingBarline {
            if final.isEmpty {
                final.append([])
            }
            let targetIdx: Int
            if let id = defaultVoiceId, let idx = voiceIndex[id] {
                targetIdx = idx
            } else {
                targetIdx = 0
            }
            final[targetIdx].append(.barLine(trailing))
        }
        let builtVoices = final.isEmpty
            ? [Voice(elements: [])]
            : final.map { Voice(elements: $0) }
        let measure = Measure(
            voices: builtVoices,
            startRepeat: startRepeat,
            endRepeatCount: endRepeatCount,
            markers: markers,
            jumps: jumps,
        )
        return Built(measure: measure, systemElements: systemElements)
    }

    // MARK: - private helpers

    private mutating func ensureFirstVoice() {
        if voices.isEmpty {
            voices.append([])
            voiceIndex["__implicit__"] = 0
        }
    }

    private mutating func internVoice(_ voiceId: String) -> Int {
        if let idx = voiceIndex[voiceId] { return idx }
        // If we seeded voice 0 with attributes only and this is the first real
        // voice, adopt that slot instead of creating a new one.
        if voices.count == 1, voiceIndex.values.first == 0,
           voiceIndex["__implicit__"] != nil, voiceIndex.count == 1
        {
            voiceIndex.removeValue(forKey: "__implicit__")
            voiceIndex[voiceId] = 0
            return 0
        }
        let idx = voices.count
        voices.append([])
        voiceIndex[voiceId] = idx
        return idx
    }

    private mutating func appendToDefaultVoice(_ element: VoiceElement) {
        if let id = defaultVoiceId {
            append(element, toVoice: id)
        } else {
            appendAttribute(element)
        }
    }
}
