import Foundation

/// A site's cadence is independent from how long each submission/vote lasts.
enum SiteCyclePattern: String, Codable, CaseIterable, Identifiable {
    case alternating, overlapping
    var id: String { rawValue }
    var title: String { self == .alternating ? "投稿と投票を順番に" : "投票中に次の投稿" }
}
enum SitePeriodKind: String, Codable, CaseIterable, Identifiable {
    case regular, exhibition, playoff, replacement, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .regular: return "通常回"
        case .exhibition: return "エキシビション"
        case .playoff: return "プレーオフ"
        case .replacement: return "入れ替え戦"
        case .other: return "その他"
        }
    }
}
enum LeagueMovement: String, Codable, CaseIterable, Identifiable {
    case unchanged, promoted, relegated
    var id: String { rawValue }
    var title: String {
        switch self { case .unchanged: return "残留"; case .promoted: return "昇格"; case .relegated: return "降格" }
    }
}
enum SiteQualification: String, Codable, CaseIterable, Identifiable {
    case none, playoff, replacement
    var id: String { rawValue }
    var title: String {
        switch self { case .none: return "なし"; case .playoff: return "プレーオフ出場"; case .replacement: return "入れ替え戦出場" }
    }
}

struct SiteSpecialPeriod: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var title: String = ""
    var kind: SitePeriodKind = .other
    var round: EventRound = EventRound()
    var seasonName: String = ""
}

/// The anchor is one actual cycle, which can be the middle of a season.
/// Season boundaries do not infer site-specific qualification or league rules.
struct SiteCycleSettings: Codable, Equatable {
    var pattern: SiteCyclePattern = .alternating
    var anchorStart: Date = Date()
    var intervalDays: Int = 14
    var anchorCycleNumber: Int = 1
    var seasonName: String = ""
    var seasonStart: Date? = nil
    var seasonLengthDays: Int? = nil
    var regularCycleCount: Int? = nil
    var leagues: [String] = []
    var specialPeriods: [SiteSpecialPeriod] = []
    var leagueChangesPerSeason: Bool = false
    var seasonID: String? = nil
    var seasonEndsAt: Date? = nil
    var trackSeasonTotals: Bool = false
    var ruleRevisionID: String? = nil
    var legacyInferredSeasonStart: Date? = nil
    /// 「第○シーズン」の番号。シーズンの最後の回が終わったら、次の番号で始める。
    var seasonNumber: Int? = nil
    /// 0.11：投稿中でも投票中でもない（シーズンの合間など）。次のお題が分かるまで通常の回を作らない。
    var waitingForNext: Bool = false
    /// 0.11：この日時より前の通常の回は作らない（次のお題の開始が分かっている時など）。
    var notBefore: Date? = nil
    /// 0.14：運営の都合で休みになった通常の回の投稿開始。その回は作らず、後ろの回の番号を詰める。
    var breakStarts: [Date] = []

    var inferredSeasonStart: Date {
        // Compatibility alias for old call sites; never reconstruct unknown
        // season history from a global prompt number or current rule duration.
        seasonStart ?? anchorStart
    }
    var seasonEnd: Date? {
        seasonEndsAt
    }
    func validate() throws {
        guard (1...730).contains(intervalDays), (1...10000).contains(anchorCycleNumber),
              regularCycleCount.map({ (1...10000).contains($0) }) ?? true,
              seasonLengthDays.map({ (1...3660).contains($0) }) ?? true,
              seasonNumber.map({ (1...10000).contains($0) }) ?? true else {
            throw GiriDataError.invalid("周期・シーズンの回数と日数を確認してください。")
        }
        if let start = seasonStart, let end = seasonEndsAt, end < start {
            throw GiriDataError.invalid("シーズンの終了が開始より前です。")
        }
        let names = leagues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !names.contains(where: \.isEmpty), Set(names.map(playerSearchKey)).count == names.count,
              Set(specialPeriods.map(\.id)).count == specialPeriods.count else {
            throw GiriDataError.invalid("リーグ名や特別日程のIDが重複しています。")
        }
        for period in specialPeriods {
            guard !period.id.isEmpty else { throw GiriDataError.invalid("特別日程のIDが空です。") }
            try period.round.validate()
            if let start = period.round.submissionStart, let end = period.round.submissionEnd, end < start {
                throw GiriDataError.invalid("特別日程の投稿締切が開始より前です。")
            }
            if let start = period.round.votingStart, let end = period.round.votingEnd, end < start {
                throw GiriDataError.invalid("特別日程の投票締切が開始より前です。")
            }
        }
    }
}

