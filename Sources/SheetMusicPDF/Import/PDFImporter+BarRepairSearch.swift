// swiftlint:disable file_length
#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Foundation
import SheetMusicCore

// P6, THE BOUNDED REPAIR SEARCH (F4, `BarRepairPasses.repairSearch`). Replaces upstream's one-note
// repair and its tuplet fallback on the repair's branch. A voice that already sums to the bar is
// left alone. Otherwise every change the ink backs is an alternative with an integer cost — a beam
// level moved to the lines found at the stem, a dot added or removed, a flag applied, a head's
// other fill, a beam group read as a triplet, upstream's evidence-free re-valuation as the dearest
// — and the search takes the cheapest set of at most three that makes the voice sum exactly.
// Ranked by cost, then by the number of changes, then by how well onsets follow x; two different
// results still tied are refused, and the voice stays as read with an "unfit" diagnostic, so a bar
// that does not fit the meter read still says so.

/// Ticks to a whole note: exact for every value the repair writes (plain, single- and
/// double-dotted down to 64ths; 3:2 and 6:4 down to 32nds).
let repairTicksPerWhole = 768
/// Two onset residuals this close are a tie (upstream's `RepairChoice.residualTie`).
let repairResidualTie: CGFloat = 0.01

extension PDFImporter {
    /// One change the search may make: new values for one element, or for a beam group.
    struct RepairUnit {
        enum Kind: Int, Comparable {
            case evidence, tuplet, phantom, legacy
            static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
        }

        var kind: Kind
        var members: [Int]
        var durations: [NoteDuration]
        var cost: Int
        var ratio: (normal: Int, actual: Int)?
        /// Ticks this unit adds to the voice.
        var delta: Int
    }

    /// The costs of §3 of the round-3 design.
    enum RepairCost {
        static let levelHint = 1
        static let stubImpliesPrimary = 1
        static let extrapolated = 2
        static let phantomGroup = 2
        static let dot = 1
        static let flag = 1
        static let fill = 1
        static let tuplet = 2
        static let brokenTuplet = 3
        static let legacy = 4
    }

    static func ticks(_ f: Fraction) -> Int? {
        let n = f.numerator * repairTicksPerWhole
        guard f.denominator > 0, n % f.denominator == 0 else { return nil }
        return n / f.denominator
    }

    static func ticks(_ d: NoteDuration, bar: Int) -> Int? {
        if case .measure = d { return bar }
        return ticks(d.asFraction)
    }

    /// What the search did with one voice.
    enum SearchOutcome: Equatable {
        case sums, repaired, unfit(String)
    }

    /// P6 on one voice (`group`, element indices in x order). Returns what happened; `elements`
    /// is changed only on `.repaired`.
    static func repairVoice(
        _ group: [Int], elements: inout [RhythmElement], bar: BarEvidence, ts: TimeSignature,
        passes: BarRepairPasses,
    ) -> SearchOutcome {
        guard !group.isEmpty else { return .sums }
        if normalizeMeasureRest(indices: group, elements: &elements) { return .sums }
        let barTicks = ticks(Fraction(numerator: ts.numerator, denominator: ts.denominator)) ?? 0
        let order = group.sorted { (elements[$0].x, $0) < (elements[$1].x, $1) }
        let current = order.map { ticks(elements[$0].chord.duration, bar: barTicks) }
        guard !current.contains(where: { $0 == nil }) else { return .unfit("a value the repair cannot count") }
        let total = current.compactMap { $0 }.reduce(0, +)
        if total == barTicks { return .sums }
        let units = repairUnits(order, elements: elements, bar: bar, ts: ts, passes: passes, barTicks: barTicks)
        let legacy = passes.contains(.legacyFallback)
            ? legacyAlternatives(order, elements: elements, barTicks: barTicks) : []
        let cap = passes.contains(.threeChanges) && order.count <= 24 ? 3 : 2
        let need = barTicks - total
        // Upstream's own repair of this voice: it wins a tie it is part of.
        var upstream = elements
        reconcileVoiceGroup(
            indices: group, barLength: Fraction(numerator: ts.numerator, denominator: ts.denominator),
            spatium: bar.spatium, elements: &upstream, diagnostics: nil, location: "",
        )
        var upstreamResult: [Int: NoteDuration] = [:]
        for m in group where upstream[m].chord.duration != elements[m].chord.duration {
            upstreamResult[m] = upstream[m].chord.duration
        }
        guard let best = searchRepair(
            units: units, legacy: legacy, need: need, cap: cap, order: order, elements: elements,
            barTicks: barTicks, ts: ts, upstream: upstreamResult,
        ) else {
            return .unfit("no repair; " + fitProfile(units, need: need))
        }
        guard let chosen = best.chosen else { return .unfit("refused tie; " + fitProfile(units, need: need)) }
        for unit in chosen {
            for (k, m) in unit.members.enumerated() {
                elements[m].chord.duration = unit.durations[k]
                elements[m].tupletRatio = unit.ratio
                elements[m].lowConfidenceDuration = false
            }
        }
        return .repaired
    }

