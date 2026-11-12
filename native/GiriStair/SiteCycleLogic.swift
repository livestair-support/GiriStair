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

/// 0.30：次のシーズンを始める時に確認する日程。シーズンごとに開始・日数・出方・回数を見直す。
struct SiteSeasonSchedule: Equatable {
    var firstDeadline: Date
    var submissionDays: Int
    var votingDays: Int
    var timing: SiteNextPromptTiming
    var intervalDays: Int
    var regularCycleCount: Int?

    /// 最初の回の投稿開始（＝シーズンの開始）。
    func firstStart(calendar: Calendar = .current) -> Date { addCalendarDays(firstDeadline, -submissionDays, calendar: calendar) }
}

/// 次のシーズンの日程の初期値：前のシーズンの日程（ルールを選んだ時はそのルールの日程）。
func siteSeasonSchedule(_ site: OnlineSite, rule: GiriRule?, firstDeadline: Date, calendar: Calendar = .current) -> SiteSeasonSchedule {
    var copy = site
    if let rule, rule.kind == .online, rule.effectiveScope == .regular {
        copy.submissionDays = rule.submissionDays
        copy.votingDays = rule.votingDays
    }
    copy.cycleSettings = siteNextSeasonSettings(copy, firstDeadline: firstDeadline, calendar: calendar)
    if let rule { giriApplyRule(rule, to: &copy) }
    let settings = copy.cycleSettings ?? SiteCycleSettings()
    let timing = SiteNextPromptTiming.current(copy)
    return SiteSeasonSchedule(firstDeadline: firstDeadline, submissionDays: copy.submissionDays, votingDays: copy.votingDays,
                              timing: timing, intervalDays: max(1, settings.intervalDays),
                              regularCycleCount: timing == .irregular ? nil : settings.regularCycleCount)
}

/// 確認した日程で次のシーズンを始める。ルールのリーグ・プレーオフも入れ、日程は確認した値を使う。
func siteStartingNextSeason(_ site: OnlineSite, schedule: SiteSeasonSchedule, rule: GiriRule?, calendar: Calendar = .current) -> OnlineSite {
    var value = site
    value.submissionDays = max(1, schedule.submissionDays)
    value.votingDays = max(1, schedule.votingDays)
    value.cycleSettings = siteNextSeasonSettings(value, firstDeadline: schedule.firstDeadline, calendar: calendar)
    if let rule { giriApplyRule(rule, to: &value) }
    // ルールより、このシーズンに確認した日程を優先する。
    value.submissionDays = max(1, schedule.submissionDays)
    value.votingDays = max(1, schedule.votingDays)
    applySiteTiming(schedule.timing, to: &value, intervalDays: schedule.intervalDays)
    let start = addCalendarDays(schedule.firstDeadline, -value.submissionDays, calendar: calendar)
    value.cycleSettings?.anchorStart = start
    value.cycleSettings?.seasonStart = start
    value.cycleSettings?.regularCycleCount = schedule.timing == .irregular ? nil : schedule.regularCycleCount.map { max(1, $0) }
    if schedule.timing == .irregular {
        // 締切が決まっていないサイトは、最初の回をその締切で作る。
        value.cycleSettings?.specialPeriods.removeAll { $0.kind == .regular }
        let first = siteIrregularPeriod(value, deadline: schedule.firstDeadline, now: start, calendar: calendar)
        value.cycleSettings?.specialPeriods.append(first)
    }
    if let rule, rule.kind == .online, rule.effectiveScope == .regular {
        // 確認した回数・日数から、プレーオフなどの日程を作り直す。
        let planned = giriRulePlanPeriods(rule, site: value, calendar: calendar)
        value.cycleSettings?.specialPeriods = planned
    }
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
    /// 生大喜利とスプシ系は大会の形が同じことが多いので、同じルールを使う。
    var title: String { self == .online ? "ネット大喜利" : "生大喜利・スプシ系" }
}

/// 0.27：通常（サイトのシーズン）と大会でルールを分ける。生大喜利・スプシ系のルールは大会だけ。
enum GiriRuleScope: String, Codable, CaseIterable, Identifiable {
    case regular, tournament
    var id: String { rawValue }
    var title: String { self == .regular ? "通常" : "大会" }
}

/// シーズン・大会の成績の出し方。
enum GiriRuleScoring: String, Codable, CaseIterable, Identifiable {
    /// 提出した全回答の平均。
    case allAnswers
    /// 規定回答数以上の時は、得票率の高い規定回答数分だけの平均。
    case topRequired
    /// 0.27：合計得点の順。
    case total
    /// 0.27：回ごとに勝ち抜けを決める（平均・合計は出さない）。
    case perRound
    var id: String { rawValue }
    var title: String {
        switch self {
        case .allAnswers: return "全回答の平均"
        case .topRequired: return "規定回答数の上位の平均"
        case .total: return "合計得点"
        case .perRound: return "回ごとの勝ち抜け（平均なし）"
        }
    }
}

/// 0.27：勝ち抜けの割合（上位1/2など）。
let giriAdvanceFractions: [(value: String, title: String)] = [("1/2", "半数"), ("2/3", "3分の2"), ("1/3", "3分の1"), ("1/4", "4分の1"), ("3/4", "4分の3")]

/// 「1/2」などを分数として読む（読めない時は nil）。
func giriFraction(_ text: String?) -> (numerator: Int, denominator: Int)? {
    guard let text else { return nil }
    let parts = text.split(separator: "/").map { Int($0.trimmingCharacters(in: .whitespaces)) }
    guard parts.count == 2, let numerator = parts[0], let denominator = parts[1], numerator > 0, denominator > 0, numerator <= denominator else { return nil }
    return (numerator, denominator)
}

/// 勝ち抜けの条件の短い説明（上位8人・上位半数など）。
func giriAdvanceText(count: Int?, fraction: String?) -> String? {
    if let count { return "上位\(count)人" }
    if let fraction, giriFraction(fraction) != nil {
        return "上位" + (giriAdvanceFractions.first { $0.value == fraction }?.title ?? fraction)
    }
    return nil
}

/// 割合で決める勝ち抜け・規定数を人数・回数にする（端数は切り上げ）。
func giriFractionCount(_ fraction: String?, of total: Int) -> Int? {
    guard let value = giriFraction(fraction), total > 0 else { return nil }
    return (total * value.numerator + value.denominator - 1) / value.denominator
}