extension SiteCycleSettings {
    private enum CodingKeys: String, CodingKey { case pattern, anchorStart, intervalDays, anchorCycleNumber, seasonName, seasonStart, seasonLengthDays, regularCycleCount, leagues, specialPeriods, leagueChangesPerSeason, seasonID, seasonEndsAt, trackSeasonTotals, ruleRevisionID, legacyInferredSeasonStart, seasonNumber, waitingForNext, notBefore, breakStarts }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pattern = try c.decodeIfPresent(SiteCyclePattern.self, forKey: .pattern) ?? .alternating
        anchorStart = try c.giriRequiredDate(forKey: .anchorStart)
        intervalDays = try c.decodeIfPresent(Int.self, forKey: .intervalDays) ?? 14
        anchorCycleNumber = try c.decodeIfPresent(Int.self, forKey: .anchorCycleNumber) ?? 1
        seasonName = try c.decodeIfPresent(String.self, forKey: .seasonName) ?? ""
        seasonStart = try c.giriDate(forKey: .seasonStart, required: false, calendarOnly: false)
        seasonLengthDays = try c.decodeIfPresent(Int.self, forKey: .seasonLengthDays)
        regularCycleCount = try c.decodeIfPresent(Int.self, forKey: .regularCycleCount)
        leagues = try c.decodeIfPresent([String].self, forKey: .leagues) ?? []
        specialPeriods = try c.decodeIfPresent([SiteSpecialPeriod].self, forKey: .specialPeriods) ?? []
        leagueChangesPerSeason = try c.decodeIfPresent(Bool.self, forKey: .leagueChangesPerSeason) ?? false
        seasonID = try c.decodeIfPresent(String.self, forKey: .seasonID)
        seasonEndsAt = try c.giriDate(forKey: .seasonEndsAt, required: false, calendarOnly: false)
        trackSeasonTotals = try c.decodeIfPresent(Bool.self, forKey: .trackSeasonTotals) ?? false
        ruleRevisionID = try c.decodeIfPresent(String.self, forKey: .ruleRevisionID)
        legacyInferredSeasonStart = try c.giriDate(forKey: .legacyInferredSeasonStart, required: false, calendarOnly: false)
        seasonNumber = try c.decodeIfPresent(Int.self, forKey: .seasonNumber)
        waitingForNext = try c.decodeIfPresent(Bool.self, forKey: .waitingForNext) ?? false
        notBefore = try c.giriDate(forKey: .notBefore, required: false, calendarOnly: false)
        let breaks = try c.decodeIfPresent([String].self, forKey: .breakStarts) ?? []
        breakStarts = breaks.compactMap { GiriDates.parse($0, calendarOnly: false) }.sorted()
        // 0.6 filled this date by counting backwards with today's rule. Clear
        // only that recognizable generated value, preserving explicit dates.
        if seasonID == nil && ruleRevisionID == nil && anchorCycleNumber > 1,
           seasonStart == addCalendarDays(anchorStart, -(anchorCycleNumber - 1) * intervalDays) {
            legacyInferredSeasonStart = legacyInferredSeasonStart ?? seasonStart
            seasonStart = nil
        }
        if let cap = regularCycleCount, cap < anchorCycleNumber { regularCycleCount = nil }
        try validate()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pattern, forKey: .pattern)
        try c.encode(GiriDates.timestamp(anchorStart), forKey: .anchorStart)
        try c.encode(intervalDays, forKey: .intervalDays)
        try c.encode(anchorCycleNumber, forKey: .anchorCycleNumber)
        try c.encode(seasonName, forKey: .seasonName)
        try c.encode(seasonStart.map(GiriDates.timestamp), forKey: .seasonStart)
        try c.encode(seasonLengthDays, forKey: .seasonLengthDays)
        try c.encode(regularCycleCount, forKey: .regularCycleCount)
        try c.encode(leagues, forKey: .leagues)
        try c.encode(specialPeriods, forKey: .specialPeriods)
        try c.encode(leagueChangesPerSeason, forKey: .leagueChangesPerSeason)
        try c.encode(seasonID, forKey: .seasonID)
        try c.encode(seasonEndsAt.map(GiriDates.timestamp), forKey: .seasonEndsAt)
        try c.encode(trackSeasonTotals, forKey: .trackSeasonTotals)
        try c.encode(ruleRevisionID, forKey: .ruleRevisionID)
        try c.encode(legacyInferredSeasonStart.map(GiriDates.timestamp), forKey: .legacyInferredSeasonStart)
        try c.encode(seasonNumber, forKey: .seasonNumber)
        try c.encode(waitingForNext, forKey: .waitingForNext)
        try c.encode(notBefore.map(GiriDates.timestamp), forKey: .notBefore)
        if !breakStarts.isEmpty { try c.encode(breakStarts.map(GiriDates.timestamp), forKey: .breakStarts) }
    }
}

/// A prior rule window is retained when a site relaunches or changes timing.
/// It ends when the next revision's anchor starts; joined events remain exact
/// snapshots independently of these templates.
struct SiteRuleRevision: Codable, Equatable, Identifiable {
    var id: String
    var settings: SiteCycleSettings
    var submissionDays: Int
    var votingDays: Int
    var recurrence: SiteRecurrence

    var effectiveFrom: Date { settings.anchorStart }
    func validate() throws {
        try settings.validate()
        guard !id.isEmpty, submissionDays >= 1, votingDays >= 1 else {
            throw GiriDataError.invalid("過去のルール設定が不正です。")
        }
    }
}

struct SiteLeagueChange: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var sourceEventID: String
    var fromLeague: String
    var toLeague: String
    var effectiveFrom: Date
    var seasonName: String = ""
}
extension SiteLeagueChange {
    private enum CodingKeys: String, CodingKey { case id, sourceEventID, fromLeague, toLeague, effectiveFrom, seasonName }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        sourceEventID = try c.decode(String.self, forKey: .sourceEventID)
        fromLeague = try c.decode(String.self, forKey: .fromLeague)
        toLeague = try c.decode(String.self, forKey: .toLeague)
        effectiveFrom = try c.giriRequiredDate(forKey: .effectiveFrom)
        seasonName = try c.decodeIfPresent(String.self, forKey: .seasonName) ?? ""
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sourceEventID, forKey: .sourceEventID)
        try c.encode(fromLeague, forKey: .fromLeague)
        try c.encode(toLeague, forKey: .toLeague)
        try c.encode(GiriDates.timestamp(effectiveFrom), forKey: .effectiveFrom)
        try c.encode(seasonName, forKey: .seasonName)
    }
}

struct SiteCycleDescriptor: Equatable, Identifiable {
    let cycleKey: String
    let round: EventRound
    let seasonName: String
    let cycleNumber: Int?
    let kind: SitePeriodKind
    let title: String
    var seasonID: String? = nil
    var ruleRevisionID: String? = nil
    var seasonStart: Date? = nil
    var seasonEnd: Date? = nil
    var id: String { cycleKey }
    var start: Date? { round.submissionStart ?? round.votingStart }
    var end: Date? { round.votingEnd ?? round.submissionEnd }
    func isActive(_ now: Date = Date()) -> Bool { round.isSubmissionOpen(now) || round.isVotingOpen(now) }
}

