#if SHEET_MUSIC_HAS_APPLE_PLATFORM_TEST_SUPPORT
    import CoreGraphics
    import Foundation
    import PDFKit
    import SheetMusicLayoutApple
    @testable import SheetMusicCore
    @testable import SheetMusicMSCX
    @testable import SheetMusicPDF
    import Testing

    /// Pieces of what bench pages 0–159 never hold — whole notes under a moving voice, grace notes,
    /// staccatos, double dots, a pickup, 3/8, 2/2, sextuplets, lyrics and tuplet numerals — written
    /// for the bar repair's tests (F4). **Provenance:** authored for this fork and owned by
    /// FretCodex, like `FretCodexBarRepairFixtures`; nothing here comes from `Resources/`.
    enum FretCodexBarRepairTextures {
        typealias F = FretCodexBarRepairFixtures

        /// A chord with `extra` markup (grace, articulation, lyric) before its notes.
        static func chord(_ pitches: [Int], _ type: String, dots: Int = 0, extra: String = "") -> String {
            let notes = pitches.map { "<Note><pitch>\($0)</pitch><tpc>\(F.tpc($0))</tpc></Note>" }.joined()
            let dotsXML = dots > 0 ? "<dots>\(dots)</dots>" : ""
            return "<Chord>\(dotsXML)<durationType>\(type)</durationType>\(extra)\(notes)</Chord>"
        }

        static let staccato = "<Articulation><subtype>articStaccatoAbove</subtype></Articulation>"
        static let grace = "<acciaccatura/>"
        static func lyric(_ text: String) -> String { "<Lyrics><text>\(text)</text></Lyrics>" }

        /// A one-staff score whose measures may each carry a `len` (a pickup) and a time change.
        static func score(_ measures: [(len: String?, time: (Int, Int)?, voices: [String])]) throws -> Score {
            var body = ""
            for (i, m) in measures.enumerated() {
                body += m.len.map { "<Measure len=\"\($0)\">" } ?? "<Measure>"
                for (v, content) in m.voices.enumerated() {
                    var lead = ""
                    if v == 0, let time = m.time {
                        lead += "<TimeSig><sigN>\(time.0)</sigN><sigD>\(time.1)</sigD></TimeSig>"
                    }
                    if i == 0, v == 0, m.time == nil { lead += "<TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>" }
                    body += "<voice>\(lead)\(content)</voice>"
                }
                body += "</Measure>"
            }
            let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <museScore version="4.60"><Score><Division>480</Division>
            <Part id="1"><Staff id="1"><StaffType group="pitched"><name>stdNormal</name></StaffType></Staff>
            <trackName>Piano</trackName><Instrument id="piano"><longName>Piano</longName><trackName>Piano</trackName>
            <instrumentId>keyboard.piano</instrumentId></Instrument></Part>
            <Staff id="1">\(body)</Staff></Score></museScore>
            """
            return try MSCXParser.parse(Data(xml.utf8))
        }

        /// 4/4 with a pickup: whole notes under quarters, grace notes, staccatos, double dots.
        static func fourFour() throws -> Score {
            func c(_ p: [Int], _ t: String, dots: Int = 0, extra: String = "") -> String { chord(p, t, dots: dots, extra: extra) }
            return try score([
                (len: "1/4", time: (4, 4), voices: [c([67], "eighth") + c([69], "eighth")]),
                (len: nil, time: nil, voices: [c([76], "quarter") + c([77], "quarter") + c([79], "quarter") + c([81], "quarter"),
                                               c([60], "whole")]),
                (len: nil, time: nil, voices: [c([74], "16th", extra: grace) + c([72], "quarter") + c([74], "quarter")
                        + c([69], "16th", extra: grace) + c([71], "half")]),
                (len: nil, time: nil, voices: [c([72], "quarter", extra: staccato) + c([74], "quarter", extra: staccato)
                        + c([76], "eighth", extra: staccato) + c([77], "eighth", extra: staccato) + c([79], "quarter")]),
                (len: nil, time: nil, voices: [c([72], "quarter", dots: 2) + c([74], "16th") + c([76], "half")]),
                (len: nil, time: nil, voices: [c([79], "half") + c([77], "half"), c([60], "whole")]),
                (len: nil, time: nil, voices: [c([72, 76, 79], "whole")]),
            ])
        }

        /// 3/8, then 2/2 with eighth triplets on the second quarter.
        static func otherMeters() throws -> Score {
            func c(_ p: [Int], _ t: String, dots: Int = 0) -> String { chord(p, t, dots: dots) }
            let t = { (p: [Int]) in F.tuplet(p.map { c([$0], "eighth") }, base: "eighth") }
            return try score([
                (len: nil, time: (3, 8), voices: [c([72], "eighth") + c([74], "eighth") + c([76], "eighth")]),
                (len: nil, time: nil, voices: [c([77], "quarter") + c([76], "eighth")]),
                (len: nil, time: nil, voices: [c([74], "eighth") + c([72], "eighth") + c([71], "eighth")]),
                (len: nil, time: nil, voices: [c([72], "quarter", dots: 1)]),
                (len: nil, time: (2, 2), voices: [c([72], "quarter") + t([74, 76, 77]) + c([79], "half")]),
                (len: nil, time: nil, voices: [c([81], "half") + c([79], "quarter") + c([77], "quarter")]),
                (len: nil, time: nil, voices: [c([76], "whole")]),
            ])
        }

        /// 2/4 with sixteenth sextuplets.
        static func sextuplets() throws -> Score {
            func c(_ p: [Int], _ t: String) -> String { chord(p, t) }
            let six = { (p: [Int]) in F.tuplet(p.map { c([$0], "16th") }, base: "16th", actual: 6, normal: 4) }
            return try score([
                (len: nil, time: (2, 4), voices: [six([72, 74, 76, 77, 79, 81]) + c([83], "quarter")]),
                (len: nil, time: nil, voices: [c([84], "quarter") + six([83, 81, 79, 77, 76, 74])]),
                (len: nil, time: nil, voices: [c([72], "16th") + c([74], "16th") + c([76], "16th") + c([77], "16th") + c([79], "quarter")]),
                (len: nil, time: nil, voices: [c([72], "half")]),
            ])
        }

        /// 3/4 with a lyric under every note and a triplet whose numeral the PDF writes as text.
        static func lyrics() throws -> Score {
            func c(_ p: Int, _ t: String, _ word: String) -> String { chord([p], t, extra: lyric(word)) }
            return try score([
                (len: nil, time: (3, 4), voices: [c(67, "quarter", "la") + c(69, "quarter", "li") + c(71, "quarter", "lo")]),
                (len: nil, time: nil, voices: [F.tuplet([c(72, "eighth", "a"), c(74, "eighth", "b"), c(76, "eighth", "c")], base: "eighth")
                        + c(77, "half", "d")]),
                (len: nil, time: nil, voices: [c(79, "half", "e") + c(77, "quarter", "f")]),
            ])
        }
    }

    @MainActor
    @Suite("FretCodex — the raster bar repair (F4): textures the bench lacks")
    struct FretCodexBarRepairTextureTests {
        typealias T = FretCodexBarRepairTests

        static func export(_ score: Score) throws -> Data? {
            guard #available(macOS 15.0, iOS 16.0, *) else { return nil }
            return try PDFExporter.export(score: score)
        }

        /// `rasterLike`, keeping the page's text — a scanned PDF's OCR layer.
        static func rasterLikeWithText(_ data: Data, options: PDFImportOptions) throws -> Score {
            let document = try PDFImporter.openDocument(data)
            let walk = try PDFImporter.walkDocument(document)
            var content = walk.content
            content.paths = content.paths.map {
                var path = $0
                path.detectedFromRaster = true
                return path
            }
            content.curves = []
            return try PDFImporter.buildScore(
                pageCount: document.pageCount, walked: content, pageSizes: walk.pageSizes,
                documentAttributes: walk.attributes, options: options, rasterPages: Set(0 ..< document.pageCount),
            )
        }

        /// The textures read with every pass on: every bar the legacy chain reads as written is
        /// read as written. Bars whose values need a dot glyph the export doesn't draw are left out,
        /// as in `theRepairKeepsEveryBarTheLegacyChainReadsAsWritten`.
        @Test(.enabled(if: T.bravuraAvailable))
        func theRepairKeepsEveryTextureBarTheLegacyChainReads() throws {
            for (name, written) in try [("4/4", FretCodexBarRepairTextures.fourFour()), ("meters", FretCodexBarRepairTextures.otherMeters()),
                                        ("sextuplets", FretCodexBarRepairTextures.sextuplets())] {
                guard let data = try Self.export(written) else { return }
                let truth = T.describe(written)
                let legacy = T.describe(try T.rasterLike(data, options: PDFImportOptions()))
                for passes in [BarRepairPasses.all, T.every] {
                    let repaired = T.describe(try T.rasterLike(data, options: T.repairOn(passes)))
                    let dotted = T.dottedBars(written)
                    for (i, bar) in truth.enumerated() where i < legacy.count && i < repaired.count && !dotted.contains(i) {
                        if legacy[i] == bar {
                            #expect(repaired[i] == bar, "\(name) bar \(i + 1) (\(passes.rawValue)): legacy \(legacy[i]) repaired \(repaired[i])")
                        }
                    }
                }
            }
        }

        /// The whole notes under the moving voice stay wholes in their own voice.
        @Test(.enabled(if: T.bravuraAvailable))
        func aWholeNoteUnderQuartersStaysAWholeOnTheRepair() throws {
            guard let data = try Self.export(FretCodexBarRepairTextures.fourFour()) else { return }
            let read = T.describe(try T.rasterLike(data, options: T.repairOn(.all)))
            #expect(read.count >= 6)
            for bar in [1, 5] where bar < read.count {
                #expect(read[bar].contains("60:whole"), "bar \(bar + 1): \(read[bar])")
            }
        }

        /// A raster page with a text layer — a scanned PDF's OCR — keeps what the legacy chain reads
        /// from it on the repair's branch, the triplet numeral here (the export writes no lyric):
        /// with no pass on, the page reads as the legacy chain exactly.
        @Test(.enabled(if: T.bravuraAvailable))
        func aTextLayerReadsAsBeforeOnTheRepairsBranch() throws {
            guard let data = try Self.export(FretCodexBarRepairTextures.lyrics()) else { return }
            let before = try Self.rasterLikeWithText(data, options: PDFImportOptions())
            #expect(T.describe(before).dropFirst().first?.contains("3:2") == true, "the legacy chain reads the numeral")
            #expect(try Self.rasterLikeWithText(data, options: T.repairOn([])) == before)
            let repaired = T.describe(try Self.rasterLikeWithText(data, options: T.repairOn(.all)))
            #expect(repaired.dropFirst().first?.contains("3:2") == true, "\(repaired)")
        }

        static func lyricCount(_ score: Score) -> Int {
            score.parts.values.flatMap { $0.staves.values }.flatMap(\.measures).flatMap(\.voices).flatMap { $0.elements.values }
                .reduce(0) { n, element in
                    guard case let .chord(chord) = element else { return n }
                    return n + chord.lyrics.count
                }
        }

        // MARK: - The meter: a signature in a dropped leading cell (bench phone #2)

        /// Phone #2's opening: the clef's stroke and the digits' right edge are found as two
        /// full-height verticals, so the system starts with two narrow cells of no note — dropped,
        /// and with them the 2/4. With the repair on, the dropped cell's time-signature glyphs (and
        /// only those) go to the first bar kept; with it off, or on a vector page, nothing changes.
        @Test(.enabled(if: T.bravuraAvailable))
        func aSignatureInADroppedLeadingCellReachesTheFirstBar() throws {
            guard #available(macOS 15.0, iOS 16.0, *) else { return }
            let written = try FretCodexBarRepairFixtures.triplets()
            let data = try PDFExporter.export(score: written)
            func read(_ options: PDFImportOptions, strokes: Bool) throws -> Score {
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
                if strokes { content.paths += Self.signatureStrokes(content) }
                return try PDFImporter.buildScore(
                    pageCount: document.pageCount, walked: content, pageSizes: walk.pageSizes,
                    documentAttributes: walk.attributes, options: options, rasterPages: Set(0 ..< document.pageCount),
                )
            }
            func firstTime(_ score: Score) -> TimeSignature? {
                guard let measure = score.parts.values.first?.staves.values.first?.measures.first else { return nil }
                for element in measure.voices.first?.elements.values ?? [] {
                    if case let .timeSignature(ts) = element { return ts }
                }
                return nil
            }
            // As engraved, the meter is read either way.
            #expect(firstTime(try read(PDFImportOptions(), strokes: false)).map { ($0.numerator, $0.denominator) } ?? (0, 0) == (2, 4))
            // With the strokes, upstream drops it …
            let lost = try read(PDFImportOptions(), strokes: true)
            #expect(firstTime(lost).map { ($0.numerator, $0.denominator) } ?? (0, 0) != (2, 4))
            // … and the repair carries it, but not the clef or key: the first bar has no clef.
            let carried = try read(T.repairOn(.all), strokes: true)
            #expect(firstTime(carried).map { ($0.numerator, $0.denominator) } ?? (0, 0) == (2, 4))
            // With no pass, the legacy chain exactly.
            #expect(try read(T.repairOn([]), strokes: true) == lost)
        }

        /// Two full-height verticals on every staff: at the clef's right edge and at the time
        /// signature's, where a phone photo's raster front end finds them.
        static func signatureStrokes(_ content: WalkedContent) -> [PathSegment] {
            let lines = content.paths.filter { $0.kind == .horizontal }
            var out: [PathSegment] = []
            let clefs = content.glyphs.filter { if case .clefG = $0.semantic { return true } else { return false } }
            let digits = content.glyphs.filter { if case .timeSignatureDigit = $0.semantic { return true } else { return false } }
            for clef in clefs {
                guard let digit = digits.filter({ abs($0.geometry.origin.y - clef.geometry.origin.y) < 40 && $0.geometry.pageIndex == clef.geometry.pageIndex })
                    .min(by: { $0.geometry.origin.x < $1.geometry.origin.x })
                else { continue }
                let staffYs = lines.filter { $0.pageIndex == clef.geometry.pageIndex && abs($0.rect.midY - clef.geometry.origin.y) < 30 }
                    .map(\.rect.midY)
                guard let lo = staffYs.min(), let hi = staffYs.max(), hi - lo > 10 else { continue }
                for x in [clef.geometry.origin.x + clef.geometry.advance * 0.95, digit.geometry.origin.x + digit.geometry.advance * 1.1] {
                    out.append(PathSegment(kind: .vertical, rect: CGRect(x: x, y: lo, width: 0, height: hi - lo),
                                           lineWidth: 0.8, pageIndex: clef.geometry.pageIndex, quad: nil, detectedFromRaster: true))
                }
            }
            return out
        }
    }
#endif
