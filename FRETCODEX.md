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
| **F3** | **Photo-reading options for the raster path.** Four `PDFImportOptions`, all off by default, so a parse that sets none reads as before: `omrStemHeadEndTolerance` (the stem gate for one parse; FretCodex sets 0.75 for photos), `omrKeepsBeamsOutOfStaffLines` (a beam's blob split from the lines it joins or refused as a line, SM-26), `omrCouplesByStaves` (a system coupled unlike the reference filled staff by staff, SM-28), `omrReportsKeyReadings` (every system's key reading and courtesy key reported as diagnostics, SM-22). And one fix with no option: a courtesy key past a system's final double barline is no longer dropped with its note-free cell (`ImportMeasure.droppedTrailingGlyphs`, read only by `readCourtesyKey`). Measured through FretCodex's `PageReader` in its ADR 0006, round 2. See *Photo options* below. | `Sources/SheetMusicPDF/Import/` (`PDFImportOptions`, `Internal`, `+Assemble`, `+AssembleParts`, `+ClefConsensus`, `+KeyReader`, `+Layout`, `+RasterFallback`, `+Rhythm`, `+ScoreState`); `Sources/SheetMusicPDF/OMR/RasterFrontEnd.swift`; `Sources/SheetMusicPDF/Raster/` (`RasterPage`, `+StaffLineBlobs`, `+StaffLines`) |
| | F3's tests | `Tests/SheetMusicTests/FretCodex{OMRStemTolerance,OMRBeamLine,Coupling,KeyReport}Tests.swift` |
| **F4** | **A bar repair for raster pages.** `PDFImportOptions.omrBarRepair`, off by default, and `omrBarRepairPasses` (`BarRepairPasses`, one bit a pass, `.all` by default). On, a page the raster fallback read takes a new branch in `buildOneMeasure`: a notehead on a stem toward its staff captured 7 spaces from it, not 5 (P7), dots counted by column in spaces (P1), beam lines counted at each stem's bare end (P3), heads grouped into column chords, a whole note a chord of its own unless it sits on the column's stem (P4), one voice split, by upstream's trigger, for repair, voices and geometry, and a voice that does not sum repaired by the cheapest evidence-backed changes or left as read with a warning (P6); a time signature in a dropped leading cell reaches the first bar (`.leadingTime`, SM-38). A page's text layer is read on the branch as the legacy chain reads it. Voice 0's tuplets survive a prepended clef, key or time on that branch (`prependingScoreStateKeepingTuplets`, SM-32). A vector page never takes the branch: with the option on, a vector PDF reads byte for byte as before. `rasterPages` now reaches `buildOneMeasure` and `layoutSystems`. Measured through FretCodex's `PageReader` in its ADR 0006, round 3. See *Bar repair* below. | `Sources/SheetMusicPDF/Import/` (`BarRepairPasses`, `PDFImportOptions`, `+BarRepair`, `+BarRepairEvidence`, `+BarRepairMarks`, `+BarRepairChords`, `+BarRepairVoices`, `+BarRepairSearch`, `+BarRepairProbe`, `+Assemble`, `+Layout`, `+GlyphCapture`, `PDFImporter`, `+TimeReader`; access widened in `Internal`, `+Rhythm`, `+BeamGroups`, `+RhythmReconcile`, `+RhythmReconcileTuplet`, `+Voicing`) |
| | F4's tests, on bars built by hand and on pieces written for them; round 3's review cases and the textures the bench lacks (whole notes under a moving voice, graces, staccatos, double dots, a pickup, 3/8, 2/2, sextuplets, a tuplet numeral in a text layer, a signature in a dropped leading cell) | `Tests/SheetMusicTests/FretCodexBarRepair{,Unit,Marks,Chords,Search,Review,Texture}Tests.swift`, `FretCodexBarRepairFixtures.swift` |
| **F5** | **Systems where the host says they are.** `PDFImportOptions.omrSystemBands`, nil by default: for page `i`, one y-range per system, in the page's points. Staves whose middle line falls in one range are one system (`bandedSystems`), whatever joins them; a staff in none is its own. Nil, or a page past the array, finds systems as before — the spine clustering, then the gap heuristic. A raster page joins a system's staves only by a vertical run that covers them, no wider than a staff space; on a photo the system barline leans, breaks, or runs into the brace beside it, and a song's voice and piano read as three systems. Measured through FretCodex's `PageReader` on its Lieder bench, round 4. | `Sources/SheetMusicPDF/Import/` (`PDFImportOptions`, `PDFImporter`, `+Layout`) |
| | F5's tests | `Tests/SheetMusicTests/FretCodexSystemBandsTests.swift` |
| **F6** | **Triplet runs and mirrored chords in the bar repair.** Two passes, both in `BarRepairPasses.all`. `.tupletRuns`: every intact beam group of a voice that could be a triplet (or sextuplet), the same size, read as one together at a single tuplet's cost — continuous triplet accompaniment is several groups to a bar, the search takes one tuplet at most, and evenly spaced groups never show the gap a lone triplet's spacing test asks for. `.mirroredChords`: a stemmed column on the stem of the column before it joins that chord when any of its heads is a second from that column's, not every one — a chord's displaced head carries the heads above it across the stem, and P4 had split the chord and moved them later. Raster pages only; a vector page never reads these bits. Measured through FretCodex's `PageReader` on its Lieder bench (ADR 0006, round 4). | `Sources/SheetMusicPDF/Import/` (`BarRepairPasses`, `+BarRepairSearch`, `+BarRepairChords`) |
| | F6's tests | `Tests/SheetMusicTests/FretCodexBarRepairF6Tests.swift` |
| **F7** | **Tuplet numerals in the detector.** Five classes appended to the frozen vocabulary, `tuplet3`, `tuplet5`, `tuplet6`, `tuplet7` and `tuplet9` (`SMuFLSemantic.tupletDigit`, canonical `[52, n]`), read by a branch of their own: `SymbolNet.extra_head`, two 3×3 convolutions and a 1×1 on the shared features, its five channels after `heatmap_head`'s. Only the branch was trained (`train.py --init … --new-classes-only`), from the 62-class model's weights recovered from its compiled form, so every other output of the bundled model — each old class's heatmap, the offsets and the boxes — is the 4.5.0 model's exactly (Core ML, max difference 0). A full fine-tune on the same renders read the tuplets as well but lost notes on pages engraved unlike MuseScore 4's; a 1×1 on the frozen features alone read them at precision 0.03–0.70. Data: renders the fork's own generator made with MuseScore 4 (`fc-tuplets-v1`, `-v2`; 6:4 and 9:8 added to `gen_texture.py`'s tuplet kinds), numerals labelled from the renders' text where a beam or bracket anchors them. `RasterFrontEnd.tupletNumeralsAsText` gives each detected numeral to the page's texts as its digit, at its origin and size, so `detectTupletMarks` anchors it to its beam or bracket as on a vector page; `applyRasterFallback` now keeps a raster page's texts with its glyphs and paths (it had dropped them, so no numeral reached the repair). A new pass in `BarRepairPasses.all`, `.numeralRevert`: a bar whose numerals leave more voices unsummed than the bar read without them is read without them — a page prints a run's first numerals and leaves the rest understood, and marks on some of a voice's groups stop F6's `.tupletRuns` finishing it. The model grows from 1.1 MB to 1.3 MB. On 154 held-out pages every tuplet class has recall 1.000, precision 0.94 (3), 0.94 (5), 0.50 (6, of 6), 0.98 (7), 1.00 (9); trained on clean renders only. Measured through FretCodex's `PageReader` against 4.5.0-fretcodex.7 (its ADR 0006, round 4): tuplet notes read on its Lieder design songs 307 → 349 clean, 138 → 174 photo, 112 → 127 phone, 89 → 101 binder; on its confirm songs 70 → 100 clean, 0 → 21 photo; note values on its corpus 0.874 → 0.896 clean, 0.870 → 0.886 scan; aligned F unchanged on every set and level, its robustness pages unchanged, no page worse by more than 0.006. | `Sources/SheetMusicPDF/OMR/` (`OMRGlyphVocabulary`, `RasterFrontEnd`), `Sources/SheetMusicPDF/Import/` (`Internal`, `+Canonical`, `+RasterFallback`, `+BarRepair`, `BarRepairPasses`), `Sources/SheetMusicOMRModel/Resources/`, `Training/` (`model/net.py`, `model/train.py`, `model/export.py`, `generate/`) |
| | F7's tests; the vocabulary-size tests move to 67 trainable and 69 detector classes, in Swift and Python | `Tests/SheetMusicTests/FretCodex{OMRTupletNumeral,NumeralRevert}Tests.swift`, `OMRPrepUnitTests.swift`, `OMRLabelClassNamesTests.swift`; `Training/tests/` (`test_net`, `test_prep`, `test_vocabulary`, `test_gen_coverage`) |
| **F8** | **Detected tuplet numerals anchored as a song page sets them.** For a numeral the detector read (`TextGlyph.isDetectedNumeral`), and only for one, `detectTupletMarks` takes a band of 7 spaces outside the staff (`tupletDetectedBandSpatia`, 3 for a PDF's own) and `beamWindow` a beam up to 5 spaces from the digit (`tupletDetectedBeamTolSpatia`, 3). A song's triplets over notes far above or below the staff carry their numerals 3–6.6 spaces out, and on a photographed page a beam's fitted y and the numeral's wander 3.4–6.7 spaces apart; a mark still needs its anchor. `RasterFrontEnd.tupletNumeralsAsText` keeps one numeral to a place: the detector can read one numeral twice, as two classes at once or as one class a point apart across a tile seam, and of numerals closer than half their size the commoner digit is kept, then the first read. Measured through FretCodex's `PageReader` against `.8`: tuplet notes read on its Lieder design songs 349 → 398 clean, 174 → 224 photo, 127 → 138 phone, 101 → 115 binder; on its confirm songs 100 → 115 clean, 21 → 27 photo, 0 → 2 phone, 8 → 12 binder; aligned F unchanged on every set and level, its corpus and robustness pages unchanged. | `Sources/SheetMusicPDF/Import/PDFImporter+TupletMark.swift`, `Sources/SheetMusicPDF/OMR/RasterFrontEnd.swift` |
| | F8's tests | `Tests/SheetMusicTests/FretCodexTupletAnchoringTests.swift` |
| **F9** | **A phone profile for training (training only; nothing the package ships changes).** `Training/generate/profiles/phone.toml`: the residue of a phone photo after FretCodex's `PageReader` has found the page and squared and straightened it — resampling, a little perspective left over, slight rotation, bolder print, blur, grey paper with the sheet under it showing through, light falling off, a soft-edged shadow, noise, sharpening, JPEG — its amounts following FretCodex's calibrated `phone` level. New `degrade.py` stages: `perspective_warp` (a homography, so labels follow it like any geometric stage), `paper_and_ink`, `shadow`, `unsharp`. `build_dataset.py freeze` gains `--out-name`, so sets degraded by different profiles sit side by side, and `--workers`, byte-identical to one. `train.py --new-classes-only --init` takes a checkpoint as well as a bare state dict, and carries on a branch it already has. | `Training/generate/` (`degrade.py`, `build_dataset.py`, `profiles/phone.toml`), `Training/model/train.py` |
| | F9's tests | `Training/tests/test_degrade.py` |
| **F10** | **The tuplet-numeral branch trained on photographed pages as well.** The bundled model's `extra_head` carried on from F7's over the tuplet sets clean and degraded twice — by `profiles/scanner.toml` and F9's `profiles/phone.toml`, each page once with seed 20261024 — 6 epochs, nothing else training: every other output is still the 4.5.0 model's exactly (Core ML, max difference 0). Numeral recall on held-out phone-degraded pages: 3s 0.953 → 0.969, 5s 0.882 → 0.976, 7s 0.897 → 0.962; clean pages unchanged at 1.000. Measured through FretCodex's `PageReader` against `.9`: tuplet notes read on its Lieder design songs 398 → 404 clean, 224 → 248 photo, 138 → 158 phone, 115 → 127 binder; on its confirm songs 115 → 118 clean, 27 → 42 photo, 2 → 8 phone, 12 → 15 binder; corpus values 0.896 → 0.904 clean, 0.886 → 0.896 scan; aligned F unchanged on every set and level, robustness pages unchanged. Tuplet notes read on pages with none rise on degraded levels (design phone 8 → 14, binder 0 → 13; confirm photo 11 → 13, phone 6 → 8). | `Sources/SheetMusicOMRModel/Resources/` |
| **F11** | **A detected numeral's score as evidence.** The detector's score now reaches a numeral it read (`ClassifiedGlyph.score`, `TextGlyph.detectorScore`), and one scoring under 0.4 (`tupletWeakNumeralScore`; the detector keeps what scores over 0.3) is weak (`TupletMark.weak`). A weak 6 is set aside: it names a triplet's ratio (4:6 is 2:3), so a stray one makes a triplet of three eighths, and it is the detector's least precise numeral (F7: precision 0.50). A weak numeral anchored to a beam scales nothing when the beam's window holds more than twice its digit's notes (`applyTupletMarks`): its beam spans its tuplet, or two under one primary, not a run of 16. Found by tracing every detected numeral that scaled notes on FretCodex's Lieder bench: all of those on pages with no tuplets scored 0.30–0.37. Measured and left out: a weak numeral held to a PDF numeral's 3 spaces from its beam (it cost note values on FretCodex's rhythm studies, whose weak 3s sit 3–5 spaces from their beams); a run required to fit its digit, its length in its shortest member the digit times a power of two (a photographed triplet is often read with a member wrong before the repair puts it right, so true triplets were lost: confirm photo 42 → 34); the band tightened for weak numerals (47 true tuplet notes lost on the design songs, traced); the numeral required on the beam's side away from the noteheads (no separation, traced). Measured through FretCodex's `PageReader` against `.10`: tuplet notes read on pages with none, on its Lieder design songs 14 → 8 phone, 13 → 6 binder, photo 3 and clean 0 unchanged; on its confirm songs 13 → 11 photo, phone 8, binder 9 and clean 3 unchanged. Tuplet notes read on pages with tuplets unchanged at every level but design photo, 248 → 246 (a weak 6 over two notes; that page's values unchanged). Aligned F unchanged on every set and level, no page worse, three better; its corpus and robustness pages unchanged. | `Sources/SheetMusicPDF/Import/` (`Internal`, `+TupletMark`, `+TupletApply`), `Sources/SheetMusicPDF/OMR/` (`OMRGlyphDetector`, `RasterFrontEnd`) |
| | F11's tests | `Tests/SheetMusicTests/FretCodexNumeralEvidenceTests.swift` |
| **F12** | **Beams read net of a page's ink spread.** `PDFImportOptions.omrBeamInkSpread`, off by default. A raster beam is found by its ink's thickness, column by column, on a ladder of 0.5 staff spaces a beam and 0.25 between stacked ones; a photographed page's ink is bolder (on FretCodex's phone-photo bench a beam binarizes 0.6–0.7 spaces), so its beams fall off their rungs and their notes read as quarters. On, `RasterPage.inkSpreadPx` takes the page's commonest column-run thickness between 0.4 and 0.8 spaces — beams give the same run in every column, so they make the sharpest peak there, below a notehead's middle columns and above any staff line — and, when it is bolder than 0.5 spaces by half the ladder's tolerance or more, every run is read that much thinner before it meets the ladder. A page printed as engraved spreads nothing. Two other measures were tried and dropped: the staff lines' thickness (rounding at 12–21 px a space the beams do not share; photo values 0.781 → 0.697) and the median of a first reading's beams (sees only a bold page's thinnest; no gain). Measured through FretCodex's `PageReader` against `.11`: on its Lieder design songs note values 0.613 → 0.724 phone and 0.590 → 0.685 binder (aligned F +0.008, +0.007), 0.781 → 0.788 photo, clean unchanged; on its confirm songs 0.612 → 0.721 phone and 0.602 → 0.704 binder (aligned F +0.013, +0.010), photo and clean unchanged; tuplet notes read on phone pages 158 → 230 and 8 → 33; corpus and robustness pages unchanged. Tuplets read on binder pages that have none rise (6 → 22, 9 → 19): more beams for F6's run inference to read. | `Sources/SheetMusicPDF/Raster/` (`RasterPage`, `RasterPage+Beams`), `Sources/SheetMusicPDF/Import/` (`PDFImportOptions`, `+RasterFallback`), `Sources/SheetMusicPDF/OMR/RasterFrontEnd.swift` |
| | F12's tests | `Tests/SheetMusicTests/FretCodexBeamInkSpreadTests.swift` |

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

