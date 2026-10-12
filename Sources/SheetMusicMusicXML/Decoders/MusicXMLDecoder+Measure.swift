import SheetMusicCore
import SheetMusicFoundation
import SheetMusicXMLTools

/// Walks the `<measure>` children of a single MusicXML `<part>` and produces
/// one `[Measure]` array per staff in the part. MusicXML interleaves notes
/// for all staves in a single `<measure>` block; `<note><staff>N</staff></note>`
/// selects the target staff, and `<attributes><staves>` declares the count.
/// Reference implementation: `MusicXmlParserPass2::measure`.
enum MusicXMLMeasureWalker {
    /// Return value grouping the decoded measures per staff (`[staff1, staff2, …]`)
    /// and the detected staff count.
    struct PartResult {
        let staffCount: Int
        /// `measuresByStaff[staffIndex][measureIndex]` — outer array has
        /// `staffCount` entries; inner array holds one `Measure` per
        /// `<measure>` block.
        let measuresByStaff: [[Measure]]
        /// `systemElementsByStaffMeasure[staffIndex][measureIndex]` —
        /// the system-level elements (currently just rehearsal marks)
        /// that were lifted out during decode, ready to be merged into
        /// the score-level `[SystemMeasure]` once the staff address is
        /// known.
        let systemElementsByStaffMeasure: [[[PositionedSystemElement]]]
        /// `<attributes><staff-details><staff-lines>` per 0-based staff
        /// index, already clamped to `1...16`. Staff-level rather than
        /// measure-level, so it is collected during the walk and handed
        /// to the `Staff` construction sites instead of being emitted
        /// into the measure stream. Staves absent from the map keep
        /// `Staff.lineCount`'s default of 5.
        let lineCountByStaff: [Int: Int]
        /// Staves whose opening clef is `TAB`: the part decoder makes them
        /// tablature staves.
        let tabStaves: Set<Int>
        /// The part's tuning: the first `<staff-tuning>` set on a TAB
        /// staff, else on any staff (`MusicXMLStaffDetailsDecoder`).
        let stringData: StringData?
        /// The `<transpose>` in force at the end of the first measure —
        /// the instrument's transposition, as MuseScore takes the one at
        /// tick 0. Pitches are converted with whichever is in force at
        /// each note.
        let transposition: MusicXMLTransposition
        /// One entry per `<measure>`: what the score decoder needs to size
        /// the bar across parts (`MusicXMLMeasureLength`).
        let measureFacts: [MusicXMLMeasureFacts]
    }

    static func decode(
        partNode: XMLTreeNode,
        drumTable: MusicXMLDrumTable = MusicXMLDrumTable(),
    ) throws -> PartResult {
        let staffCount = detectStaffCount(partNode: partNode)
        var state = WalkState()
        var perStaffMeasures: [[Measure]] = Array(repeating: [], count: staffCount)
        var perStaffSystemElements: [[[PositionedSystemElement]]] = Array(
            repeating: [],
            count: staffCount,
        )
        var measureFacts: [MusicXMLMeasureFacts] = []
        var initialTransposition = MusicXMLTransposition.none
        let measureNodes = partNode.all("measure")
        for (index, measureNode) in measureNodes.enumerated() {
            let decoded = try decodeOne(
                measureNode: measureNode,
                state: &state,
                isFirstMeasure: index == 0,
                staffCount: staffCount,
                drumTable: drumTable,
                measureIndex: index,
            )
            for (staffIdx, item) in decoded.built.enumerated() {
                perStaffMeasures[staffIdx].append(item.measure)
                perStaffSystemElements[staffIdx].append(item.systemElements)
            }
            measureFacts.append(MusicXMLMeasureFacts(
                contentLength: decoded.contentLength,
                nominalLength: state.nominalLength,
                divisionsPerQuarter: state.divisions.perQuarter,
                isImplicit: measureNode.attributes["implicit"] == "yes",
            ))
            if index == 0 { initialTransposition = state.attributes.transposition }
        }
        state.voltaTracker.finish(lastMeasureIndex: measureNodes.count - 1)
        if !perStaffMeasures.isEmpty {
            state.voltaTracker.apply(to: &perStaffMeasures[0])
        }
        let withGlides = applyGlides(
            attachments: state.glideTracker.attachments,
            measures: perStaffMeasures,
        )
        let dropped = dropUnmatchedTies(withGlides)
        let attributes = state.attributes
        return PartResult(
            staffCount: staffCount,
            measuresByStaff: dropped,
            systemElementsByStaffMeasure: perStaffSystemElements,
            lineCountByStaff: attributes.lineCountByStaff,
            tabStaves: attributes.tabStaves,
            stringData: preferredStringData(attributes),
            transposition: initialTransposition,
            measureFacts: measureFacts,
        )
    }