/// Keep both a preceding vote and the current submission visible. A 7-day
/// cadence with 7 submission + 3 voting days therefore has two simultaneous rows.
func siteCycleDescriptors(_ site: OnlineSite, around now: Date = Date(), calendar: Calendar = .current) -> [SiteCycleDescriptor] {
    guard let current = site.cycleSettings else { return [] }
    var revisions = site.ruleHistory
    let currentID = current.ruleRevisionID ?? "current"
    revisions.removeAll { $0.id == currentID }
    revisions.append(SiteRuleRevision(id: currentID, settings: current,
        submissionDays: site.submissionDays, votingDays: site.votingDays, recurrence: site.recurrence))
    revisions = revisions.enumerated().sorted {
        $0.element.effectiveFrom == $1.element.effectiveFrom ? $0.offset < $1.offset : $0.element.effectiveFrom < $1.element.effectiveFrom
    }.map(\.element)
    var output: [String: SiteCycleDescriptor] = [:]
    for (index, revision) in revisions.enumerated() {
        let upper = index + 1 < revisions.count ? revisions[index + 1].effectiveFrom : nil
        for descriptor in siteRevisionDescriptors(siteID: site.id, block: site.block,
            revision: revision, around: now, upperBound: upper,
            hasPreviousRevision: index > 0, calendar: calendar) {
            output[descriptor.cycleKey] = descriptor
        }
    }
    return output.values.sorted {
        let first = $0.start ?? .distantFuture, second = $1.start ?? .distantFuture
        return first == second ? $0.cycleKey < $1.cycleKey : first < second
    }
}

private func siteRevisionDescriptors(siteID: String, block: String, revision: SiteRuleRevision,
    around now: Date, upperBound: Date?, hasPreviousRevision: Bool, calendar: Calendar) -> [SiteCycleDescriptor] {
    let settings = revision.settings
    guard settings.intervalDays > 0 else { return [] }
    let dayDifference = calendar.dateComponents([.day], from: settings.anchorStart, to: now).day ?? 0
    let approximateIndex = Int(floor(Double(dayDifference) / Double(settings.intervalDays)))
    let span = min(732, max(2, (revision.submissionDays + revision.votingDays + settings.intervalDays - 1) / settings.intervalDays + 1))
    let hasSeason = settings.seasonID != nil || !settings.seasonName.isEmpty || settings.trackSeasonTotals
    // A known current period is an anchor, not evidence about all previous
    // seasons. A changed rule is always forward-only, even with known dates.
    let baseLower = hasPreviousRevision ? settings.anchorStart : settings.seasonStart ?? (hasSeason ? settings.anchorStart : nil)
    // 次のお題の開始が分かっている時は、それより前の回を作らない。
    let lower: Date? = [baseLower, settings.notBefore].compactMap { $0 }.max()
    let validCap = settings.regularCycleCount.flatMap { $0 >= settings.anchorCycleNumber ? $0 : nil }
    var output: [SiteCycleDescriptor] = []
    // 投稿中でも投票中でもない間（シーズンの合間など）は、通常の回を作らない（特別な日程は出す）。
    if revision.recurrence == .weekly && !settings.waitingForNext {
        for offset in (approximateIndex - span)...(approximateIndex + 1) {
            let start = addCalendarDays(settings.anchorStart, offset * settings.intervalDays, calendar: calendar)
            // 運営の都合で休みの回は作らない。後ろの回は番号を詰める。
            if siteIsBreakStart(settings, start) { continue }
            let number = siteRegularCycleNumber(settings, slotStart: start, offset: offset)
            guard !hasSeason || number >= 1, validCap.map({ number <= $0 }) ?? true else { continue }
            guard lower.map({ start >= $0 }) ?? true,
                  upperBound.map({ start < $0 }) ?? true,
                  settings.seasonEnd.map({ start < $0 }) ?? true else { continue }
            let key = cycleKeyFor(start)
            let identifier = "site:\(siteID):\(key)"
            var round = EventRound(id: identifier)
            round.stageId = identifier; round.name = number < 1 ? "前の回" : "第\(number)回"; round.promptNumber = max(1, number)
            round.block = block; round.submissionStart = start
            round = completeRoundSchedule(round, submissionDays: revision.submissionDays, votingDays: revision.votingDays)
            if settings.specialPeriods.contains(where: { $0.kind == .regular && $0.round.submissionStart == start }) { continue }
            output.append(SiteCycleDescriptor(cycleKey: key, round: round, seasonName: settings.seasonName,
                cycleNumber: number >= 1 ? number : nil, kind: .regular, title: round.name,
                seasonID: settings.seasonID, ruleRevisionID: settings.ruleRevisionID,
                seasonStart: settings.seasonStart, seasonEnd: settings.seasonEnd))
        }
    }
    for period in settings.specialPeriods {
        var round = period.round
        let start = round.submissionStart ?? round.votingStart
        guard upperBound.map({ boundary in start.map { $0 < boundary } ?? false }) ?? true else { continue }
        let key = "special:" + period.id
        round.id = "site:\(siteID):\(key)"; round.stageId = round.id
        round.name = period.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? period.kind.title : period.title
        let number: Int? = period.kind == .regular ? max(1, round.promptNumber) : nil
        output.append(SiteCycleDescriptor(cycleKey: key, round: round,
            seasonName: period.seasonName.isEmpty ? settings.seasonName : period.seasonName,
            cycleNumber: number, kind: period.kind, title: round.name,
            seasonID: settings.seasonID, ruleRevisionID: settings.ruleRevisionID,
            seasonStart: settings.seasonStart, seasonEnd: settings.seasonEnd))
    }
    return output
}