    /// The bar's fit profile (diagnostic only): for each change in length one or two
    /// evidence-backed changes reach, in ticks of `repairTicksPerWhole`, the cheapest cost — what a
    /// later meter vote would sum over a system's bars. Listed from the length needed outward.
    static func fitProfile(_ units: [RepairUnit], need: Int) -> String {
        var cheapest: [Int: Int] = [0: 0]
        for (a, ua) in units.enumerated() {
            cheapest[ua.delta] = min(cheapest[ua.delta] ?? .max, ua.cost)
            for ub in units[(a + 1)...] where compatible(ua, ub) {
                let delta = ua.delta + ub.delta
                cheapest[delta] = min(cheapest[delta] ?? .max, ua.cost + ub.cost)
            }
        }
        let listed = cheapest.keys.sorted { (abs($0 - need), $0) < (abs($1 - need), $1) }.prefix(6)
        return "need \(need); reachable " + listed.map { "\($0)@\(cheapest[$0]!)" }.joined(separator: " ")
    }

    // MARK: - Alternatives

    /// The evidence-backed alternatives of a voice's elements, and its group alternatives.
    static func repairUnits(
        _ order: [Int], elements: [RhythmElement], bar: BarEvidence, ts: TimeSignature,
        passes: BarRepairPasses, barTicks: Int,
    ) -> [RepairUnit] {
        var units: [RepairUnit] = []
        func add(_ kind: RepairUnit.Kind, _ members: [Int], _ durations: [NoteDuration], cost: Int,
                 ratio: (Int, Int)? = nil) {
            var delta = 0
            for (k, m) in members.enumerated() {
                guard let new = ticks(durations[k], bar: barTicks),
                      let old = ticks(elements[m].chord.duration, bar: barTicks)
                else { return }
                delta += new - old
            }
            guard delta != 0 else { return }
            units.append(RepairUnit(kind: kind, members: members, durations: durations, cost: cost,
                                    ratio: ratio.map { (normal: $0.0, actual: $0.1) }, delta: delta))
        }
        for m in order {
            let e = elements[m]
            guard !e.isRest, !e.inTuplet, let ev = e.evidence else { continue }
            var seen: [NoteDuration] = [e.chord.duration]
            func offer(_ alt: ElementEvidence, cost: Int) {
                let d = alt.duration
                guard !seen.contains(d) else { return }
                seen.append(d)
                add(.evidence, [m], [d], cost: cost)
            }
            let stem = ev.stem.map { bar.stems[$0] }
            if let stem, !ev.virtualStem, ev.filled, ev.base == .quarter {
                if stem.levelHint != ev.level {
                    var alt = ev
                    alt.level = stem.levelHint
                    offer(alt, cost: RepairCost.levelHint)
                }
                if passes.contains(.stubImpliesPrimary), stem.stubImpliesPrimary, ev.level < 1 + stem.stubCount {
                    var alt = ev
                    alt.level = 1 + stem.stubCount
                    offer(alt, cost: RepairCost.stubImpliesPrimary)
                }
                if passes.contains(.extrapolatedBeams), stem.extrapolated {
                    var alt = ev
                    alt.level += 1
                    offer(alt, cost: RepairCost.extrapolated)
                }
                if let loose = ev.looseFlagLevel, ev.level == 0 {
                    var alt = ev
                    alt.level = loose
                    offer(alt, cost: RepairCost.flag)
                }
            }
            if ev.dotAdd, ev.dots < 2 {
                var alt = ev
                alt.dots += 1
                offer(alt, cost: RepairCost.dot)
            }
            if ev.dotRemove, ev.dots > 0 {
                var alt = ev
                alt.dots -= 1
                offer(alt, cost: RepairCost.dot)
            }
            if ev.otherFill {
                var alt = ev
                if ev.filled {
                    alt.base = .half
                    alt.level = 0
                } else {
                    alt.base = .quarter
                    alt.level = max(ev.looseFlagLevel ?? 0, ev.flagBesideHollow)
                }
                alt.filled.toggle()
                offer(alt, cost: RepairCost.fill)
            }
        }
        if passes.contains(.tupletGroups), !isCompound(ts) {
            units += tupletUnits(order, elements: elements, bar: bar, barTicks: barTicks)
        }
        if passes.contains(.phantomGroups) {
            for run in phantomRuns(order, elements: elements, bar: bar) {
                let durations = run.map { m -> NoteDuration in
                    var alt = elements[m].evidence!
                    alt.level = 1
                    return alt.duration
                }
                add(.phantom, run, durations, cost: RepairCost.phantomGroup)
            }
        }
        return units
    }