/// 0.27：リーグごとの決まり（規定数・お題の選び方・昇格／降格の人数）。
struct GiriRuleLeague: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    /// 集計に入る規定数（結果が出たお題の数に対する割合。例：1/2）。
    var requiredFraction: String? = nil
    /// 集計に入る規定数（回数で決まっている時）。
    var requiredCount: Int? = nil
    /// 何題から1題を選んで回答するか。
    var promptChoices: Int? = nil
    /// 上位何人が上のリーグへ上がるか。
    var promotionCount: Int? = nil
    /// 下位何人が下のリーグへ下がるか。
    var relegationCount: Int? = nil
    /// 規定数に届かない人を最下位にするか。
    var unqualifiedRanksLast: Bool = false
    /// 0.28：リーグの呼び名（NIGHT・DAY など。任意）。
    var subtitle: String = ""
    /// 0.28：成績は得票率の高い上から何回答（ボケ）の平均か（例：1部は8、2部は4）。
    var topAnswerCount: Int? = nil
    /// 0.28：上位何人が残留するか（表示用）。
    var stayCount: Int? = nil
    /// 0.28：回答数が足りない人を集計に入れない（最下位にはしない）。
    var unqualifiedExcluded: Bool = false
    /// 0.28：リーグごとの日程（空ならルール全体の日数）。エントリーは投稿の前の期間。
    var entryDays: Int? = nil
    var submissionDays: Int? = nil
    var votingDays: Int? = nil
    /// 0.28：1題につき何回答まで出せるか。
    var answersPerPrompt: Int? = nil
}

extension GiriRuleLeague {
    private enum CodingKeys: String, CodingKey {
        case id, name, requiredFraction, requiredCount, promptChoices, promotionCount, relegationCount, unqualifiedRanksLast
        case subtitle, topAnswerCount, stayCount, unqualifiedExcluded, entryDays, submissionDays, votingDays, answersPerPrompt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        requiredFraction = try c.decodeIfPresent(String.self, forKey: .requiredFraction)
        requiredCount = try c.decodeIfPresent(Int.self, forKey: .requiredCount)
        promptChoices = try c.decodeIfPresent(Int.self, forKey: .promptChoices)
        promotionCount = try c.decodeIfPresent(Int.self, forKey: .promotionCount)
        relegationCount = try c.decodeIfPresent(Int.self, forKey: .relegationCount)
        unqualifiedRanksLast = try c.decodeIfPresent(Bool.self, forKey: .unqualifiedRanksLast) ?? false
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        topAnswerCount = try c.decodeIfPresent(Int.self, forKey: .topAnswerCount)
        stayCount = try c.decodeIfPresent(Int.self, forKey: .stayCount)
        unqualifiedExcluded = try c.decodeIfPresent(Bool.self, forKey: .unqualifiedExcluded) ?? false
        entryDays = try c.decodeIfPresent(Int.self, forKey: .entryDays)
        submissionDays = try c.decodeIfPresent(Int.self, forKey: .submissionDays)
        votingDays = try c.decodeIfPresent(Int.self, forKey: .votingDays)
        answersPerPrompt = try c.decodeIfPresent(Int.self, forKey: .answersPerPrompt)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(requiredFraction, forKey: .requiredFraction)
        try c.encodeIfPresent(requiredCount, forKey: .requiredCount)
        try c.encodeIfPresent(promptChoices, forKey: .promptChoices)
        try c.encodeIfPresent(promotionCount, forKey: .promotionCount)
        try c.encodeIfPresent(relegationCount, forKey: .relegationCount)
        if unqualifiedRanksLast { try c.encode(true, forKey: .unqualifiedRanksLast) }
        if !subtitle.isEmpty { try c.encode(subtitle, forKey: .subtitle) }
        try c.encodeIfPresent(topAnswerCount, forKey: .topAnswerCount)
        try c.encodeIfPresent(stayCount, forKey: .stayCount)
        if unqualifiedExcluded { try c.encode(true, forKey: .unqualifiedExcluded) }
        try c.encodeIfPresent(entryDays, forKey: .entryDays)
        try c.encodeIfPresent(submissionDays, forKey: .submissionDays)
        try c.encodeIfPresent(votingDays, forKey: .votingDays)
        try c.encodeIfPresent(answersPerPrompt, forKey: .answersPerPrompt)
    }
    /// シーズンの規定数（回数）。割合の時は、1シーズンの回数から数える。
    func requiredAnswers(cycleCount: Int?) -> Int? {
        if let requiredCount { return requiredCount }
        guard let cycleCount else { return nil }
        return giriFractionCount(requiredFraction, of: cycleCount)
    }
    /// 一覧・詳細に出す短い説明。
    var summary: String {
        var parts: [String] = []
        if !subtitle.isEmpty { parts.append(subtitle) }
        if let top = topAnswerCount { parts.append("上位\(top)回答の得票率の平均") }
        if let requiredCount { parts.append("規定\(requiredCount)回以上") }
        else if let fraction = requiredFraction, giriFraction(fraction) != nil { parts.append("規定：結果お題数の\(fraction)以上") }
        if let choices = promptChoices { parts.append("\(choices)題から1題") }
        if let up = promotionCount { parts.append("上位\(up)昇格") }
        if let stay = stayCount { parts.append("上位\(stay)残留") }
        if let down = relegationCount { parts.append("下位\(down)降格") }
        if unqualifiedRanksLast { parts.append("足りない時は最下位") }
        if unqualifiedExcluded { parts.append("足りない時は集計対象外") }
        let days = [entryDays.map { "エントリー\($0)日" }, submissionDays.map { "投稿\($0)日" }, votingDays.map { "投票\($0)日" }].compactMap { $0 }
        if !days.isEmpty { parts.append(days.joined(separator: "・")) }
        if let answers = answersPerPrompt { parts.append("1題につき\(answers)回答") }
        return parts.joined(separator: "・")
    }
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
    /// 0.27：出られる人数（上位何人）と、どのリーグから出るか。
    var entrantCount: Int? = nil
    var entrantLeague: String = ""
    /// 0.27：順位の決め方（GiriRuleScoring の値。空はシーズンと同じ）。
    var ranking: String = ""
    /// 0.27：シーズンの成績に含めるか（プレーオフ・エキシビションは含めないことが多い）。
    var countsInSeason: Bool = false
    /// 0.28：1人（1組）が出せる回答の数。
    var answersPerEntrant: Int? = nil
}

