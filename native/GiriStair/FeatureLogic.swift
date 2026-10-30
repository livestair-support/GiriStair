import Foundation

/// Keep the old two-value kind in JSON while modelling the four distinct formats.
enum EventFormat: String, Codable, CaseIterable, Identifiable {
    case live, onlineLong, onlineShort, hybrid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .live: return "生大喜利"
        case .onlineLong: return "ネット大喜利（長考）"
        case .onlineShort: return "ネット大喜利（短考）"
        case .hybrid: return "ハイブリッド"
        }
    }
    var label: String { title }
    var displayName: String { title }
    var shortTitle: String {
        switch self {
        case .live: return "生"
        case .onlineLong: return "長考"
        case .onlineShort: return "短考"
        case .hybrid: return "ハイブリッド"
        }
    }
    var isOnline: Bool { self == .onlineLong || self == .onlineShort }
    var hasOnlineRounds: Bool { self != .live }
    var hasLiveTiming: Bool { self != .onlineLong }
}

enum ParticipationState: String, Codable, CaseIterable, Identifiable {
    case upcoming, ongoing, completed, interested, canceled, unjoined
    var id: String { rawValue }
    var title: String {
        switch self {
        case .upcoming: return "参加予定"
        case .ongoing: return "参加中"
        case .completed: return "参加済"
        case .interested: return "興味あり"
        case .canceled: return "キャンセル"
        case .unjoined: return "未参加"
        }
    }
}

extension GiriEvent {
    var eventFormat: EventFormat {
        get { format ?? (kind == .live ? .live : .onlineLong) }
        set { format = newValue; kind = newValue == .live ? .live : .online }
    }
    var isActualParticipant: Bool { isParticipating && !isInterested && status != .canceled }

    /// Earliest known part of a record; periods may remain in progress between
    /// posting and voting. Unknown times never become a fictitious midnight end.
    var participationStartDate: Date? {
        var dates: [Date] = []
        if eventFormat.hasLiveTiming, let date = startsAt ?? eventDate { dates.append(date) }
        if eventFormat.hasOnlineRounds {
            for round in effectiveRounds {
                if let start = round.submissionStart ?? round.votingStart { dates.append(start) }
            }
        }
        return dates.min()
    }
    var participationEndDate: Date? {
        var dates: [Date] = []
        if eventFormat.hasLiveTiming {
            if let end = endsAt { dates.append(end) }
            else if let day = eventDate ?? startsAt,
                    let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: day)) { dates.append(nextDay) }
        }
        if eventFormat.hasOnlineRounds {
            for round in effectiveRounds {
                if let end = round.votingEnd ?? round.submissionEnd { dates.append(end) }
            }
        }
        return dates.max()
    }
    func hasEnded(now: Date = Date()) -> Bool {
        if eventFormat.hasOnlineRounds, meetingType == .tournament, !hasFinalResult {
            let latest = effectiveRounds.max { ($0.votingEnd ?? $0.submissionEnd ?? .distantPast) < ($1.votingEnd ?? $1.submissionEnd ?? .distantPast) }
            if let latest {
                let stages = tournamentResult?.stages ?? []
                let result = stages.last { $0.roundId == latest.id } ?? stages.last { $0.roundId == nil && $0.stageId == latest.effectiveStageId }
                if result?.outcome == .advanced || tournamentResult?.outcome == .advanced { return false }
            }
        }
        if eventFormat.hasOnlineRounds {
            for round in effectiveRounds {
                // Do not mark an incompletely known future/ongoing period ended.
                if round.votingRequired && round.votingEnd == nil && (round.votingStart != nil || round.submissionStart != nil) { return false }
                if !round.votingRequired && round.submissionEnabled && round.submissionEnd == nil && round.submissionStart != nil { return false }
            }
        }
        if let end = participationEndDate { return now >= end }
        return status == .attended
    }
    func participationState(now: Date = Date()) -> ParticipationState {
        if status == .canceled { return .canceled }
        if isInterested { return .interested }
        if !isParticipating { return .unjoined }
        if hasEnded(now: now) { return .completed }
        if let start = participationStartDate, start <= now { return .ongoing }
        return .upcoming
    }
    func isCountableParticipation(now: Date = Date()) -> Bool {
        isActualParticipant && participationState(now: now) == .completed
    }
    var hasCycleResult: Bool {
        cyclePlacement != nil || !cycleResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    func hasRecordedResult(for round: EventRound) -> Bool {
        let stages = tournamentResult?.stages ?? []
        if stages.contains(where: { $0.roundId == round.id && $0.hasRecord }) { return true }
        // A stage-wide rank/outcome does not record each of its repeated rounds.
        // Retain the legacy fallback only when a stage has one known round.
        guard effectiveRounds.filter({ $0.effectiveStageId == round.effectiveStageId }).count == 1 else { return false }
        return stages.contains { $0.roundId == nil && $0.stageId == round.effectiveStageId && $0.hasRecord }
    }
}

