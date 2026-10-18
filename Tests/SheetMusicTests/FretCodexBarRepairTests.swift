#if SHEET_MUSIC_HAS_APPLE_PLATFORM_TEST_SUPPORT
    import CoreGraphics
    import Foundation
    import PDFKit
    import SheetMusicLayoutApple
    @testable import SheetMusicCore
    @testable import SheetMusicMSCX
    @testable import SheetMusicPDF
    import Testing

    /// FretCodex fork, F4: `PDFImportOptions.omrBarRepair`. The gates every pass is held to — a
    /// vector page reads byte for byte as before with the option on, and a raster page reads as
    /// before with the option off, or with it on and every pass off.
    ///
    /// The "raster" pages here are vector exports read as a raster front end hands them over:
    /// the same glyphs, every path marked `detectedFromRaster`, and the page listed as one the
    /// fallback read — so the repair's branch is taken over real engraving geometry.
    @MainActor
    @Suite("FretCodex — the raster bar repair (F4): identity gates")
    struct FretCodexBarRepairTests {
        /// MSCX fixtures in this repository, exported through `PDFExporter`.
        nonisolated static let fixtures = [
            "midi01", "midi02", "midi03", "repeat52", "repeat53", "multiPartMixedStaves",
            "grace_after", "testSingleNoteDynamics", "testMeasureRepeats", "testVoltaTemp",
            "legacybend_ms3_play_and_beams", "slur_ms3_exchangevoices", "staff-line-count",
            "own/grace-notes", "own/voice-annotations", "own/staff-elements", "own/ornaments",
            "own/fingerings",
        ]

        nonisolated static var bravuraAvailable: Bool {
            guard #available(macOS 15.0, *) else { return false }
            return BravuraFont.register
        }

        static func pdf(_ name: String) throws -> Data? {
            guard #available(macOS 15.0, iOS 16.0, *) else { return nil }
            let parts = name.split(separator: "/").map(String.init)
            let url = parts.count == 2
                ? TestResources.url(forResource: parts[1], withExtension: "mscx", subdirectory: parts[0])
                : TestResources.url(forResource: name, withExtension: "mscx")
            guard let url, let score = try? MSCXParser.parse(Data(contentsOf: url)) else { return nil }
            return try? PDFExporter.export(score: score)
        }

        /// Every fixture that exports, with its PDF: the repair's own pieces first, then the
        /// repository's MSCX fixtures.
        static func corpus() throws -> [(name: String, data: Data)] {
            var out: [(name: String, data: Data)] = []
            if #available(macOS 15.0, iOS 16.0, *) {
                out.append((name: "study", data: try PDFExporter.export(score: FretCodexBarRepairFixtures.study())))
                out.append((name: "triplets", data: try PDFExporter.export(score: FretCodexBarRepairFixtures.triplets())))
            }
            out += try fixtures.compactMap { name in try pdf(name).map { (name: name, data: $0) } }
            #expect(out.count >= 8, "too few fixtures exported: \(out.map(\.name))")
            return out
        }

        /// MSCX with its element IDs taken out: two parses mint different ones.
        static func mscxWithoutIDs(_ score: Score) throws -> String {
            let text = String(decoding: try MSCXEncoder.encode(score), as: UTF8.self)
            return text.split(separator: "\n").filter { !$0.contains("<eid>") }.joined(separator: "\n")
        }

        /// Every pass the repair has, whether or not `.all` takes it yet.
        nonisolated static let every = BarRepairPasses(BarRepairPasses.names.map(\.pass))

        static func repairOn(_ passes: BarRepairPasses = every) -> PDFImportOptions {
            var options = PDFImportOptions()
            options.omrBarRepair = true
            options.omrBarRepairPasses = passes
            return options
        }

        /// `data` read as a raster front end would hand it over (see the suite's note).
        static func rasterLike(_ data: Data, options: PDFImportOptions) throws -> Score {
            let document = try PDFImporter.openDocument(data)
            let walk = try PDFImporter.walkDocument(document)
            var content = walk.content
            content.paths = content.paths.map {
                var path = $0
                path.detectedFromRaster = true
                return path
            }
            content.texts = []
            content.curves = []
            return try PDFImporter.buildScore(
                pageCount: document.pageCount, walked: content, pageSizes: walk.pageSizes,
                documentAttributes: walk.attributes, options: options,
                rasterPages: Set(0 ..< document.pageCount),
            )
        }

        static func sameGeometry(_ a: PDFScoreGeometry, _ b: PDFScoreGeometry) -> Bool {
            a.itemRects == b.itemRects && a.noteRects == b.noteRects && a.measureRects == b.measureRects
                && a.systemRects == b.systemRects
        }

        @Test(.enabled(if: bravuraAvailable))
        func aVectorPageReadsByteForByteWithTheRepairOn() throws {
            for (name, data) in try Self.corpus() {
                let off = try PDFImporter.parse(pdfData: data)
                let on = try PDFImporter.parse(pdfData: data, options: Self.repairOn())
                #expect(off == on, "\(name): Score")
                #expect(try Self.mscxWithoutIDs(off) == Self.mscxWithoutIDs(on), "\(name): MSCX")
                let geometryOff = try PDFImporter.parseWithGeometry(pdfData: data).geometry
                let geometryOn = try PDFImporter.parseWithGeometry(pdfData: data, options: Self.repairOn()).geometry
                #expect(Self.sameGeometry(geometryOff, geometryOn), "\(name): geometry")
            }
        }

        @Test(.enabled(if: bravuraAvailable))
        func aRasterPageReadsAsBeforeWithTheRepairOffOrEveryPassOff() throws {
            for (name, data) in try Self.corpus() {
                let before = try Self.rasterLike(data, options: PDFImportOptions())
                var off = Self.repairOn()
                off.omrBarRepair = false
                #expect(try Self.rasterLike(data, options: off) == before, "\(name): option off")
                #expect(try Self.rasterLike(data, options: Self.repairOn([])) == before, "\(name): no pass")
            }
        }

        /// `rasterLike` with the front end's streams shuffled first: `buildScore` sorts them into
        /// one canonical order, so the repair must read the same.
        static func rasterLike(_ data: Data, options: PDFImportOptions, shuffledWith seed: UInt64) throws -> Score {
            let document = try PDFImporter.openDocument(data)
            let walk = try PDFImporter.walkDocument(document)
            var content = walk.content
            var rng = SplitMix(seed: seed)
            content.paths = content.paths.map {
                var path = $0
                path.detectedFromRaster = true
                return path
            }.shuffled(using: &rng)
            content.glyphs.shuffle(using: &rng)
            content.texts = []
            content.curves = []
            return try PDFImporter.buildScore(
                pageCount: document.pageCount, walked: content, pageSizes: walk.pageSizes,
                documentAttributes: walk.attributes, options: options,
                rasterPages: Set(0 ..< document.pageCount),
            )
        }

        @Test(.enabled(if: bravuraAvailable))
        func aRasterPageReadsAlikeEveryTimeInAnyOrder() throws {
            guard #available(macOS 15.0, iOS 16.0, *) else { return }
            for written in try [FretCodexBarRepairFixtures.study(), FretCodexBarRepairFixtures.triplets()] {
                let data = try PDFExporter.export(score: written)
                let first = try Self.mscxWithoutIDs(Self.rasterLike(data, options: Self.repairOn()))
                for seed in 0 ..< 10 {
                    #expect(try Self.mscxWithoutIDs(Self.rasterLike(data, options: Self.repairOn())) == first)
                    #expect(try Self.mscxWithoutIDs(Self.rasterLike(data, options: Self.repairOn(), shuffledWith: UInt64(seed))) == first)
                }
            }
        }

        /// The repair's cost on a dense page: a generous bound for a debug build (the release
        /// figure is FretCodex's bench time a page).
        @Test(.enabled(if: bravuraAvailable))
        func theRepairCostsLittleTime() throws {
            guard #available(macOS 15.0, iOS 16.0, *) else { return }
            let data = try PDFExporter.export(score: FretCodexBarRepairFixtures.study())
            func time(_ options: PDFImportOptions) throws -> Double {
                let start = DispatchTime.now().uptimeNanoseconds
                for _ in 0 ..< 5 { _ = try Self.rasterLike(data, options: options) }
                return Double(DispatchTime.now().uptimeNanoseconds - start) / 5e6
            }
            let off = try time(PDFImportOptions())
            let on = try time(Self.repairOn())
            print("FretCodex bar repair: \(String(format: "%.1f", on - off)) ms a page over \(String(format: "%.1f", off)) (debug)")
            #expect(on - off < 50)
        }

        /// Every value, chord and voice of a raster-like page, bar by bar.
        static func describe(_ score: Score) -> [String] {
            guard let staff = score.parts.values.first?.staves.values.first else { return [] }
            return staff.measures.map { measure in
                measure.voices.map { voice in
                    let spans = voice.tupletSpans.map { "[\($0.startIndex)-\($0.endIndex) \($0.actualNotes):\($0.normalNotes)]" }
                    return voice.elements.values.compactMap { element -> String? in
                        guard case let .chord(chord) = element else { return nil }
                        let pitches = chord.notes.values.map { String($0.pitch) }.joined(separator: "+")
                        return "\(pitches.isEmpty ? "r" : pitches):\(chord.duration)"
                    }.joined(separator: " ") + spans.joined()
                }.joined(separator: " / ")
            }
        }

        static func dottedBars(_ score: Score) -> Set<Int> {
            guard let staff = score.parts.values.first?.staves.values.first else { return [] }
            return Set(staff.measures.indices.filter { i in
                staff.measures[i].voices.contains { voice in
                    voice.elements.values.contains { element in
                        guard case let .chord(chord) = element, case let .fraction(f) = chord.duration else { return false }
                        return f.numerator == 3 || f.numerator == 7
                    }
                }
            })
        }

        /// The written pieces read back through the repair as engraved: no bar the legacy chain
        /// reads as written is read otherwise.
        @Test(.enabled(if: bravuraAvailable))
        func theRepairKeepsEveryBarTheLegacyChainReadsAsWritten() throws {
            guard #available(macOS 15.0, iOS 16.0, *) else { return }
            for written in try [FretCodexBarRepairFixtures.study(), FretCodexBarRepairFixtures.triplets()] {
                let data = try PDFExporter.export(score: written)
                let truth = Self.describe(written)
                let legacy = Self.describe(try Self.rasterLike(data, options: PDFImportOptions()))
                let repaired = Self.describe(try Self.rasterLike(data, options: Self.repairOn()))
                // The export draws no augmentation-dot glyph, so a dotted value is read right only by
                // upstream's evidence-free repair, which the repair's search will not make without a
                // dot (its "no invented dot" rule): those bars are left out.
                let dotted = Self.dottedBars(written)
                for (i, bar) in truth.enumerated() where i < legacy.count && i < repaired.count && !dotted.contains(i) {
                    if legacy[i] == bar {
                        #expect(repaired[i] == bar, "bar \(i + 1): legacy \(legacy[i]) repaired \(repaired[i])")
                    }
                }
            }
        }
    }
#endif