func siteLeagueAfterMovement(_ site: OnlineSite, from league: String, movement: LeagueMovement) -> String? {
    guard let leagues = site.cycleSettings?.leagues, let index = leagues.firstIndex(where: { playerSearchKey($0) == playerSearchKey(league) }) else { return nil }
    let next: Int
    switch movement { case .unchanged: next = index; case .promoted: next = index - 1; case .relegated: next = index + 1 }
    guard leagues.indices.contains(next) else { return nil }
    return leagues[next]
}

/// Effective dates preserve the league for already joined and future cycles,
/// even when a promotion is recorded before its next-season effective date.
func siteLeague(_ site: OnlineSite, at date: Date = Date()) -> String {
    let changes = site.leagueChanges.enumerated().sorted { first, second in
        first.element.effectiveFrom == second.element.effectiveFrom ? first.offset < second.offset : first.element.effectiveFrom < second.element.effectiveFrom
    }.map(\.element)
    if let last = changes.last(where: { $0.effectiveFrom <= date }) { return last.toLeague }
    return site.leagueBaseline ?? changes.first?.fromLeague ?? site.affiliation
}
func siteLeagueEffectiveDate(_ site: OnlineSite, after event: GiriEvent, now: Date = Date()) -> Date {
    if let explicit = event.nextLeagueEffectiveDate { return explicit }
    if site.cycleSettings?.leagueChangesPerSeason == true, let end = event.siteSeasonEnd ?? site.cycleSettings?.seasonEnd { return end }
    return event.participationEndDate ?? now
}

// MARK: - 0.9 通常サイトのかんたん設定

/// 次のお題がいつ出るか。登録画面の選択肢で、保存は従来の recurrence / pattern / intervalDays。
enum SiteNextPromptTiming: String, CaseIterable, Identifiable {
    case withVoting, afterVoting, interval, irregular
    var id: String { rawValue }
    var title: String {
        switch self {
        case .withVoting: return "投票開始と同時"
        case .afterVoting: return "投票が終わってから"
        case .interval: return "決まった間隔"
        case .irregular: return "決まっていない"
        }
    }
    static func current(_ site: OnlineSite) -> SiteNextPromptTiming {
        guard site.recurrence == .weekly else { return .irregular }
        let settings = site.cycleSettings ?? SiteCycleSettings()
        if settings.pattern == .alternating { return .afterVoting }
        return settings.intervalDays == site.submissionDays ? .withVoting : .interval
    }
}

/// 選んだ出方を、日程の計算に使う保存項目へ反映する。
func applySiteTiming(_ timing: SiteNextPromptTiming, to site: inout OnlineSite, intervalDays: Int) {
    var settings = site.cycleSettings ?? SiteCycleSettings()
    switch timing {
    case .withVoting:
        site.recurrence = .weekly; settings.pattern = .overlapping; settings.intervalDays = site.submissionDays
    case .afterVoting:
        site.recurrence = .weekly; settings.pattern = .alternating; settings.intervalDays = site.submissionDays + site.votingDays
    case .interval:
        site.recurrence = .weekly; settings.pattern = .overlapping; settings.intervalDays = max(1, intervalDays)
    case .irregular:
        site.recurrence = .irregular
    }
    site.cycleSettings = settings
}

/// 今の状態（投稿中・投票中）とその締切から、この回の投稿開始を求める。
/// 投稿締切＝投票開始、投票締切＝結果発表として扱う。
func siteAnchorStart(posting: Bool, deadline: Date, submissionDays: Int, votingDays: Int, calendar: Calendar = .current) -> Date {
    posting ? addCalendarDays(deadline, -submissionDays, calendar: calendar)
        : addCalendarDays(deadline, -(submissionDays + votingDays), calendar: calendar)
}

/// シーズンの最後の通常回（「1シーズン○回」の最後）の投票締切。分からなければ nil。
func siteSeasonLastCycleEnd(_ site: OnlineSite, calendar: Calendar = .current) -> Date? {
    guard site.recurrence == .weekly, let settings = site.cycleSettings,
          let last = settings.regularCycleCount, last >= settings.anchorCycleNumber else { return nil }
    var round = EventRound()
    round.submissionStart = siteRegularCycleStart(settings, number: last, calendar: calendar)
    round = completeRoundSchedule(round, submissionDays: site.submissionDays, votingDays: site.votingDays)
    return round.votingEnd
}

// MARK: - 0.14 運営の都合で休みの回

/// 休みの回か（同じ分の投稿開始なら同じ回）。
func siteIsBreakStart(_ settings: SiteCycleSettings, _ start: Date) -> Bool {
    settings.breakStarts.contains { abs($0.timeIntervalSince(start)) < 60 }
}

/// 休みの回を飛ばした通常の回の番号。基準の回より後ろは、その間の休みの数だけ詰める。
/// 基準の回より前は、その間の休みの数だけ前の番号が小さくならない。
func siteRegularCycleNumber(_ settings: SiteCycleSettings, slotStart: Date, offset: Int) -> Int {
    let anchor = settings.anchorStart
    if offset >= 0 {
        let skipped = settings.breakStarts.filter { $0.timeIntervalSince(anchor) > -60 && slotStart.timeIntervalSince($0) > 60 }.count
        return settings.anchorCycleNumber + offset - skipped
    }
    let skipped = settings.breakStarts.filter { $0.timeIntervalSince(slotStart) > 60 && anchor.timeIntervalSince($0) > 60 }.count
    return settings.anchorCycleNumber + offset + skipped
}

/// 通常の回の番号から、その回の投稿開始（休みの回を飛ばす）。
func siteRegularCycleStart(_ settings: SiteCycleSettings, number: Int, calendar: Calendar = .current) -> Date {
    let target = number - settings.anchorCycleNumber
    // 前へ数える時は、基準の回の1つ前から数える。
    let backward = target < 0
    let step = backward ? -1 : 1
    let needed = backward ? -target - 1 : target
    let limit = needed + settings.breakStarts.count + 1
    var counted = 0
    var index = backward ? -1 : 0
    var start = settings.anchorStart
    for _ in 0...limit {
        start = addCalendarDays(settings.anchorStart, index * settings.intervalDays, calendar: calendar)
        if !siteIsBreakStart(settings, start) {
            if counted == needed { return start }
            counted += 1
        }
        index += step
    }
    return start
}