extension GiriRuleSpecialPlan {
    private enum CodingKeys: String, CodingKey { case id, kind, title, startOffsetDays, submissionDays, votingDays, count, entrantCount, entrantLeague, ranking, countsInSeason, answersPerEntrant }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        kind = (try? c.decodeIfPresent(SitePeriodKind.self, forKey: .kind)) ?? .other
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        startOffsetDays = max(0, try c.decodeIfPresent(Int.self, forKey: .startOffsetDays) ?? 0)
        submissionDays = max(1, try c.decodeIfPresent(Int.self, forKey: .submissionDays) ?? 7)
        votingDays = max(1, try c.decodeIfPresent(Int.self, forKey: .votingDays) ?? 7)
        count = max(1, try c.decodeIfPresent(Int.self, forKey: .count) ?? 1)
        entrantCount = try c.decodeIfPresent(Int.self, forKey: .entrantCount)
        entrantLeague = try c.decodeIfPresent(String.self, forKey: .entrantLeague) ?? ""
        ranking = try c.decodeIfPresent(String.self, forKey: .ranking) ?? ""
        countsInSeason = try c.decodeIfPresent(Bool.self, forKey: .countsInSeason) ?? false
        answersPerEntrant = try c.decodeIfPresent(Int.self, forKey: .answersPerEntrant)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(title, forKey: .title)
        try c.encode(startOffsetDays, forKey: .startOffsetDays)
        try c.encode(submissionDays, forKey: .submissionDays)
        try c.encode(votingDays, forKey: .votingDays)
        try c.encode(count, forKey: .count)
        try c.encodeIfPresent(entrantCount, forKey: .entrantCount)
        if !entrantLeague.isEmpty { try c.encode(entrantLeague, forKey: .entrantLeague) }
        if !ranking.isEmpty { try c.encode(ranking, forKey: .ranking) }
        if countsInSeason { try c.encode(true, forKey: .countsInSeason) }
        try c.encodeIfPresent(answersPerEntrant, forKey: .answersPerEntrant)
    }
    var displayTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? kind.title : title }
    /// 0.27：出る人・順位の決め方・シーズンに含めるかの短い説明。
    var detailText: String {
        var parts: [String] = []
        if let entrants = entrantCount { parts.append((entrantLeague.isEmpty ? "" : entrantLeague) + "上位\(entrants)人") }
        if let scoring = GiriRuleScoring(rawValue: ranking) { parts.append(scoring.title + "の順") }
        if let answers = answersPerEntrant { parts.append("\(answers)回答") }
        parts.append(countsInSeason ? "シーズン成績に含める" : "シーズン成績に含めない")
        return parts.joined(separator: "・")
    }
}

/// 0.28：通常のサイトの「タッグ」部門（シングルとは別の順位。2人で組み、2人の成績を合わせる）。
struct GiriRuleTagDivision: Codable, Equatable {
    var name: String = "タッグ"
    /// 1組の人数。
    var memberCount: Int = 2
    /// 組の成績の出し方（"sum"：2人の値の合計・"average"：平均）。
    var teamScoring: String = "sum"
    /// リーグごとの決まり（入れ替え・残留の組数、上位何回答の平均、組んでいない人の扱い）。名前はシングルと同じ。
    var leagueDetails: [GiriRuleLeague] = []
    /// 回答数が足りない人は、その人の値を0にする。
    var memberShortfallZero: Bool = false
    /// 同率の時の決め方。
    var tieBreak: String = ""
    /// プレーオフに出る組数。
    var playoffEntrants: Int? = nil
    /// 組む・解消するの決まり（メモ）。
    var formationNote: String = ""

    static let scorings: [(value: String, title: String)] = [("sum", "2人の値を合計"), ("average", "2人の値を平均")]
    var scoringTitle: String { Self.scorings.first { $0.value == teamScoring }?.title ?? "2人の値を合計" }
    func leagueDetail(_ name: String) -> GiriRuleLeague { leagueDetails.first { $0.name == name } ?? GiriRuleLeague(name: name) }
}

extension GiriRuleTagDivision {
    private enum CodingKeys: String, CodingKey { case name, memberCount, teamScoring, leagueDetails, memberShortfallZero, tieBreak, playoffEntrants, formationNote }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "タッグ"
        memberCount = max(2, try c.decodeIfPresent(Int.self, forKey: .memberCount) ?? 2)
        teamScoring = try c.decodeIfPresent(String.self, forKey: .teamScoring) ?? "sum"
        leagueDetails = try c.decodeIfPresent([GiriRuleLeague].self, forKey: .leagueDetails) ?? []
        memberShortfallZero = try c.decodeIfPresent(Bool.self, forKey: .memberShortfallZero) ?? false
        tieBreak = try c.decodeIfPresent(String.self, forKey: .tieBreak) ?? ""
        playoffEntrants = try c.decodeIfPresent(Int.self, forKey: .playoffEntrants)
        formationNote = try c.decodeIfPresent(String.self, forKey: .formationNote) ?? ""
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(memberCount, forKey: .memberCount)
        try c.encode(teamScoring, forKey: .teamScoring)
        let details = leagueDetails.filter { !$0.summary.isEmpty }
        if !details.isEmpty { try c.encode(details, forKey: .leagueDetails) }
        if memberShortfallZero { try c.encode(true, forKey: .memberShortfallZero) }
        if !tieBreak.isEmpty { try c.encode(tieBreak, forKey: .tieBreak) }
        try c.encodeIfPresent(playoffEntrants, forKey: .playoffEntrants)
        if !formationNote.isEmpty { try c.encode(formationNote, forKey: .formationNote) }
    }
    /// 一覧・詳細に出す短い説明。
    var summary: String {
        var parts = ["\(memberCount)人1組", scoringTitle]
        if memberShortfallZero { parts.append("回答が足りない人は0") }
        if let entrants = playoffEntrants { parts.append("プレーオフ上位\(entrants)組") }
        return parts.joined(separator: "・")
    }
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
    /// 0.27：割合で決める勝ち抜け（上位1/2など）。人数で決める時は advanceCount。
    var advanceFraction: String? = nil
    /// 0.27：ほかの勝ち抜けの条件（得点・ボーダーなど）のメモ。
    var advanceNote: String = ""
    /// 0.28：この段階でのメンバーの変更（"add"：増やせる・"swap"：入れ替えられる。空は変えない）と人数。
    var memberChange: String = ""
    var memberChangeCount: Int? = nil
}