    /// n/8 with n a multiple of 3 (6/8, 9/8, 12/8): beamed in threes, never a triplet.
    static func isCompound(_ ts: TimeSignature) -> Bool {
        ts.denominator >= 8 && ts.numerator > 3 && ts.numerator % 3 == 0
    }

    /// Upstream's re-valuation, per element: every plain, single- or double-dotted value, a
    /// filled head never a half or longer, a rest or a tuplet member never.
    static func legacyAlternatives(_ order: [Int], elements: [RhythmElement], barTicks: Int) -> [(member: Int, byTicks: [Int: NoteDuration])] {
        // Plain values only: a dot needs a dot column (P1, or P6's dot alternative).
        let values: [NoteDuration] = [.whole, .half, .quarter, .eighth, .sixteenth, .thirtySecond, .sixtyFourth]
        return order.compactMap { m in
            let e = elements[m]
            guard !e.isRest, !e.inTuplet, let old = ticks(e.chord.duration, bar: barTicks) else { return nil }
            var byTicks: [Int: NoteDuration] = [:]
            for v in values {
                guard v != e.chord.duration, let t = ticks(v.asFraction) else { continue }
                if e.noteheadIsFilled, v.asFraction.numerator * 2 >= v.asFraction.denominator { continue }
                byTicks[t - old] = byTicks[t - old] ?? v
            }
            return (m, byTicks)
        }
    }

    // MARK: - Group alternatives

    /// A beam group (by its sorted union-find root) of 3 or 6 equal plain values, every stem with
    /// a beam line, spaced as a tuplet: scaled 2/3 at cost 2. "Broken": one member's line
    /// missing, beside the others — a group of 2 or 5 and its neighbour — at cost 3.
    static func tupletUnits(_ order: [Int], elements: [RhythmElement], bar: BarEvidence, barTicks: Int) -> [RepairUnit] {
        var out: [RepairUnit] = []
        let notes = order
        func stemOf(_ m: Int) -> StemEvidence? {
            guard let ev = elements[m].evidence, !ev.virtualStem, let s = ev.stem else { return nil }
            return bar.stems[s]
        }
        func lined(_ s: StemEvidence) -> Bool { s.levelHint >= 1 || s.fullCount >= 1 }
        let roots = Array(Set(notes.compactMap { m in stemOf(m).map(\.groupRoot) })).sorted()
        for root in roots {
            let members = notes.filter { stemOf($0)?.groupRoot == root }
            guard let first = members.first, let index = order.firstIndex(of: first),
                  order[index ..< min(order.count, index + members.count)].elementsEqual(members)
            else { continue }
            var runs: [(members: [Int], cost: Int)] = []
            if [3, 6].contains(members.count), members.allSatisfy({ stemOf($0).map(lined) ?? false }) {
                runs.append((members, RepairCost.tuplet))
            }
            if [2, 5].contains(members.count), members.allSatisfy({ stemOf($0).map(lined) ?? false }) {
                // The missing member stands just before or after, its stem with no line.
                for neighbour in [index - 1, index + members.count] where order.indices.contains(neighbour) {
                    let n = order[neighbour]
                    guard !elements[n].isRest, let s = stemOf(n), !lined(s) else { continue }
                    let run = neighbour < index ? [n] + members : members + [n]
                    runs.append((run, RepairCost.brokenTuplet))
                }
            }
            for (run, cost) in runs {
                let value = elements[members[0]].chord.duration
                guard isPlainValue(value), members.allSatisfy({ elements[$0].chord.duration == value }),
                      runHasTupletSpacing(run: run, ordered: order, elements: elements, spatium: bar.spatium)
                else { continue }
                let (normal, actual) = run.count == 3 ? (2, 3) : (4, 6)
                let base = value.asFraction
                let scaled = NoteDuration.fraction(Fraction(numerator: base.numerator * normal, denominator: base.denominator * actual))
                guard let new = ticks(scaled, bar: barTicks) else { continue }
                let old = run.compactMap { ticks(elements[$0].chord.duration, bar: barTicks) }.reduce(0, +)
                out.append(RepairUnit(kind: .tuplet, members: run, durations: run.map { _ in scaled }, cost: cost,
                                      ratio: (normal, actual), delta: new * run.count - old))
            }
        }
        return out
    }