/// 休みにする／休みを取り消す。投稿開始は分単位で同じものを1つだけ残す。
func siteSettingsTogglingBreak(_ settings: SiteCycleSettings, start: Date, isBreak: Bool) -> SiteCycleSettings {
    var value = settings
    value.breakStarts.removeAll { abs($0.timeIntervalSince(start)) < 60 }
    if isBreak { value.breakStarts.append(start) }
    value.breakStarts.sort()
    return value
}

/// 今の投稿期間にあたる休みの回（カードに「今回は休み」を出す）。
func siteCurrentBreak(_ site: OnlineSite, now: Date = Date(), calendar: Calendar = .current) -> EventRound? {
    guard site.recurrence == .weekly, let settings = site.cycleSettings, !settings.waitingForNext else { return nil }
    for start in settings.breakStarts {
        var round = EventRound()
        round.submissionStart = start
        round = completeRoundSchedule(round, submissionDays: site.submissionDays, votingDays: site.votingDays)
        if round.isSubmissionOpen(now) { return round }
    }
    return nil
}

/// 次のシーズンの番号。番号がない旧設定は「第12シーズン」のような名前から読む。
func siteNextSeasonNumber(_ settings: SiteCycleSettings) -> Int {
    if let number = settings.seasonNumber { return number + 1 }
    let digits = settings.seasonName.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? settings.seasonName
    if let range = digits.range(of: #"[0-9]+"#, options: .regularExpression), let number = Int(digits[range]) { return number + 1 }
    return settings.seasonName.isEmpty ? 1 : 2
}

/// 次のシーズン：最初の回の投稿締切だけで、番号・名前・回数（1から）を進める。
/// 「1シーズン○回」と投稿・投票の日数は前のシーズンを引き継ぐ。
func siteNextSeasonSettings(_ site: OnlineSite, firstDeadline: Date, calendar: Calendar = .current) -> SiteCycleSettings {
    var value = site.cycleSettings ?? SiteCycleSettings()
    let number = siteNextSeasonNumber(value)
    value.seasonNumber = number
    value.seasonName = "第\(number)シーズン"
    value.seasonID = UUID().uuidString
    value.ruleRevisionID = UUID().uuidString
    value.anchorStart = addCalendarDays(firstDeadline, -site.submissionDays, calendar: calendar)
    value.anchorCycleNumber = 1
    value.seasonStart = value.anchorStart
    value.seasonEndsAt = nil
    value.seasonLengthDays = nil
    value.specialPeriods = []
    value.waitingForNext = false
    value.notBefore = nil
    value.breakStarts = []
    return value
}

/// 締切が決まっていないサイトの次の回。投稿締切だけ分かれば作れる。
func siteIrregularPeriod(_ site: OnlineSite, deadline: Date, votingEnd: Date? = nil, now: Date = Date(), calendar: Calendar = .current) -> SiteSpecialPeriod {
    let settings = site.cycleSettings ?? SiteCycleSettings()
    let regular = settings.specialPeriods.filter { $0.kind == .regular }
    let number = (regular.map(\.round.promptNumber).max() ?? 0) + 1
    let previousEnd = settings.specialPeriods.compactMap(\.round.submissionEnd).filter { $0 < deadline }.max()
    var period = SiteSpecialPeriod()
    period.kind = .regular
    period.title = "第\(number)回"
    period.seasonName = settings.seasonName
    var round = EventRound()
    round.name = period.title
    round.promptNumber = number
    round.submissionStart = previousEnd ?? min(now, deadline)
    round.submissionEnd = deadline
    round.votingStart = deadline
    round.votingEnd = votingEnd ?? addCalendarDays(deadline, site.votingDays, calendar: calendar)
    period.round = round
    return period
}

/// 次のお題を待っている間から、次の回の投稿締切で通常の回を再開する。
/// 回の番号は、これまでに記録した回の続き（画面で変えられる）。
func siteResumeSettings(_ site: OnlineSite, firstDeadline: Date, cycleNumber: Int?, calendar: Calendar = .current) -> SiteCycleSettings {
    var value = site.cycleSettings ?? SiteCycleSettings()
    let start = addCalendarDays(firstDeadline, -site.submissionDays, calendar: calendar)
    value.anchorStart = start
    value.notBefore = start
    value.waitingForNext = false
    // 再開した回より前の休みは、新しい番号の数え方に使わない。
    value.breakStarts.removeAll { $0.timeIntervalSince(start) < -60 }
    if let cycleNumber { value.anchorCycleNumber = max(1, cycleNumber) }
    if let cap = value.regularCycleCount, cap < value.anchorCycleNumber { value.regularCycleCount = nil }
    return value
}

/// 再開する回の番号の候補：今のシーズンで参加・見送り・結果を記録した通常の回の続き。
/// 記録がなければ今の番号のまま。
func siteSuggestedResumeCycleNumber(_ site: OnlineSite, events: [GiriEvent]) -> Int {
    let settings = site.cycleSettings ?? SiteCycleSettings()
    var latest: Int? = nil
    for event in events where event.onlineSiteId == site.id && event.sitePeriodKind == .regular {
        guard let number = event.siteCycleNumber else { continue }
        guard event.isActualParticipant || event.siteSkipped || event.hasCycleResult else { continue }
        if let season = settings.seasonID, let eventSeason = event.siteSeasonID, eventSeason != season { continue }
        latest = max(latest ?? number, number)
    }
    return latest.map { $0 + 1 } ?? max(1, settings.anchorCycleNumber)
}

// MARK: - 0.14 シーズンのルールと過去の回

/// リーグ・プレーオフ・入れ替え戦などがある、ルールが複雑なサイト。
/// シーズン明けのルール変更の確認と、過去の回のルールの同じ／違うは、このサイトだけで聞く。
func siteHasComplexRules(_ site: OnlineSite, events: [GiriEvent]) -> Bool {
    let settings = site.cycleSettings ?? SiteCycleSettings()
    if site.hasAffiliations || !settings.leagues.isEmpty || settings.leagueChangesPerSeason { return true }
    if settings.specialPeriods.contains(where: { $0.kind != .regular }) { return true }
    if site.ruleHistory.contains(where: { $0.settings.specialPeriods.contains { $0.kind != .regular } }) { return true }
    return events.contains { $0.onlineSiteId == site.id && ($0.siteQualification != .none || $0.sitePeriodKind != .regular) }
}

/// サイトでシーズンを使っているか（シーズン名・ID・合計成績のどれか）。
func siteUsesSeasons(_ site: OnlineSite) -> Bool {
    guard let settings = site.cycleSettings else { return false }
    return settings.seasonID != nil || !settings.seasonName.isEmpty || settings.trackSeasonTotals || settings.seasonNumber != nil
}

/// 過去に参加した回の入力。シーズン名が今のシーズンと同じなら今のシーズン、
/// 記録済みの過去のシーズンと同じならそのシーズンにまとめる。
struct SitePastCycleInput: Equatable {
    var seasonName: String = ""
    var cycleNumber: Int? = nil
    var kind: SitePeriodKind = .regular
    var deadline: Date
    var votingEnd: Date? = nil
    var league: String = ""
    /// ルールが今のシーズンと同じか（ルールが複雑なサイトで、違うシーズンの時だけ聞く）。
    var sameRulesAsCurrent: Bool = true
}

/// 過去のシーズンのID・ルールのID。今のシーズンと同じ名前なら今の値を使う。
/// 違うシーズンでルールが同じなら今のルールのID、違うならそのシーズン用のIDにする。
func sitePastSeasonIdentity(_ site: OnlineSite, input: SitePastCycleInput, events: [GiriEvent]) -> (seasonName: String, seasonID: String?, ruleID: String?, isCurrent: Bool) {
    let settings = site.cycleSettings ?? SiteCycleSettings()
    let name = input.seasonName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard siteUsesSeasons(site) else { return ("", nil, settings.ruleRevisionID, true) }
    if name.isEmpty || playerSearchKey(name) == playerSearchKey(settings.seasonName) {
        return (settings.seasonName, settings.seasonID, settings.ruleRevisionID, true)
    }
    let sameSeason = events.filter {
        $0.onlineSiteId == site.id && playerSearchKey($0.siteSeason) == playerSearchKey(name) && $0.siteSeasonID != settings.seasonID
    }
    let seasonID = sameSeason.compactMap(\.siteSeasonID).first ?? "past-season:" + UUID().uuidString
    if input.sameRulesAsCurrent { return (name, seasonID, settings.ruleRevisionID, false) }
    let pastRule = sameSeason.compactMap(\.siteRuleRevisionID).first { $0 != settings.ruleRevisionID }
    return (name, seasonID, pastRule ?? "past-rule:" + UUID().uuidString, false)
}

// MARK: - 0.23 ルール（ネット大喜利のシーズン・生大喜利の大会で使い回す）

/// ルールの種類。
enum GiriRuleKind: String, Codable, CaseIterable, Identifiable {
    case online, live
    var id: String { rawValue }
    var title: String { self == .online ? "ネット大喜利" : "生大喜利" }
}

/// シーズンの成績の出し方。
enum GiriRuleScoring: String, Codable, CaseIterable, Identifiable {
    /// 提出した全回答の平均。
    case allAnswers
    /// 規定回答数以上の時は、得票率の高い規定回答数分だけの平均。
    case topRequired
    var id: String { rawValue }
    var title: String { self == .allAnswers ? "全回答の平均" : "規定回答数の上位の平均" }
}

/// プレーオフ・入れ替え戦などの日程の決め方（最後の通常回の投票締切から何日後か）。
struct GiriRuleSpecialPlan: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var kind: SitePeriodKind = .playoff
    var title: String = ""
    /// 最後の通常回の投票締切から、何日後に投稿を始めるか。
    var startOffsetDays: Int = 0
    var submissionDays: Int = 7
    var votingDays: Int = 7
    /// 同じ種類の回を何回行うか。
    var count: Int = 1
}

