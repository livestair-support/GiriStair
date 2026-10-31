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

    var rateSampleCount: Int { scoredAnswerCount + legacyRoundResultCount }
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
    notes: [ThoughtNote]
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
    var rates: [Double] = []
    for event in included {
        let eventNotes = notes.filter {
            $0.eventId == event.id && $0.kind == .answers && !$0.isOthersAnswer
        }.sorted { $0.updatedAt > $1.updatedAt }
        var seenNotes = Set<String>()
        var roundsWithAnswerRates = Set<String>()
        var hasUnlinkedAnswerRate = false
        for note in eventNotes where seenNotes.insert(note.id).inserted {
            var seenAnswers = Set<String>()
            let submitted = note.effectiveAnswerRecords.filter {
                $0.isSubmitted && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                seenAnswers.insert($0.id).inserted
            }
            totals.submittedAnswerCount += submitted.count
            for answer in submitted {
                guard let rate = seasonAnalyticsRate(answer.voteRate) else { continue }
                rates.append(rate)
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

        guard !hasUnlinkedAnswerRate else { continue }
        let stages = event.tournamentResult?.stages ?? []
        var fallbackRates: [String: Double] = [:]
        // Exact round results win over a stage-wide legacy result for the same
        // round regardless of their position in the stored result array.
        for stage in stages where seasonAnalyticsID(stage.roundId) == nil {
            guard let rate = seasonAnalyticsRate(stage.voteRate),
                  let roundID = seasonAnalyticsStageRoundID(stage, event: event, stages: stages),
                  !roundsWithAnswerRates.contains(roundID) else { continue }
            fallbackRates[roundID] = rate
        }
        for stage in stages {
            guard let roundID = seasonAnalyticsID(stage.roundId),
                  let rate = seasonAnalyticsRate(stage.voteRate),
                  !roundsWithAnswerRates.contains(roundID) else { continue }
            fallbackRates[roundID] = rate
        }
        for key in fallbackRates.keys.sorted() {
            if let rate = fallbackRates[key] { rates.append(rate) }
        }
        totals.legacyRoundResultCount += fallbackRates.count
    }

    if !rates.isEmpty {
        // An incremental mean avoids overflowing a sum for finite input rates.
        var mean = 0.0
        for (index, rate) in rates.enumerated() {
            mean += (rate - mean) / Double(index + 1)
        }
        totals.averageVoteRate = mean
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
