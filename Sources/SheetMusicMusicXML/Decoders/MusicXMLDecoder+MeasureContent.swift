import SheetMusicCore
import SheetMusicFoundation
import SheetMusicXMLTools

/// The `<measure>` children `MusicXMLMeasureWalker.decodeOne` routes to a staff: notes, directions and chord symbols.
extension MusicXMLMeasureWalker {
    /// What a `<note>` needs from the walk beyond the note itself.
    struct NoteContext {
        let divisions: DivisionsContext
        /// The part's `<transpose>` in force: the note is stored at concert pitch.
        let transposition: MusicXMLTransposition
        let drumTable: MusicXMLDrumTable
        let measureIndex: Int
    }

    /// `<attributes>` emissions: a staff-targeted one (a clef, a capo) to its staff, the rest (key, time) to every
    /// staff.
    static func appendAttributes(_ emitted: [AttributesDecoder.Emission], to perStaff: inout [StaffMeasureBuilder]) {
        for emission in emitted {
            if let idx = emission.staffIndex {
                perStaff[idx].appendAttribute(emission.element)
            } else {
                for builder in perStaff.indices {
                    perStaff[builder].appendAttribute(emission.element)
                }
            }
        }
    }

    /// Decode a `<note>` onto the staff `<staff>` selects, in the voice `<voice>` names.
    static func appendNote(
        _ child: XMLTreeNode,
        to perStaff: inout [StaffMeasureBuilder],
        context: NoteContext,
        glideTracker: inout MusicXMLGlideTracker,
    ) throws {
        let staffIdx = noteStaffIndex(child, staffCount: perStaff.count)
        let voice = child.first("voice")?.text ?? "1"
        perStaff[staffIdx].setDefaultVoice(voice)
        let existing = perStaff[staffIdx].elements(forVoice: voice)
        let decoded = try MusicXMLNoteDecoder.decodeNote(
            node: child,
            divisions: context.divisions,
            existingVoiceElements: existing,
            drumTable: context.drumTable,
            transposition: context.transposition,
        )
        switch decoded {
        case let .foldIntoLastChord(note, duration, trailingBreaths, articulations):
            perStaff[staffIdx].foldIntoLastChord(
                voice: voice,
                note: note,
                duration: duration,
                articulations: articulations,
            )
            // Breath marks / caesuras on a chord-folded note still
            // belong after the host chord, which is the same chord
            // we just merged into.
            for breath in trailingBreaths {
                perStaff[staffIdx].append(.breath(breath), toVoice: voice)
            }
        case let .new(elements):
            for element in elements {
                perStaff[staffIdx].append(element, toVoice: voice)
            }
        case let .grace(grace):
            // No voice element of its own, so nothing for a glissando to
            // be recorded against.
            perStaff[staffIdx].appendGrace(grace, toVoice: voice)
            return
        }
        // Glissando / slide events on this note: record the
        // chord's voice + index now (after append) so the
        // post-walk pass can mutate the start chord in place.
        // For fold-into-chord notes, the chord index didn't
        // change — `count - 1` still points at the same chord.
        if let voiceIdx = perStaff[staffIdx].voicePositionIndex(forVoice: voice) {
            let elements = perStaff[staffIdx].elements(forVoice: voice)
            let chordIdx = elements.count - 1
            if chordIdx >= 0 {
                glideTracker.consume(
                    noteNode: child,
                    staffIndex: staffIdx,
                    measureIndex: context.measureIndex,
                    voiceIndex: voiceIdx,
                    chordElementIndex: chordIdx,
                )
            }
        }
    }

    /// A `<direction>`'s navigation marks, rehearsal marks and tempo, all on the part's first staff.
    static func appendDirection(
        _ child: XMLTreeNode,
        to perStaff: inout [StaffMeasureBuilder],
        at position: Fraction,
    ) {
        guard !perStaff.isEmpty else { return }
        // MuseScore attaches measure-level jumps/markers to the
        // first staff only, matching the .mscx layout where they
        // live on `<Staff id="1">`'s `<Measure>`.
        let navigation = MusicXMLJumpDecoder.decode(child)
        perStaff[0].addMarkers(navigation.markers)
        perStaff[0].addJumps(navigation.jumps)
        // Rehearsal marks ride on the same `<direction>` element
        // as a `<direction-type><rehearsal>` child. Attach to
        // staff 0 so they match the MSCX `RehearsalMark` shape
        // (system-flagged, drawn once above the top staff).
        for mark in MusicXMLRehearsalDecoder.decode(child) {
            perStaff[0].addRehearsalMark(mark)
        }
        // A tempo is system-level too; it keeps its time in the bar.
        if let tempo = MusicXMLTempoDecoder.decode(direction: child) {
            perStaff[0].addTempo(tempo, at: position)
        }
    }

    /// A `<harmony>` on the staff its `<staff>` names (the part's first by default), at the cursor plus its
    /// `<offset>`.
    static func appendHarmony(
        _ child: XMLTreeNode,
        to perStaff: inout [StaffMeasureBuilder],
        cursor: MusicXMLMeasureCursor,
        divisions: DivisionsContext,
    ) {
        guard let decoded = MusicXMLHarmonyDecoder.decode(child), !perStaff.isEmpty else { return }
        let staffIndex = decoded.staffIndex.flatMap { perStaff.indices.contains($0) ? $0 : nil } ?? 0
        perStaff[staffIndex].addHarmony(decoded.harmony, at: cursor.position(of: child, divisions: divisions))
    }

    /// Read `<note><staff>N</staff>` and convert to a 0-based staff index.
    /// Defaults to 0 when absent or out of range.
    static func noteStaffIndex(_ note: XMLTreeNode, staffCount: Int) -> Int {
        guard let text = note.first("staff")?.text, let n = Int(text), n >= 1 else {
            return 0
        }
        return min(n - 1, staffCount - 1)
    }
}