extension GiriRuleSpecialPlan {
    private enum CodingKeys: String, CodingKey { case id, kind, title, startOffsetDays, submissionDays, votingDays, count }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        kind = (try? c.decodeIfPresent(SitePeriodKind.self, forKey: .kind)) ?? .other
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        startOffsetDays = max(0, try c.decodeIfPresent(Int.self, forKey: .startOffsetDays) ?? 0)
        submissionDays = max(1, try c.decodeIfPresent(Int.self, forKey: .submissionDays) ?? 7)
        votingDays = max(1, try c.decodeIfPresent(Int.self, forKey: .votingDays) ?? 7)
        count = max(1, try c.decodeIfPresent(Int.self, forKey: .count) ?? 1)
    }
    var displayTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? kind.title : title }
}

/// 生大喜利の大会の段階の骨組み（結果・順位・人数は持たない）。
struct GiriRuleStage: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    /// StageKind の値（知らない値は nil として扱う）。
    var kind: String? = nil
    var lineup: String = ""
    var judging: String = ""
    var promptCount: Int? = nil
    var advanceCount: Int? = nil
}

extension GiriRuleStage {
    private enum CodingKeys: String, CodingKey { case id, name, kind, lineup, judging, promptCount, advanceCount }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        lineup = try c.decodeIfPresent(String.self, forKey: .lineup) ?? ""
        judging = try c.decodeIfPresent(String.self, forKey: .judging) ?? ""
        promptCount = try c.decodeIfPresent(Int.self, forKey: .promptCount)
        advanceCount = try c.decodeIfPresent(Int.self, forKey: .advanceCount)
    }
    var stageKind: StageKind? { kind.flatMap(StageKind.init(rawValue:)) }
}

