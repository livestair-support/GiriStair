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
        case .hybrid: return "スプシ系"
        }
    }
    var label: String { title }
    var displayName: String { title }
    var shortTitle: String {
        switch self {
        case .live: return "生"
        case .onlineLong: return "長考"
        case .onlineShort: return "短考"
        case .hybrid: return "スプシ系"
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
        cyclePlacement != nil || !cycleResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || leagueMovement != .unchanged || siteQualification != .none || (!nextAffiliation.isEmpty && nextAffiliation != affiliation)
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
    /// 空は自分の回答。名前があれば、その人の回答（ツボ）。
    var answerer: String = ""

    init(id: String = UUID().uuidString, text: String = "", isSubmitted: Bool = false, placement: Int? = nil, points: Double? = nil, voterCount: Int? = nil, maxPointsPerVoter: Int = 1, memo: String = "", answerer: String = "") {
        self.id = id; self.text = text; self.isSubmitted = isSubmitted
        self.placement = placement; self.points = points; self.voterCount = voterCount
        self.maxPointsPerVoter = maxPointsPerVoter; self.memo = memo; self.answerer = answerer
    }

    private enum CodingKeys: String, CodingKey { case id, text, isSubmitted, placement, points, voterCount, maxPointsPerVoter, memo, answerer }
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
        answerer = try c.decodeIfPresent(String.self, forKey: .answerer) ?? ""
        try validate()
    }
    var isOwn: Bool { answerer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// 1人あたりの点（得点÷投票人数）。
    var pointsPerVoter: Double? {
        guard let points, points.isFinite, points >= 0, let voterCount, voterCount > 0 else { return nil }
        return points / Double(voterCount)
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
    /// 0.7以前の「他人の回答」メモ（1メモ1人）は、各回答にその回答者を付けて読む。
    var effectiveAnswerRecords: [AnswerRecord] {
        let base: [AnswerRecord]
        if usesAnswerRecords || !answerRecords.isEmpty { base = answerRecords }
        else {
            let legacy = answers.isEmpty && kind == .answers ? body.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } : answers
            base = legacy.enumerated().map { AnswerRecord(id: "\(id)::answer:\($0.offset)", text: $0.element) }
        }
        guard isOthersAnswer else { return base }
        let name = answerer.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.map { record in
            var copy = record
            if copy.isOwn { copy.answerer = name.isEmpty ? "回答者不明" : name; copy.isSubmitted = false }
            return copy
        }
    }
    var ownAnswerRecords: [AnswerRecord] { effectiveAnswerRecords.filter(\.isOwn) }
    var otherAnswerRecords: [AnswerRecord] { effectiveAnswerRecords.filter { !$0.isOwn } }
    var submittedAnswers: [AnswerRecord] { ownAnswerRecords.filter(\.isSubmitted) }
    /// 作題者・回答者として出てくる名前（プレイヤー一覧・名前の変更に使う）。
    var referencedPeople: [String] {
        var names = effectiveAnswerRecords.map(\.answerer).filter { !$0.isEmpty && $0 != "回答者不明" }
        if !promptAuthor.isEmpty { names.append(promptAuthor) }
        return names
    }
    /// 紐付けた会の形式。会がない記録は保存した形式、旧データは長考／生とみなす。
    func effectiveFormat(event: GiriEvent?) -> EventFormat {
        event?.eventFormat ?? format ?? (answerCategory == "long" ? .onlineLong : .live)
    }
}

/// ネット大喜利の段階の競い方。点はいずれも1人あたりの点（得点÷投票人数）。
enum StageScoring: String, Codable, CaseIterable, Identifiable {
    case total, bestPerPrompt
    var id: String { rawValue }
    var title: String {
        switch self {
        case .total: return "回答の点の合計"
        case .bestPerPrompt: return "お題ごとに高い方の合計"
        }
    }
}

struct GiriStageScoreSummary: Equatable {
    var total: Double = 0
    var scoredPrompts: Int = 0
    var remainingPrompts: Int = 0
    /// 通過ラインまでに足りない点（通過ラインを入れた場合）
    var neededTotal: Double? = nil
    /// 残りのお題1題あたりに必要な点
    var neededPerPrompt: Double? = nil
}

/// 段階全体の記録に対して、その段階のお題で提出した自分の回答の点を合計し、
/// 通過ラインがあれば残りのお題で必要な点を逆算する。
func giriStageScoreSummary(event: GiriEvent, stage: ResultStage, notes: [ThoughtNote]) -> GiriStageScoreSummary? {
    guard stage.roundId == nil, let stageID = stage.stageId else { return nil }
    let rounds = event.effectiveRounds.filter { $0.effectiveStageId == stageID }
    guard !rounds.isEmpty else { return nil }
    let roundIDs = Set(rounds.map(\.id))
    var summary = GiriStageScoreSummary()
    var scoredRounds = Set<String>()
    let promptNotes = notes.filter { note in
        guard note.eventId == event.id, note.kind == .answers else { return false }
        return roundIDs.contains(note.roundId ?? "legacy")
    }
    for note in promptNotes {
        let values = note.submittedAnswers.compactMap(\.pointsPerVoter)
        guard !values.isEmpty else { continue }
        summary.total += stage.scoring == .bestPerPrompt ? (values.max() ?? 0) : values.reduce(0, +)
        summary.scoredPrompts += 1
        scoredRounds.insert(note.roundId ?? "legacy")
    }
    summary.remainingPrompts = rounds.filter { !scoredRounds.contains($0.id) }.count
    if let border = stage.borderScore {
        let needed = max(0, border - summary.total)
        summary.neededTotal = needed
        if summary.remainingPrompts > 0 { summary.neededPerPrompt = needed / Double(summary.remainingPrompts) }
    }
    return summary
}

/// 1人あたりの点の表示（例：1.18）。
func giriScoreText(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(2))) }

