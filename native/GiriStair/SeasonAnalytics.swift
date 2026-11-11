import Foundation

/// Submitted answers and result samples are different counts: an older round
/// score can contribute to the average without proving how many answers were
/// submitted. The UI can show that fallback separately rather than inventing
/// a submission count.
struct GiriSeasonTotals: Equatable {
    var submittedAnswerCount: Int = 0
    var scoredAnswerCount: Int = 0
    var legacyRoundResultCount: Int = 0
    var averageVoteRate: Double? = nil
    /// 1人あたりの点（得票÷投票人数）の算術平均。画面ではこちらを表示する。
    var averagePointsPerVoter: Double? = nil
    /// 0.23：ルールの規定回答数（上位だけの平均にする時）。
    var requiredAnswerCount: Int? = nil
    /// 平均に使った数（規定回答数で上位だけにした時は、その数）。
    var countedSampleCount: Int = 0
    /// 0.27：回答（または回の点数）を残した回の数。リーグの規定数（○回以上）と比べる。
    var answeredCycleCount: Int = 0

    var rateSampleCount: Int { scoredAnswerCount + legacyRoundResultCount }
    /// 規定回答数より多く記録があり、低い方を平均から外したか。
    var droppedLowerSamples: Bool { requiredAnswerCount.map { rateSampleCount > $0 } ?? false }
}

/// Arithmetic mean of each submitted answer's recorded vote rate. Unknown
/// scores are excluded; voter counts never weight one answer above another.
/// When a round has no submitted answer rate, one old round-level rate may be
/// used. Stage-wide rates only resolve to a round when that stage has one round.
func giriSeasonTotals(
    siteID: String,
    seasonID: String?,
    seasonName: String,
    events: [GiriEvent],
    notes: [ThoughtNote],
    requiredAnswerCount: Int? = nil
) -> GiriSeasonTotals {
    let requestedID = seasonAnalyticsID(seasonID)
    let name = seasonName.trimmingCharacters(in: .whitespacesAndNewlines)
    var seenEvents = Set<String>()
    let included = events.filter { event in
        guard event.onlineSiteId == siteID, event.isActualParticipant,
              seenEvents.insert(event.id).inserted else { return false }
        if let eventID = seasonAnalyticsID(event.siteSeasonID) {
            return requestedID == eventID
        }
        // Older schema-one events have only a textual snapshot. Never merge a
        // different explicit season ID just because the display names match.
        if requestedID != nil && name.isEmpty { return false }
        return event.siteSeason.trimmingCharacters(in: .whitespacesAndNewlines) == name
    }

    var totals = GiriSeasonTotals()
    // 0.23：得票率と1人あたりの点を1組で持つ（規定回答数の上位だけにする時、同じ回答の値を使う）。
    var samples: [(rate: Double, perVoter: Double?)] = []
    for event in included {
        let eventNotes = notes.filter {
            $0.eventId == event.id && $0.kind == .answers && !$0.isOthersAnswer
        }.sorted { $0.updatedAt > $1.updatedAt }
        var seenNotes = Set<String>()
        var roundsWithAnswerRates = Set<String>()
        var hasUnlinkedAnswerRate = false
        var eventSubmitted = 0
        for note in eventNotes where seenNotes.insert(note.id).inserted {
            var seenAnswers = Set<String>()
            let submitted = note.effectiveAnswerRecords.filter {
                $0.countsForSelf && $0.isSubmitted && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                seenAnswers.insert($0.id).inserted
            }
            totals.submittedAnswerCount += submitted.count
            eventSubmitted += submitted.count
            for answer in submitted {
                guard let rate = seasonAnalyticsRate(answer.voteRate) else { continue }
                samples.append((rate, seasonAnalyticsRate(answer.pointsPerVoter)))
                totals.scoredAnswerCount += 1
                if let roundID = seasonAnalyticsRoundID(note.roundId, event: event) {
                    roundsWithAnswerRates.insert(roundID)
                } else {
                    // With a score unlinked to a multi-round event we cannot
                    // tell which round it replaces. Suppress legacy fallbacks
                    // for that event to avoid counting the same result twice.
                    hasUnlinkedAnswerRate = true
                }
            }
        }

        if eventSubmitted > 0 { totals.answeredCycleCount += 1 }
        guard !hasUnlinkedAnswerRate else { continue }
        let stages = event.tournamentResult?.stages ?? []
        var fallbackRates: [String: Double] = [:]
        var fallbackPerVoter: [String: Double] = [:]
        // Exact round results win over a stage-wide legacy result for the same
        // round regardless of their position in the stored result array.
        for stage in stages where seasonAnalyticsID(stage.roundId) == nil {
            guard let rate = seasonAnalyticsRate(stage.voteRate),
                  let roundID = seasonAnalyticsStageRoundID(stage, event: event, stages: stages),
                  !roundsWithAnswerRates.contains(roundID) else { continue }
            fallbackRates[roundID] = rate
            fallbackPerVoter[roundID] = seasonAnalyticsRate(stage.pointsPerVoter)
        }
        for stage in stages {
            guard let roundID = seasonAnalyticsID(stage.roundId),
                  let rate = seasonAnalyticsRate(stage.voteRate),
                  !roundsWithAnswerRates.contains(roundID) else { continue }
            fallbackRates[roundID] = rate
            fallbackPerVoter[roundID] = seasonAnalyticsRate(stage.pointsPerVoter)
        }
        for key in fallbackRates.keys.sorted() {
            if let rate = fallbackRates[key] { samples.append((rate, fallbackPerVoter[key])) }
        }
        totals.legacyRoundResultCount += fallbackRates.count
        if eventSubmitted == 0 && !fallbackRates.isEmpty { totals.answeredCycleCount += 1 }
    }

    // 規定回答数より多い時は、得票率の高い規定回答数分だけを平均する（低い回答は考えない）。
    if let required = requiredAnswerCount, required > 0 {
        totals.requiredAnswerCount = required
        if samples.count > required {
            samples = Array(samples.enumerated().sorted { $0.element.rate == $1.element.rate ? $0.offset < $1.offset : $0.element.rate > $1.element.rate }
                .prefix(required).map(\.element))
        }
    }
    totals.countedSampleCount = samples.count
    let rates = samples.map(\.rate)
    let perVoter = samples.compactMap(\.perVoter)
    if !rates.isEmpty {
        // An incremental mean avoids overflowing a sum for finite input rates.
        var mean = 0.0
        for (index, rate) in rates.enumerated() {
            mean += (rate - mean) / Double(index + 1)
        }
        totals.averageVoteRate = mean
    }
    if !perVoter.isEmpty {
        var mean = 0.0
        for (index, value) in perVoter.enumerated() { mean += (value - mean) / Double(index + 1) }
        totals.averagePointsPerVoter = mean
    }
    return totals
}