/// 保存して使い回すルール。ネット大喜利はシーズンごとに、生大喜利は大会ごとに選ぶ。
struct GiriRule: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    var kind: GiriRuleKind = .online
    var memo: String = ""
    // ネット大喜利
    var scoring: GiriRuleScoring = .allAnswers
    var requiredAnswerCount: Int? = nil
    var submissionDays: Int = 7
    var votingDays: Int = 7
    var nextPrompt: String = SiteNextPromptTiming.withVoting.rawValue
    var intervalDays: Int = 7
    /// 1シーズンの通常回の回数（分からない時は nil）。
    var regularCycleCount: Int? = nil
    var leagues: [String] = []
    var specialPlans: [GiriRuleSpecialPlan] = []
    // 生大喜利
    var tournamentFormat: TournamentFormat = .individual
    var knockout: Bool = false
    var judging: String = ""
    var stages: [GiriRuleStage] = []
    var updatedAt: Date = Date()

    var timing: SiteNextPromptTiming { SiteNextPromptTiming(rawValue: nextPrompt) ?? .withVoting }
    var displayName: String { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "名前のないルール" : name }

    func validate() throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...365).contains(submissionDays), (1...365).contains(votingDays), (1...730).contains(intervalDays),
              requiredAnswerCount.map({ (1...10000).contains($0) }) ?? true,
              regularCycleCount.map({ (1...10000).contains($0) }) ?? true,
              Set(specialPlans.map(\.id)).count == specialPlans.count, Set(stages.map(\.id)).count == stages.count else {
            throw GiriDataError.invalid("ルールの日数・回数を確認してください。")
        }
    }
}

extension GiriRule {
    private enum CodingKeys: String, CodingKey {
        case id, name, kind, memo, scoring, requiredAnswerCount, submissionDays, votingDays, nextPrompt, intervalDays, regularCycleCount, leagues, specialPlans, tournamentFormat, knockout, judging, stages, updatedAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = (try? c.decodeIfPresent(GiriRuleKind.self, forKey: .kind)) ?? .online
        memo = try c.decodeIfPresent(String.self, forKey: .memo) ?? ""
        scoring = (try? c.decodeIfPresent(GiriRuleScoring.self, forKey: .scoring)) ?? .allAnswers
        requiredAnswerCount = try c.decodeIfPresent(Int.self, forKey: .requiredAnswerCount)
        submissionDays = try c.decodeIfPresent(Int.self, forKey: .submissionDays) ?? 7
        votingDays = try c.decodeIfPresent(Int.self, forKey: .votingDays) ?? 7
        nextPrompt = try c.decodeIfPresent(String.self, forKey: .nextPrompt) ?? SiteNextPromptTiming.withVoting.rawValue
        intervalDays = try c.decodeIfPresent(Int.self, forKey: .intervalDays) ?? 7
        regularCycleCount = try c.decodeIfPresent(Int.self, forKey: .regularCycleCount)
        leagues = try c.decodeIfPresent([String].self, forKey: .leagues) ?? []
        specialPlans = try c.decodeIfPresent([GiriRuleSpecialPlan].self, forKey: .specialPlans) ?? []
        tournamentFormat = (try? c.decodeIfPresent(TournamentFormat.self, forKey: .tournamentFormat)) ?? .individual
        knockout = try c.decodeIfPresent(Bool.self, forKey: .knockout) ?? false
        judging = try c.decodeIfPresent(String.self, forKey: .judging) ?? ""
        stages = try c.decodeIfPresent([GiriRuleStage].self, forKey: .stages) ?? []
        updatedAt = try c.giriDate(forKey: .updatedAt, required: false, calendarOnly: false) ?? Date()
        try validate()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encode(memo, forKey: .memo)
        try c.encode(scoring, forKey: .scoring)
        try c.encodeIfPresent(requiredAnswerCount, forKey: .requiredAnswerCount)
        try c.encode(submissionDays, forKey: .submissionDays)
        try c.encode(votingDays, forKey: .votingDays)
        try c.encode(nextPrompt, forKey: .nextPrompt)
        try c.encode(intervalDays, forKey: .intervalDays)
        try c.encodeIfPresent(regularCycleCount, forKey: .regularCycleCount)
        try c.encode(leagues, forKey: .leagues)
        try c.encode(specialPlans, forKey: .specialPlans)
        try c.encode(tournamentFormat, forKey: .tournamentFormat)
        try c.encode(knockout, forKey: .knockout)
        try c.encode(judging, forKey: .judging)
        try c.encode(stages, forKey: .stages)
        try c.encode(GiriDates.timestamp(updatedAt), forKey: .updatedAt)
    }

    /// 一覧に出す短い説明。
    var summary: String {
        switch kind {
        case .online:
            var parts = [timing.title, "投稿\(submissionDays)日・投票\(votingDays)日"]
            if let count = regularCycleCount { parts.append("1シーズン\(count)回") }
            if scoring == .topRequired, let required = requiredAnswerCount { parts.append("規定\(required)回答") }
            if !specialPlans.isEmpty { parts.append(specialPlans.map(\.displayTitle).joined(separator: "・")) }
            return parts.joined(separator: "・")
        case .live:
            var parts = [tournamentFormat.title]
            if knockout { parts.append("トーナメント") }
            if !stages.isEmpty { parts.append(stages.map { $0.name.isEmpty ? ($0.stageKind?.title ?? "段階") : $0.name }.joined(separator: "→")) }
            return parts.joined(separator: "・")
        }
    }
}

/// シーズンのルールを引くキー（シーズンがないサイトはサイト全体で1つ）。
func giriSeasonRuleKey(_ seasonID: String?) -> String {
    let trimmed = seasonID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? "site" : trimmed
}

