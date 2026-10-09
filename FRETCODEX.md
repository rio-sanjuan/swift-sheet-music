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
| F1 | *Not yet.* MusicXML tab import (`<technical>` string/fret, `<staff-tuning>`, the TAB clef, `<clef-octave-change>`, `<transpose>`). Only if FretCodex puts MusicXML in v1 scope. | `Sources/SheetMusicMusicXML/Decoders/` |

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
- `Sources/SheetMusicMusicXML/Decoders`;
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