/// 大会の最終結果の選択肢。保存は従来の outcome（優勝・準優勝・入賞・敗退…）と
/// 順位・ベスト○に分け、3位とベスト4を戦績で区別できるようにする。
enum GiriFinalResultChoice: String, CaseIterable, Identifiable {
    case unrecorded, champion, runnerUp, third, best4, best8, best16, placed, eliminated, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .unrecorded: return "未記録"
        case .champion: return "優勝"
        case .runnerUp: return "準優勝"
        case .third: return "3位"
        case .best4: return "ベスト4"
        case .best8: return "ベスト8"
        case .best16: return "ベスト16"
        case .placed: return "入賞（順位を入力）"
        case .eliminated: return "敗退"
        case .other: return "その他"
        }
    }
    var bestOf: Int? {
        switch self {
        case .best4: return 4
        case .best8: return 8
        case .best16: return 16
        default: return nil
        }
    }
    static func current(outcome: TournamentOutcome, placement: Int?, bestOf: Int?) -> GiriFinalResultChoice {
        switch outcome {
        case .unrecorded: return .unrecorded
        case .champion: return .champion
        case .runnerUp: return .runnerUp
        case .eliminated, .advanced: return .eliminated
        case .other: return .other
        case .placed:
            switch bestOf {
            case 4?: return .best4
            case 8?: return .best8
            case 16?: return .best16
            default: return placement == 3 ? .third : .placed
            }
        }
    }
    var outcome: TournamentOutcome {
        switch self {
        case .unrecorded: return .unrecorded
        case .champion: return .champion
        case .runnerUp: return .runnerUp
        case .third, .best4, .best8, .best16, .placed: return .placed
        case .eliminated: return .eliminated
        case .other: return .other
        }
    }
}