extension OnlineSite {
    /// そのシーズンに選んだルールのID。
    func ruleID(forSeason seasonID: String?) -> String? { seasonRuleIDs[giriSeasonRuleKey(seasonID)] }
    /// 今のシーズンに選んだルールのID。
    var currentRuleID: String? { ruleID(forSeason: cycleSettings?.seasonID) }
}

/// 今のサイトの設定からルールを作る（名前はサイト名・シーズン名から）。
func giriRule(from site: OnlineSite) -> GiriRule {
    let settings = site.cycleSettings ?? SiteCycleSettings()
    var rule = GiriRule()
    rule.kind = .online
    rule.name = [site.name, settings.seasonName].filter { !$0.isEmpty }.joined(separator: " ")
    rule.submissionDays = site.submissionDays
    rule.votingDays = site.votingDays
    let timing = SiteNextPromptTiming.current(site)
    rule.nextPrompt = timing.rawValue
    rule.intervalDays = timing == .interval ? settings.intervalDays : max(1, site.submissionDays)
    rule.regularCycleCount = settings.regularCycleCount
    rule.leagues = site.hasAffiliations ? settings.leagues : []
    return rule
}

/// ルールの日程・リーグ・回数をサイトに入れる（今の回の締切・番号は変えない）。
func giriApplyRule(_ rule: GiriRule, to site: inout OnlineSite) {
    guard rule.kind == .online else { return }
    site.submissionDays = rule.submissionDays
    site.votingDays = rule.votingDays
    applySiteTiming(rule.timing, to: &site, intervalDays: rule.intervalDays)
    var settings = site.cycleSettings ?? SiteCycleSettings()
    if let count = rule.regularCycleCount, count >= settings.anchorCycleNumber { settings.regularCycleCount = count }
    else if rule.regularCycleCount == nil { settings.regularCycleCount = nil }
    let leagues = rule.leagues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    if !leagues.isEmpty {
        settings.leagues = leagues
        site.hasAffiliations = true
        if !leagues.contains(site.affiliation) && site.affiliation.isEmpty { site.affiliation = leagues.last ?? "" }
    }
    site.cycleSettings = settings
    site.seasonRuleIDs[giriSeasonRuleKey(settings.seasonID)] = rule.id
    // プレーオフなどは、最後の通常回が分かる時だけ日程を作る。
    site.cycleSettings?.specialPeriods = giriRulePlanPeriods(rule, site: site)
}

/// ルールの「プレーオフ・入れ替え戦」から、シーズンの特別な日程を作る。
/// 最後の通常回の投票締切から数えるので、1シーズンの回数が分からない時は作らない。
/// 前にルールから作った日程は置き換え、手で入れた日程はそのまま残す。
func giriRulePlanPeriods(_ rule: GiriRule, site: OnlineSite, calendar: Calendar = .current) -> [SiteSpecialPeriod] {
    let settings = site.cycleSettings ?? SiteCycleSettings()
    var periods = settings.specialPeriods.filter { !$0.id.hasPrefix("rule-plan:") }
    guard rule.kind == .online, let lastEnd = siteSeasonLastCycleEnd(site, calendar: calendar) else { return periods }
    let sequentialAfterVoting = rule.timing == .afterVoting
    for plan in rule.specialPlans {
        var start = addCalendarDays(lastEnd, plan.startOffsetDays, calendar: calendar)
        for index in 0..<max(1, plan.count) {
            var period = SiteSpecialPeriod(id: "rule-plan:\(plan.id):\(index + 1)")
            period.kind = plan.kind
            period.title = plan.count > 1 ? plan.displayTitle + " \(index + 1)回目" : plan.displayTitle
            period.seasonName = settings.seasonName
            var round = EventRound()
            round.name = period.title
            round.submissionStart = start
            round = completeRoundSchedule(round, submissionDays: plan.submissionDays, votingDays: plan.votingDays)
            period.round = round
            periods.append(period)
            // 同じ種類の次の回：投票が終わってから出るルールなら投票締切から、そうでなければ投稿締切から。
            start = (sequentialAfterVoting ? round.votingEnd : round.submissionEnd) ?? addCalendarDays(start, plan.submissionDays, calendar: calendar)
        }
    }
    return periods
}

/// 生大喜利の大会の形式から、ルールを作る（段階の名前・種類・形式・審査方法・お題数・通過枠）。
func giriRule(from event: GiriEvent) -> GiriRule {
    var rule = GiriRule()
    rule.kind = .live
    rule.name = event.series.isEmpty ? event.title : event.series
    rule.tournamentFormat = event.tournamentFormat
    rule.knockout = event.knockout
    rule.judging = event.judging
    rule.stages = event.stageResults.map { stage in
        GiriRuleStage(name: stage.name, kind: stage.kind?.rawValue, lineup: stage.lineup, judging: stage.judging,
                      promptCount: stage.promptCount, advanceCount: stage.advanceCount)
    }
    return rule
}

/// 生大喜利のルールを大会に入れる（参加形式・対戦形式・審査方法）。段階は結果の入力で入れる。
func giriApplyRule(_ rule: GiriRule, to event: inout GiriEvent) {
    guard rule.kind == .live else { return }
    event.ruleID = rule.id
    event.tournamentFormat = rule.tournamentFormat
    event.knockout = rule.knockout
    if !rule.judging.isEmpty { event.judging = rule.judging }
}

/// ルールの段階を、結果の段階（未入力）にする。
func giriRuleStageResults(_ rule: GiriRule) -> [ResultStage] {
    rule.stages.map { item in
        var stage = ResultStage()
        stage.name = item.name
        stage.kind = item.stageKind
        stage.lineup = item.lineup
        stage.judging = item.judging
        stage.promptCount = item.promptCount
        stage.advanceCount = item.advanceCount
        return stage
    }
}
