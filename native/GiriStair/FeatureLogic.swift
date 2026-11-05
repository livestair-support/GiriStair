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
    /// 0.13：回答案に付けた印（◎・〇・△・× や点数）。空は印なし。
    var mark: String = ""

    init(id: String = UUID().uuidString, text: String = "", isSubmitted: Bool = false, placement: Int? = nil, points: Double? = nil, voterCount: Int? = nil, maxPointsPerVoter: Int = 1, memo: String = "", answerer: String = "", mark: String = "") {
        self.id = id; self.text = text; self.isSubmitted = isSubmitted
        self.placement = placement; self.points = points; self.voterCount = voterCount
        self.maxPointsPerVoter = maxPointsPerVoter; self.memo = memo; self.answerer = answerer; self.mark = mark
    }

    private enum CodingKeys: String, CodingKey { case id, text, isSubmitted, placement, points, voterCount, maxPointsPerVoter, memo, answerer, mark }
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
        mark = try c.decodeIfPresent(String.self, forKey: .mark) ?? ""
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
    case unrecorded, champion, runnerUp, third, finalist, best4, best8, best16, placed, eliminated, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .unrecorded: return "未記録"
        case .champion: return "優勝"
        case .runnerUp: return "準優勝"
        case .third: return "3位"
        case .finalist: return "決勝進出"
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
    static func current(outcome: TournamentOutcome, placement: Int?, bestOf: Int?, finalist: Bool = false) -> GiriFinalResultChoice {
        if finalist && outcome == .placed && bestOf == nil { return .finalist }
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
        case .third, .finalist, .best4, .best8, .best16, .placed: return .placed
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
            if result.finalist {
                // 3位以上は順位で、それ以外は「決勝進出」（順位・人数は分かる時だけ添える）。
                switch placement {
                case 1?: return "優勝"
                case 2?: return "準優勝"
                case 3?: return "3位"
                default:
                    let detail = [result.finalEntrants.map { "\($0)人中" }, placement.map { "\($0)位" }].compactMap { $0 }.joined()
                    return detail.isEmpty ? "決勝進出" : "決勝進出（\(detail)）"
                }
            }
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
        guard isActualParticipant, isSelfPlayer, eventFormat.hasOnlineRounds else { return [] }
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
    // 決勝進出は「決勝進出」として別に数える。
    if event.tournamentResult?.finalist == true { return false }
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

// MARK: - 0.10 段階の種類・結果のまとめ・トーナメント表

/// 段階名から種類の初期値を決める（ユーザーが選んだ種類があればそちらを使う）。
/// 「予選決勝」は予選、「決勝トーナメント」「決勝リーグ」は本戦として扱う。
func giriInferredStageKind(_ name: String) -> StageKind {
    let value = name.replacingOccurrences(of: #"\s"#, with: "", options: .regularExpression)
    guard !value.isEmpty else { return .other }
    func has(_ words: [String]) -> Bool { words.contains { value.contains($0) } }
    if has(["敗者復活", "3位決定", "３位決定", "三位決定", "エキシビション"]) { return .other }
    if has(["予選"]) { return .qualifier }
    if has(["準々決勝", "クォーターファイナル"]) { return .quarterfinal }
    if has(["準決勝", "セミファイナル"]) { return .semifinal }
    if has(["決勝トーナメント", "決勝リーグ", "決勝ラウンド"]) { return .main }
    if has(["決勝", "ファイナル"]) { return .final }
    if has(["本戦", "本選", "回戦", "ラウンド"]) { return .main }
    return .other
}

extension ResultStage {
    var effectiveKind: StageKind { kind ?? giriInferredStageKind(name) }
    /// 段階を勝ち抜いたか（通過・優勝）。敗退・準優勝・入賞は勝ち抜いていない。未記録・その他は nil。
    var passed: Bool? {
        switch outcome {
        case .advanced, .champion: return true
        case .eliminated, .runnerUp, .placed: return false
        case .unrecorded, .other: return nil
        }
    }
    fileprivate var hasOutcomeRecord: Bool { outcome != .unrecorded || placement != nil }
}

extension GiriEvent {
    /// 決勝に出たか：優勝・準優勝・決勝進出、または決勝の段階に結果がある。
    var reachedFinal: Bool {
        if let result = tournamentResult {
            if result.finalist || result.outcome == .champion || result.outcome == .runnerUp { return true }
            if stageResults.contains(where: { $0.effectiveKind == .final && $0.hasOutcomeRecord }) { return true }
        }
        return effectivePlacement == 1 || effectivePlacement == 2
    }
    /// どこまで進んだか（予選＜本戦＜準々決勝＜準決勝＜決勝）。記録から分からなければ nil。
    /// 通過した段階は次の深さまで進んだとみなす（予選通過→本戦、準決勝通過→決勝）。
    var furthestStageKind: StageKind? {
        if reachedFinal { return .final }
        var depth = -1
        for stage in stageResults where stage.hasOutcomeRecord {
            guard var reached = stage.effectiveKind.depth else { continue }
            if stage.passed == true {
                switch stage.effectiveKind {
                case .qualifier, .quarterfinal, .semifinal: reached += 1
                default: break
                }
            }
            depth = max(depth, reached)
        }
        if let result = tournamentResult, result.outcome == .placed, let bestOf = result.bestOf {
            if bestOf <= 4 { depth = max(depth, StageKind.semifinal.depth ?? 0) }
            else if bestOf <= 8 { depth = max(depth, StageKind.quarterfinal.depth ?? 0) }
        }
        return StageKind.allCases.first { $0.depth == depth }
    }
    /// 予選（予選がない大会は最初の段階）を通過したか。分からなければ nil。
    var qualifierPassed: Bool? {
        let stages = stageResults
        let qualifiers = stages.filter { $0.effectiveKind == .qualifier }
        let target: [ResultStage]
        if !qualifiers.isEmpty { target = qualifiers }
        else if let first = stages.first, first.effectiveKind != .final { target = [first] }
        else if stages.isEmpty, let result = tournamentResult, result.outcome == .placed || reachedFinal { return true }
        else { return nil }
        if target.contains(where: { $0.outcome == .eliminated }) { return false }
        let targetIDs = Set(target.map(\.id))
        if reachedFinal || stages.contains(where: { !targetIDs.contains($0.id) && $0.hasOutcomeRecord }) { return true }
        if target.last?.passed == true { return true }
        if let result = tournamentResult, result.outcome == .placed { return true }
        return nil
    }
}

/// 戦績のまとめ（終了した参加済みの大会）。3位とベスト4は分けて数え、決勝進出は優勝・準優勝を含む。
struct GiriTournamentSummary: Equatable {
    var completed = 0
    var champions = 0
    var runnersUp = 0
    var thirds = 0
    var bestFours = 0
    var finalists = 0
    var qualifierPassed = 0
    var qualifierKnown = 0
    var individualChampions = 0
    var teamChampions = 0
    var individualCount = 0
    var teamCount = 0
    var furthest: [StageKind: Int] = [:]
}

func giriTournamentSummary(_ events: [GiriEvent], now: Date = Date()) -> GiriTournamentSummary {
    var value = GiriTournamentSummary()
    for event in events where event.meetingType == .tournament && event.isSelfPlayer && event.isCountableParticipation(now: now) {
        let team = event.tournamentFormat != .individual
        value.completed += 1
        if team { value.teamCount += 1 } else { value.individualCount += 1 }
        if event.effectivePlacement == 1 {
            value.champions += 1
            if team { value.teamChampions += 1 } else { value.individualChampions += 1 }
        }
        if event.effectivePlacement == 2 { value.runnersUp += 1 }
        if event.isThirdPlace { value.thirds += 1 }
        if event.isBest(4) { value.bestFours += 1 }
        if event.reachedFinal { value.finalists += 1 }
        if let passed = event.qualifierPassed {
            value.qualifierKnown += 1
            if passed { value.qualifierPassed += 1 }
        }
        if let kind = event.furthestStageKind { value.furthest[kind, default: 0] += 1 }
    }
    return value
}

/// 率の行（例：横並び5人 3/5）。
struct GiriRateRow: Identifiable, Equatable {
    var label: String
    var passed: Int
    var total: Int
    var id: String { label }
}

/// 割合の表示（例：60%）。分母が0なら「—」。
func giriRateText(_ passed: Int, _ total: Int) -> String {
    guard total > 0 else { return "—" }
    return "\(Int((Double(passed) * 100 / Double(total)).rounded()))%"
}

/// 段階の形式・審査方法などごとの勝ち抜き率（通過・優勝 ÷ 結果を入れた段階）。
/// key は大会と段階から分類名を返す（段階が空なら大会の審査方法・対戦形式を使うなど）。
func giriStagePassRates(_ events: [GiriEvent], now: Date = Date(), by key: (GiriEvent, ResultStage) -> String) -> [GiriRateRow] {
    var counts: [String: (label: String, passed: Int, total: Int)] = [:]
    for event in events where event.meetingType == .tournament && event.isSelfPlayer && event.isCountableParticipation(now: now) {
        for stage in event.stageResults {
            guard let passed = stage.passed else { continue }
            let label = key(event, stage).trimmingCharacters(in: .whitespacesAndNewlines)
            let id = playerSearchKey(label)
            guard !id.isEmpty else { continue }
            var row = counts[id] ?? (label, 0, 0)
            row.total += 1
            if passed { row.passed += 1 }
            counts[id] = row
        }
    }
    return counts.values.map { GiriRateRow(label: $0.label, passed: $0.passed, total: $0.total) }
        .sorted { $0.total == $1.total ? $0.label < $1.label : $0.total > $1.total }
}

/// 審査方法の選択肢（段階ごと）。0.14：印象審査は投票だけにして、拍手審査を分ける。
let giriJudgingChoices = ["印象審査", "拍手審査", "加点審査", "超加点審査", "その他"]

/// 集計で使う審査方法の分類。以前の版の「挙手（1人1票）」などの投票は印象審査、拍手は拍手審査、
/// 「審査員の採点」などの分類できないものはその他にまとめる（保存した文字は変えない）。
func giriJudgingCategory(_ value: String) -> String {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return "" }
    if text.contains("超加点") { return "超加点審査" }
    if text.contains("加点") { return "加点審査" }
    if text.contains("拍手") { return "拍手審査" }
    if text.contains("印象") || text.contains("挙手") || text.contains("投票") { return "印象審査" }
    return "その他"
}

/// 主催ごとの出場・決勝進出・優勝。
struct GiriOrganizerRow: Identifiable, Equatable {
    var name: String
    var entries: Int
    var finals: Int
    var champions: Int
    var id: String { name }
}

func giriOrganizerResults(_ events: [GiriEvent], now: Date = Date()) -> [GiriOrganizerRow] {
    var rows: [String: GiriOrganizerRow] = [:]
    for event in events where event.meetingType == .tournament && event.isSelfPlayer && event.isCountableParticipation(now: now) {
        let name = event.organizer.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = playerSearchKey(name)
        guard !key.isEmpty else { continue }
        var row = rows[key] ?? GiriOrganizerRow(name: name, entries: 0, finals: 0, champions: 0)
        row.entries += 1
        if event.reachedFinal { row.finals += 1 }
        if event.effectivePlacement == 1 { row.champions += 1 }
        rows[key] = row
    }
    return rows.values.sorted { $0.entries == $1.entries ? $0.name < $1.name : $0.entries > $1.entries }
}

/// 段階の記録から最終結果の候補を出す（決勝の負けは、タイマンなら準優勝・横並びなら決勝進出）。
/// 0.14：予選・本戦の敗退は「敗退」（表示は「予選敗退」など段階の名前から）。
func giriSuggestedFinalChoice(_ stages: [ResultStage]) -> GiriFinalResultChoice? {
    guard let last = stages.filter({ $0.roundId == nil }).last(where: { $0.outcome != .unrecorded }) else { return nil }
    switch last.effectiveKind {
    case .qualifier, .main: return last.outcome == .eliminated ? .eliminated : nil
    case .final:
        switch last.outcome {
        case .champion, .advanced: return .champion
        case .runnerUp: return .runnerUp
        case .eliminated, .placed:
            if last.placement == 2 { return .runnerUp }
            if last.placement == 3 { return .third }
            let oneOnOne = last.lineup.contains("タイマン") || last.entrantCount == 2
            return oneOnOne ? .runnerUp : .finalist
        default: return nil
        }
    case .semifinal: return last.outcome == .eliminated ? .best4 : nil
    case .quarterfinal: return last.outcome == .eliminated ? .best8 : nil
    default: return nil
    }
}

/// 「第3回〇〇杯」「〇〇杯 vol.2」などの回数を除いた大会名（前回の大会を探すため）。
func giriSeriesKey(_ title: String) -> String {
    var value = playerSearchKey(title)
    value = value.replacingOccurrences(of: #"第?[0-9一二三四五六七八九十百]+回"#, with: "", options: .regularExpression)
    value = value.replacingOccurrences(of: #"(?:vol|no|#)\.?\s*[0-9]+"#, with: "", options: [.regularExpression, .caseInsensitive])
    value = value.replacingOccurrences(of: #"[0-9]+"#, with: "", options: .regularExpression)
    return value.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
}

/// 同じ主催者、または回数を除いて同じ名前の、段階を入れた直近の大会。
func giriStageTemplateSource(for event: GiriEvent, in events: [GiriEvent]) -> GiriEvent? {
    let organizer = playerSearchKey(event.organizer)
    let series = event.seriesKey
    return events.filter { other in
        other.id != event.id && other.meetingType == .tournament && other.eventFormat == event.eventFormat && !other.stageResults.isEmpty &&
            ((!organizer.isEmpty && playerSearchKey(other.organizer) == organizer) || (!series.isEmpty && other.seriesKey == series))
    }.max { ($0.eventDate ?? $0.startsAt ?? $0.createdAt) < ($1.eventDate ?? $1.startsAt ?? $1.createdAt) }
}

/// 前回の段階構成（名前・種類・形式・審査方法・通過枠）。結果・順位・人数は引き継がない。
func giriStageTemplate(from source: GiriEvent) -> [ResultStage] {
    source.stageResults.map { old in
        var stage = ResultStage()
        stage.name = old.name
        stage.kind = old.kind
        stage.lineup = old.lineup
        stage.judging = old.judging
        stage.advanceCount = old.advanceCount
        return stage
    }
}

/// プレイヤーと同じ組・対戦になった段階（自分の記録）。新しい大会から。
struct GiriMeeting: Identifiable {
    var event: GiriEvent
    var stage: ResultStage
    var id: String { event.id + ":" + stage.id }
}

func giriOpponentMeetings(_ events: [GiriEvent], playerKey: String, now: Date = Date()) -> [GiriMeeting] {
    giriOpponentMeetings(events, playerKeys: [playerKey], now: now)
}

/// 別名義をまとめる時は、名前の照合キーのどれかで探す。
func giriOpponentMeetings(_ events: [GiriEvent], playerKeys: Set<String>, now: Date = Date()) -> [GiriMeeting] {
    let keys = playerKeys.filter { !$0.isEmpty }
    guard !keys.isEmpty else { return [] }
    return events.filter { $0.isCountableParticipation(now: now) }.flatMap { event in
        (event.tournamentResult?.stages ?? []).filter { stage in stage.opponents.contains { keys.contains(playerSearchKey($0)) } }
            .map { GiriMeeting(event: event, stage: $0) }
    }.sorted { ($0.event.eventDate ?? $0.event.startsAt ?? $0.event.createdAt) > ($1.event.eventDate ?? $1.event.startsAt ?? $1.event.createdAt) }
}

/// 文字認識の1行（位置は 0〜1、midY は上が 0）。
struct GiriOCRLine: Equatable {
    var text: String
    var midX: Double
    var midY: Double
    /// 文字の高さ（0〜1）。見出し・タイトルの大きさを比べるのに使う。分からない時は 0。
    var height: Double = 0
}

/// トーナメント表の名前らしくない行（回戦名・数字・得点など）を除く。
func giriBracketCleanName(_ raw: String) -> String {
    var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    name = name.replacingOccurrences(of: #"^(?:[0-9０-９]+[.．)）:：]\s*|[(（][0-9０-９]+[)）]\s*)"#, with: "", options: .regularExpression)
    name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty,
          name.range(of: #"^[0-9０-９\s\-ー－:：.．()（）]+$"#, options: .regularExpression) == nil,
          name.range(of: #"^(?:第?[0-9０-９一二三四五六七八九十]+回戦|準々決勝|準決勝|決勝|優勝|準優勝|[3３三]位決定戦|シード|不戦勝|bye|トーナメント表?|.?ブロック)$"#, options: [.regularExpression, .caseInsensitive]) == nil
    else { return "" }
    return name
}

/// 読み取ったトーナメント表を上から順の名前に並べる。左右に山がある表は左の山 → 右の山。
/// 勝ち上がりで同じ名前がもう一度書かれていても、最初の位置だけを使う。
func giriBracketOrder(_ lines: [GiriOCRLine]) -> [String] {
    let cleaned = lines.compactMap { line -> GiriOCRLine? in
        let text = giriBracketCleanName(line.text)
        return text.isEmpty ? nil : GiriOCRLine(text: text, midX: line.midX, midY: line.midY)
    }
    let twoSided = cleaned.filter { $0.midX < 0.4 }.count >= 2 && cleaned.filter { $0.midX > 0.6 }.count >= 2
    let sides = twoSided ? [cleaned.filter { $0.midX < 0.5 }, cleaned.filter { $0.midX >= 0.5 }] : [cleaned]
    var seen = Set<String>()
    return sides.flatMap { side in
        side.sorted { abs($0.midY - $1.midY) < 0.005 ? $0.midX < $1.midX : $0.midY < $1.midY }
    }.map(\.text).filter { seen.insert(playerSearchKey($0)).inserted }
}

/// トーナメントの回戦数（4人なら2、6人なら3）。
func giriBracketRoundCount(_ count: Int) -> Int {
    guard count >= 2 else { return 0 }
    var rounds = 0
    while (1 << rounds) < count && rounds < 16 { rounds += 1 }
    return rounds
}

/// 回戦の名前（最後から決勝・準決勝・準々決勝、それより前は「1回戦」など）。
func giriBracketStageNames(_ count: Int) -> [String] {
    let rounds = giriBracketRoundCount(count)
    return (0..<rounds).map { index in
        switch rounds - index {
        case 1: return "決勝"
        case 2: return "準決勝"
        case 3: return "準々決勝"
        default: return "\(index + 1)回戦"
        }
    }
}

/// トーナメント表で、自分が round 回戦（1始まり）で当たる可能性のある相手（隣の山）。
func giriBracketOpponents(_ bracket: [String], round: Int, isSelf: (String) -> Bool) -> [String] {
    guard round >= 1, round <= giriBracketRoundCount(bracket.count), let position = bracket.firstIndex(where: isSelf) else { return [] }
    let half = 1 << (round - 1)
    let start = ((position / half) ^ 1) * half
    guard start < bracket.count else { return [] }
    return Array(bracket[start..<min(bracket.count, start + half)])
}

extension GiriEvent {
    /// 参加者とチームのメンバー（読みで重複を除く）。チーム戦は参加者ではなくチームとして入力する。
    var everyone: [String] {
        var seen = Set<String>()
        return (participants + teams.flatMap(\.members))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(playerSearchKey($0)).inserted }
    }
    /// まだどのチームにも入っていない参加者（即席チームのチーム分け前）。
    var unassignedParticipants: [String] {
        let assigned = Set(teams.flatMap(\.members).map(playerSearchKey))
        var seen = Set<String>()
        return participants.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !assigned.contains(playerSearchKey($0)) && seen.insert(playerSearchKey($0)).inserted }
    }
}

extension GiriEvent {
    /// 自分がプレイヤーとして出た（出る）会。戦績・結果の入力案内はこれだけを対象にする。
    var isSelfPlayer: Bool { selfRole == .player }
    /// 戦績に数える大会（参加して、プレイヤーとして出たもの）。
    var countsForResults: Bool { meetingType == .tournament && isActualParticipant && isSelfPlayer }
}

extension GiriEvent {
    /// 主催（個人）・共催・MC・審査員として名前がある人。
    var staffNames: [String] {
        var names: [String] = organizerIsGroup ? [] : [organizer]
        names += coOrganizers
        names += mcs
        names += judges
        return names
    }
    /// 主催者の表示（団体は「（団体）」を添える）。
    var organizerText: String {
        let name = organizer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "" }
        return organizerIsGroup ? name + "（団体）" : name
    }
}

extension GiriEvent {
    /// 主催（個人）または共催としてこの人の名前がある。
    func isHosted(byKey key: String) -> Bool {
        guard !key.isEmpty else { return false }
        return (!organizerIsGroup && playerSearchKey(organizer) == key) || coOrganizers.contains { playerSearchKey($0) == key }
    }
    /// MC・審査員としてこの人の名前がある。
    func isMCOrJudge(byKey key: String) -> Bool {
        guard !key.isEmpty else { return false }
        return (mcs + judges).contains { playerSearchKey($0) == key }
    }
    /// 別名義をまとめて数える時（名前の照合キーのどれか）。
    func isHosted(byKeys keys: Set<String>) -> Bool { keys.contains { isHosted(byKey: $0) } }
    func isMCOrJudge(byKeys keys: Set<String>) -> Bool { keys.contains { isMCOrJudge(byKey: $0) } }
    /// リザーバーの名前（大会で「リザーバーあり」の時だけ）。
    var reserveNames: [String] {
        guard hasReserves && meetingType == .tournament else { return [] }
        var seen = Set<String>()
        return reserves.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(playerSearchKey($0)).inserted }
    }
    /// 生大喜利の自分の立場を、入力した内容から決める（選ぶ項目にはしない）。
    /// 観覧は参加状況で選ぶ。リザーバーにいれば リザーバー、参加者・チームにいれば プレイヤー、
    /// 主催・共催・MC・審査員だけにいれば 主催・MCなど、どれでもなければ プレイヤー。
    func derivedSelfRole(isSelf: (String) -> Bool) -> GiriSelfRole {
        guard eventFormat == .live else { return .player }
        if selfRole == .spectator && isParticipating && !isInterested && status != .canceled { return .spectator }
        if meetingType == .tournament && reserveNames.contains(where: isSelf) { return .reserve }
        if everyone.contains(where: isSelf) { return .player }
        if staffNames.contains(where: isSelf) { return .staff }
        return .player
    }
}

/// 地域（地方）と都道府県。プレイヤーの地域は地方で入れ、分かれば都道府県も入れる。
let giriRegions: [(name: String, prefectures: [String])] = [
    ("北海道", ["北海道"]),
    ("東北", ["青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県"]),
    ("関東", ["茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県"]),
    ("中部", ["新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県", "岐阜県", "静岡県", "愛知県"]),
    ("近畿", ["三重県", "滋賀県", "京都府", "大阪府", "兵庫県", "奈良県", "和歌山県"]),
    ("中国", ["鳥取県", "島根県", "岡山県", "広島県", "山口県"]),
    ("四国", ["徳島県", "香川県", "愛媛県", "高知県"]),
    ("九州・沖縄", ["福岡県", "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県"]),
]

/// 都道府県の地方（「大阪」「大阪府」のどちらでも）。分からなければ nil。
func giriRegion(ofPrefecture value: String) -> String? {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    return giriRegions.first { region in
        region.prefectures.contains { $0 == text || $0.dropLast() == Substring(text) }
    }?.name
}

/// 都道府県の正式な名前（「大阪」→「大阪府」）。分からなければ nil。
func giriPrefectureName(_ value: String) -> String? {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    return giriRegions.flatMap { $0.prefectures }.first { $0 == text || $0.dropLast() == Substring(text) }
}

/// 地域の表示（「関東・東京都」）。以前の版の自由入力の地域はそのまま出す。
func giriRegionText(region: String, prefecture: String) -> String {
    [region, prefecture].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "・")
}

/// シリーズの表示名：会の名前から「#5」「第5回」「vol.2」と末尾の数字を除いたもの。
func giriSeriesTitle(_ title: String) -> String {
    var value = title.trimmingCharacters(in: .whitespacesAndNewlines)
    for pattern in [#"[#＃]\s*[0-9０-９]+"#, #"第\s*[0-9０-９一二三四五六七八九十百]+\s*回"#, #"(?i)vol\.?\s*[0-9０-９]+"#, #"\s*[0-9０-９]+\s*$"#] {
        value = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
}

extension GiriEvent {
    /// シリーズの表示名。シリーズ名が空なら会の名前から作る。
    var seriesTitle: String {
        let explicit = series.trimmingCharacters(in: .whitespacesAndNewlines)
        return explicit.isEmpty ? giriSeriesTitle(title) : explicit
    }
    /// 同じシリーズかどうかの照合キー（表記揺れ・回数を除く）。
    var seriesKey: String {
        let explicit = series.trimmingCharacters(in: .whitespacesAndNewlines)
        return giriSeriesKey(explicit.isEmpty ? title : explicit)
    }
}

/// 同じシリーズの会（生大喜利）。古い順。
func giriSeriesEvents(of event: GiriEvent, in events: [GiriEvent]) -> [GiriEvent] {
    let key = event.seriesKey
    guard !key.isEmpty else { return [] }
    return events.filter { $0.eventFormat == event.eventFormat && $0.seriesKey == key }
        .sorted { ($0.eventDate ?? $0.startsAt ?? $0.createdAt) < ($1.eventDate ?? $1.startsAt ?? $1.createdAt) }
}

/// 登録のシリーズ名の候補。名前が同じ・含む関係のシリーズを先に、ほかは新しい順。
func giriSeriesSuggestions(for title: String, in events: [GiriEvent]) -> [String] {
    let key = giriSeriesKey(title)
    var seen = Set<String>()
    var related: [String] = []
    var others: [String] = []
    for event in events.filter({ $0.eventFormat == .live }).sorted(by: { $0.createdAt > $1.createdAt }) {
        let name = event.seriesTitle
        let seriesKey = event.seriesKey
        guard !name.isEmpty, !seriesKey.isEmpty, seen.insert(seriesKey).inserted else { continue }
        let isRelated = !key.isEmpty && (seriesKey == key || (min(seriesKey.count, key.count) >= 3 && (key.contains(seriesKey) || seriesKey.contains(key))))
        if isRelated { related.append(name) } else { others.append(name) }
    }
    return related + others
}


// MARK: - 0.10 参加者一覧の読み取り（ツイプラ・note などの画面・文章）

/// 読み取った行がどの欄か。参加者だけを最初から選び、興味あり・不参加は選ばない。
enum GiriParticipantSection: String {
    case participants, interested, other
    var title: String {
        switch self {
        case .participants: return "参加者"
        case .interested: return "興味あり"
        case .other: return "不参加・キャンセル待ちなど"
        }
    }
}

struct GiriParticipantCandidate: Identifiable, Equatable {
    var id: Int
    /// 読み取った元の文字
    var source: String
    /// 追加する名前（登録済みのプレイヤーと合えばその名前）
    var name: String
    /// 照合できた登録済みのプレイヤー
    var registered: String?
    /// 名前が「…」で途中までしか読めなかった
    var truncated: Bool
    /// 先頭の1文字がアイコンの読み違いかもしれない（「Gしゆにく」の G など）
    var suspiciousPrefix: String?
    var section: GiriParticipantSection
    var included: Bool
    /// もう参加者に入っている（追加しても重ならないように、最初は選ばない）
    var alreadyAdded: Bool = false
}

/// 選んだ名前（同じ人は1回だけ）。
func giriSelectedParticipantNames(_ candidates: [GiriParticipantCandidate]) -> [String] {
    var seen = Set<String>()
    return candidates.filter(\.included).map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && seen.insert(giriOCRNameKey($0)).inserted }
}

/// 今の参加者と同じ人（読み違いの吸収込み）を「追加済み」にして、最初は選ばない。
func giriMarkingAlreadyAdded(_ candidates: [GiriParticipantCandidate], existing: [String]) -> [GiriParticipantCandidate] {
    let keys = Set(existing.map(giriOCRNameKey).filter { !$0.isEmpty })
    guard !keys.isEmpty else { return candidates }
    return candidates.map { candidate in
        var value = candidate
        if keys.contains(giriOCRNameKey(candidate.name)) {
            value.alreadyAdded = true
            value.included = false
        }
        return value
    }
}

/// 照合用の名前：読み（ひらがな）・小書き文字・記号・空白の違いを吸収する。
func giriOCRNameKey(_ value: String) -> String {
    let small: [Character: Character] = ["ぁ": "あ", "ぃ": "い", "ぅ": "う", "ぇ": "え", "ぉ": "お", "っ": "つ",
                                         "ゃ": "や", "ゅ": "ゆ", "ょ": "よ", "ゎ": "わ", "ゕ": "か", "ゖ": "け"]
    let ignored = Set("・･.。、,，-‐－―—~〜…‥()（）[]［］「」『』【】!！?？:：;；'\"’”*＊#＃@＠_")
    return String(playerSearchKey(value).compactMap { character -> Character? in
        if character.isWhitespace || ignored.contains(character) { return nil }
        return small[character] ?? character
    })
}

/// 2つの名前の近さ（0〜1）。文字の置き換え・抜け・増えを1文字ずつ数える。
func giriNameSimilarity(_ first: String, _ second: String) -> Double {
    let a = Array(first), b = Array(second)
    guard !a.isEmpty, !b.isEmpty else { return 0 }
    var previous = Array(0...b.count)
    for i in 1...a.count {
        var current = [i] + Array(repeating: 0, count: b.count)
        for j in 1...b.count {
            current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
        }
        previous = current
    }
    return 1 - Double(previous[b.count]) / Double(max(a.count, b.count))
}

/// 登録済みのプレイヤーと照合する。完全一致 → 先頭のアイコンの読み違いを除いて一致 →
/// 「…」で切れた名前の前方一致 → 読み違い1〜2文字まで（3文字以上の名前だけ）。候補が1人に決まる時だけ返す。
func giriMatchRegisteredName(_ text: String, truncated: Bool = false, known: [String]) -> String? {
    let key = giriOCRNameKey(text)
    guard !key.isEmpty else { return nil }
    var seen = Set<String>()
    let index = known.compactMap { name -> (String, String)? in
        let normalized = giriOCRNameKey(name)
        guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
        return (name, normalized)
    }
    if let hit = index.first(where: { $0.1 == key }) { return hit.0 }
    for drop in 1...2 where key.count - drop >= 2 {
        let rest = String(key.dropFirst(drop))
        if let hit = index.first(where: { $0.1 == rest }) { return hit.0 }
    }
    if truncated {
        // 「…」で切れた名前（ツイプラの長い名前など）：登録名の前方と比べる。先頭のアイコンの読み違いは2文字まで除く。
        // 候補が複数ある時は、先に並んだ名前（よく出る人）を選ぶ。
        for drop in 0...2 where key.count - drop >= 2 {
            let rest = String(key.dropFirst(drop))
            if let hit = index.first(where: { $0.1.count > rest.count && $0.1.hasPrefix(rest) }) { return hit.0 }
        }
        // 切れた部分にも読み違いがある時は、登録名の先頭の同じ長さと比べる（3文字以上）。
        if key.count >= 3 {
            var best: (name: String, score: Double)? = nil
            for entry in index where entry.1.count > key.count {
                let score = giriNameSimilarity(key, String(entry.1.prefix(key.count)))
                if score >= 0.75 && score > (best?.score ?? 0) { best = (entry.0, score) }
            }
            if let best { return best.name }
        }
    }
    guard key.count >= 3, !key.allSatisfy(\.isNumber) else { return nil }
    // 読み違い1〜2文字。同じくらい近い名前が複数ある時は、先に並んだ名前（よく出る人）。
    var best: (name: String, score: Double)? = nil
    for entry in index where entry.1.count >= 3 {
        let score = giriNameSimilarity(key, entry.1)
        if score >= 0.75 && score > (best?.score ?? 0) + 0.0001 { best = (entry.0, score) }
    }
    return best?.name
}

/// 欄の見出し（「参加者（15人／定員15人）」「興味あり（5人）」「不参加（0人）」など）。
/// 見出しは短く、語のすぐ後が人数・括弧・「一覧」などの時だけ（説明文の「キャンセル待ちはないので…」は見出しにしない）。
func giriParticipantHeader(_ text: String) -> GiriParticipantSection? {
    let value = text.replacingOccurrences(of: #"\s"#, with: "", options: .regularExpression)
    guard value.count <= 24, !value.contains("プロフィール") else { return nil }
    let tail = #"([（(［\[]|[0-9０-９]|一覧|リスト|[:：]|$)"#
    if value.range(of: #"^(参加者|参加予定者?|参加メンバー|エントリー者?|出場者)"# + tail, options: .regularExpression) != nil { return .participants }
    if value.range(of: #"^(興味あり|気になる)"# + tail, options: .regularExpression) != nil { return .interested }
    if value.range(of: #"^(不参加|キャンセル待ち|補欠)"# + tail, options: .regularExpression) != nil { return .other }
    return nil
}

/// 一覧の終わり（ボタン・コメント欄など）。
func giriParticipantListEnds(_ text: String) -> Bool {
    let value = text.replacingOccurrences(of: #"\s"#, with: "", options: .regularExpression)
    let markers = ["参加者プロフィール", "名前をID表示", "コメント", "ログインしてコメント", "イベント詳細", "参加をやめる", "シェアする"]
    return markers.contains { value.contains($0) }
}

/// 名前ではない行（時刻・電波・URL・人数・案内文など）。
func giriIsParticipantNoise(_ text: String) -> Bool {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty { return true }
    if value.count == 1, let scalar = value.unicodeScalars.first, !CharacterSet.letters.contains(scalar) || scalar.isASCII { return true }
    // 名前としては長すぎる行（説明文・案内文）。
    if value.replacingOccurrences(of: #"\s"#, with: "", options: .regularExpression).count > 24 { return true }
    let patterns = [#"^[0-9０-９]{1,2}[:：][0-9０-９]{2}$"#, #"(?i)^(https?://|www\.)"#, #"(?i)[a-z0-9-]+\.(jp|com|net|me|org)(/|$)"#,
                    #"^[（(]?[0-9０-９]+\s*人[)）]?$"#, #"(?i)(^|\s)[345]G(\s|$)|LTE|Wi-?Fi"#,
                    #"ログイン|ツイート|フォロー|ありません|しますか|定員|参加する$"#,
                    // 日付・時刻の範囲・金額・人数（「2025/11/18」「18:00〜21:15」「500円」「15名」）
                    #"[0-9０-９]{4}\s*[年/／.]\s*[0-9０-９]{1,2}|[0-9０-９]{1,2}\s*月\s*[0-9０-９]{1,2}\s*日"#,
                    #"[0-9０-９]{1,2}[:：][0-9０-９]{2}\s*[〜~～\-－−ー]"#, #"[0-9０-９,，]+\s*円|[0-9０-９]+\s*名"#,
                    // 「《日時》」「【場所】」のような見出し、「場所：」のような項目名
                    #"^[《【\[［〈<].*[》】\]］〉>]$"#, #"^(日時|日程|場所|会場|定員|参加費|料金|持ち物|開場|開演|内容|概要|注意事項|ルール)\s*[:：]"#,
                    // 交通案内・案内文・広告・ページのボタン
                    #"徒歩\s*[0-9０-９]|駅\s*(から|より)?\s*徒歩|「[^」]+」駅"#, #"(します|しません|ください|ません|ました|でした|します。)$|。$"#,
                    #"(?i)インストール|キャンペーン|今すぐ|詳しくはこちら|カレンダー登録|で送る|でシェア|\bviews?\b"#]
    return patterns.contains { value.range(of: $0, options: .regularExpression) != nil }
}

/// 名前の前に付いたアイコンの読み違い（●・◆・①・「(」など）と、末尾の「…」を外す。
func giriCleanParticipantText(_ raw: String) -> (name: String, truncated: Bool) {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    var truncated = false
    if let range = value.range(of: #"\s*(…+|‥+|・・+|･･+|\.\.+)$"#, options: .regularExpression) {
        value.removeSubrange(range)
        truncated = true
    }
    value = value.replacingOccurrences(of: #"^[\s・･•●○◎◆◇■□▲△▼▽★☆※＊*\-－—―~〜～凸(（\[［「『【①-⓿❶-➓]+"#, with: "", options: .regularExpression)
    // アイコンが英数字1文字に読まれて、空白をはさんで名前が続く（「1 3104」「G しゅにく」）。
    if let range = value.range(of: #"^[A-Za-z0-9Ａ-Ｚａ-ｚ０-９]\s+(?=\S)"#, options: .regularExpression) { value.removeSubrange(range) }
    if !value.contains("(") && !value.contains("（") {
        value = value.replacingOccurrences(of: #"[)）]+$"#, with: "", options: .regularExpression)
    }
    return (value.trimmingCharacters(in: .whitespacesAndNewlines), truncated)
}

/// 欄ごとに分けた行から候補を作る（同じ人は最初の1回だけ）。
/// stripsIconLetter：画面の読み取りだけ、名前の前のアイコンが英数字1文字に読まれたものを外す（貼り付けた文章にはアイコンがない）。
func giriParticipantCandidates(entries: [(text: String, section: GiriParticipantSection)], known: [String], stripsIconLetter: Bool = false) -> [GiriParticipantCandidate] {
    var seen = Set<String>()
    var output: [GiriParticipantCandidate] = []
    for entry in entries {
        let source = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 見出し・一覧の終わりのボタン（「名前をID表示に」など）は名前にしない。
        guard !giriIsParticipantNoise(source), giriParticipantHeader(source) == nil, !giriParticipantListEnds(source) else { continue }
        let cleaned = giriCleanParticipantText(source)
        guard !cleaned.name.isEmpty, !giriIsParticipantNoise(cleaned.name) else { continue }
        var text = cleaned.name
        var registered = giriMatchRegisteredName(text, truncated: cleaned.truncated, known: known)
        // アイコンが英数字1文字に読まれた（「2守」「Gしゅにく」）時は、確認画面に出さずにここで外す。
        let scalars = Array(text.unicodeScalars)
        if stripsIconLetter, registered == nil, scalars.count >= 2, scalars[0].isASCII, CharacterSet.letters.union(.decimalDigits).contains(scalars[0]), !scalars[1].isASCII {
            text = String(text.dropFirst())
            registered = giriMatchRegisteredName(text, truncated: cleaned.truncated, known: known)
        }
        let name = registered ?? text
        guard seen.insert(giriOCRNameKey(name)).inserted else { continue }
        output.append(GiriParticipantCandidate(id: output.count, source: source, name: name, registered: registered,
                                               truncated: cleaned.truncated && registered == nil, suspiciousPrefix: nil,
                                               section: entry.section, included: entry.section == .participants))
    }
    return output
}

/// 貼り付けた文章：見出しがあれば欄ごとに分け、なければ全部を参加者として読む。
func giriParticipantCandidates(text: String, known: [String]) -> [GiriParticipantCandidate] {
    let lines = text.components(separatedBy: .newlines).flatMap { line -> [String] in
        line.range(of: #"[、,，\t]"#, options: .regularExpression) == nil ? [line] : line.components(separatedBy: CharacterSet(charactersIn: "、,，\t"))
    }
    guard lines.contains(where: { giriParticipantHeader($0) != nil }) else {
        return giriParticipantCandidates(entries: lines.map { ($0, .participants) }, known: known)
    }
    var section: GiriParticipantSection? = nil
    var entries: [(text: String, section: GiriParticipantSection)] = []
    // 「参加者」の見出しがあれば、そこから読む（上の説明文・ボタンは使わない）。
    let start = lines.firstIndex { giriParticipantHeader($0) == .participants } ?? 0
    for line in lines[start...] {
        if let header = giriParticipantHeader(line) { section = header; continue }
        if giriParticipantListEnds(line) { section = nil; continue }
        if let section { entries.append((line, section)) }
    }
    return giriParticipantCandidates(entries: entries, known: known)
}

/// 画面の読み取り：見出しの位置から欄（列）を分け、見出しより下・一覧の終わりより上の行だけを使う。
/// 見出しがない画像は、上から順に全部を参加者として読む。
func giriParticipantCandidates(lines: [GiriOCRLine], known: [String]) -> [GiriParticipantCandidate] {
    let sorted = lines.sorted { abs($0.midY - $1.midY) < 0.004 ? $0.midX < $1.midX : $0.midY < $1.midY }
    let allHeaders = sorted.compactMap { line in giriParticipantHeader(line.text).map { (line: line, section: $0) } }
    // 「参加者」の見出しから読む。それより上（説明文・「興味あり」「不参加」のボタンなど）は使わない。
    guard let firstHeader = allHeaders.first(where: { $0.section == .participants }) ?? allHeaders.first else {
        return giriParticipantCandidates(entries: sorted.map { ($0.text, .participants) }, known: known, stripsIconLetter: true)
    }
    let rowTolerance = max(0.006, firstHeader.line.height * 0.7)
    let headers = allHeaders.filter { $0.line.midY >= firstHeader.line.midY - rowTolerance }
    let end = sorted.first { $0.midY > firstHeader.line.midY && giriParticipantListEnds($0.text) }?.midY ?? .infinity
    var entries: [(text: String, section: GiriParticipantSection)] = []
    for line in sorted where line.midY > firstHeader.line.midY && line.midY < end && giriParticipantHeader(line.text) == nil {
        // 行より上にある見出しのうち、横の位置がいちばん近い欄に入れる。
        let above = headers.filter { $0.line.midY < line.midY }
        guard let column = above.min(by: { abs($0.line.midX - line.midX) < abs($1.line.midX - line.midX) }) else { continue }
        entries.append((line.text, column.section))
    }
    return giriParticipantCandidates(entries: entries, known: known, stripsIconLetter: true)
}

// MARK: - イベントページの読み取り（生大喜利）

/// 縦に分けて読み取った画面の行をまとめる：重なった部分で2回読んだ同じ行は1つにする。
func giriMergeTileLines(_ lines: [GiriOCRLine]) -> [GiriOCRLine] {
    let sorted = lines.sorted { abs($0.midY - $1.midY) < 0.002 ? $0.midX < $1.midX : $0.midY < $1.midY }
    var output: [GiriOCRLine] = []
    for line in sorted {
        let key = line.text.replacingOccurrences(of: #"\s"#, with: "", options: .regularExpression)
        guard !key.isEmpty else { continue }
        let tolerance = max(0.004, max(line.height, 0.001) * 0.8)
        let duplicate = output.contains { other in
            abs(other.midY - line.midY) < tolerance && abs(other.midX - line.midX) < 0.05
                && other.text.replacingOccurrences(of: #"\s"#, with: "", options: .regularExpression) == key
        }
        if !duplicate { output.append(line) }
    }
    return output
}

/// 時刻（日付なし）。会の日付と組み合わせて使う。
struct GiriClock: Equatable {
    var hour: Int
    var minute: Int
}

/// イベントページの画面から読み取った基本情報と参加者。反映する前に確認する。
struct GiriEventPageDraft: Equatable, Identifiable {
    var id = UUID().uuidString
    var title = ""
    var date: Date? = nil
    var opens: GiriClock? = nil
    var start: GiriClock? = nil
    var end: GiriClock? = nil
    var venue = ""
    var venueRoom = ""
    var organizer = ""
    var fee: Int? = nil
    var participants: [GiriParticipantCandidate] = []
    var recognizedText = ""

    var hasBasicInfo: Bool {
        !title.isEmpty || date != nil || opens != nil || start != nil || end != nil || !venue.isEmpty || !organizer.isEmpty || fee != nil
    }
}

func giriClockDate(_ clock: GiriClock, on day: Date, calendar: Calendar = .current) -> Date? {
    calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: day)
}

/// 全角の数字・コロン・スラッシュを半角にする（ほかの文字は変えない）。
func giriHalfwidthDigits(_ text: String) -> String {
    String(text.map { character -> Character in
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else { return character }
        switch scalar.value {
        case 0xFF10...0xFF19: return UnicodeScalar(scalar.value - 0xFEE0).map(Character.init) ?? character
        case 0xFF1A: return ":"
        case 0xFF0F: return "/"
        default: return character
        }
    })
}

private func giriRegexGroups(_ pattern: String, in text: String) -> [[String]] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: range).map { match in
        (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}

/// 行の最初の日付。年がない時は、今日から見て近い年（60日以上前なら来年）にする。
func giriEventPageDate(_ raw: String, now: Date, calendar: Calendar = .current) -> Date? {
    let text = giriHalfwidthDigits(raw)
    if let groups = giriRegexGroups(#"(20[0-9]{2})\s*[年/.\-]\s*([0-9]{1,2})\s*[月/.\-]\s*([0-9]{1,2})"#, in: text).first,
       let year = Int(groups[1]), let month = Int(groups[2]), let day = Int(groups[3]) {
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
    let monthDay = giriRegexGroups(#"([0-9]{1,2})\s*月\s*([0-9]{1,2})\s*日"#, in: text).first
        ?? giriRegexGroups(#"(?<![0-9/])([0-9]{1,2})/([0-9]{1,2})(?=\s*[(（\[［])"#, in: text).first
    guard let groups = monthDay, let month = Int(groups[1]), let day = Int(groups[2]), (1...12).contains(month), (1...31).contains(day) else { return nil }
    let year = calendar.component(.year, from: now)
    guard let candidate = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
    if candidate < now.addingTimeInterval(-60 * 86400) {
        return calendar.date(from: DateComponents(year: year + 1, month: month, day: day))
    }
    return candidate
}

private let giriClockPattern = #"([0-9]{1,2})\s*(?::\s*([0-9]{2})|時\s*(?:([0-9]{1,2})\s*分|(半))?)"#

private func giriClock(_ groups: [String], offset: Int) -> GiriClock? {
    guard let hour = Int(groups[offset]), (0...29).contains(hour) else { return nil }
    let minute: Int
    if let value = Int(groups[offset + 1]) { minute = value }
    else if let value = Int(groups[offset + 2]) { minute = value }
    else if !groups[offset + 3].isEmpty { minute = 30 }
    else { minute = 0 }
    guard (0...59).contains(minute) else { return nil }
    return GiriClock(hour: hour, minute: minute)
}

/// 1行の時刻の読み取り。「18:15開場」「開場 18:15」「18:45〜21:00」の形に対応する。
struct GiriEventPageTimes: Equatable {
    var opens: GiriClock? = nil
    var start: GiriClock? = nil
    var end: GiriClock? = nil
    var teardown: GiriClock? = nil
    var rangeStart: GiriClock? = nil
    var rangeEnd: GiriClock? = nil
    var lone: [GiriClock] = []
}

func giriEventPageTimes(_ raw: String) -> GiriEventPageTimes {
    var text = giriHalfwidthDigits(raw)
    var output = GiriEventPageTimes()
    let labels = #"(開場|開演|開始|終了|終演|撤収|(?i:\bopen\b|\bstart\b|\bend\b))"#
    func assign(_ label: String, _ clock: GiriClock) {
        switch label.lowercased() {
        case "開場", "open": if output.opens == nil { output.opens = clock }
        case "開演", "開始", "start": if output.start == nil { output.start = clock }
        case "終了", "終演", "end": if output.end == nil { output.end = clock }
        default: if output.teardown == nil { output.teardown = clock }
        }
    }
    // 項目名が先（「開場 18:00 開演 18:30」）か、時刻が先（「18:15開場 21:15撤収」）かを、行の最初で決める。
    let firstLabel = text.range(of: labels, options: .regularExpression)?.lowerBound
    let firstClock = text.range(of: giriClockPattern, options: .regularExpression)?.lowerBound
    let labelFirst = firstLabel.map { label in firstClock.map { label < $0 } ?? false } ?? false
    let labeled = labelFirst ? labels + #"\s*[:：/]?\s*"# + giriClockPattern : giriClockPattern + #"\s*"# + labels
    for groups in giriRegexGroups(labeled, in: text) {
        if labelFirst, let clock = giriClock(groups, offset: 2) { assign(groups[1], clock) }
        if !labelFirst, let clock = giriClock(groups, offset: 1) { assign(groups[5], clock) }
    }
    text = text.replacingOccurrences(of: labeled, with: " ", options: .regularExpression)
    let range = giriClockPattern + #"\s*[〜~～\-－−ー―]\s*"# + giriClockPattern
    if let groups = giriRegexGroups(range, in: text).first {
        output.rangeStart = giriClock(groups, offset: 1)
        output.rangeEnd = giriClock(groups, offset: 5)
        text = text.replacingOccurrences(of: range, with: " ", options: .regularExpression)
    }
    for groups in giriRegexGroups(giriClockPattern, in: text) {
        if let clock = giriClock(groups, offset: 1) { output.lone.append(clock) }
    }
    return output
}

/// 「福島区民センター 306」「豊中市庄内公民館205会議室2（…）」を、会場と部屋に分ける。
/// 登録済みの会場の名前で始まる時はその名前を会場にする。
func giriSplitVenueRoom(_ raw: String, venues: [String]) -> (venue: String, room: String) {
    var text = raw.replacingOccurrences(of: #"[（(][^）)]*[）)]?"#, with: " ", options: .regularExpression)
    text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return ("", "") }
    let compact = playerSearchKey(text)
    let registered = venues.filter { !$0.isEmpty && compact.hasPrefix(playerSearchKey($0)) }.max { $0.count < $1.count }
    if let registered {
        let rest = String(text.dropFirst(min(text.count, registered.count))).trimmingCharacters(in: .whitespacesAndNewlines)
        if playerSearchKey(String(text.prefix(registered.count))) == playerSearchKey(registered) { return (registered, rest) }
    }
    // 施設名の終わり（センター・公民館・会館など）の後ろを部屋にする。部屋は空白の後か、
    // 番号・「室」「階」などで始まる・終わる時だけ（「カフェ＆バー」を分けない）。
    let facility = #"^(.*(センター|公民館|会館|市民館|区民館|コミュニティ|プラザ|ホール|会議所|ビル|カフェ|スタジオ|劇場|図書館|学習館|交流館))(\s*)(\S.*)?$"#
    if let groups = giriRegexGroups(facility, in: text).first, !groups[4].isEmpty {
        let room = groups[4].trimmingCharacters(in: .whitespaces)
        let roomLike = !groups[3].isEmpty || room.first?.isNumber == true
            || room.range(of: #"室|ルーム|階|ホール|スペース|ステージ|[0-9]F$"#, options: .regularExpression) != nil
        if roomLike { return (groups[1].trimmingCharacters(in: .whitespaces), room) }
    }
    // 「会場 306」のように、最後の語が部屋番号・部屋名。
    if let groups = giriRegexGroups(#"^(.+?)\s+([0-9]{2,4}[A-Za-z号]?室?|\S*(室|ルーム|ホール|階))$"#, in: text).first {
        return (groups[1], groups[2])
    }
    return (text, "")
}

/// 説明文の始まり（「詳細」「概要」の見出し、【】《》で囲んだ見出し）。会の名前はこれより前で探す。
func giriIsEventPageSectionStart(_ raw: String) -> Bool {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if ["詳細", "概要", "内容", "イベント詳細"].contains(text) { return true }
    return text.range(of: #"^[【《［\[〈<]"#, options: .regularExpression) != nil
}

/// 項目名（「場所：」「《場所》」「【参加費】」）。値が同じ行にあれば返す。
private func giriEventPageLabel(_ raw: String, names: String) -> (matched: Bool, value: String) {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let pattern = #"^[《【\[［〈<(（]?\s*"# + names + #"\s*[》】\]］〉>)）]?\s*(?:[:：]\s*(.*)|\s+(.*)|$)"#
    guard let groups = giriRegexGroups(pattern, in: text).first else { return (false, "") }
    let value = (groups[2].isEmpty ? groups[3] : groups[2]).trimmingCharacters(in: .whitespacesAndNewlines)
    return (true, value)
}

private func giriIsEventPageNoise(_ text: String) -> Bool {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.count < 2 { return true }
    return value.range(of: #"(?i)\bviews?\b|シェア|で送る|カレンダー登録|ログイン|^https?://|\.(jp|com|net)\b|^[0-9:\s]+$|LTE|[345]G$"#, options: .regularExpression) != nil
}

/// イベントページの画面（ツイプラなど）から、会の名前・日付・時刻・会場・主催・参加費・参加者を読む。
/// 特定のサイトの決まった位置ではなく、日付の近くの大きい文字・項目名・時刻の書き方から判断する。
func giriEventPageDraft(lines: [GiriOCRLine], known: [String], venues: [String], organizers: [String] = [],
                        now: Date = Date(), calendar: Calendar = .current) -> GiriEventPageDraft {
    let sorted = lines.sorted { abs($0.midY - $1.midY) < 0.004 ? $0.midX < $1.midX : $0.midY < $1.midY }
    var draft = GiriEventPageDraft()
    draft.recognizedText = sorted.map(\.text).joined(separator: "\n")
    // イベントページの参加者は「参加者」などの見出しの下だけ（見出しがなければ説明文を名前にしない）。
    let hasParticipantHeader = sorted.contains { giriParticipantHeader($0.text) != nil }
    draft.participants = hasParticipantHeader ? giriParticipantCandidates(lines: lines, known: known) : []
    // 基本情報は参加者の欄より上だけから読む（下のコメント欄の時刻などを使わない）。
    let listTop = sorted.first { giriParticipantHeader($0.text) == .participants }?.midY ?? .infinity
    let info = sorted.filter { $0.midY < listTop }

    // 日付：最初に出てくる日付（ページの見出しの日付）。
    let dateIndex = info.firstIndex { giriEventPageDate($0.text, now: now, calendar: calendar) != nil }
    if let dateIndex { draft.date = giriEventPageDate(info[dateIndex].text, now: now, calendar: calendar) }

    // 会の名前：日付のすぐ後の行（タグ・ボタンより大きい文字）。説明文の見出し（【】《》・「詳細」）より前だけを見る。
    let titleIndex: Int? = {
        var window: [Int] = []
        let first = dateIndex.map { $0 + 1 } ?? 0
        for index in first..<min(info.count, first + 6) {
            if giriIsEventPageSectionStart(info[index].text) { break }
            window.append(index)
        }
        let candidates = window.filter { index in
            let text = info[index].text
            return !giriIsEventPageNoise(text) && giriEventPageDate(text, now: now, calendar: calendar) == nil
                && text.unicodeScalars.contains { !$0.isASCII } && giriParticipantHeader(text) == nil
        }
        // 日付と同じくらいの大きさの最初の行。分からなければ一番大きい行。
        if let dateIndex, info[dateIndex].height > 0,
           let near = candidates.first(where: { info[$0].height >= info[dateIndex].height * 0.75 }) { return near }
        guard let tallest = candidates.map({ info[$0].height }).max() else { return nil }
        return candidates.first { info[$0].height >= tallest * 0.9 }
    }()
    if let titleIndex { draft.title = info[titleIndex].text.trimmingCharacters(in: .whitespacesAndNewlines) }

    // 項目名のある行（同じ行か次の行の値）。
    func labeledValue(_ names: String) -> String? {
        for (index, line) in info.enumerated() {
            let label = giriEventPageLabel(line.text, names: names)
            guard label.matched else { continue }
            if !label.value.isEmpty { return label.value }
            if let next = info[(index + 1)...].first(where: { !giriIsEventPageNoise($0.text) }) { return next.text }
        }
        return nil
    }
    if let place = labeledValue(#"(場所|会場|開催場所|会場名)"#) {
        let split = giriSplitVenueRoom(place, venues: venues)
        draft.venue = split.venue; draft.venueRoom = split.room
    }
    if let fee = labeledValue(#"(参加費|料金|入場料|参加料|エントリー費)"#) {
        let text = giriHalfwidthDigits(fee)
        if let groups = giriRegexGroups(#"([0-9][0-9,]*)\s*円"#, in: text).first { draft.fee = Int(groups[1].replacingOccurrences(of: ",", with: "")) }
        else if text.contains("無料") { draft.fee = 0 }
    }
    if let host = labeledValue(#"(主催|主催者|運営)"#) {
        draft.organizer = giriMatchRegisteredName(host, known: organizers) ?? host
    } else if let titleIndex {
        // 項目名がない時は、会の名前のすぐ下の短い名前（ツイプラなどの主催者の表示）。
        let nearby = info[(titleIndex + 1)...].prefix(3).prefix { !giriIsEventPageSectionStart($0.text) }
        let following = nearby.first { line in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return !giriIsEventPageNoise(text) && text.count <= 16 && giriEventPageDate(text, now: now, calendar: calendar) == nil
                && !giriIsParticipantNoise(text) && text.range(of: #"[。、：:]"#, options: .regularExpression) == nil
        }
        if let following {
            let cleaned = giriCleanParticipantText(following.text).name
            draft.organizer = giriMatchRegisteredName(cleaned, known: organizers) ?? cleaned
        }
    }

    // 時刻：項目名つき → 「18:45〜21:00」の範囲 → 日付の行の時刻。撤収は終了が分からない時だけ。
    var times: [GiriEventPageTimes] = []
    for line in info { times.append(giriEventPageTimes(line.text)) }
    draft.opens = times.compactMap(\.opens).first
    draft.start = times.compactMap(\.start).first ?? times.compactMap(\.rangeStart).first
        ?? dateIndex.flatMap { times[$0].lone.first }
    draft.end = times.compactMap(\.end).first ?? times.compactMap(\.rangeEnd).first ?? times.compactMap(\.teardown).first
    return draft
}

// MARK: - 長考の段階・回（0.13）

/// 同じ段階に並列のお題がある（1回目で「全N回」を選んだ、または同じ段階に2回以上ある）。
func giriRoundIsParallel(_ round: EventRound, in rounds: [EventRound]) -> Bool {
    let siblings = rounds.filter { $0.effectiveStageId == round.effectiveStageId }
    if siblings.count > 1 || round.promptNumber > 1 { return true }
    return (siblings.compactMap(\.promptCount).max() ?? round.promptCount ?? 0) > 1
}

/// 「1回目」などの表示。並列のお題がない段階は出さない（「--」）。
func giriRoundNumberText(_ round: EventRound, in rounds: [EventRound]) -> String? {
    giriRoundIsParallel(round, in: rounds) ? "\(round.promptNumber)回目" : nil
}

/// 次に入れるのが同じ段階の次の回（並列）か。1回目で選んだ「全N回」に足りない時だけ並列、それ以外は次の段階。
func giriNextRoundIsParallel(_ rounds: [EventRound]) -> Bool {
    guard let last = rounds.last else { return false }
    let siblings = rounds.filter { $0.effectiveStageId == last.effectiveStageId }
    let total = siblings.compactMap(\.promptCount).max() ?? 0
    return total > siblings.count
}

// MARK: - お題の種類・穴埋め・回答案のメモ（0.13）

enum GiriPromptStyle: String, CaseIterable, Identifiable {
    case plain, image, fill
    var id: String { rawValue }
    var title: String {
        switch self {
        case .plain: return "通常お題"
        case .image: return "画像お題"
        case .fill: return "穴埋めお題"
        }
    }
}

extension ThoughtNote {
    /// お題の種類。以前の版の記録は画像があれば画像お題、なければ通常お題（穴埋めにはしない）。
    var effectivePromptStyle: GiriPromptStyle {
        if let style = GiriPromptStyle(rawValue: promptStyle) { return style }
        return imageDataBase64.isEmpty ? .plain : .image
    }
}

/// 穴埋めの部分（〇〇・△△・××・＿＿。個数は問わない）。
let giriPromptBlankPattern = #"[〇○◯]{2,}|△{2,}|[×✕]{2,}|＿{2,}|_{2,}"#

func giriPromptBlankCount(_ prompt: String) -> Int {
    guard let regex = try? NSRegularExpression(pattern: giriPromptBlankPattern) else { return 0 }
    return regex.numberOfMatches(in: prompt, range: NSRange(prompt.startIndex..., in: prompt))
}

/// 穴埋めのお題を回答で埋めた表示。お題の文と、回答で埋めた部分（isFill）に分ける。
/// 2か所以上の時は、回答を「／」で分けて順に入れる（足りない所は〇〇のまま）。
func giriFilledPromptSegments(prompt: String, answer: String) -> [(text: String, isFill: Bool)] {
    guard let regex = try? NSRegularExpression(pattern: giriPromptBlankPattern) else { return [(answer, true)] }
    let matches = regex.matches(in: prompt, range: NSRange(prompt.startIndex..., in: prompt))
    guard !matches.isEmpty else { return [(answer, true)] }
    let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = matches.count > 1
        ? trimmed.components(separatedBy: CharacterSet(charactersIn: "／/｜|")).map { $0.trimmingCharacters(in: .whitespaces) }
        : [trimmed]
    var segments: [(text: String, isFill: Bool)] = []
    var cursor = prompt.startIndex
    for (index, match) in matches.enumerated() {
        guard let range = Range(match.range, in: prompt) else { continue }
        if cursor < range.lowerBound { segments.append((String(prompt[cursor..<range.lowerBound]), false)) }
        if index < parts.count && !parts[index].isEmpty { segments.append((parts[index], true)) }
        else { segments.append((String(prompt[range]), false)) }
        cursor = range.upperBound
    }
    if cursor < prompt.endIndex { segments.append((String(prompt[cursor...]), false)) }
    return segments
}

/// 穴埋めの回答を、お題に入れた1つの文にする（共有・一覧の表示用）。
func giriFilledPromptText(prompt: String, answer: String) -> String {
    giriFilledPromptSegments(prompt: prompt, answer: answer).map { $0.text }.joined()
}

/// メモのように1行に1つ書いた回答案。先頭の「・」と、印（◎〇△×☆ や「3・」の点数）を分ける。
struct GiriAnswerLine: Equatable {
    var mark: String
    var text: String
}

func giriAnswerLines(_ text: String) -> [GiriAnswerLine] {
    text.components(separatedBy: .newlines).compactMap { raw in
        var line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        var mark = ""
        if let range = line.range(of: #"^([◎〇○◯△▲×✕☆★]|[0-9０-９]{1,2}(?=\s*[・･•:：]))"#, options: .regularExpression) {
            mark = String(line[range])
            line.removeSubrange(range)
        }
        line = line.replacingOccurrences(of: #"^\s*[・･•\-－]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        let normalized: String
        switch mark {
        case "○", "◯": normalized = "〇"
        case "✕": normalized = "×"
        case "▲": normalized = "△"
        default: normalized = giriHalfwidthDigits(mark)
        }
        return GiriAnswerLine(mark: normalized, text: line)
    }
}

/// メモを書き直した時に、前の回答案（採用・結果）をできるだけ残す：同じ文の案、次に同じ位置の案を引き継ぐ。
func giriReconcileAnswers(_ lines: [GiriAnswerLine], previous: [AnswerRecord]) -> [AnswerRecord] {
    var unused = previous
    var output: [AnswerRecord] = []
    for (index, line) in lines.enumerated() {
        if let match = unused.firstIndex(where: { $0.text == line.text }) {
            var record = unused.remove(at: match)
            record.mark = line.mark
            output.append(record)
        } else if previous.indices.contains(index), let match = unused.firstIndex(where: { $0.id == previous[index].id }),
                  !lines.contains(where: { $0.text == previous[index].text }) {
            var record = unused.remove(at: match)
            record.text = line.text
            record.mark = line.mark
            output.append(record)
        } else {
            output.append(AnswerRecord(text: line.text, mark: line.mark))
        }
    }
    return output
}

/// 回答案をメモの形に戻す（印があれば「△・」、なければ「・」）。
func giriAnswerMemo(_ records: [AnswerRecord]) -> String {
    records.map { $0.mark + "・" + $0.text }.joined(separator: "\n")
}

// MARK: - 企画・応募（0.13.1）

extension EventFormat {
    /// 「企画」を選べる形式（生大喜利・スプシ系）。
    var allowsProject: Bool { self == .live || self == .hybrid }
}

extension GiriEvent {
    /// 企画として扱う（生大喜利・スプシ系の通常の会で「企画」を選んだ時）。
    var isProjectEvent: Bool { isProject && meetingType == .casual && eventFormat.allowsProject }
    /// 会の種類の表示（通常・大会・企画）。
    var meetingTitle: String { isProjectEvent ? "企画" : meetingType.title }
    /// 一覧の絞り込み・共有で使う会の種類の値（"casual"・"tournament"・"project"）。
    var meetingFilterKey: String { isProjectEvent ? "project" : meetingType.rawValue }
}


// MARK: - 0.14 お題/回答の画面から回答を足す

/// お題/回答の画面から、移動せずに自分の回答（案）を足す。1行に1つで、先頭の印（◎・〇・△・× や点数）も読む。
/// 足す回答がなければ nil。今までの回答・印・提出の記録はそのまま残す。
func giriNoteAddingAnswers(_ note: ThoughtNote, text: String, now: Date = Date()) -> ThoughtNote? {
    let lines = giriAnswerLines(text)
    guard !lines.isEmpty else { return nil }
    var updated = note
    var answers = updated.effectiveAnswerRecords
    for line in lines { answers.append(AnswerRecord(text: line.text, mark: line.mark)) }
    updated.answerRecords = answers
    updated.usesAnswerRecords = true
    updated.isOthersAnswer = false
    updated.answerer = ""
    updated.answers = answers.map(\.text)
    updated.updatedAt = now
    return updated
}

/// お題/回答の日程を畳んだ時に出す締切：投稿中は投稿の締切、それ以外は投票の締切。
func giriThoughtCurrentDeadline(_ round: EventRound, now: Date = Date()) -> Date? {
    if round.isSubmissionOpen(now) { return round.submissionEnd }
    if let end = round.votingEnd, round.votingRequired { return end }
    return round.submissionEnd
}

// MARK: - 0.14 大会の段階（周ごとの結果・自動の結果・次の段階）

/// 次の段階の名前。予選の後は本戦、本戦の後は生大喜利なら決勝・ネット大喜利なら準々決勝。
func giriEditorNextStage(_ name: String, live: Bool = true) -> String {
    if let range = name.range(of: #"[0-9]+(?=回戦$)"#, options: .regularExpression), let number = Int(name[range]) {
        return name.replacingCharacters(in: range, with: String(number + 1))
    }
    if name.contains("準々決勝") { return "準決勝" }
    if name.contains("準決勝") { return "決勝" }
    if name.contains("決勝") { return "追加日程" }
    if name.contains("予選") { return "本戦" }
    if name.contains("本戦") || name.contains("本選") { return live ? "決勝" : "準々決勝" }
    return "予選"
}

/// 段階の結果の選び方：決勝は優勝・準優勝など、それ以外は通過・敗退。
func giriStageOutcomeChoices(_ kind: StageKind) -> [TournamentOutcome] {
    kind == .final ? [.unrecorded, .champion, .runnerUp, .placed, .other] : [.unrecorded, .advanced, .eliminated, .other]
}

/// 全角の英数字だけ半角にする（カタカナは半角にしない。「ブロック」「タイマン」をそのまま比べるため）。
func giriHalfwidthAlphanumerics(_ text: String) -> String {
    String(text.unicodeScalars.map { scalar -> Character in
        let value = scalar.value
        let isWide = (0xFF10...0xFF19).contains(value) || (0xFF21...0xFF3A).contains(value) || (0xFF41...0xFF5A).contains(value)
        guard isWide, let narrow = Unicode.Scalar(value - 0xFEE0) else { return Character(scalar) }
        return Character(narrow)
    })
}

/// 「横並び5人」なら対戦相手は4人、タイマンは1人。分からなければ nil。
func giriOpponentSlotCount(_ lineup: String) -> Int? {
    if lineup.contains("タイマン") { return 1 }
    let value = giriHalfwidthAlphanumerics(lineup)
    if value.contains("横並び"), let range = value.range(of: #"[0-9]+"#, options: .regularExpression), let count = Int(value[range]), count >= 2 {
        return count - 1
    }
    return nil
}

/// 対戦相手の候補：その会に来ている人（参加者・チーム）だけ。自分と、入力済みの人は除く。
func giriOpponentCandidates(attendees: [String], chosen: [String], isSelf: (String) -> Bool) -> [String] {
    let taken = Set(chosen.map(playerSearchKey))
    var seen = Set<String>()
    return attendees.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && !isSelf($0) && !taken.contains(playerSearchKey($0)) && seen.insert(playerSearchKey($0)).inserted }
}

/// 1周分の点の合計（お題ごとの点を足す）。何も入っていなければ nil。
func giriLapTotal(_ lap: StageLap) -> Double? {
    let values = lap.points.compactMap { $0 }
    return values.isEmpty ? nil : values.reduce(0, +)
}

/// その周のブロックの中の順位：ほかの人の点が入っていれば、自分より点の高い人の数 + 1。
func giriLapPlacement(_ lap: StageLap) -> Int? {
    guard let total = giriLapTotal(lap) else { return lap.placement }
    let scored = lap.others.compactMap(\.points)
    guard !scored.isEmpty else { return lap.placement }
    return scored.filter { $0 > total }.count + 1
}

/// 段階の点の合計（周ごとの合計を足す）。周の記録がない以前の版は段階の得点。
func giriStageTotal(_ stage: ResultStage) -> Double? {
    guard !stage.laps.isEmpty else { return stage.points }
    let totals = stage.laps.compactMap(giriLapTotal)
    return totals.isEmpty ? nil : totals.reduce(0, +)
}

/// 周の記録をそろえる：周の数・お題の数（お題ごとの投票の時）に合わせて欄を足し、余りは空のものだけ消す。
func giriNormalizedLaps(_ stage: ResultStage, lapCount: Int) -> [StageLap] {
    var laps = stage.laps
    if laps.isEmpty {
        // 以前の版の1周分（組・対戦相手・得点）を1周目にする。
        var first = StageLap()
        first.group = stage.group
        first.opponents = stage.opponents
        if let points = stage.points { first.points = [points] }
        first.voterCount = stage.voterCount
        first.placement = stage.placement
        laps = [first]
    }
    let count = max(1, lapCount)
    while laps.count < count { laps.append(StageLap()) }
    while laps.count > count, let last = laps.last, last.group.isEmpty && last.opponents.isEmpty && last.points.allSatisfy({ $0 == nil }) && last.others.isEmpty {
        laps.removeLast()
    }
    let slots = stage.votesPerPrompt ? max(1, stage.promptCount ?? 1) : 1
    for index in laps.indices {
        while laps[index].points.count < slots { laps[index].points.append(nil) }
        if laps[index].points.count > slots {
            // 全お題で1回の投票にした時は、入っている点を1つにまとめる。
            let total = giriLapTotal(laps[index])
            laps[index].points = slots == 1 ? [total] : Array(laps[index].points.prefix(slots))
        }
    }
    return laps
}

/// 周の記録から段階の組・対戦相手・得点を合わせる（プレイヤー詳細の「同じ組になった」・以前の版の表示用）。
func giriStageSyncedFromLaps(_ stage: ResultStage) -> ResultStage {
    guard !stage.laps.isEmpty else { return stage }
    var value = stage
    var seen = Set<String>()
    value.opponents = stage.laps.flatMap(\.opponents).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && seen.insert(playerSearchKey($0)).inserted }
    let groups = stage.laps.map { $0.group.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    value.group = groups.joined(separator: "・")
    value.points = giriStageTotal(stage)
    if stage.laps.count == 1 {
        value.voterCount = stage.laps[0].voterCount
        if let placement = giriLapPlacement(stage.laps[0]) { value.placement = placement }
    }
    return value
}

/// 自動で入れる段階の結果：決勝以外で通過ラインがあり、全部の周の点が入っていれば通過・敗退。
func giriSuggestedStageOutcome(_ stage: ResultStage) -> TournamentOutcome? {
    guard stage.roundId == nil, stage.effectiveKind != .final, let border = stage.borderScore, !stage.laps.isEmpty,
          stage.laps.allSatisfy({ giriLapTotal($0) != nil }), let total = giriStageTotal(stage) else { return nil }
    return total >= border ? .advanced : .eliminated
}

/// トーナメント表に沿って、通過した回戦の次の回戦を足す（まだない時だけ）。相手は1人に決まる時だけ入れる。
func giriNextBracketStage(_ stages: [ResultStage], bracket: [String], isSelf: (String) -> Bool) -> ResultStage? {
    let names = giriBracketStageNames(bracket.count)
    let wide = stages.filter { $0.roundId == nil }
    guard let last = wide.last, last.passed == true, let index = names.firstIndex(of: last.name), index + 1 < names.count,
          !wide.contains(where: { $0.name == names[index + 1] }) else { return nil }
    var next = ResultStage()
    next.name = names[index + 1]
    next.lineup = last.lineup.isEmpty ? "タイマン" : last.lineup
    next.judging = last.judging
    next.promptCount = last.promptCount
    let candidates = giriBracketOpponents(bracket, round: index + 2, isSelf: isSelf)
    if candidates.count == 1 { next.opponents = candidates }
    return next
}

/// ブロック表の1つのブロック。
struct GiriBlockEntry: Equatable {
    var name: String
    var members: [String]
}

/// ブロック表の見出し（「Aブロック」「1組」「第2組」「ブロックB」など）。
func giriBlockHeading(_ text: String) -> String? {
    let value = giriHalfwidthAlphanumerics(text).trimmingCharacters(in: .whitespacesAndNewlines)
    let patterns = [#"^第?[A-Za-z0-9一二三四五六七八九十]{1,3}\s*(?:ブロック|組|グループ|卓)$"#, #"^(?:ブロック|グループ|組)\s*[A-Za-z0-9]{1,3}$"#]
    return patterns.contains { value.range(of: $0, options: .regularExpression) != nil } ? value : nil
}

/// 読み取ったブロック表を、見出しごとの名前に分ける。名前はその見出しの下（近い列）の行。
func giriBlockTable(_ lines: [GiriOCRLine]) -> [GiriBlockEntry] {
    let headings = lines.filter { giriBlockHeading($0.text) != nil }
    guard !headings.isEmpty else { return [] }
    var blocks = headings.map { GiriBlockEntry(name: giriBlockHeading($0.text) ?? $0.text, members: []) }
    for line in lines.sorted(by: { $0.midY < $1.midY }) where giriBlockHeading(line.text) == nil {
        let name = giriBracketCleanName(line.text)
        guard !name.isEmpty else { continue }
        // 上にある見出しのうち、列が近いもの（横に並んだ表）→ いちばん近い上の見出し。
        let above = headings.enumerated().filter { $0.element.midY < line.midY }
        guard let owner = above.min(by: { first, second in
            let a = abs(first.element.midX - line.midX) * 3 + (line.midY - first.element.midY)
            let b = abs(second.element.midX - line.midX) * 3 + (line.midY - second.element.midY)
            return a < b
        }) else { continue }
        if !blocks[owner.offset].members.contains(where: { playerSearchKey($0) == playerSearchKey(name) }) {
            blocks[owner.offset].members.append(name)
        }
    }
    return blocks.filter { !$0.members.isEmpty }
}

/// 名前のフリガナの候補（ひらがな）。漢字の読みは端末の辞書によるので、確認して直せるようにする。
/// 日本語の文字がない名前（英字だけなど）は空にする。
func giriFuriganaCandidate(_ name: String) -> String {
    let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.range(of: #"[\p{Han}\p{Hiragana}\p{Katakana}]"#, options: .regularExpression) != nil else { return "" }
    var output = ""
    let range = CFRange(location: 0, length: (text as NSString).length)
    let tokenizer = CFStringTokenizerCreate(nil, text as CFString, range, kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja_JP") as CFLocale)
    var type = CFStringTokenizerAdvanceToNextToken(tokenizer)
    while !type.isEmpty {
        let tokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
        let token = (text as NSString).substring(with: NSRange(location: tokenRange.location, length: tokenRange.length))
        if token.range(of: #"\p{Han}"#, options: .regularExpression) != nil,
           let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
            output += latin.applyingTransform(.latinToHiragana, reverse: false) ?? token
        } else {
            output += token.applyingTransform(.hiraganaToKatakana, reverse: true) ?? token
        }
        type = CFStringTokenizerAdvanceToNextToken(tokenizer)
    }
    return output.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
}