/// 0.28：段階でのメンバーの変更の選び方。
let giriRuleMemberChanges: [(value: String, title: String)] = [("add", "メンバーを増やせる"), ("swap", "メンバーを入れ替えられる")]

/// 0.27：段階ごとの形式（準決勝だけタイマン、など）。
let giriRuleStageLineups = ["横並び", "タイマン（1対1）", "グループ対戦", "リーグ（総当たり）", "お題ごとに勝ち抜け"]

extension GiriRuleStage {
    private enum CodingKeys: String, CodingKey { case id, name, kind, lineup, judging, promptCount, advanceCount, advanceFraction, advanceNote, memberChange, memberChangeCount }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        lineup = try c.decodeIfPresent(String.self, forKey: .lineup) ?? ""
        judging = try c.decodeIfPresent(String.self, forKey: .judging) ?? ""
        promptCount = try c.decodeIfPresent(Int.self, forKey: .promptCount)
        advanceCount = try c.decodeIfPresent(Int.self, forKey: .advanceCount)
        advanceFraction = try c.decodeIfPresent(String.self, forKey: .advanceFraction)
        advanceNote = try c.decodeIfPresent(String.self, forKey: .advanceNote) ?? ""
        memberChange = try c.decodeIfPresent(String.self, forKey: .memberChange) ?? ""
        memberChangeCount = try c.decodeIfPresent(Int.self, forKey: .memberChangeCount)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(kind, forKey: .kind)
        try c.encode(lineup, forKey: .lineup)
        try c.encode(judging, forKey: .judging)
        try c.encodeIfPresent(promptCount, forKey: .promptCount)
        try c.encodeIfPresent(advanceCount, forKey: .advanceCount)
        try c.encodeIfPresent(advanceFraction, forKey: .advanceFraction)
        if !advanceNote.isEmpty { try c.encode(advanceNote, forKey: .advanceNote) }
        if !memberChange.isEmpty { try c.encode(memberChange, forKey: .memberChange) }
        try c.encodeIfPresent(memberChangeCount, forKey: .memberChangeCount)
    }
    /// 0.28：メンバーの変更の短い説明（「2人まで増やせる」など）。
    var memberChangeText: String? {
        guard let title = giriRuleMemberChanges.first(where: { $0.value == memberChange })?.title else { return nil }
        return memberChangeCount.map { "\($0)人まで" + title.replacingOccurrences(of: "メンバーを", with: "") } ?? title
    }
    var stageKind: StageKind? { kind.flatMap(StageKind.init(rawValue:)) }
    /// 0.27：勝ち抜けの条件（上位8人・上位半数など）。
    var advanceText: String? { giriAdvanceText(count: advanceCount, fraction: advanceFraction) }
}

/// 保存して使い回すルール。ネット大喜利はシーズンごとに、生大喜利は大会ごとに選ぶ。
struct GiriRule: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    var kind: GiriRuleKind = .online
    /// 0.27：通常（シーズン）か大会か。生大喜利・スプシ系は大会だけ。
    var scope: GiriRuleScope = .regular
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
    /// 0.24：シーズンの上位○人が勝ち抜け（次の段階・昇格など）。自動では判定しない。
    var advanceCount: Int? = nil
    var leagues: [String] = []
    /// 0.27：リーグごとの決まり（名前は leagues と同じ順）。
    var leagueDetails: [GiriRuleLeague] = []
    /// 0.27：割合で決める勝ち抜け（上位1/2など）。
    var advanceFraction: String? = nil
    /// 0.27：同率の時の決め方（例：投稿数が多い方を上位）。
    var tieBreak: String = ""
    /// 0.27：投票した時のボーナス点。
    var voteBonusPoints: Int? = nil
    /// 0.27：チーム戦の回答の出し方（"each"：各自が回答して合計・"team"：チームで回答を出す）。
    var teamAnswerStyle: String? = nil
    /// 0.28：エントリー（申し込み）の期間・定員・決まり。大会や、回の前にエントリーがあるサイトで使う。
    var entryDays: Int? = nil
    var capacity: Int? = nil
    var entryNote: String = ""
    /// 0.28：通常のサイトの「タッグ」部門（なければ nil）。
    var tagDivision: GiriRuleTagDivision? = nil
    /// 0.28：大会の途中でメンバーが変わる（段階ごとに増やせる・入れ替えられる）。
    var hasMemberChanges: Bool = false
    var specialPlans: [GiriRuleSpecialPlan] = []
    // 生大喜利
    var tournamentFormat: TournamentFormat = .individual
    var knockout: Bool = false
    var judging: String = ""
    var stages: [GiriRuleStage] = []
    var updatedAt: Date = Date()

    var timing: SiteNextPromptTiming { SiteNextPromptTiming(rawValue: nextPrompt) ?? .withVoting }
    /// 0.27：生大喜利・スプシ系は大会だけ。
    var effectiveScope: GiriRuleScope { kind == .live ? .tournament : scope }
    /// 0.27：成績の出し方は、大会と、リーグ・シーズンのある通常で使う。
    var usesScoring: Bool { effectiveScope == .tournament || !leagues.isEmpty || regularCycleCount != nil }
    /// 0.27：リーグの決まり（名前で引く。なければ名前だけ）。
    func leagueDetail(_ name: String) -> GiriRuleLeague {
        leagueDetails.first { $0.name == name } ?? GiriRuleLeague(name: name)
    }
    /// 0.27：リーグ名を並べ直す（決まりは同じ名前のものを残す）。
    mutating func setLeagues(_ names: [String]) {
        leagues = names
        leagueDetails = names.map { leagueDetail($0) }
        if let tag = tagDivision { tagDivision?.leagueDetails = names.map { tag.leagueDetail($0) } }
    }
    /// 0.28：シングル／タッグのどちらかのリーグの決まり（タッグ部門がない時はシングル）。
    func leagueDetail(_ name: String, tag: Bool) -> GiriRuleLeague {
        if tag, let division = tagDivision { return division.leagueDetail(name) }
        return leagueDetail(name)
    }
    static let teamAnswerStyles: [(value: String, title: String)] = [("each", "各自が回答して合計"), ("team", "チームで回答を出す")]
    var displayName: String { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "名前のないルール" : name }

    /// 0.24：複製（新しいIDで「のコピー」を付ける。プレーオフ・段階も新しいIDにする）。
    func duplicated(now: Date = Date()) -> GiriRule {
        var copy = self
        copy.id = UUID().uuidString
        copy.name = displayName + "のコピー"
        copy.specialPlans = specialPlans.map { var plan = $0; plan.id = UUID().uuidString; return plan }
        copy.leagueDetails = leagueDetails.map { var league = $0; league.id = UUID().uuidString; return league }
        copy.tagDivision?.leagueDetails = (tagDivision?.leagueDetails ?? []).map { var league = $0; league.id = UUID().uuidString; return league }
        copy.stages = stages.map { var stage = $0; stage.id = UUID().uuidString; return stage }
        copy.updatedAt = now
        return copy
    }

    func validate() throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...365).contains(submissionDays), (1...365).contains(votingDays), (1...730).contains(intervalDays),
              requiredAnswerCount.map({ (1...10000).contains($0) }) ?? true,
              advanceCount.map({ (1...10000).contains($0) }) ?? true,
              voteBonusPoints.map({ (0...10000).contains($0) }) ?? true,
              entryDays.map({ (1...365).contains($0) }) ?? true,
              capacity.map({ (1...100000).contains($0) }) ?? true,
              regularCycleCount.map({ (1...10000).contains($0) }) ?? true,
              Set(specialPlans.map(\.id)).count == specialPlans.count, Set(stages.map(\.id)).count == stages.count else {
            throw GiriDataError.invalid("ルールの日数・回数を確認してください。")
        }
    }
}