struct AnswerRecord: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var text: String = ""
    var isSubmitted: Bool = false
    var placement: Int? = nil
    var points: Double? = nil
    var voterCount: Int? = nil
    var maxPointsPerVoter: Int = 1
    var memo: String = ""

    init(id: String = UUID().uuidString, text: String = "", isSubmitted: Bool = false, placement: Int? = nil, points: Double? = nil, voterCount: Int? = nil, maxPointsPerVoter: Int = 1, memo: String = "") {
        self.id = id; self.text = text; self.isSubmitted = isSubmitted
        self.placement = placement; self.points = points; self.voterCount = voterCount
        self.maxPointsPerVoter = maxPointsPerVoter; self.memo = memo
    }

    private enum CodingKeys: String, CodingKey { case id, text, isSubmitted, placement, points, voterCount, maxPointsPerVoter, memo }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        isSubmitted = try c.decodeIfPresent(Bool.self, forKey: .isSubmitted) ?? false
        placement = try c.decodeIfPresent(Int.self, forKey: .placement)
        points = try c.decodeIfPresent(Double.self, forKey: .points)
        voterCount = try c.decodeIfPresent(Int.self, forKey: .voterCount)
        maxPointsPerVoter = try c.decodeIfPresent(Int.self, forKey: .maxPointsPerVoter) ?? 1
        memo = try c.decodeIfPresent(String.self, forKey: .memo) ?? ""
        try validate()
    }
    func validate() throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (placement ?? 1) > 0, (voterCount ?? 0) >= 0, maxPointsPerVoter > 0,
              points.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw GiriDataError.invalid("回答の順位・得点・投票人数が不正です。") }
    }
    var voteRate: Double? {
        guard let points, let voterCount, voterCount > 0, maxPointsPerVoter > 0 else { return nil }
        return points * 100 / (Double(voterCount) * Double(maxPointsPerVoter))
    }
    var hasResult: Bool { placement != nil || points != nil || voterCount != nil || !memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

extension ThoughtNote {
    /// Bridges legacy strings without mutating the decoded document. Stable IDs
    /// are based on the note and original position until an editor saves records.
    var effectiveAnswerRecords: [AnswerRecord] {
        if usesAnswerRecords || !answerRecords.isEmpty { return answerRecords }
        let legacy = answers.isEmpty && kind == .answers ? body.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } : answers
        return legacy.enumerated().map { AnswerRecord(id: "\(id)::answer:\($0.offset)", text: $0.element) }
    }
    var submittedAnswers: [AnswerRecord] { effectiveAnswerRecords.filter(\.isSubmitted) }
}

extension EventRound {
    var resultPromptKey: String { "round:\(id)" }
}

extension GiriEvent {
    func endedRoundsNeedingResult(now: Date = Date()) -> [EventRound] {
        guard isActualParticipant, eventFormat.hasOnlineRounds else { return [] }
        return effectiveRounds.filter { round in
            guard let end = round.votingEnd, end <= now else { return false }
            return !hasRecordedResult(for: round) && !promptedResultKeys.contains(round.resultPromptKey)
        }.sorted { ($0.votingEnd ?? .distantPast) < ($1.votingEnd ?? .distantPast) }
    }
}