/// 段階の結果の短い表示（例：予選1位通過／予選敗退（12人中5位）／決勝 優勝）。
func giriStageResultText(_ stage: ResultStage) -> String {
    let name = stage.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let rank = stage.placement.map { "\($0)位" } ?? ""
    let rankDetail: String = {
        guard let placement = stage.placement else { return stage.entrantCount.map { "（\($0)人中）" } ?? "" }
        return stage.entrantCount.map { "（\($0)人中\(placement)位）" } ?? "（\(placement)位）"
    }()
    switch stage.outcome {
    case .advanced: return name + rank + "通過" + (stage.entrantCount.map { "（\($0)人中）" } ?? "")
    case .eliminated: return (name.hasSuffix("敗退") ? name : name + "敗退") + rankDetail
    case .unrecorded: return rank.isEmpty ? "" : name + " " + rank + (stage.entrantCount.map { "（\($0)人中）" } ?? "")
    default: return [name, stage.outcome.title, rank].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

extension GiriEvent {
    /// 段階全体の記録（生大喜利の段階・ネットの段階）。お題ごとの記録は含めない。
    var stageResults: [ResultStage] { (tournamentResult?.stages ?? []).filter { $0.roundId == nil } }
    /// 最後に敗退した段階の名前から「予選敗退」「本戦1回戦敗退」を作る。
    var eliminationTitle: String {
        let stages = tournamentResult?.stages ?? []
        let stage = stages.last { $0.roundId == nil && $0.outcome == .eliminated } ?? stages.last { $0.outcome == .eliminated }
        guard let name = stage?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return "敗退" }
        return name.hasSuffix("敗退") ? name : name + "敗退"
    }
    /// 最終結果の表示（優勝・準優勝・3位・ベスト4・○○敗退など）。未記録は nil。
    var finalResultTitle: String? {
        guard let result = tournamentResult else { return effectivePlacement.map { "\($0)位" } }
        switch result.outcome {
        case .unrecorded: return effectivePlacement.map { "\($0)位" }
        case .champion: return "優勝"
        case .runnerUp: return "準優勝"
        case .placed:
            if let best = result.bestOf { return "ベスト\(best)" }
            return placement.map { "\($0)位" } ?? "入賞"
        case .eliminated: return eliminationTitle
        case .advanced: return "通過"
        case .other: return "その他"
        }
    }
    /// 一覧・戦績のカードに出す結果（例：予選1位通過・本戦1回戦敗退）。
    var resultProgressSummary: String {
        var parts = stageResults.map(giriStageResultText).filter { !$0.isEmpty }
        if let finalTitle = finalResultTitle, tournamentResult?.outcome != .eliminated || parts.isEmpty,
           !parts.contains(where: { $0.contains(finalTitle) }) {
            parts.append(finalTitle)
        }
        return parts.joined(separator: "・")
    }
    var isThirdPlace: Bool { tournamentResult?.bestOf == nil && effectivePlacement == 3 }
    func isBest(_ count: Int) -> Bool { tournamentResult?.outcome == .placed && tournamentResult?.bestOf == count }
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


/// 「#大喜利〇〇杯」「＃〇〇」「 〇〇 」を「大喜利〇〇杯」の形で保存する（空白は除く）。
func giriNormalizedHashtag(_ raw: String) -> String {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while let first = value.first, first == "#" || first == "＃" { value.removeFirst() }
    return value.components(separatedBy: .whitespacesAndNewlines).joined()
}

/// 参加費などの金額表示（例：¥1,500）。
func giriYenText(_ value: Int) -> String { "¥" + value.formatted(.number) }

extension AppPreferences {
    /// A partial/duplicated old preference still exposes all four categories.
    var effectiveFormatOrder: [EventFormat] {
        var seen = Set<EventFormat>()
        return (formatOrder + EventFormat.allCases).filter { seen.insert($0).inserted }
    }
    /// 一覧・戦績のタブと登録の選択肢に出す形式。すべて外れた古い値でも
    /// タブが空にならないよう、その場合は4形式を出す。
    var visibleFormatOrder: [EventFormat] {
        let hidden = Set(hiddenFormats)
        let visible = effectiveFormatOrder.filter { !hidden.contains($0) }
        return visible.isEmpty ? effectiveFormatOrder : visible
    }
    func isFormatVisible(_ format: EventFormat) -> Bool { visibleFormatOrder.contains(format) }
    /// 自分の名前と別名義の検索キー。
    var selfKeys: Set<String> {
        var keys = Set(([selfName] + selfAliases).map(playerSearchKey))
        keys.remove("")
        return keys
    }
    func isSelf(_ name: String) -> Bool { selfKeys.contains(playerSearchKey(name)) }
    /// 選択肢用。使わない形式でも、いま選ばれている（保存済みの記録の）形式は残す。
    func formatChoices(including current: EventFormat?) -> [EventFormat] {
        var choices = visibleFormatOrder
        if let current, !choices.contains(current) { choices.append(current) }
        return choices
    }
}

/// 優勝・準優勝・3位・ベスト4以外の入賞（ベスト8・4位以下・順位なしの入賞）。
func giriIsOtherPlacement(_ event: GiriEvent) -> Bool {
    let rank = event.effectivePlacement
    guard rank != 1, rank != 2, !event.isThirdPlace, !event.isBest(4) else { return false }
    return (rank ?? 0) > 3 || event.tournamentResult?.outcome == .placed
}

/// 大会の参加形式（「個人戦」「チーム戦（3人）」）。登録の基本情報と同じ値を詳細・結果入力で使う。
func giriTournamentFormatText(_ event: GiriEvent) -> String {
    switch event.tournamentFormat {
    case .individual: return "個人戦"
    case .pair: return "タッグ戦（2人）"
    case .team:
        guard let size = event.teamSize else { return "チーム戦" }
        return "チーム戦（\(size)人）"
    }
}

extension GiriEvent {
    /// この会で入力済みの名前（参加者・チームのメンバー・上位成績）。結果入力の候補に先に出す。
    var enteredPlayerNames: [String] {
        var seen = Set<String>()
        return (participants + teams.flatMap(\.members) + standings.flatMap(\.playerNames))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(playerSearchKey($0)).inserted }
    }
}
