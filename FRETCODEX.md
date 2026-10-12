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
- **Fork tests** live in `Tests/SheetMusicTests/MusicXML/FretCodex*.swift`, with fixtures
  written inline and owned by FretCodex (`FretCodexFixtures.swift` records their provenance).
- `Scripts/fretcodex-check-consumer-lite.sh` names the package `swift-sheet-music`, which SwiftPM
  takes from the checkout's directory name. Run it from a checkout (or a symlink to one) with
  that name.

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
  suffix only (`""`, `"m7"`, `"7"`, `"maj7"`). An ending is a volta `Spanner` on the part's first
  staff, begin side only. A bar whose content differs from its time signature has
  `actualLength`; `implicit="yes"` sets `irregular`. Both are set on every staff.

## Must not change

- `NotatedClef.init(rawType:)` stays non-failable. Unknown clefs collapse to treble; 18 call
  sites and EditWire depend on that.
- With `SWIFT_SHEET_MUSIC_DEV=1`, the manifest stays identical to upstream's: same targets,
  dependencies, pins and `Package.resolved`.
- MSCX encoder output stays byte-stable.
- Public initialisers only gain parameters with defaults.
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
- `Sources/SheetMusicMusicXML/Decoders` and `Internal` (F1);
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
