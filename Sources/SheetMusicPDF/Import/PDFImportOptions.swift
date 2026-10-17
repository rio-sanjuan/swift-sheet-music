import Foundation

/// Non-fatal recognition issues surfaced from `PDFImporter`.
///
/// `Sendable` because the callback that delivers it already is: a host that
/// parses off the main actor collects these on the parse's thread and reads
/// them back on its own.
public struct PDFImportDiagnostic: Sendable {
    public enum Severity: Sendable { case info, warning }
    public let severity: Severity
    public let location: String // e.g. "page 3, system 2, measure 17"
    public let message: String
    public let context: String?

    public init(
        severity: Severity, location: String,
        message: String, context: String? = nil,
    ) {
        self.severity = severity
        self.location = location
        self.message = message
        self.context = context
    }
}

/// `Sendable` so a host can build the options once and hand them to the
/// parse wherever it runs it: every stored value is a plain value, a
/// `@Sendable` closure, or a `Sendable` protocol existential.
public struct PDFImportOptions: Sendable {
    public var preserveBreaks = true
    public var useMetadataAsFallback = true
    /// Expand a collapsed "N-bar" multi-measure rest (the H-bar captioned
    /// with a count) back into its N constituent measures, so the imported
    /// score's measure count matches the uncollapsed source. Enabled by
    /// default; disable to keep each mm-rest as the single bar MuseScore drew.
    public var expandMultiMeasureRests = true
    /// Enable Tier 4 (outline shape matching) in the glyph classification
    /// cascade. **Default OFF.**
    ///
    /// Tier 4's acceptance threshold cannot be chosen without measuring it
    /// against Tier 1's known-correct answer. At the original placeholder
    /// threshold, with no per-font gate, it matched essentially every glyph
    /// outline — including Latin text and CJK lyrics — to some Bravura
    /// exemplar: on ギブス.pdf, 0 of 4254 glyphs were left `.unknown` and
    /// lyric recall collapsed to 0%. Both the measured threshold and the
    /// gate now exist, but flipping this default is its own decision, to be
    /// made on a measurement of unknown-font accuracy (last measured: 63.3%
    /// against a Bravura-only exemplar set — short of useful).
    public var enableShapeMatching = false
    /// TESTING ONLY, INTERNAL. Suppress Tier 1 (SMuFL codepoint)
    /// classification so the shape-matching tier can be measured against
    /// Tier 1's known-correct answer. Never set this in production; it
    /// degrades every SMuFL PDF.
    ///
    /// Not `public`: its only caller is the measurement harness, which
    /// already reaches internals through `@testable import SheetMusicPDF`.
    /// A public symbol cannot be withdrawn without a breaking change, and
    /// the package is past 1.0 — so a knob that exists to break the
    /// importer on purpose stays inside the module. Same for
    /// `anchorMusicGlyphsToPUARange` and `bypassMusicFontGateForTesting`
    /// below.
    var disableSMuFLCodepointTier = false
    /// TESTING ONLY, INTERNAL. Anchors the music/text routing decision in `emitShow`
    /// to whether the raw decoded codepoint falls in the SMuFL PUA range,
    /// ignoring which (if any) tier supplied the glyph's `SMuFLSemantic`.
    ///
    /// Exists so the Tier-1 ablation (toggling `disableSMuFLCodepointTier`)
    /// promotes the IDENTICAL set of codepoints to `ClassifiedGlyph` in both
    /// the truth and probe runs — only the assigned semantic may differ,
    /// making `truth.count == probe.count` hold by construction. Without
    /// this, Tier 4 (with Tier 1 disabled) also shape-matches non-music
    /// glyph outlines — lyric / title text from an unrelated embedded font
    /// — and wrongly promotes them into the music stream, desynchronizing
    /// any positional comparison against Tier 1's answer. A no-op whenever
    /// Tier 1 is enabled (Tier 1 only ever answers PUA-range codepoints), so
    /// this only ever changes behavior in combination with
    /// `disableSMuFLCodepointTier`. Never set this in production.
    var anchorMusicGlyphsToPUARange = false
    /// TESTING ONLY, INTERNAL. Skips the per-font music-font gate
    /// (`GlyphClassifier.isLikelyMusicFont`) so `enableShapeMatching` behaves
    /// exactly as it did before that gate existed — Tier 4 answers for
    /// every embedded font's glyphs, not just the ones the gate accepts.
    ///
    /// Exists so the Tier-4 ablation (`tier4Ablation`) keeps measuring Tier
    /// 4's raw per-glyph classification accuracy against Tier 1's
    /// known-correct answer, independent of font-level eligibility — the
    /// ablation already anchors to the PUA range (see
    /// `anchorMusicGlyphsToPUARange`), so it doesn't need the gate for
    /// correctness, and letting the gate filter individual font resources
    /// mid-ablation (measured: it wrongly declines a real 3-glyph "Bravura"
    /// resource in ロビンソン.pdf — too small a sample to pass the fraction
    /// test) would entangle two different measurements. The gate is a
    /// PRODUCTION safeguard; this flag keeps it out of that measurement.
    /// Never set this in production.
    var bypassMusicFontGateForTesting = false
    /// TESTING ONLY, INTERNAL. Overrides `GlyphClassifier`'s default
    /// per-font music-font gate knobs (see its `default*` constants) for
    /// every `GlyphClassifier` this parse creates. Not `public` — reached
    /// only from within `SheetMusicPDF` or via `@testable import` — because
    /// these are instance configuration on an internal type, not a stable
    /// public knob. Exists so a test that must go through the real
    /// `PDFImporter.parse(pdfData:options:)` entry point (rather than
    /// constructing a `GlyphClassifier` directly) can loosen or tighten the
    /// gate without mutating shared process-global state — see
    /// `PDFImporterShapeMatchingGateTests`'
    /// `noGateAtPlaceholderThresholdReproducesTask12Collapse`.
    ///
    /// The literal defaults below MUST track `GlyphClassifier`'s
    /// `default*` constants — duplicated rather than referenced because
    /// `GlyphClassifier` is CoreText-backed and excluded from the Android
    /// build (see `Package.swift`), while this file (and the rest of
    /// `PDFImportOptions`) is not.
    var musicFontGateBound = 0.10
    var musicFontGateFraction = 0.5
    var shapeAcceptanceThreshold = 0.15
    public var diagnostics: (@Sendable (PDFImportDiagnostic) -> Void)?