extension GiriRule {
    private enum CodingKeys: String, CodingKey {
        case id, name, kind, scope, memo, scoring, requiredAnswerCount, submissionDays, votingDays, nextPrompt, intervalDays, regularCycleCount, advanceCount, leagues, specialPlans, tournamentFormat, knockout, judging, stages, updatedAt
        case leagueDetails, advanceFraction, tieBreak, voteBonusPoints, teamAnswerStyle, entryDays, capacity, entryNote, tagDivision, hasMemberChanges
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = (try? c.decodeIfPresent(GiriRuleKind.self, forKey: .kind)) ?? .online
        // 0.26以前のルールは、ネットは通常・生は大会として読む。
        scope = (try? c.decodeIfPresent(GiriRuleScope.self, forKey: .scope)) ?? (kind == .live ? .tournament : .regular)
        memo = try c.decodeIfPresent(String.self, forKey: .memo) ?? ""
        scoring = (try? c.decodeIfPresent(GiriRuleScoring.self, forKey: .scoring)) ?? .allAnswers
        requiredAnswerCount = try c.decodeIfPresent(Int.self, forKey: .requiredAnswerCount)
        submissionDays = try c.decodeIfPresent(Int.self, forKey: .submissionDays) ?? 7
        votingDays = try c.decodeIfPresent(Int.self, forKey: .votingDays) ?? 7
        nextPrompt = try c.decodeIfPresent(String.self, forKey: .nextPrompt) ?? SiteNextPromptTiming.withVoting.rawValue
        intervalDays = try c.decodeIfPresent(Int.self, forKey: .intervalDays) ?? 7
        regularCycleCount = try c.decodeIfPresent(Int.self, forKey: .regularCycleCount)
        advanceCount = try c.decodeIfPresent(Int.self, forKey: .advanceCount)
        let leagueNames = try c.decodeIfPresent([String].self, forKey: .leagues) ?? []
        leagues = leagueNames
        let details = try c.decodeIfPresent([GiriRuleLeague].self, forKey: .leagueDetails) ?? []
        // 決まりを書いていない（0.26以前の）ルールは空のまま読む（名前だけのリーグは leagueDetail で引ける）。
        leagueDetails = details.isEmpty ? [] : leagueNames.map { name in details.first { $0.name == name } ?? GiriRuleLeague(name: name) }
        advanceFraction = try c.decodeIfPresent(String.self, forKey: .advanceFraction)
        tieBreak = try c.decodeIfPresent(String.self, forKey: .tieBreak) ?? ""
        voteBonusPoints = try c.decodeIfPresent(Int.self, forKey: .voteBonusPoints)
        teamAnswerStyle = try c.decodeIfPresent(String.self, forKey: .teamAnswerStyle)
        entryDays = try c.decodeIfPresent(Int.self, forKey: .entryDays)
        capacity = try c.decodeIfPresent(Int.self, forKey: .capacity)
        entryNote = try c.decodeIfPresent(String.self, forKey: .entryNote) ?? ""
        tagDivision = try c.decodeIfPresent(GiriRuleTagDivision.self, forKey: .tagDivision)
        hasMemberChanges = try c.decodeIfPresent(Bool.self, forKey: .hasMemberChanges) ?? false
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
        try c.encode(scope, forKey: .scope)
        try c.encode(memo, forKey: .memo)
        try c.encode(scoring, forKey: .scoring)
        try c.encodeIfPresent(requiredAnswerCount, forKey: .requiredAnswerCount)
        try c.encode(submissionDays, forKey: .submissionDays)
        try c.encode(votingDays, forKey: .votingDays)
        try c.encode(nextPrompt, forKey: .nextPrompt)
        try c.encode(intervalDays, forKey: .intervalDays)
        try c.encodeIfPresent(regularCycleCount, forKey: .regularCycleCount)
        try c.encodeIfPresent(advanceCount, forKey: .advanceCount)
        try c.encode(leagues, forKey: .leagues)
        // 0.27：決まりを入れたリーグだけ書く。
        let details = leagueDetails.filter { !$0.summary.isEmpty && leagues.contains($0.name) }
        if !details.isEmpty { try c.encode(details, forKey: .leagueDetails) }
        try c.encodeIfPresent(advanceFraction, forKey: .advanceFraction)
        if !tieBreak.isEmpty { try c.encode(tieBreak, forKey: .tieBreak) }
        try c.encodeIfPresent(voteBonusPoints, forKey: .voteBonusPoints)
        try c.encodeIfPresent(teamAnswerStyle, forKey: .teamAnswerStyle)
        try c.encodeIfPresent(entryDays, forKey: .entryDays)
        try c.encodeIfPresent(capacity, forKey: .capacity)
        if !entryNote.isEmpty { try c.encode(entryNote, forKey: .entryNote) }
        try c.encodeIfPresent(tagDivision, forKey: .tagDivision)
        if hasMemberChanges { try c.encode(true, forKey: .hasMemberChanges) }
        try c.encode(specialPlans, forKey: .specialPlans)
        try c.encode(tournamentFormat, forKey: .tournamentFormat)
        try c.encode(knockout, forKey: .knockout)
        try c.encode(judging, forKey: .judging)
        try c.encode(stages, forKey: .stages)
        try c.encode(GiriDates.timestamp(updatedAt), forKey: .updatedAt)
    }