    /// A part has one tuning (`Instrument.stringData`). A TAB staff's is
    /// preferred — MuseScore reads `<staff-tuning>` for TAB staves only —
    /// but a tuning given on a standard staff is kept rather than dropped
    /// when there is no TAB staff's to prefer. Lowest staff first.
    private static func preferredStringData(_ attributes: MusicXMLAttributesSnapshot) -> StringData? {
        let staves = attributes.stringDataByStaff.keys.sorted()
        let staff = staves.first { attributes.tabStaves.contains($0) } ?? staves.first
        return staff.flatMap { attributes.stringDataByStaff[$0] }
    }

    /// The per-part state carried from one `<measure>` to the next.
    private struct WalkState {
        var divisions = DivisionsContext(perQuarter: 1)
        var attributes = MusicXMLAttributesSnapshot()
        // Glissando / slide events span notes (and possibly measures)
        // within a part; the tracker accumulates pending starts and
        // resolved attachments across the full per-part walk, then
        // attachments are applied after measures are built. Scope is
        // strictly per-part — no cross-part state leaks because the
        // tracker is a fresh local here.
        var glideTracker = MusicXMLGlideTracker()
        /// `<ending>` starts waiting for their stop, and the finished voltas.
        var voltaTracker = MusicXMLVoltaTracker()

        /// The time signature in force, as a bar length.
        var nominalLength: Fraction? {
            guard let numerator = attributes.timeN, let denominator = attributes.timeD,
                  numerator > 0, denominator > 0
            else { return nil }
            return Fraction(numerator: numerator, denominator: denominator)
        }
    }

    /// Mutate the start chord's first note for each resolved glissando /
    /// slide attachment. Unmatched stops never produce an attachment, so
    /// the loop here only sees fully-paired events. Indices are validated
    /// defensively — out-of-range entries (impossible under well-formed
    /// input, but cheap insurance) silently drop.
    private static func applyGlides(
        attachments: [MusicXMLGlideTracker.StartLocation],
        measures: [[Measure]],
    ) -> [[Measure]] {
        var result = measures
        for attach in attachments {
            guard attach.staffIndex < result.count else { continue }
            guard attach.measureIndex < result[attach.staffIndex].count else { continue }
            var measure = result[attach.staffIndex][attach.measureIndex]
            guard attach.voiceIndex < measure.voices.count else { continue }
            var voice = measure.voices[attach.voiceIndex]
            guard attach.elementIndex < voice.elements.count else { continue }
            guard case var .chord(chord) = voice.elements[attach.elementIndex] else {
                continue
            }
            guard !chord.notes.isEmpty else { continue }
            chord.notes.updateNote(at: 0) { $0.glissando = attach.glissando }
            voice.elements.updateValue(at: attach.elementIndex) { $0 = .chord(chord) }
            measure.voices[attach.voiceIndex] = voice
            result[attach.staffIndex][attach.measureIndex] = measure
        }
        return result
    }