    /// A tile classifier for pages the vector path cannot read. `nil` — the
    /// default — means the importer behaves exactly as it always has: no
    /// rasterization, no detection, no new pass over the pages.
    ///
    /// Takes the tile classifier rather than a glyph detector because the
    /// detector's seam mentions importer internals; the importer builds
    /// `OMRGlyphDetector(classifier:)` from this.
    ///
    /// The PDFKit entry points act on it: `PDFImporter.parse(pdfData:)` /
    /// `parse(pdfURL:)` and their `parseWithGeometry` twins (whose side-car
    /// carries no rects for the pages read this way). `parseUsingSwiftReader`
    /// and the Android entry emit an `info` diagnostic saying they do not,
    /// rather than ignoring it silently.
    public var omrTileClassifier: (any OMRTileClassifier)?

    /// Resolution at which a page with no vector content is rasterized. The
    /// training corpus's DPI grid is 200/300/400, so 300 sits mid-distribution.
    ///
    /// Values below `PDFImporter.minimumRenderDPI` (72 — one pixel per point),
    /// and non-finite ones, are clamped with a `warning` diagnostic rather
    /// than silently rasterizing a 1x1 page.
    public var omrRenderDPI: Double = 300

    /// How close, in staff spaces, a notehead must sit to one END of a
    /// raster-detected vertical for that vertical to be the note's stem;
    /// nil — the default — for the measured 0.5 (see `isStem`).
    ///
    /// For a host whose pages are photographs: a camera's blur and a
    /// straightening's resampling move a stem's end and its notehead apart
    /// by more than a scan does, and at 0.5 the stem is refused and the
    /// note read as a quarter or a half. 0.75 is the value measured for
    /// that through FretCodex's `PageReader`, which sets it for photos only
    /// — on its clean and scanned pages it costs aligned note F 0.007, so it
    /// is a per-parse choice, not a new default. Vector pages never read it.
    public var omrStemHeadEndTolerance: Double?

    /// Whether the raster staff-line finder keeps beams out of the lines it
    /// finds. Off by default.
    ///
    /// The finder takes a row inked 50 points or more across, three quarters
    /// of it, for a line, and a beam's rows are that too: one lying across a
    /// space joins two lines into one blob, which gives one line, and one
    /// within a space adds a sixth; either way the staff is lost with its
    /// system. On, a blob is split into the lines a beam joined
    /// (`RasterPage.linesInBlob`), and a blob thicker than a line and
    /// narrower than a system is not one (`RasterPage.isBeam`). For a host
    /// reading photographs, where a page is often held closer than 300 dpi
    /// and a beam's 50 points are a few staff spaces long.
    public var omrKeepsBeamsOutOfStaffLines = false

    /// Whether a system whose staves are coupled into parts unlike the
    /// reference system's still fills the parts staff by staff, from the top,
    /// rather than part by part. Off by default.
    ///
    /// A raster system's coupling comes from a brace glyph the detector sees
    /// on one system and misses on the next, so a piano reads as one part of
    /// two staves in one system and two parts of one staff in the next. Part
    /// by part, the first such system's second staff — or the second part —
    /// has nowhere to go, and is dropped. On, the reference coupling is the
    /// one most of the richest systems read, and a system coupled otherwise,
    /// with no more staves, puts its staves into the reference's slots in
    /// order.
    public var omrCouplesByStaves = false

    /// Whether every staff's key signature reading is reported as an `info`
    /// diagnostic: the one at its system's start, as read — "none" too — and
    /// the courtesy key signature at its system's end, when there is one.
    /// Off by default.
    ///
    /// The score holds a key signature only where the key changes, so a
    /// system that read its key again and one that lost it look alike in it.
    /// A host that checks one system's key against the others — a photo's
    /// key signatures are a handful of small glyphs, read short or lost a
    /// system at a time — needs to know which systems read the key, and
    /// whether a change at a system break was announced before it.
    public var omrReportsKeyReadings = false

    /// TESTING ONLY, INTERNAL. Substitutes the whole glyph-detection stage so the
    /// harness can replay labels or precomputed detections through the product
    /// path. Takes precedence over `omrTileClassifier`. Not `public` for the same
    /// reason as `disableSMuFLCodepointTier`: a knob whose purpose is to bypass
    /// the real detector cannot be withdrawn once it is API.
    var omrDetector: (any OMRGlyphDetecting)?

    public init() {}
}