    /// 一覧に出す短い説明。
    var summary: String {
        var parts: [String] = []
        if effectiveScope == .tournament {
            parts.append(tournamentFormat.title)
            if knockout && kind == .live { parts.append("トーナメント") }
            if kind == .online { parts.append("投稿\(submissionDays)日・投票\(votingDays)日") }
            if !stages.isEmpty { parts.append(stages.map { $0.name.isEmpty ? ($0.stageKind?.title ?? "段階") : $0.name }.joined(separator: "→")) }
        } else {
            parts = [timing.title, "投稿\(submissionDays)日・投票\(votingDays)日"]
            if let count = regularCycleCount { parts.append("全\(count)回で1シーズン") }
            if !leagues.isEmpty { parts.append(leagues.joined(separator: "・")) }
        }
        if usesScoring && scoring != .allAnswers { parts.append(scoring.title) }
        if scoring == .topRequired, let required = requiredAnswerCount { parts.append("規定\(required)回答") }
        if let advance = giriAdvanceText(count: advanceCount, fraction: advanceFraction) { parts.append(advance + "勝ち抜け") }
        if let bonus = voteBonusPoints { parts.append("投票ボーナス\(bonus)点") }
        if let days = entryDays { parts.append("エントリー\(days)日" + (capacity.map { "（定員\($0)）" } ?? "")) }
        if let tag = tagDivision { parts.append(tag.name + "部門あり") }
        if !specialPlans.isEmpty { parts.append(specialPlans.map(\.displayTitle).joined(separator: "・")) }
        return parts.joined(separator: "・")
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
    // 0.27：サイトのシーズンには「通常」のルールだけを入れる。
    guard rule.kind == .online, rule.effectiveScope == .regular else { return }
    // 0.28：リーグごとに投稿・投票の日数が違う時は、今のリーグの日数にする。
    let current = rule.leagueDetail(site.affiliation)
    site.submissionDays = current.submissionDays ?? rule.submissionDays
    site.votingDays = current.votingDays ?? rule.votingDays
    applySiteTiming(rule.timing, to: &site, intervalDays: rule.intervalDays)
    // 0.28：投稿の前にエントリーの期間があるリーグは、エントリーと投稿を合わせた間隔で次の回が出る。
    if let entry = current.entryDays, rule.timing == .withVoting {
        site.cycleSettings?.intervalDays = site.submissionDays + entry
    }
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
    let planned = giriRulePlanPeriods(rule, site: site)
    site.cycleSettings?.specialPeriods = planned
}

/// ルールの「プレーオフ・入れ替え戦」から、シーズンの特別な日程を作る。
/// 最後の通常回の投票締切から数えるので、1シーズンの回数が分からない時は作らない。
/// 前にルールから作った日程は置き換え、手で入れた日程はそのまま残す。
func giriRulePlanPeriods(_ rule: GiriRule, site: OnlineSite, calendar: Calendar = .current) -> [SiteSpecialPeriod] {
    let settings = site.cycleSettings ?? SiteCycleSettings()
    var periods = settings.specialPeriods.filter { !$0.id.hasPrefix("rule-plan:") }
    guard rule.kind == .online, rule.effectiveScope == .regular, let lastEnd = siteSeasonLastCycleEnd(site, calendar: calendar) else { return periods }
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
    // 0.27：ネットの大会のルールは、ネット大喜利の「大会」として作る。
    rule.kind = event.eventFormat.isOnline ? .online : .live
    rule.scope = .tournament
    rule.submissionDays = event.effectiveRounds.first.flatMap { round in
        guard let start = round.submissionStart, let end = round.submissionEnd else { return nil }
        return max(1, Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0)
    } ?? rule.submissionDays
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

/// 大会のルールを大会に入れる（参加形式・対戦形式・審査方法）。段階は結果の入力で入れる。
/// 0.27：ネットの大会には、ネット大喜利の「大会」のルールを入れる。
func giriApplyRule(_ rule: GiriRule, to event: inout GiriEvent) {
    guard giriRuleFits(rule, event: event) else { return }
    event.ruleID = rule.id
    event.tournamentFormat = rule.tournamentFormat
    // 0.28：チーム戦で途中でメンバーが変わるルール。
    if rule.hasMemberChanges && rule.tournamentFormat != .individual { event.hasMemberChanges = true }
    // 0.28：エントリーの期間があるルールは、まだ入れていない時だけ、最初の投稿開始（なければ開始）の前に入れる。
    if let days = rule.entryDays, event.entryStart == nil && event.entryEnd == nil,
       let start = event.effectiveRounds.compactMap(\.submissionStart).min() ?? event.startsAt {
        event.entryEnd = start
        event.entryStart = Calendar.current.date(byAdding: .day, value: -days, to: start)
    }
    // トーナメント（1対1）の対戦形式は生大喜利だけ（スプシ系では使わない）。
    event.knockout = event.eventFormat == .live ? rule.knockout : false
    if !rule.judging.isEmpty { event.judging = rule.judging }
}

/// 0.27：その大会に選べるルールか（ネットの大会はネットの大会のルール、生・スプシ系は生大喜利・スプシ系のルール）。
func giriRuleFits(_ rule: GiriRule, event: GiriEvent) -> Bool {
    if event.eventFormat.isOnline { return rule.kind == .online && rule.effectiveScope == .tournament }
    return rule.kind == .live
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
        // 0.27：割合や得点で決める勝ち抜けは、段階のメモに残す（人数は結果の参加者数で変わるため）。
        let notes = [item.advanceCount == nil ? item.advanceText.map { $0 + "が勝ち抜け" } : nil, item.advanceNote.isEmpty ? nil : item.advanceNote, item.memberChangeText].compactMap { $0 }
        if !notes.isEmpty { stage.memo = notes.joined(separator: "。") }
        return stage
    }
}

// MARK: - 0.24 ルールのテンプレート・大会の流れ

/// 段階を1つ作る（名前は種類の名前）。
func giriRuleStage(_ kind: StageKind, name: String? = nil, lineup: String = "", promptCount: Int? = nil, advanceCount: Int? = nil) -> GiriRuleStage {
    GiriRuleStage(name: name ?? kind.title, kind: kind.rawValue, lineup: lineup, promptCount: promptCount, advanceCount: advanceCount)
}

/// 段階を流れに足す。決勝などより深い段階があれば、その前に入れる。
/// 敗者復活は決勝の前、決勝・その他は最後に足す。
func giriRuleInsertingStage(_ stage: GiriRuleStage, into stages: [GiriRuleStage]) -> [GiriRuleStage] {
    var result = stages
    guard let kind = stage.stageKind, kind != .final, kind != .other else {
        result.append(stage)
        return result
    }
    let depth = kind == .repechage ? (StageKind.final.depth ?? 4) : (kind.depth ?? 0)
    if let index = result.firstIndex(where: { other in
        guard let otherKind = other.stageKind, otherKind != .repechage, let otherDepth = otherKind.depth else { return false }
        return kind == .repechage ? otherDepth >= depth : otherDepth > depth
    }) {
        result.insert(stage, at: index)
    } else {
        result.append(stage)
    }
    return result
}

/// よくあるルール（テンプレート）。選ぶと、そのコピーを自分のルールとして編集して保存する。
let giriRuleTemplates: [GiriRule] = {
    var templates: [GiriRule] = []
    func add(_ id: String, _ name: String, _ kind: GiriRuleKind, _ change: (inout GiriRule) -> Void) {
        var rule = GiriRule(id: "template:" + id, name: name, kind: kind)
        rule.scope = kind == .live ? .tournament : .regular
        rule.updatedAt = Date(timeIntervalSince1970: 0)
        change(&rule)
        templates.append(rule)
    }
    add("weekly-average", "毎週・全回答の平均", .online) { rule in
        rule.nextPrompt = SiteNextPromptTiming.withVoting.rawValue
        rule.memo = "毎週お題が出て、前の回の投票と並行。シーズンの成績は提出した全回答の平均。"
    }
    add("required-top", "規定回答数の上位の平均", .online) { rule in
        rule.scoring = .topRequired
        rule.requiredAnswerCount = 8
        rule.memo = "規定回答数より多く回答した時は、得票率の高い規定回答数分だけで平均する。"
    }
    add("top-advance", "上位○人が勝ち抜け", .online) { rule in
        rule.regularCycleCount = 10
        rule.advanceCount = 10
        rule.memo = "シーズンの上位の人が次の段階に勝ち抜ける。"
    }
    add("league", "リーグ・入れ替え戦", .online) { rule in
        rule.regularCycleCount = 10
        rule.leagues = ["1部", "2部", "3部"]
        rule.specialPlans = [GiriRuleSpecialPlan(kind: .replacement, title: "入れ替え戦", startOffsetDays: 0, submissionDays: 7, votingDays: 7, count: 1)]
    }
    add("playoff", "プレーオフあり", .online) { rule in
        rule.regularCycleCount = 10
        rule.specialPlans = [GiriRuleSpecialPlan(kind: .playoff, title: "プレーオフ", startOffsetDays: 0, submissionDays: 7, votingDays: 7, count: 2)]
    }
    add("alternating", "投稿と投票を順番に", .online) { rule in
        rule.nextPrompt = SiteNextPromptTiming.afterVoting.rawValue
        rule.memo = "投稿が終わって投票、投票が終わってから次のお題。"
    }
    // 0.27：2部制の昇格・降格リーグ（規定数以上の人をシーズン得票率で並べ、入れ替える）。
    // 0.28：ユーザーの指定で、このルールの名前は元のサイトのシーズン（S28〜S29）の名前にする（S30からは下の別のテンプレート）。
    add("two-league-promotion", "大喜利天文台(S28～S29)", .online) { rule in
        rule.submissionDays = 7
        rule.votingDays = 4
        rule.regularCycleCount = 8
        rule.scoring = .allAnswers
        rule.leagues = ["1部", "2部"]
        rule.leagueDetails = [
            GiriRuleLeague(name: "1部", requiredFraction: "1/2", promptChoices: 2, relegationCount: 15, unqualifiedRanksLast: true),
            GiriRuleLeague(name: "2部", requiredFraction: "1/8", promptChoices: 4, promotionCount: 15),
        ]
        rule.tieBreak = "同率は投稿数が多い方を上位"
        rule.voteBonusPoints = 3
        rule.specialPlans = [
            GiriRuleSpecialPlan(kind: .playoff, title: "プレーオフ", startOffsetDays: 0, submissionDays: 7, votingDays: 4, count: 1,
                                entrantCount: 7, entrantLeague: "1部", ranking: GiriRuleScoring.total.rawValue, countsInSeason: false),
            GiriRuleSpecialPlan(kind: .exhibition, title: "エキシビション", startOffsetDays: 0, submissionDays: 7, votingDays: 4, count: 1, countsInSeason: false),
        ]
        rule.memo = "規定数（1部は結果が出たお題数の1/2以上、2部は1/8以上）に届いた人を、シーズンの得票率で並べる。1部の下位と2部の上位が入れ替わる。プレーオフ・エキシビションはシーズンの成績に含めない。"
    }
    // 0.28：S30からの2部制（シングルとタッグ、リーグごとの日程・エントリー、上位○回答の平均）。
    add("two-league-tag-s30", "大喜利天文台(S30～)", .online) { rule in
        rule.submissionDays = 7
        rule.votingDays = 4
        rule.regularCycleCount = 8
        rule.scoring = .topRequired
        rule.leagues = ["1部", "2部"]
        rule.leagueDetails = [
            GiriRuleLeague(name: "1部", requiredFraction: "1/2", promptChoices: 2, relegationCount: 15, unqualifiedRanksLast: true,
                           subtitle: "NIGHT", topAnswerCount: 8, stayCount: 35, submissionDays: 7, votingDays: 4, answersPerPrompt: 2),
            GiriRuleLeague(name: "2部", requiredFraction: "1/4", promptChoices: 4, promotionCount: 15,
                           subtitle: "DAY", topAnswerCount: 4, unqualifiedExcluded: true, entryDays: 1, submissionDays: 6, votingDays: 4, answersPerPrompt: 1),
        ]
        rule.tieBreak = "同率は投稿数が多い方を上位"
        rule.voteBonusPoints = 3
        rule.entryNote = "2部はエントリー制（先着順・取り下げ不可）。エントリー期間のあとも、定員に達するまでは随時エントリーできる。"
        rule.tagDivision = GiriRuleTagDivision(
            name: "タッグ", memberCount: 2, teamScoring: "sum",
            leagueDetails: [
                GiriRuleLeague(name: "1部", requiredFraction: "1/2", promptChoices: 2, relegationCount: 8, unqualifiedRanksLast: true,
                               subtitle: "NIGHT", topAnswerCount: 8, stayCount: 17),
                GiriRuleLeague(name: "2部", requiredFraction: "1/4", promptChoices: 4, promotionCount: 8,
                               subtitle: "DAY", topAnswerCount: 4, unqualifiedExcluded: true),
            ],
            memberShortfallZero: true,
            tieBreak: "同率は投稿数が多いタッグを上位",
            playoffEntrants: 4,
            formationNote: "タッグはシーズン中いつでも組める。組んでいる間は、相手が承諾すると解消でき、解消したあと改めて申し込める。1部はタッグを組んでいない人は最下位、2部は集計対象外。")
        rule.specialPlans = [
            GiriRuleSpecialPlan(kind: .playoff, title: "プレーオフ", startOffsetDays: 0, submissionDays: 7, votingDays: 4, count: 1,
                                entrantLeague: "1部", ranking: GiriRuleScoring.total.rawValue, countsInSeason: false, answersPerEntrant: 2),
            GiriRuleSpecialPlan(kind: .exhibition, title: "エキシビション", startOffsetDays: 0, submissionDays: 7, votingDays: 4, count: 1, countsInSeason: false),
        ]
        rule.memo = "成績（H得票率）は、1部は得票率の高い上から8回答、2部は上から4回答の平均。シーズン中のランキングは、1部は結果お題の1/2以上、2部は1/4以上の投稿がある人が対象。自分の投稿したお題に投票すると投票ボーナス3点。1部は1題につき2回答、2部は1回答。"
    }
    // 0.27：ネット大喜利の大会。
    add("online-half-knockout", "お題ごとに上位半数が勝ち抜け", .online) { rule in
        rule.scope = .tournament
        rule.scoring = .perRound
        let rounds = (1...4).map { number in
            GiriRuleStage(name: "\(number)回戦", kind: StageKind.other.rawValue, lineup: "お題ごとに勝ち抜け", promptCount: 1, advanceFraction: "1/2")
        }
        rule.stages = rounds + [
            GiriRuleStage(name: "準決勝", kind: StageKind.semifinal.rawValue, lineup: "お題ごとに勝ち抜け", promptCount: 1, advanceFraction: "1/2"),
            GiriRuleStage(name: "決勝", kind: StageKind.final.rawValue, promptCount: 1),
        ]
    }
    add("online-league-final", "予選リーグ→敗者復活→決勝リーグ", .online) { rule in
        rule.scope = .tournament
        rule.scoring = .total
        rule.stages = [
            GiriRuleStage(name: "予選リーグ", kind: StageKind.qualifier.rawValue, lineup: "グループ対戦", promptCount: 3),
            GiriRuleStage(name: "敗者復活戦", kind: StageKind.repechage.rawValue),
            GiriRuleStage(name: "決勝リーグ", kind: StageKind.main.rawValue, lineup: "グループ対戦"),
            GiriRuleStage(name: "決勝戦", kind: StageKind.final.rawValue),
        ]
    }
    add("online-team", "チーム戦（チームで回答）", .online) { rule in
        rule.scope = .tournament
        rule.tournamentFormat = .team
        rule.teamAnswerStyle = "team"
        rule.scoring = .total
        rule.stages = [giriRuleStage(.qualifier), giriRuleStage(.final)]
    }
    add("qualifier-final", "予選→決勝", .live) { rule in
        rule.stages = [giriRuleStage(.qualifier, lineup: "横並び"), giriRuleStage(.final)]
    }
    add("qualifier-main-final", "予選→本戦→決勝", .live) { rule in
        rule.stages = [giriRuleStage(.qualifier, lineup: "横並び"), giriRuleStage(.main), giriRuleStage(.final)]
    }
    add("qualifier-semifinal", "予選→準決勝→決勝", .live) { rule in
        rule.stages = [giriRuleStage(.qualifier, lineup: "横並び"), giriRuleStage(.semifinal), giriRuleStage(.final)]
    }
    add("semifinal-taiman", "予選→準決勝だけタイマン→決勝", .live) { rule in
        rule.stages = [giriRuleStage(.qualifier, lineup: "横並び", advanceCount: 4), giriRuleStage(.semifinal, lineup: "タイマン（1対1）", advanceCount: 2), giriRuleStage(.final, lineup: "横並び")]
    }
    add("knockout", "トーナメント（準々決勝から）", .live) { rule in
        rule.knockout = true
        rule.stages = [giriRuleStage(.quarterfinal, lineup: "タイマン"), giriRuleStage(.semifinal, lineup: "タイマン"), giriRuleStage(.final, lineup: "タイマン")]
    }
    add("repechage", "予選→敗者復活→決勝", .live) { rule in
        rule.stages = [giriRuleStage(.qualifier, lineup: "横並び"), giriRuleStage(.repechage, name: "敗者復活戦"), giriRuleStage(.final)]
    }
    add("team", "チーム戦（予選→決勝）", .live) { rule in
        rule.tournamentFormat = .team
        rule.stages = [giriRuleStage(.qualifier), giriRuleStage(.final)]
    }
    return templates
}()

/// テンプレートから自分のルールを作る（新しいID・今の日時）。
func giriRuleFromTemplate(_ template: GiriRule, now: Date = Date()) -> GiriRule {
    var rule = template.duplicated(now: now)
    rule.name = template.name
    return rule
}