    /// Remove ties that don't connect to the **immediately following** chord
    /// of the same voice and pitch. MuseScore's MusicXML importer requires
    /// the successor note to be both the next chord in the voice and carry
    /// a matching `tieBack`; ties that jump over intervening notes (e.g.
    /// `testUnterminatedTies`'s stray starts) are silently dropped.
    private static func dropUnmatchedTies(_ perStaff: [[Measure]]) -> [[Measure]] {
        perStaff.map { TieValidator.process($0) }
    }

    /// Scan the part for the first `<attributes><staves>N</staves>` and return
    /// `N`. Defaults to 1. Most piano parts declare `<staves>2</staves>` in the
    /// first measure's attributes.
    private static func detectStaffCount(partNode: XMLTreeNode) -> Int {
        for measure in partNode.all("measure") {
            for attrs in measure.all("attributes") {
                if let stavesText = attrs.first("staves")?.text,
                   let staves = Int(stavesText), staves >= 1
                {
                    return staves
                }
            }
        }
        return 1
    }

    /// Decode a single `<measure>`. Returns `staffCount` `Measure` values —
    /// one per staff — and how far the measure's content reaches.
    /// Attributes and barlines broadcast to every staff; `<note>` elements
    /// go to the staff selected by `<staff>N</staff>` (default 1).
    ///
    /// Notes still go to voices in document order; `cursor` follows
    /// `<duration>` / `<backup>` / `<forward>` only to place what has no
    /// note of its own (tempo, chord symbols) and to measure the bar.
    private static func decodeOne(
        measureNode: XMLTreeNode,
        state: inout WalkState,
        isFirstMeasure: Bool,
        staffCount: Int,
        drumTable: MusicXMLDrumTable,
        measureIndex: Int,
    ) throws -> (built: [StaffMeasureBuilder.Built], contentLength: Fraction) {
        var perStaff: [StaffMeasureBuilder] = (0 ..< staffCount).map { _ in
            StaffMeasureBuilder()
        }
        var cursor = MusicXMLMeasureCursor()

        for child in measureNode.children {
            switch child.name {
            case "attributes":
                let emitted = AttributesDecoder.decode(
                    node: child,
                    divisions: &state.divisions,
                    previous: &state.attributes,
                    isFirstMeasure: isFirstMeasure,
                    staffCount: staffCount,
                )
                appendAttributes(emitted, to: &perStaff)

            case "note":
                cursor.advance(overNote: child, divisions: state.divisions)
                try appendNote(
                    child,
                    to: &perStaff,
                    context: NoteContext(
                        divisions: state.divisions, transposition: state.attributes.transposition,
                        drumTable: drumTable, measureIndex: measureIndex,
                    ),
                    glideTracker: &state.glideTracker,
                )

            case "direction":
                appendDirection(
                    child, to: &perStaff,
                    at: cursor.position(of: child, divisions: state.divisions),
                )

            case "harmony":
                appendHarmony(child, to: &perStaff, cursor: cursor, divisions: state.divisions)

            case "sound":
                // A measure-level `<sound tempo>` (not inside a `<direction>`).
                if let tempo = MusicXMLTempoDecoder.decode(sound: child), !perStaff.isEmpty {
                    perStaff[0].addTempo(tempo, at: cursor.time)
                }

            case "backup":
                cursor.backup(child, divisions: state.divisions)

            case "forward":
                cursor.forward(child, divisions: state.divisions)

            case "barline":
                let decoded = MusicXMLBarlineDecoder.decode(child)
                for builder in perStaff.indices {
                    perStaff[builder].apply(barline: decoded)
                }
                if let ending = decoded.ending {
                    state.voltaTracker.consume(ending, measureIndex: measureIndex)
                }

            default:
                // <print>, <figured-bass>, ... — out of scope.
                continue
            }
        }

        let measureLength = state.nominalLength ?? Fraction(numerator: 4, denominator: 4)
        return (perStaff.map { $0.build(measureLength: measureLength) }, cursor.length)
    }
}

// `StaffMeasureBuilder` lives in `StaffMeasureBuilder.swift` next to this
// file.
