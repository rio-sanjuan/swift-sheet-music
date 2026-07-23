# Adding a clef

`NotatedClef.init?(rawType:)` is **failable**: an unrecognized MuseScore
clef string returns `nil`, and each call site chooses its fallback
explicitly (layout and rendering default to `?? .treble`). That keeps
"unknown clef" visible at the seam instead of silently misrendering —
when you add a clef, the compiler and this checklist are the whole
job:

1. **`NotatedClef`** (`Sources/SheetMusicCore/Score/NotatedClef.swift`)
   — add the case, its `init?(rawType:)` spellings (MuseScore's
   canonical string + any legacy aliases), and the `rawType` inverse.
2. **`SMuFLCodepoint`**
   (`Sources/SheetMusicLayout/Engraving/SMuFLCodepoints.swift`) — add
   the glyph's SMuFL codepoint, and mirror it as a `Character` in
   `Sources/SheetMusicUI/Rendering/SMuFLGlyph.swift`.
3. **`ClefGlyph.glyph(for:)`**
   (`Sources/SheetMusicLayout/Engraving/ClefGlyph.swift`) — codepoint
   + staff-space Y offset from the middle line. Mirror the same
   pairing in the CALayer path
   (`Sources/SheetMusicUI/Rendering/ScoreLayerBuilder+Notation.swift`)
   and the hit-test offset table
   (`Sources/SheetMusicUI/Selection/ScoreHitTester.swift`,
   `clefYOffset`).
4. **Pitch mapping — pitched clefs only**
   (`Sources/SheetMusicLayout/Layout/PitchStaffPosition.swift`) — add
   the `midLineDiatonic` arm (which diatonic pitch sits on the middle
   line), and its MIDI mirror in
   `Sources/SheetMusicMIDI/Import/ClefInference.swift`
   (`midLineMIDIPitch`). Non-pitched clefs (percussion, tab) use a
   positional B4 fallback here — they place notes by drum line / string
   index, not by pitch.

The exhaustive switches over `NotatedClef` in those files mean a new
case fails the build until every arm exists — that's intentional.

Verify the glyph actually exists in the bundled Bravura font before
shipping (`CTFontGetGlyphsForCharacters` at runtime, or a render test
asserting ink at the clef position).
