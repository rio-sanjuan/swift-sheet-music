#if SHEET_MUSIC_HAS_APPLE_PLATFORM_TEST_SUPPORT
    import CoreGraphics
    import Foundation
    @testable import SheetMusicCore
    @testable import SheetMusicPDF
    import Testing

    /// A bar built by hand at staff space `sp` (in points): a staff whose bottom line is at y 100,
    /// heads, stems, beams, flags and dots placed in staff spaces. For the bar repair's tests.
    struct RepairBarBuilder {
        var sp: CGFloat
        var glyphs: [ClassifiedGlyph] = []
        var paths: [PathSegment] = []
        var xRange: ClosedRange<CGFloat> = 0 ... 400

        var lines: [CGFloat] { (0 ..< 5).map { 100 + CGFloat($0) * sp } }
        /// y of a staff position: 0 the bottom line, 1 the space above it, … in half spaces.
        func y(_ step: CGFloat) -> CGFloat { 100 + step * sp / 2 }

        mutating func glyph(_ semantic: SMuFLSemantic, x: CGFloat, y: CGFloat) {
            glyphs.append(ClassifiedGlyph(
                geometry: GlyphGeometry(origin: CGPoint(x: x, y: y), advance: 1.18 * sp, renderedSize: 4 * sp,
                                        pageIndex: 0, fontSize: 0),
                semantic: semantic,
            ))
        }

        /// A head at `x` (points) on staff step `step`, its stem `up` (3.5 sp) or down; returns the
        /// stem's bare-end y.
        @discardableResult
        mutating func note(x: CGFloat, step: CGFloat, up: Bool = true, filled: Bool = true, stem: Bool = true,
                           stemGap: CGFloat = 0) -> CGFloat {
            let headY = y(step)
            glyph(filled ? .noteheadBlack : .noteheadHalf, x: x, y: headY)
            guard stem else { return headY }
            let stemX = up ? x + 1.18 * sp : x
            let near = up ? headY + stemGap * sp : headY - stemGap * sp
            let far = up ? headY + 3.5 * sp : headY - 3.5 * sp
            paths.append(PathSegment(
                kind: .vertical, rect: CGRect(x: stemX, y: min(near, far), width: 0, height: abs(far - near)),
                lineWidth: 0.1 * sp, pageIndex: 0, quad: nil, detectedFromRaster: true,
            ))
            return far
        }

        /// A beam line 0.5 sp thick whose top edge runs from (x0, y0) to (x1, y1).
        mutating func beam(from x0: CGFloat, _ y0: CGFloat, to x1: CGFloat, _ y1: CGFloat) {
            let slope = (y1 - y0) / (x1 - x0)
            let intercept = y0 - slope * x0
            let quad = BeamQuad(xRange: x0 ... x1, topSlope: slope, topIntercept: intercept,
                                botSlope: slope, botIntercept: intercept - 0.5 * sp, pageIndex: 0)
            paths.append(PathSegment(
                kind: .beam, rect: CGRect(x: x0, y: min(y0, y1) - 0.5 * sp, width: x1 - x0, height: abs(y1 - y0) + 0.5 * sp),
                lineWidth: 0.5 * sp, pageIndex: 0, quad: quad, detectedFromRaster: true,
            ))
        }

        var measure: ImportMeasure { ImportMeasure(xRange: xRange, glyphs: glyphs, staffYLines: lines) }

        func decoded() -> [PDFImporter.DecodedPitch] {
            PDFImporter.decodePitches(measure: measure, activeClef: Clef(concertClefType: "G"), activeKey: KeySignature(concertKey: 0))
        }

        func decode(_ passes: BarRepairPasses = [], tolerance: CGFloat = 0.5) -> ([RhythmElement], BarEvidence) {
            PDFImporter.decodeRhythmWithEvidence(
                measure: measure, decoded: decoded(), paths: paths, tieMarks: PDFImporter.TieMarks(), graceSizeThreshold: 0,
                stemHeadEndTolerance: tolerance, passes: passes,
            )
        }

        func legacy(tolerance: CGFloat = 0.5) -> [RhythmElement] {
            PDFImporter.decodeRhythm(measure: measure, decoded: decoded(), paths: paths, stemHeadEndTolerance: tolerance)
        }
    }

    @Suite("FretCodex — the raster bar repair (F4): ink passes")
    struct FretCodexBarRepairMarksTests {
        static let spatia: [CGFloat] = [4.6, 6.0, 7.9]

        static func durations(_ elements: [RhythmElement]) -> [NoteDuration] { elements.map(\.chord.duration) }

        // MARK: - The evidence builder

        @Test(arguments: spatia)
        func withNoPassItReadsAsDecodeRhythm(sp: CGFloat) {
            var b = RepairBarBuilder(sp: sp)
            let e1 = b.note(x: 20, step: 2)
            let e2 = b.note(x: 20 + 3 * sp, step: 4)
            b.beam(from: 20 + 1.18 * sp, e1, to: 20 + 4.18 * sp, e2)
            b.note(x: 20 + 7 * sp, step: 3, filled: false)
            b.glyph(.augmentationDot, x: 20 + 8.4 * sp, y: b.y(3) + 0.5 * sp)
            let (elements, _) = b.decode()
            let legacy = b.legacy()
            #expect(Self.durations(elements) == Self.durations(legacy))
            #expect(elements.map(\.x) == legacy.map(\.x))
            #expect(elements.map(\.chord.notes) == legacy.map(\.chord.notes))
            #expect(elements.map(\.stemDirection) == legacy.map(\.stemDirection))
        }

        @Test(arguments: spatia)
        func theBeamEvidenceIsTheSameAtEverySize(sp: CGFloat) {
            var b = RepairBarBuilder(sp: sp)
            // Two eighths, a stub owned by a stem no full beam reaches, a beam ending 2 sp short.
            let e1 = b.note(x: 20, step: 2)
            let e2 = b.note(x: 20 + 3 * sp, step: 2)
            b.beam(from: 20 + 1.18 * sp, e1, to: 20 + 4.18 * sp, e2)
            let e3 = b.note(x: 20 + 8 * sp, step: 2)
            b.beam(from: 20 + 9.18 * sp - 1.2 * sp, e3 - 0.75 * sp, to: 20 + 9.18 * sp, e3 - 0.75 * sp)
            let e4 = b.note(x: 20 + 13 * sp, step: 2)
            b.beam(from: 20 + 15.18 * sp, e4, to: 20 + 18 * sp, e4)
            let (_, bar) = b.decode()
            let byX = bar.stems.sorted { $0.x < $1.x }
            #expect(byX.map(\.levelHint) == [1, 1, 1, 0])
            #expect(byX.map(\.fullCount) == [1, 1, 0, 0])
            #expect(byX[2].stubImpliesPrimary)
            #expect(byX[3].extrapolated && !byX[0].extrapolated)
            #expect(byX[0].groupRoot == byX[1].groupRoot && byX[0].groupSize == 2)
        }

        // MARK: - P7: the ledger band

        static func staff(_ bottom: CGFloat, sp: CGFloat) -> SheetMusicPDF.Staff {
            SheetMusicPDF.Staff(pageIndex: 0, yLines: (0 ..< 5).map { bottom + CGFloat($0) * sp }, xRange: 0 ... 400, barlineCandidates: [])
        }

        static func head(_ semantic: SMuFLSemantic = .noteheadBlack, y: CGFloat) -> ClassifiedGlyph {
            ClassifiedGlyph(geometry: GlyphGeometry(origin: CGPoint(x: 50, y: y), advance: 6, pageIndex: 0), semantic: semantic)
        }

        @Test(arguments: spatia)
        func aLedgerHeadSixSpacesUpAndFourAndAHalfDownIsItsStaffs(sp: CGFloat) {
            let staff = Self.staff(100, sp: sp)
            let up = Self.head(y: 100 + 4 * sp + 6 * sp)
            let down = Self.head(y: 100 - 4.5 * sp)
            let wide = PDFImporter.filterGlyphs(classified: [up, down], staff: staff, lo: 0, hi: 400, noteheadBandSpaces: 7)
            #expect(wide.count == 2)
            let narrow = PDFImporter.filterGlyphs(classified: [up, down], staff: staff, lo: 0, hi: 400)
            #expect(narrow.count == 1, "upstream's 5 spaces keep only the lower one")
        }

        @Test func aHeadInATightGapIsCapturedByOneStaff() {
            let sp: CGFloat = 6
            let lower = Self.staff(100, sp: sp), upper = Self.staff(100 + 4 * sp + 9 * sp, sp: sp)
            let bands = [lower, upper].map { (lo: $0.yLines.min()!, hi: $0.yLines.max()!) }
            let head = Self.head(y: 100 + 4 * sp + 5 * sp) // 5 sp over the lower, 4 under the upper
            let captured = [lower, upper].map { staff in
                PDFImporter.filterGlyphs(
                    classified: [head], staff: staff, lo: 0, hi: 400,
                    clamp: PDFImporter.neighborBandClamp(top: staff.yLines.max()!, bottom: staff.yLines.min()!, bands: bands),
                    noteheadBandSpaces: 7,
                ).count
            }
            #expect(captured == [0, 1])
        }

        @Test func flagCaptureIsUnchanged() {
            let sp: CGFloat = 6
            let staff = Self.staff(100, sp: sp)
            let flags = [5.5, 6.5, 7].map { Self.head(.flag8thUp, y: 100 + 4 * sp + $0 * sp) }
            #expect(PDFImporter.filterGlyphs(classified: flags, staff: staff, lo: 0, hi: 400, noteheadBandSpaces: 7)
                == PDFImporter.filterGlyphs(classified: flags, staff: staff, lo: 0, hi: 400))
        }

        // MARK: - P1: dots by column

        static func dotted(_ b: RepairBarBuilder) -> [Int] {
            var (elements, bar) = b.decode()
            PDFImporter.applyDotColumns(&elements, bar: bar, apply: true)
            return elements.map { $0.evidence?.dots ?? -1 }
        }

        @Test(arguments: spatia)
        func aDottedChordWithASecondTakesOneDot(sp: CGFloat) {
            var b = RepairBarBuilder(sp: sp)
            // D4 E4 (a second, E mirrored right) G4 B4 on one up stem; one dot per head, in one column.
            for step: CGFloat in [-3, 1, 3] { b.glyph(.noteheadBlack, x: 20, y: b.y(step)) }
            b.glyph(.noteheadBlack, x: 20 + 1.18 * sp, y: b.y(-2))
            b.paths.append(PathSegment(kind: .vertical, rect: CGRect(x: 20 + 1.18 * sp, y: b.y(-3), width: 0, height: 7.5 * sp),
                                       lineWidth: 0.1 * sp, pageIndex: 0, quad: nil, detectedFromRaster: true))
            for step: CGFloat in [-3, -1, 1, 3] { b.glyph(.augmentationDot, x: 20 + 2.9 * sp, y: b.y(step)) }
            #expect(Self.dotted(b) == [1])
        }

        @Test(arguments: spatia)
        func aDotHalfASpaceAboveALineNoteIsItsOwn(sp: CGFloat) {
            var b = RepairBarBuilder(sp: sp)
            b.note(x: 20, step: 2)
            b.glyph(.augmentationDot, x: 20 + 1.6 * sp, y: b.y(2) + 0.5 * sp)
            #expect(Self.dotted(b) == [1])
            // Upstream's window stops 1.35 head widths (1.59 spaces) right of the head, and its
            // 4-point bound in y refuses the dot once a space is 8 points.
            #expect(b.legacy().first?.chord.duration == .quarter)
        }

        @Test func aStaccatoIsNoDot() {
            var b = RepairBarBuilder(sp: 6)
            b.note(x: 20, step: 2, up: false)
            b.glyph(.augmentationDot, x: 20 + 0.3 * 1.18 * 6, y: b.y(2) - 0.6 * 1.18 * 6)
            #expect(Self.dotted(b) == [0])
        }

        @Test(arguments: spatia)
        func neighboursKeepTheirOwnDots(sp: CGFloat) {
            var b = RepairBarBuilder(sp: sp)
            b.note(x: 20, step: 2)
            b.glyph(.augmentationDot, x: 20 + 1.6 * sp, y: b.y(2) + 0.5 * sp)
            b.note(x: 20 + 2.6 * sp, step: 3)
            b.note(x: 20 + 5 * sp, step: 4)
            b.glyph(.augmentationDot, x: 20 + 6.6 * sp, y: b.y(5))
            #expect(Self.dotted(b) == [1, 0, 1])
        }

        @Test func noDotIsOwnedTwice() {
            var b = RepairBarBuilder(sp: 6)
            // Two heads a step apart in x, a dot in reach of both: the nearer takes it.
            b.note(x: 20, step: 2, stem: false)
            b.note(x: 20 + 1.0 * 6, step: 2, stem: false)
            b.glyph(.augmentationDot, x: 20 + 2.6 * 6, y: b.y(2))
            #expect(Self.dotted(b).reduce(0, +) == 1)
        }

        // MARK: - P2: flags in spaces

        static func flagged(_ b: RepairBarBuilder) -> [NoteDuration] {
            var (elements, bar) = b.decode()
            PDFImporter.applyFlagsInSpaces(&elements, bar: bar, flagBand: PDFImporter.staffBeamBand(b.lines), apply: true)
            return elements.map(\.chord.duration)
        }

        @Test(arguments: spatia)
        func aFlagAtTheMeasuredOffsetsAttaches(sp: CGFloat) {
            var b = RepairBarBuilder(sp: sp)
            let bare = b.note(x: 20, step: 2)
            b.glyph(.flag8thUp, x: 20 + 1.18 * sp - 0.15 * sp, y: bare - 0.2 * sp)
            let down = b.note(x: 20 + 4 * sp, step: 6, up: false)
            b.glyph(.flag16thDown, x: 20 + 4 * sp - 0.15 * sp, y: down + 0.2 * sp)
            #expect(Self.flagged(b) == [.eighth, .sixteenth])
        }

        @Test func aFlagBesideAHollowHeadIsNoQuarter() {
            var b = RepairBarBuilder(sp: 6)
            let bare = b.note(x: 20, step: 2, filled: false)
            b.glyph(.flag8thUp, x: 20 + 1.18 * 6 - 0.15 * 6, y: bare - 0.2 * 6)
            var (elements, bar) = b.decode()
            #expect(elements[0].chord.duration == .quarter, "upstream halves the half")
            PDFImporter.applyFlagsInSpaces(&elements, bar: bar, flagBand: PDFImporter.staffBeamBand(b.lines), apply: true)
            #expect(elements[0].chord.duration == .half)
            #expect(elements[0].evidence?.otherFill == true)
        }

        // MARK: - P3: beam rescue

        static func rescued(_ b: RepairBarBuilder, tolerance: CGFloat = 0.5) -> [NoteDuration] {
            var (elements, bar) = b.decode([.beamRescue], tolerance: tolerance)
            PDFImporter.applyBeamRescue(&elements, bar: bar)
            return elements.map(\.chord.duration)
        }

        @Test(arguments: spatia)
        func aBeamWhosePartnerStemWasRefusedStillMakesAnEighth(sp: CGFloat) {
            var b = RepairBarBuilder(sp: sp)
            let e1 = b.note(x: 20, step: 2)
            // The second stem stops a space short of its head: the head-end gate refuses it.
            let e2 = b.note(x: 20 + 3 * sp, step: 2, stemGap: 1.0)
            b.beam(from: 20 + 1.18 * sp, e1, to: 20 + 4.18 * sp, e2)
            #expect(Self.durations(b.legacy()) == [.quarter, .quarter])
            #expect(Self.rescued(b) == [.eighth, .eighth])
        }

        @Test(arguments: spatia)
        func aBeamWhoseMiddleIsInTheNextBarStillCounts(sp: CGFloat) {
            var b = RepairBarBuilder(sp: sp)
            b.xRange = 0 ... (20 + 3 * sp)
            let e1 = b.note(x: 20, step: 2)
            b.beam(from: 20 + 1.18 * sp, e1, to: 20 + 9 * sp, e1)
            #expect(Self.durations(b.legacy()) == [.quarter])
            #expect(Self.rescued(b) == [.eighth])
        }

        @Test func aNoteWithNoBeamNearbyIsUnchanged() {
            var b = RepairBarBuilder(sp: 6)
            b.note(x: 20, step: 2)
            let far = b.note(x: 80, step: 2)
            b.beam(from: 81.18, far + 6 * 3, to: 120, far + 6 * 3)
            #expect(Self.rescued(b) == [.quarter, .quarter])
        }
    }
#endif