    /// Runs of 3 or more successive black notes on stems one way, read with no beam and no flag,
    /// whose bare ends stand on one straight line (within 0.4 sp) and whose stems are not all the
    /// free length (3.5 ± 0.4 sp): a beam the raster never saw.
    static func phantomRuns(_ order: [Int], elements: [RhythmElement], bar: BarEvidence) -> [[Int]] {
        let sp = bar.spatium
        func candidate(_ m: Int) -> (x: CGFloat, bare: CGFloat, up: Bool, length: CGFloat)? {
            let e = elements[m]
            guard !e.isRest, !e.inTuplet, let ev = e.evidence, ev.filled, ev.base == .quarter, ev.level == 0,
                  !ev.virtualStem, let si = ev.stem, let bare = bar.stems[si].bareEndY, let up = ev.stemUp
            else { return nil }
            let headY = e.y
            return (bar.stems[si].x, bare, up, abs(bare - headY))
        }
        var runs: [[Int]] = []
        var current: [Int] = []
        func close() {
            defer { current = [] }
            guard current.count >= 3 else { return }
            let points = current.compactMap(candidate)
            let xs = points.map(\.x), ys = points.map(\.bare)
            let n = CGFloat(points.count)
            let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
            let sxx = xs.map { ($0 - mx) * ($0 - mx) }.reduce(0, +)
            let slope = sxx > 0 ? zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0, +) / sxx : 0
            let worst = zip(xs, ys).map { abs($1 - (my + slope * ($0 - mx))) }.max() ?? 0
            let free = points.allSatisfy { abs($0.length / sp - 3.5) <= 0.4 }
            if worst <= 0.4 * sp, !free { runs.append(current) }
        }
        for m in order {
            if let c = candidate(m), current.isEmpty || candidate(current.last!)?.up == c.up {
                current.append(m)
            } else {
                close()
                if candidate(m) != nil { current = [m] }
            }
        }
        close()
        return runs
    }

    // MARK: - The search

    struct SearchResult {
        /// The units applied; nil when the best results tied and the repair was refused.
        var chosen: [RepairUnit]?
    }

    /// The cheapest disjoint set of at most `cap` units (at most one tuplet, at most one legacy
    /// re-valuation) adding `need` ticks. Nil when none does.
    static func searchRepair(
        units: [RepairUnit], legacy: [(member: Int, byTicks: [Int: NoteDuration])], need: Int, cap: Int,
        order: [Int], elements: [RhythmElement], barTicks: Int, ts: TimeSignature,
        upstream: [Int: NoteDuration] = [:],
    ) -> SearchResult? {
        var found: [(cost: Int, count: Int, units: [RepairUnit])] = []
        var bestKey: (Int, Int)?
        func consider(_ set: [RepairUnit]) {
            let key = (set.map(\.cost).reduce(0, +), set.count)
            if let b = bestKey, key > b { return }
            guard tupletOnBeat(set, order: order, elements: elements, barTicks: barTicks, ts: ts) else { return }
            if bestKey == nil || key < bestKey! {
                bestKey = key
                found = []
            }
            found.append((key.0, key.1, set))
        }
        func legacyCompletions(_ set: [RepairUnit], remaining: Int) {
            guard set.count < cap else { return }
            let used = Set(set.flatMap(\.members))
            for alt in legacy where !used.contains(alt.member) {
                if let d = alt.byTicks[remaining] {
                    consider(set + [RepairUnit(kind: .legacy, members: [alt.member], durations: [d],
                                               cost: RepairCost.legacy, ratio: nil, delta: remaining)])
                }
            }
        }
        legacyCompletions([], remaining: need)
        let n = units.count
        for a in 0 ..< n {
            let ua = units[a]
            if ua.delta == need { consider([ua]) }
            legacyCompletions([ua], remaining: need - ua.delta)
            guard cap >= 2 else { continue }
            for b in (a + 1) ..< max(a + 1, n) {
                let ub = units[b]
                guard compatible(ua, ub) else { continue }
                if ua.delta + ub.delta == need { consider([ua, ub]) }
                legacyCompletions([ua, ub], remaining: need - ua.delta - ub.delta)
                guard cap >= 3 else { continue }
                for c in (b + 1) ..< max(b + 1, n) {
                    let uc = units[c]
                    guard ua.delta + ub.delta + uc.delta == need, compatible(ua, uc), compatible(ub, uc) else { continue }
                    consider([ua, ub, uc])
                }
            }
        }
        guard !found.isEmpty else { return nil }
        // Rank the cheapest by how well onsets follow x; refuse two different results in a tie.
        let scored = found.map { ($0.units, onsetResidual($0.units, order: order, elements: elements)) }
        let best = scored.map(\.1).min()!
        let tied = scored.filter { $0.1 - best <= repairResidualTie }
        var distinct: [[Int: NoteDuration]] = []
        var first: [RepairUnit]?
        for (set, _) in tied.sorted(by: { $0.1 < $1.1 }) {
            let result = outcome(set)
            if !distinct.contains(result) {
                distinct.append(result)
                if first == nil { first = set }
            }
        }
        if distinct.count == 1 { return SearchResult(chosen: first) }
        // Exact ties go to upstream's reading when it is one of them.
        if !upstream.isEmpty, let index = tied.firstIndex(where: { outcome($0.0) == upstream }) {
            return SearchResult(chosen: tied[index].0)
        }
        return SearchResult(chosen: nil)
    }

    private static func outcome(_ set: [RepairUnit]) -> [Int: NoteDuration] {
        var out: [Int: NoteDuration] = [:]
        for unit in set {
            for (k, m) in unit.members.enumerated() {
                out[m] = unit.durations[k]
            }
        }
        return out
    }

    static func compatible(_ a: RepairUnit, _ b: RepairUnit) -> Bool {
        if a.kind == .tuplet, b.kind == .tuplet { return false }
        return Set(a.members).isDisjoint(with: b.members)
    }

    /// A tuplet in `set` must start on a beat of the meter read, counting the set's other changes.
    private static func tupletOnBeat(
        _ set: [RepairUnit], order: [Int], elements: [RhythmElement], barTicks: Int, ts: TimeSignature,
    ) -> Bool {
        guard let tuplet = set.first(where: { $0.kind == .tuplet }), let start = tuplet.members.first else { return true }
        let changed = outcome(set)
        var onset = 0
        for m in order {
            if m == start { break }
            onset += ticks(changed[m] ?? elements[m].chord.duration, bar: barTicks) ?? 0
        }
        let beat = repairTicksPerWhole / max(1, ts.denominator)
        return beat > 0 && onset % beat == 0
    }

    /// `onsetFitResidual` for a set of changes: how far the voice's onsets, under the changed
    /// values, stand from a straight line through the elements' x.
    static func onsetResidual(_ set: [RepairUnit], order: [Int], elements: [RhythmElement]) -> CGFloat {
        guard order.count >= 3 else { return 0 }
        let changed = outcome(set)
        var ts: [CGFloat] = []
        var xs: [CGFloat] = []
        var t: CGFloat = 0
        for m in order {
            ts.append(t)
            xs.append(elements[m].x)
            let f = changed[m].map { d -> Fraction in
                if case .measure = d { return Fraction(numerator: 1, denominator: 1) }
                return d.asFraction
            } ?? elementFraction(elements[m])
            t += CGFloat(f.numerator) / CGFloat(f.denominator)
        }
        let span = (xs.max() ?? 0) - (xs.min() ?? 0)
        guard span > 0 else { return 0 }
        let n = CGFloat(ts.count)
        let mt = ts.reduce(0, +) / n, mx = xs.reduce(0, +) / n
        var num: CGFloat = 0, den: CGFloat = 0
        for k in ts.indices {
            num += (ts[k] - mt) * (xs[k] - mx)
            den += (ts[k] - mt) * (ts[k] - mt)
        }
        let slope = den > 0 ? num / den : 0
        let sumSq = ts.indices.map { k -> CGFloat in
            let r = xs[k] - (mx + slope * (ts[k] - mt))
            return r * r
        }.reduce(0, +)
        return (sumSq / n).squareRoot() / span
    }

    static func isPlainValue(_ d: NoteDuration) -> Bool {
        switch d {
        case .whole, .half, .quarter, .eighth, .sixteenth, .thirtySecond, .sixtyFourth: true
        default: false
        }
    }
}
