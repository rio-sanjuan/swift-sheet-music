# The FretCodex fork

This branch, `fretcodex/main`, is upstream swift-sheet-music plus the smallest delta FretCodex
needs. It is released as tags `<upstream>-fretcodex.<n>`, for example `4.5.0-fretcodex.1`.
FretCodex pins those tags with `exact:`.

The decision and its evidence are FretCodex's `docs/adr/0001-sheet-music-fork-strategy.md`.
This file is the working summary for whoever syncs the fork.

## The delta

| | What | Files |
|---|---|---|
| **F0** | **Consumer-lite product gate.** The products that reach Wirelet or SwiftySynth (`SheetMusicAudioCore`, `SheetMusicEditWire`, `SheetMusicPages`, `SheetMusicPDFWriter`, `SheetMusicAudio`, `SheetMusicAudioApple`, `SheetMusicAudioSwiftySynth`) and the `render-previews` executable are declared only when `SWIFT_SHEET_MUSIC_DEV=1`, or when an upstream platform flag implies it. Targets and package dependencies are untouched. | `Package.swift` |
| | The fork's notes and the F0 check script | `FRETCODEX.md`, `Scripts/fretcodex-check-consumer-lite.sh` |
| **F1** | **MusicXML tab and chart import.** A MusicXML part decodes into the `Score` an equivalent MSCX gives: `<technical><string>`/`<fret>` → `Note.string` (n − 1) / `Note.fret`; `<staff-tuning>` → `Instrument.stringData`; `<staff-details><capo>` → `.capo`; the TAB clef → a tablature staff; `<clef-octave-change>` → MuseScore's octave clefs; `<transpose>` → the instrument's transposition, with pitches and keys stored at concert pitch. For charts: `<sound tempo>` / `<metronome>` → `.tempo`; `<harmony>` → `.harmony`; `<ending>` → the volta `Spanner`; short or implicit bars → `Measure.actualLength` / `irregular`. Additive; MSCX untouched. See *Reading a MusicXML score* below. | `Sources/SheetMusicMusicXML/Decoders/` (`+Attributes`, `+Barline`, `+Harmony`, `+HarmonyKind`, `+Measure`, `+MeasureContent`, `+Note`, `+PartShape`, `+StaffDetails`, `+TabPosition`, `+Tempo`, `MusicXMLDecoder.swift`, `MusicXMLVoltaTracker.swift`, `StaffMeasureBuilder.swift`), `Sources/SheetMusicMusicXML/Internal/` (`MusicXMLTransposition`, `MusicXMLMeasureCursor`, `MusicXMLMeasureLength`, `MusicXMLHarmonyPlacement`, `PitchDecoder`) |
| | F1's tests, on fixtures FretCodex owns | `Tests/SheetMusicTests/MusicXML/FretCodex*.swift` |
| **F2** | **Bug fixes from FretCodex's tracker.** MSCX encoder: a whole-bar `.measure` chord is written as its bar's note value instead of trapping (SM-1); a chord or grace takes up to four dots (MuseScore's `MAX_DOTS`), and one no note value spells throws `mscx.encoder.chordDurationNotRepresentable` instead of writing a file nothing reads (SM-2). A voice-level spanner's end side keeps its `<prev><location>` — new `Spanner.prevMeasuresOffset` / `prevFractionsOffset` — so MuseScore can pair a re-saved volta, hairpin or ottava again (SM-4). MusicXML: an `<ending>` decodes into the volta's begin AND end side (SM-15); `<grace>` notes decode into grace chords that take no time (SM-9). The consumer-lite check runs from a checkout of any name (SM-16). See *Volta end sides*, *Graces in MusicXML* and *Writing durations to MSCX* below. | `Sources/SheetMusicCore/Score/Spanner.swift`, `ScoreFingerprint.swift` (doc only); `Sources/SheetMusicMSCX/Decoders/MSCXDecoder+Spanner.swift`; `Sources/SheetMusicMSCX/Encoders/` (`+Chord`, `+NoteDuration`, `+Spanner`, `+Voice+Emit`, `+Voice+EncodeChord`, `+Voice+Helpers`); `Sources/SheetMusicMusicXML/Decoders/` (`+Grace`, `+Measure`, `+MeasureContent`, `+Note`, `MusicXMLDecoder.swift`, `MusicXMLGraceRun.swift`, `MusicXMLVoltaTracker.swift`, `StaffMeasureBuilder.swift`); `Scripts/fretcodex-check-consumer-lite.sh` |
| | F2's tests; and the preservation gate's allowlist loses two entries F2 made stale (`location/measures`, `prev/location`) | `Tests/SheetMusicTests/MSCX/FretCodexMSCX*.swift`, `Tests/SheetMusicTests/MusicXML/FretCodexMusicXML{Endings,Grace}Tests.swift`; `Tests/SheetMusicTests/MSCXPreservationGateTests.swift` |

**Why F0 exists.** SwiftPM fetches the package dependencies of every target reachable from
**any product a package declares**, whichever products a consumer actually links. Upstream
declares the audio, edit-wire, pages and PDF-writer products unconditionally, so every
consumer fetches:
- swift-wirelet;
- swiftysynth;
- swift-syntax (including a 115 MB prebuilt);
- swift-java-jni-core.

Two of those float through `from:` requirements. Removing only the product declarations brings
that to zero.

## Working on this branch

- **Building or testing the whole package** (CI, local work): set `SWIFT_SHEET_MUSIC_DEV=1`.
  The manifest is then upstream's exactly, apart from product order.
- **Without the flag**, the root still builds every target, but declares only the consumer
  products.
- **Fork tests** live in `Tests/SheetMusicTests/MusicXML/FretCodex*.swift` and
  `Tests/SheetMusicTests/MSCX/FretCodex*.swift`, with fixtures written inline and owned by
  FretCodex (`FretCodexFixtures.swift` records their provenance).
- `Scripts/fretcodex-check-consumer-lite.sh` addresses the package by the identity SwiftPM gives a
  path dependency — the checkout directory's name, lowercased — so it runs from a checkout of any
  name. Unset `SWIFT_SHEET_MUSIC_DEV` first: it checks the consumer shape.

## Reading a MusicXML score (after F1)

F1's tests are `FretCodexMusicXMLTabTests`, `FretCodexMusicXMLTabStaffTests`,
`FretCodexMusicXMLTransposeTests` and `FretCodexMusicXMLChartTests`; the last covers tempo,
chord symbols, endings and pickups.

- **Pitch is concert (sounding) in both formats.** `Note.pitch` / `Note.tpc` sound. A
  transposing part says so in `Instrument.transposeDiatonic` / `transposeChromatic` (guitar
  −7 / −12); key signatures are concert keys. `Score.writtenPitchView()` gives the written page.
  The instrument carries the *opening* `<transpose>`; a later one still converts the notes after
  it, but is not modeled on the instrument. A `<transpose number="…">` applies to the whole part.
- **Strings.** `Note.string` 0 is the **highest** string (MusicXML `<string>` n is n − 1).
  `StringData.strings` is listed low → high, so string `s` is tuned to `strings[count − 1 − s]`.
  A flat-spelled tuning has `useFlat`. A MusicXML tuning has 25 frets (MusicXML has no fret
  count) and its pitches as `<staff-tuning>` spells them, with no `<transpose>` applied —
  MuseScore's exporter writes them sounding, as MSCX stores them.
  `<fret>` / `<string>` are read on any staff that gives them; most files give them only on the
  tab staff, whereas an MSCX standard staff linked to a tab carries them too.
- **Tab staves.** Test `Staff.group == "tablature"` in both formats. `staffType` is
  `tab<N>StrCommon` (`tab6StrCommon` outside 4…10 lines) and there is no
  `staffTypePreservedMarkup`: read the preset's defaults. The `"TAB"` clef is an opening
  `.clef` element in MusicXML and `Staff.defaultClefType` in MSCX; `NotatedClef` reads it as a
  treble either way.
- **Pairing a tab staff with its pitched staff.** MSCX: the tab staff's `Staff.preservedMarkup`
  holds `<linkedTo>` (an index or an EID). MusicXML has no such markup and F1 invents none:
  pair the `tablature` staff with the pitched staff **of the same part** (MusicXML's usual
  guitar form, `<staves>2</staves>`), chord by chord by measure and position. A file that
  writes standard and tab as two parts has no structural link; pairing those is the consumer's
  heuristic (adjacent parts, same instrument or part name).
- **Capo.** `<staff-details><capo>` is a `.capo` element on the staff that carried it.
  MusicXML defines the capo as raising the open strings, so the decoder leaves pitches alone and
  `tuning + capo + fret == pitch`. An MSCX `<pitch>` is the capo *shape*: `tuning + fret ==
  pitch` and it sounds `pitch + capo`. Branch on `Score.source == .musicXML`.
- **Charts.** A tempo is a `.tempo` system element at its time in the bar, quarter-normalised,
  one per position across parts. A chord symbol is a `.harmony` voice element before the chord
  at its time (or wrapped in a balanced `.locationShift` pair between onsets), `name` being the
  suffix only (`""`, `"m7"`, `"7"`, `"maj7"`). An ending is a volta pair on the part's first
  staff — begin side and end side, as MSCX holds it (see *Volta end sides*). A bar whose content
  differs from its time signature has `actualLength`; `implicit="yes"` sets `irregular`. Both are
  set on every staff.
- **Graces** (after F2) are `GraceChord`s on `Chord.graceNotesBefore` / `graceNotesAfter`, never
  voice elements — see *Graces in MusicXML*.

## Volta end sides (after F2)

MuseScore writes a voice-level spanner (volta, hairpin, ottava, pedal, …) as two `<Spanner>`
elements and pairs them on load **only when their locations agree**; an unpaired one is dropped.

- The **begin side** is a visible `Spanner` with the payload (`voltaEndings`, `beginText`, …) and
  `nextMeasuresOffset` / `nextFractionsOffset` — `<next><location>`.
- The **end side** is an invisible `Spanner` (`visible: false`, no payload) where the spanner ends,
  with `prevMeasuresOffset` / `prevFractionsOffset` — `<prev><location>`: the begin side's offsets
  negated. Both default to `0` / `nil`, which writes the bare `<prev/>` every end side got before
  F2 (and which MuseScore never pairs).

The MSCX decoder fills both fields from any `<Spanner>`, so a MuseScore file re-saves with its
pairs intact. The encoder writes an end side only where the voice holds one; it never synthesizes
one from a begin side. The editing commands write begin sides only and do not move an end side's
`prev` offsets when they move bars — an edit that changes a decoded spanner's length leaves its
end side pointing at the old begin.

**Building a volta in code** (what FretCodex's exporter needs, replacing its preserved-markup
end side). A first ending covering `n` bars from bar `b`, voice 0 of the part's first staff:

```swift
// Bar b, on the downbeat — anywhere before the bar's first chord or rest:
.spanner(Spanner(kind: .volta, rawType: "Volta", nextMeasuresOffset: n,
                 voltaEndings: [1], beginText: "1."))
// Bar b + n — the bar after the ending — on its downbeat too, ahead of a begin side starting there:
.spanner(Spanner(kind: .volta, rawType: "Volta", prevMeasuresOffset: -n, visible: false))
```

(The MusicXML decoder puts both after the bar's clef / key / time / capo and downbeat chord
symbol, where MuseScore writes them; `SetVolta` puts a begin side at index 0. Any spot before the
first chord or rest is the downbeat to MuseScore's reader.)

An ending whose last bar is the **score's last bar** ends on the score's final tick, which
MuseScore keeps inside that bar at its length `L` (the bar's effective length, `actualLength` if
set): the begin side is `nextMeasuresOffset: n - 1, nextFractionsOffset: L`, and the end side,
`prevMeasuresOffset: -(n - 1), prevFractionsOffset: -L`, goes at the END of that last bar's voice 0
(after its content, ahead of a trailing `.barLine`).

The end side built this way encodes to exactly the `<Spanner type="Volta"><prev><location>…`
FretCodex's `.preserved(PreservedXML(name: "Spanner", …))` workaround writes
(`FretCodexMSCXVoltaTests.builtEndSideMatchesPreservedWorkaround` pins it), so swapping one for the
other changes no output. Use one or the other per end side, not both: the encoder writes each
element it is given, so both would give two end sides. Read back, either form decodes to the
modeled end side.

## Graces in MusicXML (after F2)

A `<grace>` note decodes into the `GraceChord` the MSCX decoder gives the same notes, following
MuseScore's importer:

- **Kind.** `slash="yes"` → `.acciaccatura`; otherwise the written `<type>` picks `.grace4`
  (quarter), `.grace16`, `.grace32`, and anything else (an eighth) is `.appoggiatura`.
  `GraceChord.duration` is the written `<type>` + dots (`.eighth` if there is none). A `<chord/>`
  grace joins the grace chord before it.
- **No time.** A grace is never a voice element: onsets, chord-symbol and tempo placement and
  bar lengths are what they would be without it.
- **Which chord.** The next ordinary chord of the same voice takes the waiting graces as
  `graceNotesBefore` (a rest leaves them waiting). A run that ends a slur or a trill's wavy line
  belongs AFTER the previous chord, and graces no chord follows in the bar go after the bar's last
  chord: `.appoggiatura` → `.grace8after`, `.grace16` / `.grace32` → their `…after` forms;
  `.acciaccatura` and `.grace4`, having no after form, land in that chord's `graceNotesBefore`, as
  in MuseScore. `graceNotesAfter` is in sounding (document) order.
- **Kept / dropped.** The note keeps pitch (concert), spelling, accidental, ties, parentheses and
  `<string>` / `<fret>`. A fermata on a grace becomes a `.fermata` in the voice where the grace
  stood, ahead of the chord that follows it. Grace articulations, lyrics, breath marks and
  `steal-time-*` / `make-time` are dropped; a grace rest is ignored.

## Writing durations to MSCX (after F2)

- A `<Chord>` (a chord or a grace) is written as a note value with **up to four dots**
  (MuseScore's `MAX_DOTS`). A chord whose duration has no such spelling — five dots, an irregular
  fraction outside a tuplet, a stray `.measure` on a grace — makes `MSCXEncoder.encode` throw
  `SheetMusicError.malformedScore` with code `mscx.encoder.chordDurationNotRepresentable`.
  Rests keep their `<durationType>measure</durationType>` + `<duration>` fallback.
- A **whole-bar chord** (`.measure` with notes) is written as its bar's note value — a whole in
  4/4, a dotted half in 3/4 — and reads back as that concrete value, not as `.measure`. A bar no
  single value fills (5/4, 4/2) throws the same error; split such a chord into tied chords first.

## Must not change

- `NotatedClef.init(rawType:)` stays non-failable. Unknown clefs collapse to treble; 18 call
  sites and EditWire depend on that.
- With `SWIFT_SHEET_MUSIC_DEV=1`, the manifest stays identical to upstream's: same targets,
  dependencies, pins and `Package.resolved`.
- MSCX encoder output stays byte-stable. (F2's one deliberate change: an end side decoded from
  a file writes back the `<prev><location>` it was read with, where it used to write a bare
  `<prev/>` that MuseScore could not pair. Scores built in code encode as before.)
- Public initialisers only gain parameters with defaults.
- An end side's `<prev><location>` round-trips (`Spanner.prevMeasuresOffset` /
  `prevFractionsOffset`), and the MSCX encoder never synthesizes an end side (F2).
- Nothing from `Tests/SheetMusicTests/Resources/` (GPL-3.0 MuseScore fixtures) leaves this
  repository. Fork tests use fixtures FretCodex owns.

## Syncing with upstream

Sync when a fix or feature FretCodex needs lands, otherwise at most once per FretCodex
milestone. Take the newest upstream tag at that point.

1. `git fetch origin --tags`
2. `git checkout -b fretcodex/sync-<tag> <tag>`. Re-apply F0 by its rule rather than by
   patch: gate whichever declared products reach Wirelet or SwiftySynth *now*.
3. Cherry-pick the remaining delta commits.
4. `Scripts/fretcodex-check-consumer-lite.sh` must print `OK`.
5. `SWIFT_SHEET_MUSIC_DEV=1 swift test`
6. Run FretCodex's Notation round-trip tests against the branch, using the workspace's
   sibling checkout.
7. Fast-forward `fretcodex/main`, then tag `<tag>-fretcodex.1`.

**Check on every sync:**
- the products in `Package.swift`;
- `Sources/SheetMusicMusicXML/Decoders` and `Internal` (F1, F2);
- `Spanner`'s fields and the MSCX spanner decoder / encoder; `NoteDuration`'s MSCX encoder and the
  voice encoder's chord path (F2);
- the preservation gate's allowlist (`MSCXPreservationGateTests`) — F2 deleted two entries;
- `NotatedClef`;
- `ScoreView`'s initialiser and `playbackCursor`;
- `PDFImportOptions` and the OMR types;
- the preserved-markup fields on `Staff` and `Note`;
- the `EID` and `IdentifiedArray` APIs.

## Licences FretCodex must acknowledge

- `Sources/`: MIT.
- Bravura: OFL 1.1, bundled in `SheetMusicLayoutApple`.
- The OMR model: MIT, per the README.
- The Adobe Glyph List table in `SheetMusicPDF`: Apache-2.0.