private func seasonAnalyticsID(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func seasonAnalyticsRate(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value >= 0 else { return nil }
    return value
}

private func seasonAnalyticsRoundID(_ id: String?, event: GiriEvent) -> String? {
    if let id = seasonAnalyticsID(id) { return id }
    let rounds = event.effectiveRounds
    return rounds.count == 1 ? rounds.first?.id : nil
}

private func seasonAnalyticsStageRoundID(
    _ stage: ResultStage,
    event: GiriEvent,
    stages: [ResultStage]
) -> String? {
    let rounds = event.effectiveRounds
    if let stageID = seasonAnalyticsID(stage.stageId) {
        let candidates = rounds.filter { $0.effectiveStageId == stageID }
        return candidates.count == 1 ? candidates.first?.id : nil
    }
    if rounds.count == 1 { return rounds.first?.id }
    // A single historical result with no remaining schedule is still one
    // known result sample. Multiple unlinked stages may be aggregate records.
    return rounds.isEmpty && stages.count == 1 ? "event:" + event.id : nil
}

// MARK: - 0.28 タッグの相手などのシーズンの得票率

/// ほかの人（タッグの相手など）のシーズンの得票率。記録した回答から数える。
struct GiriPersonSeasonRate: Equatable {
    /// 得票率の分かる回答の数。
    var sampleCount: Int = 0
    /// 平均に使った数（上から○回答の時はその数まで）。
    var countedSampleCount: Int = 0
    var averageVoteRate: Double? = nil
}

/// 名前の人の回答（他人の回答として記録したもの・その人が原案のチーム回答）の得票率を、
/// 高い方から topCount 件まで平均する。サイトとシーズンは giriSeasonTotals と同じ決め方（キャンセルした回は除く）。
func giriPersonSeasonRate(
    name: String,
    siteID: String,
    seasonID: String?,
    seasonName: String,
    events: [GiriEvent],
    notes: [ThoughtNote],
    topCount: Int? = nil
) -> GiriPersonSeasonRate {
    let key = playerSearchKey(name)
    guard !key.isEmpty else { return GiriPersonSeasonRate() }
    let requestedID = seasonAnalyticsID(seasonID)
    let seasonTitle = seasonName.trimmingCharacters(in: .whitespacesAndNewlines)
    let eventIDs = Set(events.filter { event in
        guard event.onlineSiteId == siteID, event.status != .canceled else { return false }
        if let eventID = seasonAnalyticsID(event.siteSeasonID) { return requestedID == eventID }
        if requestedID != nil && seasonTitle.isEmpty { return false }
        return event.siteSeason.trimmingCharacters(in: .whitespacesAndNewlines) == seasonTitle
    }.map(\.id))
    var seen = Set<String>()
    var rates: [Double] = []
    for note in notes where note.kind == .answers {
        guard let eventID = note.eventId, eventIDs.contains(eventID) else { continue }
        for record in note.effectiveAnswerRecords where seen.insert(record.id).inserted {
            guard playerSearchKey(record.creditedName) == key, let rate = seasonAnalyticsRate(record.voteRate) else { continue }
            rates.append(rate)
        }
    }
    var result = GiriPersonSeasonRate()
    result.sampleCount = rates.count
    let counted = topCount.map { Array(rates.sorted(by: >).prefix(max(1, $0))) } ?? rates
    result.countedSampleCount = counted.count
    if !counted.isEmpty {
        var mean = 0.0
        for (index, rate) in counted.enumerated() { mean += (rate - mean) / Double(index + 1) }
        result.averageVoteRate = mean
    }
    return result
}

/// 0.28：タッグの成績（2人の値の合計か平均）。回答数が足りない人を0にする決まりの時は、足りない人を0にする。
func giriTagSeasonRate(own: Double?, ownCount: Int, partner: Double?, partnerCount: Int?, topCount: Int?,
                       scoring: String, shortfallZero: Bool) -> Double? {
    func value(_ rate: Double?, _ count: Int?) -> Double? {
        guard let rate else { return shortfallZero ? 0 : nil }
        if shortfallZero, let topCount, let count, count < topCount { return 0 }
        return rate
    }
    guard let first = value(own, ownCount), let second = value(partner, partnerCount) else { return nil }
    return scoring == "average" ? (first + second) / 2 : first + second
}