## Photo options (after F3)

A host reading photographs, not scans, sets these per parse on `PDFImportOptions`; each is off by
default and changes nothing for vector pages:

- `omrStemHeadEndTolerance: Double?` — how close, in staff spaces, a notehead must sit to an end
  of a raster vertical for it to be the note's stem (nil: the measured 0.5). A photo's blur moves
  the two apart; at 0.5 the stem is refused and an eighth read as a quarter. 0.75 costs clean and
  scanned pages about 0.007 aligned F, so it is not a default.
- `omrKeepsBeamsOutOfStaffLines: Bool` — a blob a beam joined to the lines is split back into them
  (`RasterPage.linesInBlob`), and a beam's own blob is not taken for a line (`RasterPage.isBeam`).
- `omrCouplesByStaves: Bool` — a system whose staves couple into fewer parts than the reference
  system's (a missed brace) is mapped staff by staff, not by part order, so no staff is dropped.
- `omrReportsKeyReadings: Bool` — every system's key reading, and the courtesy key at a system's
  end, is reported through `diagnostics`; a key element is still written only where the key
  changes, so a host can tell a system that read the key again from one that lost it.

## Bar repair (after F4)

`PDFImportOptions.omrBarRepair` acts on a page the raster fallback read (`rasterPages`), never
on a vector page. With it on, `buildOneMeasure` hands each bar to `buildRepairedMeasure`
(`PDFImporter+BarRepair`); with no pass on (`omrBarRepairPasses = []`) that branch is the
legacy chain exactly. The passes, in order, and whether `.all` takes them:

