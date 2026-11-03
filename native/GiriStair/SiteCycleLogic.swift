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
    private enum CodingKeys: String, CodingKey { case pattern, anchorStart, intervalDays, anchorCycleNumber, seasonName, seasonStart, seasonLengthDays, regularCycleCount, leagues, specialPeriods, leagueChangesPerSeason, seasonID, seasonEndsAt, trackSeasonTotals, ruleRevisionID, legacyInferredSeasonStart, seasonNumber }
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
    let lower = hasPreviousRevision ? settings.anchorStart : settings.seasonStart ?? (hasSeason ? settings.anchorStart : nil)
    let validCap = settings.regularCycleCount.flatMap { $0 >= settings.anchorCycleNumber ? $0 : nil }
    var output: [SiteCycleDescriptor] = []
    if revision.recurrence == .weekly {
        for offset in (approximateIndex - span)...(approximateIndex + 1) {
            let number = settings.anchorCycleNumber + offset
            guard !hasSeason || number >= 1, validCap.map({ number <= $0 }) ?? true else { continue }
            let start = addCalendarDays(settings.anchorStart, offset * settings.intervalDays, calendar: calendar)
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
    round.submissionStart = addCalendarDays(settings.anchorStart, (last - settings.anchorCycleNumber) * settings.intervalDays, calendar: calendar)
    round = completeRoundSchedule(round, submissionDays: site.submissionDays, votingDays: site.votingDays)
    return round.votingEnd
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