| Pass | Bit | What it does | In `.all` |
|---|---|---|---|
| P7 | `.ledgerBand` | A staff captures a notehead 7 spaces past its outer line, not 5, when a stem runs from it back toward the staff, with its accidental and dot. Past the five spaces it is clamped at the midpoint to every staff on the page, not only the system's, and only this page's heads near the bar count as far heads a sign may stand beside | yes |
| P4 | `.columnChords` | Heads grouped into columns (0.6 sp in x, a mirrored second across its column's stem); a column is one chord on the stem along every head, or a virtual stem when none was found — unless an up stem holds the upper heads and a down stem the lower (two chords). A whole or double-whole head never takes a stem: it is a chord of its own — unless a found stem runs along every other head and the "whole" sits within a quarter space of the stem's span, where it is a misread head of that chord and never sets its value | yes |
| | `.headKindRule` | A stemless column's black and hollow heads stay two notes | no |
| P1 | `.dotColumns` | Each dot owned by the nearest head to its left (0.8–2.2 sp by 0.75 sp), a note's dots its dot columns, at most two; a double dot's second (0.4–0.9 sp past the first) chained to it; a dot over or under a later note's head is that note's staccato, no dot | yes |
| P2 | `.flagsInSpaces` | Flags matched in spaces at the stem's bare end; a flag never shortens a hollow head | no |
| P3 | `.beamRescue` | A black stemmed note with no beam and no flag takes the beam lines hung from its stem's bare end; a stem the head-end gate refused is kept when a beam reaches its far end | yes |
| P5 | `.voiceRule` | Two voices only on opposite stems within a space, or a displaced rest. Not in `.all`: the branch splits voices with upstream's 3-point trigger, once, for repair, voices and geometry | no |
| P6 | `.repairSearch` | A voice that does not sum: the cheapest set of at most two (three with `.threeChanges`) evidence-backed changes that makes it sum exactly, or left as read with a "bar repair: … does not sum" warning. A beam level rises only to the lines hung from the stem's bare end and falls only to the lines counted at it; never from a flag, never below one. A meter with no positive denominator takes the legacy chain | yes |
| | `.extrapolatedBeams`, `.stubImpliesPrimary` | P6's alternatives: a beam line ending just short of the stem; a stub on a stem no full beam reaches | see `BarRepairPasses.all` |
| | `.tupletGroups` | P6's alternative: an intact beam group of 3 or 6 equal values, every stem with a line, spaced as a tuplet, starting on a beat (or on its own span when shorter than a beat), never in n/8 with n a multiple of 3 (3/8 included), as 3:2 or 6:4 at cost 2 — one change, so it beats two cost-1 straight changes | yes |
| | `.brokenTuplets` | With `.tupletGroups`: a beamed 2 or 5 and the black, unflagged, undotted note beside it whose line was lost, its stem the group's way and its bare end on one of the group's beam lines carried on, at cost 3 | no |
| | `.leadingTime` | A dropped leading cell — a clef's or signature's stroke taken for a barline — hands its time-signature glyphs, only those, to the first bar kept (FretCodex SM-38) | yes |
| | `.phantomGroups`, `.legacyFallback`, `.threeChanges`, `.revertRule`, `.revertEverywhere`, `.leaveUnfit` | Measured and left out (see `BarRepairPasses.all`); `.leaveUnfit` (no repair at all) and `.revertEverywhere` are for measuring only | no |

On the branch, voice 0's tuplets survive a prepended clef, key or time
(`prependingScoreStateKeepingTuplets`, FretCodex SM-32), `recordGeometry` takes the
placements the voices were built from, and a page's text — a scanned PDF's OCR layer, which
`applyRasterFallback` keeps — is read as the legacy chain reads it (tuplet numerals, then
lyrics), so with no pass on the branch is the legacy chain exactly on any raster page. `PDFImportOptions.barRepairProbe` (internal) is a
test-only sink for the geometry the windows were set from.

## Must not change

- `NotatedClef.init(rawType:)` stays non-failable. Unknown clefs collapse to treble; 18 call
  sites and EditWire depend on that.
- With `SWIFT_SHEET_MUSIC_DEV=1`, the manifest stays identical to upstream's: same targets,
  dependencies, pins and `Package.resolved`.
- MSCX encoder output stays byte-stable. (F2's one deliberate change: an end side decoded from
  a file writes back the `<prev><location>` it was read with, where it used to write a bare
  `<prev/>` that MuseScore could not pair. Scores built in code encode as before.)
- Public initialisers only gain parameters with defaults.
- With `omrBarRepair` off — the default — every page reads as before F4; with it on, every
  vector page still does (F4).
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
- the raster staff-line blobs, part coupling (`partSlotMapping`) and the key reader's courtesy
  key, with F3's options and `ImportMeasure.droppedTrailingGlyphs` (F3);
- `buildOneMeasure`, `decodeRhythm` and its helpers (`stemCluster`, `applyFlags`, `applyDots`,
  `buildChordNotes`), `beamLevels`, `reconcileVoiceGroup`, `voiceAssignment`,
  `prependingScoreState`, `recordGeometry` and `filterGlyphs`, which the bar repair calls or
  mirrors, and its identity gates (`FretCodexBarRepairTests`: a vector page byte for byte with
  the repair on; a raster page as before with it off or with no pass) (F4);
- the preserved-markup fields on `Staff` and `Note`;
- the `EID` and `IdentifiedArray` APIs.

## Licences FretCodex must acknowledge

- `Sources/`: MIT.
- Bravura: OFL 1.1, bundled in `SheetMusicLayoutApple`.
- The OMR model: MIT, per the README.
- The Adobe Glyph List table in `SheetMusicPDF`: Apache-2.0.
