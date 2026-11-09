import Foundation

// JSON keys and enum raw values deliberately match the shipping Flutter document.

enum EventKind: String, Codable, CaseIterable, Identifiable {
    case live, online
    var id: String { rawValue }
    var title: String {
        switch self {
        case .live: return "生大喜利"
        case .online: return "ネット大喜利"
        }
    }
    var label: String { title }
    var displayName: String { title }
}

enum MeetingType: String, Codable, CaseIterable, Identifiable {
    case tournament, casual
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tournament: return "大会"
        case .casual: return "通常"
        }
    }
    var label: String { title }
    var displayName: String { title }
}

enum EventStatus: String, Codable, CaseIterable, Identifiable {
    case planned, attended, canceled
    var id: String { rawValue }
    var title: String {
        switch self {
        case .planned: return "参加予定"
        case .attended: return "参加済"
        case .canceled: return "キャンセル"
        }
    }
    var label: String { title }
    var displayName: String { title }
}

enum NoteKind: String, Codable, CaseIterable, Identifiable {
    case answers, prompts, free
    var id: String { rawValue }
    var title: String {
        switch self {
        case .answers: return "回答"
        case .prompts: return "お題"
        case .free: return "自由"
        }
    }
    var label: String { title }
    var displayName: String { title }
}

enum TournamentFormat: String, Codable, CaseIterable, Identifiable {
    case individual, pair, team
    var id: String { rawValue }
    var title: String {
        switch self {
        case .individual: return "個人戦"
        case .pair: return "タッグ"
        case .team: return "チーム戦"
        }
    }
    var label: String { title }
    var displayName: String { title }
}

enum TournamentOutcome: String, Codable, CaseIterable, Identifiable {
    case unrecorded, champion, runnerUp, placed, eliminated, advanced, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .unrecorded: return "未記録"
        case .champion: return "優勝"
        case .runnerUp: return "準優勝"
        case .placed: return "入賞"
        case .eliminated: return "敗退"
        case .advanced: return "通過"
        case .other: return "その他"
        }
    }
    var label: String { title }
    var displayName: String { title }
}

/// 段階の種類。大会ごとに段階の数が違っても「どこまで進んだか」を比べられるよう、
/// 予選 → 本戦 → 準々決勝 → 準決勝 → 決勝 の順に並べる（その他は順番に数えない）。
enum StageKind: String, CaseIterable, Identifiable {
    case qualifier, main, quarterfinal, semifinal, final, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .qualifier: return "予選"
        case .main: return "本戦"
        case .quarterfinal: return "準々決勝"
        case .semifinal: return "準決勝"
        case .final: return "決勝"
        case .other: return "その他"
        }
    }
    /// 進んだ深さ（その他は nil）。
    var depth: Int? {
        switch self {
        case .qualifier: return 0
        case .main: return 1
        case .quarterfinal: return 2
        case .semifinal: return 3
        case .final: return 4
        case .other: return nil
        }
    }
}

enum SiteRecurrence: String, Codable, CaseIterable, Identifiable {
    case irregular, weekly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .irregular: return "不定期"
        case .weekly: return "毎週"
        }
    }
    var label: String { title }
    var displayName: String { title }
}

struct EventRound: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = "投稿・投票"
    var submissionStart: Date? = nil
    var submissionEnd: Date? = nil
    var votingStart: Date? = nil
    var votingEnd: Date? = nil
    var stageId: String? = nil
    var promptNumber: Int = 1
    var block: String = ""
    var submissionEnabled: Bool = true
    var votingRequired: Bool = true
    /// 0.13：同じ段階で並列に出るお題の数（1回目に「全N回」を入れた時だけ）。ない時は並列の回なし。
    var promptCount: Int? = nil
}

extension EventRound {
    private enum CodingKeys: String, CodingKey {
        case id, name, submissionStart, submissionEnd, votingStart, votingEnd, stageId, promptNumber, block, submissionEnabled, votingRequired, promptCount
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(String.self, forKey: .id)

        name = try c.decode(String.self, forKey: .name)

        submissionStart = try c.giriDate(forKey: .submissionStart, required: false, calendarOnly: false)

        submissionEnd = try c.giriDate(forKey: .submissionEnd, required: false, calendarOnly: false)

        votingStart = try c.giriDate(forKey: .votingStart, required: false, calendarOnly: false)

        votingEnd = try c.giriDate(forKey: .votingEnd, required: false, calendarOnly: false)

        stageId = try c.decodeIfPresent(String.self, forKey: .stageId)

        promptNumber = try c.decodeIfPresent(Int.self, forKey: .promptNumber) ?? 1

        block = try c.decodeIfPresent(String.self, forKey: .block) ?? ""

        submissionEnabled = try c.decodeIfPresent(Bool.self, forKey: .submissionEnabled) ?? true

        votingRequired = try c.decodeIfPresent(Bool.self, forKey: .votingRequired) ?? true

        promptCount = try c.decodeIfPresent(Int.self, forKey: .promptCount)

        try validate()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(id, forKey: .id)

        try c.encode(name, forKey: .name)

        try c.encode(submissionStart.map(GiriDates.timestamp), forKey: .submissionStart)

        try c.encode(submissionEnd.map(GiriDates.timestamp), forKey: .submissionEnd)

        try c.encode(votingStart.map(GiriDates.timestamp), forKey: .votingStart)

        try c.encode(votingEnd.map(GiriDates.timestamp), forKey: .votingEnd)

        try c.encode(stageId, forKey: .stageId)

        try c.encode(promptNumber, forKey: .promptNumber)

        try c.encode(block, forKey: .block)

        try c.encode(submissionEnabled, forKey: .submissionEnabled)

        try c.encode(votingRequired, forKey: .votingRequired)

        try c.encode(promptCount, forKey: .promptCount)

    }
}

struct ResultStage: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    var outcome: TournamentOutcome = .unrecorded
    var placement: Int? = nil
    var memo: String = ""
    var roundId: String? = nil
    var stageId: String? = nil
    var teamPlacement: Int? = nil
    var individualPlacement: Int? = nil
    var voterCount: Int? = nil
    var points: Double? = nil
    var maxPointsPerVoter: Int = 1
    // 0.8：段階の形式と結果の補足。旧データにはないため空・未入力で読む。
    /// 組・ブロック（例：Bブロック）
    var group: String = ""
    /// 横並び○人／タイマン／総当たりなど
    var lineup: String = ""
    /// 挙手・拍手・加点・印象・超加点・ネット得票など
    var judging: String = ""
    /// 同じ組の人・対戦相手
    var opponents: [String] = []
    /// 何人中（任意）
    var entrantCount: Int? = nil
    /// 通過枠（任意）
    var advanceCount: Int? = nil
    /// ネット大喜利の競い方（段階全体の記録だけで使う）
    var scoring: StageScoring? = nil
    /// 通過ライン（1人あたりの点の合計など、競い方の単位）
    var borderScore: Double? = nil
    /// 0.10：段階の種類（予選・本戦・準々決勝・準決勝・決勝・その他）。nil は段階名から判断する。
    /// 知らない値（新しい版の値）は読み込みを止めずに nil として扱う。
    var kind: StageKind? = nil
    /// 0.14：1周あたりのお題数（生大喜利）。分からない時は nil。
    var promptCount: Int? = nil
    /// 0.14：印象審査でお題が2つ以上の時、お題ごとに投票するか（false は全お題で1回の投票）。
    var votesPerPrompt: Bool = false
    /// 0.14：同じ段階を違うブロックで何周か行う時の、周ごとの結果（1周だけの時も入れる）。
    /// 空は以前の版の記録で、group・opponents・points をそのまま使う。
    var laps: [StageLap] = []
    /// 0.14：一緒に通過した人（任意）。
    var advancedWith: [String] = []
}

/// 0.14：段階の1周分（ブロック・対戦相手・お題ごとの点・ほかの人の点）。
struct StageLap: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var group: String = ""
    var opponents: [String] = []
    /// お題ごとの点（全お題で1回の投票の時は1つ）。未入力は nil。
    var points: [Double?] = []
    var voterCount: Int? = nil
    /// その周のブロックの中の順位（ほかの人の点があれば自動で出す）。
    var placement: Int? = nil
    var others: [StageOtherScore] = []
}

/// 0.14：同じブロックのほかの人の点（任意）。
struct StageOtherScore: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    var points: Double? = nil
}

extension StageLap {
    private enum CodingKeys: String, CodingKey { case id, group, opponents, points, voterCount, placement, others }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? ""
        opponents = try c.decodeIfPresent([String].self, forKey: .opponents) ?? []
        points = try c.decodeIfPresent([Double?].self, forKey: .points) ?? []
        voterCount = try c.decodeIfPresent(Int.self, forKey: .voterCount)
        placement = try c.decodeIfPresent(Int.self, forKey: .placement)
        others = try c.decodeIfPresent([StageOtherScore].self, forKey: .others) ?? []
    }
}

extension StageOtherScore {
    private enum CodingKeys: String, CodingKey { case id, name, points }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        points = try c.decodeIfPresent(Double.self, forKey: .points)
    }
}

extension ResultStage {
    private enum CodingKeys: String, CodingKey {
        case id, name, outcome, placement, memo, roundId, stageId, teamPlacement, individualPlacement, voterCount, points, maxPointsPerVoter
        case group, lineup, judging, opponents, entrantCount, advanceCount, scoring, borderScore, kind
        case promptCount, votesPerPrompt, laps, advancedWith
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(String.self, forKey: .id)

        name = try c.decode(String.self, forKey: .name)

        outcome = try c.decodeIfPresent(TournamentOutcome.self, forKey: .outcome) ?? .unrecorded

        placement = try c.decodeIfPresent(Int.self, forKey: .placement)

        memo = try c.decodeIfPresent(String.self, forKey: .memo) ?? ""

        roundId = try c.decodeIfPresent(String.self, forKey: .roundId)

        stageId = try c.decodeIfPresent(String.self, forKey: .stageId)

        teamPlacement = try c.decodeIfPresent(Int.self, forKey: .teamPlacement)

        individualPlacement = try c.decodeIfPresent(Int.self, forKey: .individualPlacement)

        voterCount = try c.decodeIfPresent(Int.self, forKey: .voterCount)

        points = try c.decodeIfPresent(Double.self, forKey: .points)

        maxPointsPerVoter = try c.decodeIfPresent(Int.self, forKey: .maxPointsPerVoter) ?? 1

        group = try c.decodeIfPresent(String.self, forKey: .group) ?? ""
        lineup = try c.decodeIfPresent(String.self, forKey: .lineup) ?? ""
        judging = try c.decodeIfPresent(String.self, forKey: .judging) ?? ""
        opponents = try c.decodeIfPresent([String].self, forKey: .opponents) ?? []
        entrantCount = try c.decodeIfPresent(Int.self, forKey: .entrantCount)
        advanceCount = try c.decodeIfPresent(Int.self, forKey: .advanceCount)
        scoring = try c.decodeIfPresent(StageScoring.self, forKey: .scoring)
        borderScore = try c.decodeIfPresent(Double.self, forKey: .borderScore)
        kind = (try c.decodeIfPresent(String.self, forKey: .kind)).flatMap(StageKind.init(rawValue:))
        promptCount = try c.decodeIfPresent(Int.self, forKey: .promptCount)
        votesPerPrompt = try c.decodeIfPresent(Bool.self, forKey: .votesPerPrompt) ?? false
        laps = try c.decodeIfPresent([StageLap].self, forKey: .laps) ?? []
        advancedWith = try c.decodeIfPresent([String].self, forKey: .advancedWith) ?? []

        try validate()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(id, forKey: .id)

        try c.encode(name, forKey: .name)

        try c.encode(outcome, forKey: .outcome)

        try c.encode(placement, forKey: .placement)

        try c.encode(memo, forKey: .memo)

        try c.encode(roundId, forKey: .roundId)

        try c.encode(stageId, forKey: .stageId)

        try c.encode(teamPlacement, forKey: .teamPlacement)

        try c.encode(individualPlacement, forKey: .individualPlacement)

        try c.encode(voterCount, forKey: .voterCount)

        try c.encode(points, forKey: .points)

        try c.encode(maxPointsPerVoter, forKey: .maxPointsPerVoter)

        try c.encode(group, forKey: .group)
        try c.encode(lineup, forKey: .lineup)
        try c.encode(judging, forKey: .judging)
        try c.encode(opponents, forKey: .opponents)
        try c.encode(entrantCount, forKey: .entrantCount)
        try c.encode(advanceCount, forKey: .advanceCount)
        try c.encode(scoring, forKey: .scoring)
        try c.encode(borderScore, forKey: .borderScore)
        try c.encode(kind?.rawValue, forKey: .kind)
        // 0.14 の項目は入れた時だけ書く（以前の版のJSONの形を保つ）。
        try c.encodeIfPresent(promptCount, forKey: .promptCount)
        if votesPerPrompt { try c.encode(votesPerPrompt, forKey: .votesPerPrompt) }
        if !laps.isEmpty { try c.encode(laps, forKey: .laps) }
        if !advancedWith.isEmpty { try c.encode(advancedWith, forKey: .advancedWith) }
    }
}

struct TournamentResult: Codable, Equatable {
    var format: TournamentFormat = .individual
    var outcome: TournamentOutcome = .unrecorded
    var teamName: String = ""
    var members: [String] = []
    var stages: [ResultStage] = []
    var memo: String = ""
    /// 最終結果の「ベスト○」（outcome は placed）。旧データにはない。
    var bestOf: Int? = nil
    /// 0.10：最終結果「決勝進出」（outcome は placed）。順位は任意で placement、決勝の人数は finalEntrants。
    var finalist: Bool = false
    var finalEntrants: Int? = nil
}

extension TournamentResult {
    private enum CodingKeys: String, CodingKey {
        case format, outcome, teamName, members, stages, memo, bestOf, finalist, finalEntrants
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        format = try c.decodeIfPresent(TournamentFormat.self, forKey: .format) ?? .individual

        outcome = try c.decodeIfPresent(TournamentOutcome.self, forKey: .outcome) ?? .unrecorded

        teamName = try c.decodeIfPresent(String.self, forKey: .teamName) ?? ""

        members = try c.decodeIfPresent([String].self, forKey: .members) ?? []

        stages = try c.decodeIfPresent([ResultStage].self, forKey: .stages) ?? []

        memo = try c.decodeIfPresent(String.self, forKey: .memo) ?? ""

        bestOf = try c.decodeIfPresent(Int.self, forKey: .bestOf)
        finalist = try c.decodeIfPresent(Bool.self, forKey: .finalist) ?? false
        finalEntrants = try c.decodeIfPresent(Int.self, forKey: .finalEntrants)

        try validate()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(format, forKey: .format)

        try c.encode(outcome, forKey: .outcome)

        try c.encode(teamName, forKey: .teamName)

        try c.encode(members, forKey: .members)

        try c.encode(stages, forKey: .stages)

        try c.encode(memo, forKey: .memo)

        try c.encode(bestOf, forKey: .bestOf)
        try c.encode(finalist, forKey: .finalist)
        try c.encode(finalEntrants, forKey: .finalEntrants)
    }
}

struct GiriEvent: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var title: String = ""
    var kind: EventKind = .live
    var meetingType: MeetingType = .casual
    var createdAt: Date = Date()
    var organizer: String = ""
    var venue: String = ""
    var participants: [String] = []
    var eventDate: Date? = nil
    var startsAt: Date? = nil
    var endsAt: Date? = nil
    var submissionStart: Date? = nil
    var submissionEnd: Date? = nil
    var votingStart: Date? = nil
    var votingEnd: Date? = nil
    var siteUrl: String = ""
    var memo: String = ""
    var resultText: String = ""
    var placement: Int? = nil
    var status: EventStatus = .planned
    var rounds: [EventRound] = []
    var tournamentResult: TournamentResult? = nil
    var onlineSiteId: String? = nil
    var cycleKey: String? = nil
    var affiliation: String = ""
    var block: String = ""
    var teams: [GiriTeam] = []
    var teamSize: Int? = nil
    var myTeamId: String? = nil
    var tournamentFormat: TournamentFormat = .individual
    var venueId: String? = nil
    var standings: [TournamentStanding] = []
    var isParticipating: Bool = true
    var format: EventFormat? = nil
    var isInterested: Bool = false
    var promptedResultKeys: [String] = []
    var cycleResult: String = ""
    var cyclePlacement: Int? = nil
    var nextAffiliation: String = ""
    var siteScheduleCustomized: Bool = false
    var siteSeason: String = ""
    var siteSeasonID: String? = nil
    var siteRuleRevisionID: String? = nil
    var siteSeasonStart: Date? = nil
    var siteSeasonEnd: Date? = nil
    var legacyInferredSeasonEnd: Date? = nil
    var siteCycleNumber: Int? = nil
    var sitePeriodKind: SitePeriodKind = .regular
    var leagueMovement: LeagueMovement = .unchanged
    var siteQualification: SiteQualification = .none
    var nextLeagueEffectiveDate: Date? = nil
    /// 参加費（円）。旧データにはないため未入力（nil）として読み込む。
    var entryFee: Int? = nil
    /// ツボ上げ・感想用に会が指定するハッシュタグ（「#」なしで保存）。旧データは空。
    var hashtag: String = ""
    /// 通常サイトの回を「今回は見送る」にした（参加回数・通知・結果入力の対象外）。
    var siteSkipped: Bool = false
    /// 0.10：チーム戦で、当日にチームを分ける（参加者を先に入れ、後からチームへ振り分ける）。
    var impromptuTeams: Bool = false
    /// 0.10：大会の対戦形式がトーナメント（1対1の勝ち抜き）。個人戦では参加者の並びをトーナメント表の順に使う。
    var knockout: Bool = false
    /// 0.10：大会の審査方法（段階ごとの審査方法が空の時に使う）。
    var judging: String = ""
    /// 0.10（生大喜利）：共催・MC・審査員。主催者と同じく、プレイヤーとは別に記録する。MC・審査員は大会だけ。
    var coOrganizers: [String] = []
    var mcs: [String] = []
    var judges: [String] = []
    /// 0.10（生大喜利）：主催が団体（個人ではない）。団体名はプレイヤー一覧に入れない。
    var organizerIsGroup: Bool = false
    /// 0.10（生大喜利）：自分の立場（プレイヤー／主催・MCなど／観覧／リザーバー）。プレイヤー以外は戦績・結果の案内の対象外。
    /// 知らない値（新しい版の値）はプレイヤーとして読む。
    var selfRole: GiriSelfRole = .player
    /// 0.10（生大喜利）：会場の部屋（会議室名・部屋番号）。会場名とは分けて保存する。
    var venueRoom: String = ""
    /// 0.10（生大喜利）：開場時刻。
    var opensAt: Date? = nil
    /// 0.12（生大喜利）：リザーバー（当日キャンセルに備えて観覧する人）がいる会か、とその名前。
    /// 自分がリザーバーにいる時は、自分の立場をリザーバーにする。
    var hasReserves: Bool = false
    var reserves: [String] = []
    /// 0.13.1（生大喜利・スプシ系）：通常・大会とは別の「企画」。会の種類の保存値は通常（casual）のままにして、以前の版・Android 版でも読めるようにする。
    var isProject: Bool = false
    /// 0.13.1：応募の開始と締切（任意）。応募開始の前に通知する（LiveStair のチケット予定と同じく、日時だけ入れる）。
    var entryStart: Date? = nil
    var entryEnd: Date? = nil
    /// 0.14：同じ日の会の中で行う大会の時、元の会のID（集計の参加回数は会として1回）。
    var parentEventId: String? = nil
    /// 0.19：組手（主役に対してたくさんのメンバーが対戦する企画）。会の種類の保存値は通常（casual）のまま。
    var isKumite: Bool = false
    /// 組手の主役（タッグなどは複数）。
    var kumiteMains: [String] = []
    /// 組手の対戦ごとの記録（主役から見た勝敗）。
    var kumiteBouts: [KumiteBout] = []
    /// 0.10（生大喜利）：シリーズ名（「#5」などの回数を除いた名前）。空なら会の名前から判断する。
    var series: String = ""
}

/// その会での自分の立場。主催・共催・MCの名前は主催者・共催・MCの欄に入れ、ここでは「出たかどうか」を表す。
enum GiriSelfRole: String, CaseIterable, Identifiable {
    case player, staff, spectator, reserve
    var id: String { rawValue }
    /// 通常の会は主催がMCを兼ねることが多いので「主催」、大会は「主催・MC・審査員」。リザーバーは大会だけ。
    static func choices(tournament: Bool) -> [GiriSelfRole] { tournament ? allCases : [.player, .staff, .spectator] }
    func title(tournament: Bool) -> String {
        switch self {
        case .player: return "プレイヤー"
        case .staff: return tournament ? "主催・MC・審査員（出ない）" : "主催（出ない）"
        case .spectator: return "観覧"
        case .reserve: return "リザーバー（当日キャンセルに備えて観覧）"
        }
    }
    /// 一覧・詳細の短い表示。
    func shortTitle(tournament: Bool) -> String {
        switch self {
        case .player: return "プレイヤー"
        case .staff: return tournament ? "運営" : "主催"
        case .spectator: return "観覧"
        case .reserve: return "リザーバー"
        }
    }
}

extension GiriEvent {
    private enum CodingKeys: String, CodingKey {
        case id, title, kind, meetingType, createdAt, organizer, venue, participants, eventDate, startsAt, endsAt, submissionStart, submissionEnd, votingStart, votingEnd, siteUrl, memo, resultText, placement, status, rounds, tournamentResult, onlineSiteId, cycleKey, affiliation, block, teams, teamSize, myTeamId, tournamentFormat, venueId, standings, isParticipating, format, isInterested, promptedResultKeys, cycleResult, cyclePlacement, nextAffiliation, siteScheduleCustomized, siteSeason, siteSeasonID, siteRuleRevisionID, siteSeasonStart, siteSeasonEnd, legacyInferredSeasonEnd, siteCycleNumber, sitePeriodKind, leagueMovement, siteQualification, nextLeagueEffectiveDate, entryFee, hashtag, siteSkipped, impromptuTeams, knockout, judging, coOrganizers, mcs, judges, organizerIsGroup, selfRole, venueRoom, opensAt, series, hasReserves, reserves, isProject, entryStart, entryEnd, parentEventId, isKumite, kumiteMains, kumiteBouts
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(String.self, forKey: .id)

        title = try c.decode(String.self, forKey: .title)

        kind = try c.decode(EventKind.self, forKey: .kind)

        meetingType = try c.decode(MeetingType.self, forKey: .meetingType)

        createdAt = try c.giriRequiredDate(forKey: .createdAt)

        organizer = try c.decodeIfPresent(String.self, forKey: .organizer) ?? ""

        venue = try c.decodeIfPresent(String.self, forKey: .venue) ?? ""

        participants = try c.decodeIfPresent([String].self, forKey: .participants) ?? []

        eventDate = try c.giriDate(forKey: .eventDate, required: false, calendarOnly: true)

        startsAt = try c.giriDate(forKey: .startsAt, required: false, calendarOnly: false)

        endsAt = try c.giriDate(forKey: .endsAt, required: false, calendarOnly: false)

        submissionStart = try c.giriDate(forKey: .submissionStart, required: false, calendarOnly: false)

        submissionEnd = try c.giriDate(forKey: .submissionEnd, required: false, calendarOnly: false)

        votingStart = try c.giriDate(forKey: .votingStart, required: false, calendarOnly: false)

        votingEnd = try c.giriDate(forKey: .votingEnd, required: false, calendarOnly: false)

        siteUrl = try c.decodeIfPresent(String.self, forKey: .siteUrl) ?? ""

        memo = try c.decodeIfPresent(String.self, forKey: .memo) ?? ""

        resultText = try c.decodeIfPresent(String.self, forKey: .resultText) ?? ""

        placement = try c.decodeIfPresent(Int.self, forKey: .placement)

        status = try c.decodeIfPresent(EventStatus.self, forKey: .status) ?? .planned

        rounds = try c.decodeIfPresent([EventRound].self, forKey: .rounds) ?? []

        tournamentResult = try c.decodeIfPresent(TournamentResult.self, forKey: .tournamentResult)

        onlineSiteId = try c.decodeIfPresent(String.self, forKey: .onlineSiteId)

        cycleKey = try c.decodeIfPresent(String.self, forKey: .cycleKey)

        affiliation = try c.decodeIfPresent(String.self, forKey: .affiliation) ?? ""

        block = try c.decodeIfPresent(String.self, forKey: .block) ?? ""

        teams = try c.decodeIfPresent([GiriTeam].self, forKey: .teams) ?? []

        teamSize = try c.decodeIfPresent(Int.self, forKey: .teamSize)

        myTeamId = try c.decodeIfPresent(String.self, forKey: .myTeamId)

        tournamentFormat = try c.decodeIfPresent(TournamentFormat.self, forKey: .tournamentFormat) ?? .individual

        venueId = try c.decodeIfPresent(String.self, forKey: .venueId)

        standings = try c.decodeIfPresent([TournamentStanding].self, forKey: .standings) ?? []

        isParticipating = try c.decodeIfPresent(Bool.self, forKey: .isParticipating) ?? true

        if !c.contains(.tournamentFormat) { tournamentFormat = tournamentResult?.format ?? .individual } else if try c.decodeNil(forKey: .tournamentFormat) { tournamentFormat = tournamentResult?.format ?? .individual }

        format = try c.decodeIfPresent(EventFormat.self, forKey: .format)
        isInterested = try c.decodeIfPresent(Bool.self, forKey: .isInterested) ?? false
        promptedResultKeys = try c.decodeIfPresent([String].self, forKey: .promptedResultKeys) ?? []
        cycleResult = try c.decodeIfPresent(String.self, forKey: .cycleResult) ?? ""
        cyclePlacement = try c.decodeIfPresent(Int.self, forKey: .cyclePlacement)
        nextAffiliation = try c.decodeIfPresent(String.self, forKey: .nextAffiliation) ?? ""
        siteScheduleCustomized = try c.decodeIfPresent(Bool.self, forKey: .siteScheduleCustomized) ?? false
        siteSeason = try c.decodeIfPresent(String.self, forKey: .siteSeason) ?? ""
        siteSeasonID = try c.decodeIfPresent(String.self, forKey: .siteSeasonID)
        siteRuleRevisionID = try c.decodeIfPresent(String.self, forKey: .siteRuleRevisionID)
        siteSeasonStart = try c.giriDate(forKey: .siteSeasonStart, required: false, calendarOnly: false)
        siteSeasonEnd = try c.giriDate(forKey: .siteSeasonEnd, required: false, calendarOnly: false)
        legacyInferredSeasonEnd = try c.giriDate(forKey: .legacyInferredSeasonEnd, required: false, calendarOnly: false)
        if siteSeasonID == nil && siteRuleRevisionID == nil, let oldEnd = siteSeasonEnd {
            legacyInferredSeasonEnd = legacyInferredSeasonEnd ?? oldEnd
            siteSeasonEnd = nil
        }
        siteCycleNumber = try c.decodeIfPresent(Int.self, forKey: .siteCycleNumber)
        sitePeriodKind = try c.decodeIfPresent(SitePeriodKind.self, forKey: .sitePeriodKind) ?? .regular
        leagueMovement = try c.decodeIfPresent(LeagueMovement.self, forKey: .leagueMovement) ?? .unchanged
        siteQualification = try c.decodeIfPresent(SiteQualification.self, forKey: .siteQualification) ?? .none
        nextLeagueEffectiveDate = try c.giriDate(forKey: .nextLeagueEffectiveDate, required: false, calendarOnly: false)
        entryFee = try c.decodeIfPresent(Int.self, forKey: .entryFee)
        hashtag = try c.decodeIfPresent(String.self, forKey: .hashtag) ?? ""
        siteSkipped = try c.decodeIfPresent(Bool.self, forKey: .siteSkipped) ?? false
        impromptuTeams = try c.decodeIfPresent(Bool.self, forKey: .impromptuTeams) ?? false
        knockout = try c.decodeIfPresent(Bool.self, forKey: .knockout) ?? false
        judging = try c.decodeIfPresent(String.self, forKey: .judging) ?? ""
        coOrganizers = try c.decodeIfPresent([String].self, forKey: .coOrganizers) ?? []
        mcs = try c.decodeIfPresent([String].self, forKey: .mcs) ?? []
        judges = try c.decodeIfPresent([String].self, forKey: .judges) ?? []
        organizerIsGroup = try c.decodeIfPresent(Bool.self, forKey: .organizerIsGroup) ?? false
        selfRole = (try c.decodeIfPresent(String.self, forKey: .selfRole)).flatMap(GiriSelfRole.init(rawValue:)) ?? .player
        venueRoom = try c.decodeIfPresent(String.self, forKey: .venueRoom) ?? ""
        opensAt = try c.giriDate(forKey: .opensAt, required: false, calendarOnly: false)
        series = try c.decodeIfPresent(String.self, forKey: .series) ?? ""
        hasReserves = try c.decodeIfPresent(Bool.self, forKey: .hasReserves) ?? false
        reserves = try c.decodeIfPresent([String].self, forKey: .reserves) ?? []
        isProject = try c.decodeIfPresent(Bool.self, forKey: .isProject) ?? false
        entryStart = try c.giriDate(forKey: .entryStart, required: false, calendarOnly: false)
        entryEnd = try c.giriDate(forKey: .entryEnd, required: false, calendarOnly: false)
        parentEventId = try c.decodeIfPresent(String.self, forKey: .parentEventId)
        isKumite = try c.decodeIfPresent(Bool.self, forKey: .isKumite) ?? false
        kumiteMains = try c.decodeIfPresent([String].self, forKey: .kumiteMains) ?? []
        kumiteBouts = try c.decodeIfPresent([KumiteBout].self, forKey: .kumiteBouts) ?? []

        try validate()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(id, forKey: .id)

        try c.encode(title, forKey: .title)

        try c.encode(kind, forKey: .kind)

        try c.encode(meetingType, forKey: .meetingType)

        try c.encode(GiriDates.timestamp(createdAt), forKey: .createdAt)

        try c.encode(organizer, forKey: .organizer)

        try c.encode(venue, forKey: .venue)

        try c.encode(participants, forKey: .participants)

        try c.encode(eventDate.map(GiriDates.calendarString), forKey: .eventDate)

        try c.encode(startsAt.map(GiriDates.timestamp), forKey: .startsAt)

        try c.encode(endsAt.map(GiriDates.timestamp), forKey: .endsAt)

        try c.encode(submissionStart.map(GiriDates.timestamp), forKey: .submissionStart)

        try c.encode(submissionEnd.map(GiriDates.timestamp), forKey: .submissionEnd)

        try c.encode(votingStart.map(GiriDates.timestamp), forKey: .votingStart)

        try c.encode(votingEnd.map(GiriDates.timestamp), forKey: .votingEnd)

        try c.encode(siteUrl, forKey: .siteUrl)

        try c.encode(memo, forKey: .memo)

        try c.encode(resultText, forKey: .resultText)

        try c.encode(placement, forKey: .placement)

        try c.encode(status, forKey: .status)

        try c.encode(rounds, forKey: .rounds)

        try c.encode(tournamentResult, forKey: .tournamentResult)

        try c.encode(onlineSiteId, forKey: .onlineSiteId)

        try c.encode(cycleKey, forKey: .cycleKey)

        try c.encode(affiliation, forKey: .affiliation)

        try c.encode(block, forKey: .block)

        try c.encode(teams, forKey: .teams)

        try c.encode(teamSize, forKey: .teamSize)

        try c.encode(myTeamId, forKey: .myTeamId)

        try c.encode(tournamentFormat, forKey: .tournamentFormat)

        try c.encode(venueId, forKey: .venueId)

        try c.encode(standings, forKey: .standings)

        try c.encode(isParticipating, forKey: .isParticipating)

        try c.encode(format, forKey: .format)
        try c.encode(isInterested, forKey: .isInterested)
        try c.encode(promptedResultKeys, forKey: .promptedResultKeys)
        try c.encode(cycleResult, forKey: .cycleResult)
        try c.encode(cyclePlacement, forKey: .cyclePlacement)
        try c.encode(nextAffiliation, forKey: .nextAffiliation)
        try c.encode(siteScheduleCustomized, forKey: .siteScheduleCustomized)
        try c.encode(siteSeason, forKey: .siteSeason)
        try c.encode(siteSeasonID, forKey: .siteSeasonID)
        try c.encode(siteRuleRevisionID, forKey: .siteRuleRevisionID)
        try c.encode(siteSeasonStart.map(GiriDates.timestamp), forKey: .siteSeasonStart)
        try c.encode(siteSeasonEnd.map(GiriDates.timestamp), forKey: .siteSeasonEnd)
        try c.encode(legacyInferredSeasonEnd.map(GiriDates.timestamp), forKey: .legacyInferredSeasonEnd)
        try c.encode(siteCycleNumber, forKey: .siteCycleNumber)
        try c.encode(sitePeriodKind, forKey: .sitePeriodKind)
        try c.encode(leagueMovement, forKey: .leagueMovement)
        try c.encode(siteQualification, forKey: .siteQualification)
        try c.encode(nextLeagueEffectiveDate.map(GiriDates.timestamp), forKey: .nextLeagueEffectiveDate)
        try c.encode(entryFee, forKey: .entryFee)
        try c.encode(hashtag, forKey: .hashtag)
        try c.encode(siteSkipped, forKey: .siteSkipped)
        try c.encode(impromptuTeams, forKey: .impromptuTeams)
        try c.encode(knockout, forKey: .knockout)
        try c.encode(judging, forKey: .judging)
        try c.encode(coOrganizers, forKey: .coOrganizers)
        try c.encode(mcs, forKey: .mcs)
        try c.encode(judges, forKey: .judges)
        try c.encode(organizerIsGroup, forKey: .organizerIsGroup)
        try c.encode(selfRole.rawValue, forKey: .selfRole)
        try c.encode(venueRoom, forKey: .venueRoom)
        try c.encode(opensAt.map(GiriDates.timestamp), forKey: .opensAt)
        try c.encode(series, forKey: .series)
        try c.encode(hasReserves, forKey: .hasReserves)
        try c.encode(reserves, forKey: .reserves)
        try c.encode(isProject, forKey: .isProject)
        try c.encode(entryStart.map(GiriDates.timestamp), forKey: .entryStart)
        try c.encode(entryEnd.map(GiriDates.timestamp), forKey: .entryEnd)
        try c.encodeIfPresent(parentEventId, forKey: .parentEventId)
        // 組手の項目は入れた時だけ書く（以前の版のJSONの形を保つ）。
        if isKumite { try c.encode(isKumite, forKey: .isKumite) }
        if !kumiteMains.isEmpty { try c.encode(kumiteMains, forKey: .kumiteMains) }
        if !kumiteBouts.isEmpty { try c.encode(kumiteBouts, forKey: .kumiteBouts) }

    }
}

struct ThoughtNote: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var title: String = ""
    var kind: NoteKind = .answers
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var body: String = ""
    var eventId: String? = nil
    var roundId: String? = nil
    var prompt: String = ""
    var answers: [String] = []
    var used: Bool = false
    var imageDataBase64: String = ""
    var answerRecords: [AnswerRecord] = []
    var isOthersAnswer: Bool = false
    var answerer: String = ""
    var answerCategory: String? = nil
    var usesAnswerRecords: Bool = false
    // 0.8：お題の作題者と、会に紐付けない記録の形式・大会の段階。旧データにはない。
    var promptAuthor: String = ""
    /// 作題者の名前に「（改）」が付くお題
    var promptRevised: Bool = false
    var format: EventFormat? = nil
    /// 生大喜利などの大会の段階（TournamentResult.stages の段階全体の記録ID）
    var resultStageId: String? = nil
    /// お題・回答についてのメモ（ウケた・スベったなど）。旧データの本文 body とは分ける。
    var memo: String = ""
    /// 0.13：お題の種類（plain 通常・image 画像・fill 穴埋め）。空は以前の版（画像があれば画像お題）。
    var promptStyle: String = ""
    /// 0.16：このお題に参加したか（false は参加していないブロックのお題などを考えるため）。nil は以前の版で、参加として読む。
    var participates: Bool? = nil
}

extension ThoughtNote {
    private enum CodingKeys: String, CodingKey {
        case id, title, kind, createdAt, updatedAt, body, eventId, roundId, prompt, answers, used, imageDataBase64, answerRecords, isOthersAnswer, answerer, usesAnswerRecords, answerCategory
        case promptAuthor, promptRevised, format, resultStageId, memo, promptStyle, participates
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(String.self, forKey: .id)

        title = try c.decode(String.self, forKey: .title)

        kind = try c.decode(NoteKind.self, forKey: .kind)

        createdAt = try c.giriRequiredDate(forKey: .createdAt)

        updatedAt = try c.giriRequiredDate(forKey: .updatedAt)

        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""

        eventId = try c.decodeIfPresent(String.self, forKey: .eventId)

        roundId = try c.decodeIfPresent(String.self, forKey: .roundId)

        prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? ""

        answers = try c.decodeIfPresent([String].self, forKey: .answers) ?? []

        used = try c.decodeIfPresent(Bool.self, forKey: .used) ?? false

        imageDataBase64 = try c.decodeIfPresent(String.self, forKey: .imageDataBase64) ?? ""

        answerRecords = try c.decodeIfPresent([AnswerRecord].self, forKey: .answerRecords) ?? []
        isOthersAnswer = try c.decodeIfPresent(Bool.self, forKey: .isOthersAnswer) ?? false
        answerer = try c.decodeIfPresent(String.self, forKey: .answerer) ?? ""
        usesAnswerRecords = try c.decodeIfPresent(Bool.self, forKey: .usesAnswerRecords) ?? false
        answerCategory = try c.decodeIfPresent(String.self, forKey: .answerCategory)
        promptAuthor = try c.decodeIfPresent(String.self, forKey: .promptAuthor) ?? ""
        promptRevised = try c.decodeIfPresent(Bool.self, forKey: .promptRevised) ?? false
        format = try c.decodeIfPresent(EventFormat.self, forKey: .format)
        resultStageId = try c.decodeIfPresent(String.self, forKey: .resultStageId)
        memo = try c.decodeIfPresent(String.self, forKey: .memo) ?? ""
        promptStyle = try c.decodeIfPresent(String.self, forKey: .promptStyle) ?? ""
        participates = try c.decodeIfPresent(Bool.self, forKey: .participates)

        try validate()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(id, forKey: .id)

        try c.encode(title, forKey: .title)

        try c.encode(kind, forKey: .kind)

        try c.encode(GiriDates.timestamp(createdAt), forKey: .createdAt)

        try c.encode(GiriDates.timestamp(updatedAt), forKey: .updatedAt)

        try c.encode(body, forKey: .body)

        try c.encode(eventId, forKey: .eventId)

        try c.encode(roundId, forKey: .roundId)

        try c.encode(prompt, forKey: .prompt)

        try c.encode(answers, forKey: .answers)

        try c.encode(used, forKey: .used)

        try c.encode(imageDataBase64, forKey: .imageDataBase64)

        try c.encode(answerRecords, forKey: .answerRecords)
        try c.encode(isOthersAnswer, forKey: .isOthersAnswer)
        try c.encode(answerer, forKey: .answerer)
        try c.encode(usesAnswerRecords, forKey: .usesAnswerRecords)
        try c.encode(answerCategory, forKey: .answerCategory)
        try c.encode(promptAuthor, forKey: .promptAuthor)
        try c.encode(promptRevised, forKey: .promptRevised)
        try c.encode(format, forKey: .format)
        try c.encode(resultStageId, forKey: .resultStageId)
        try c.encode(memo, forKey: .memo)
        try c.encode(promptStyle, forKey: .promptStyle)
        try c.encodeIfPresent(participates, forKey: .participates)
    }
}

struct GiriPlayer: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    var furigana: String = ""
    var region: String = ""
    var iconDataBase64: String = ""
    var twitterUrl: String = ""
    var memo: String = ""
    /// 0.12：都道府県（地域は「関東」などの地方。以前の版の自由入力の地域はそのまま残す）。
    var prefecture: String = ""
    /// 0.12：別名義。mergesAliases が true なら、プレイヤー一覧・集計でこの人にまとめて表示する。
    var aliases: [String] = []
    var mergesAliases: Bool = true
}

extension GiriPlayer {
    private enum CodingKeys: String, CodingKey {
        case id, name, furigana, region, iconDataBase64, twitterUrl, memo, prefecture, aliases, mergesAliases
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(String.self, forKey: .id)

        name = try c.decode(String.self, forKey: .name)

        furigana = try c.decodeIfPresent(String.self, forKey: .furigana) ?? ""

        region = try c.decodeIfPresent(String.self, forKey: .region) ?? ""

        iconDataBase64 = try c.decodeIfPresent(String.self, forKey: .iconDataBase64) ?? ""

        twitterUrl = try c.decodeIfPresent(String.self, forKey: .twitterUrl) ?? ""

        memo = try c.decodeIfPresent(String.self, forKey: .memo) ?? ""

        prefecture = try c.decodeIfPresent(String.self, forKey: .prefecture) ?? ""

        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []

        mergesAliases = try c.decodeIfPresent(Bool.self, forKey: .mergesAliases) ?? true

        try validate()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(id, forKey: .id)

        try c.encode(name, forKey: .name)

        try c.encode(furigana, forKey: .furigana)

        try c.encode(region, forKey: .region)

        try c.encode(iconDataBase64, forKey: .iconDataBase64)

        try c.encode(twitterUrl, forKey: .twitterUrl)

        try c.encode(memo, forKey: .memo)

        try c.encode(prefecture, forKey: .prefecture)

        try c.encode(aliases, forKey: .aliases)

        try c.encode(mergesAliases, forKey: .mergesAliases)

    }
}

struct AppPreferences: Codable, Equatable {
    var theme: String = "light"
    var notificationsEnabled: Bool = false
    var reminderMinutes: Int = 60
    var reminderHour: Int = 9
    var reminderMinute: Int = 0
    var selfName: String = ""
    var onboardingCompleted: Bool = false
    var listCurrentMode: Bool = false
    var submissionDays: Int = 7
    var votingDays: Int = 7
    var submissionStartDayOffset: Int = -1
    var submissionStartHour: Int = 22
    var submissionStartMinute: Int = 0
    var playerIconMode: String = "auto"
    var hasShownInitialResultPrompt: Bool = false
    var formatOrder: [EventFormat] = EventFormat.allCases
    /// デフォルト設定で使わないことにした形式。記録は残し、タブと選択肢にだけ出さない。
    var hiddenFormats: [EventFormat] = []
    /// 自分の別名義（複数の名前で出ている場合）。参加者・回答者に出てきたら自分として扱う。
    var selfAliases: [String] = []
    /// 0.12：自分の別名義をプレイヤー一覧で自分にまとめて表示する（以前の版はそれぞれ表示）。
    var mergesSelfAliases: Bool = false
    /// 0.19：募集期間の通知（LiveStair のチケット通知と同じく、開始前と開始時を分ける）。
    /// 開始前の通知。以前の版は開始前に通知していたので true。
    var entryNotifyBefore: Bool = true
    /// 開始前の通知を何分前にするか。nil は以前の版と同じく「開始・締切の前」の分数。
    var entryLeadMinutes: Int? = nil
    /// 募集開始の時刻ちょうどの通知。
    var entryNotifyAtStart: Bool = false
}

extension AppPreferences {
    private enum CodingKeys: String, CodingKey {
        case theme, notificationsEnabled, reminderMinutes, reminderHour, reminderMinute, selfName, onboardingCompleted, listCurrentMode, submissionDays, votingDays, submissionStartDayOffset, submissionStartHour, submissionStartMinute, playerIconMode, hasShownInitialResultPrompt, formatOrder, hiddenFormats, selfAliases, mergesSelfAliases, entryNotifyBefore, entryLeadMinutes, entryNotifyAtStart
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? "light"

        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false

        reminderMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderMinutes) ?? 60

        reminderHour = try c.decodeIfPresent(Int.self, forKey: .reminderHour) ?? 9

        reminderMinute = try c.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? 0

        selfName = try c.decodeIfPresent(String.self, forKey: .selfName) ?? ""

        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false

        listCurrentMode = try c.decodeIfPresent(Bool.self, forKey: .listCurrentMode) ?? false

        submissionDays = try c.decodeIfPresent(Int.self, forKey: .submissionDays) ?? 7

        votingDays = try c.decodeIfPresent(Int.self, forKey: .votingDays) ?? 7

        submissionStartDayOffset = try c.decodeIfPresent(Int.self, forKey: .submissionStartDayOffset) ?? -1

        submissionStartHour = try c.decodeIfPresent(Int.self, forKey: .submissionStartHour) ?? 22

        submissionStartMinute = try c.decodeIfPresent(Int.self, forKey: .submissionStartMinute) ?? 0

        playerIconMode = try c.decodeIfPresent(String.self, forKey: .playerIconMode) ?? "auto"

        hasShownInitialResultPrompt = try c.decodeIfPresent(Bool.self, forKey: .hasShownInitialResultPrompt) ?? false
        formatOrder = try c.decodeIfPresent([EventFormat].self, forKey: .formatOrder) ?? EventFormat.allCases
        hiddenFormats = try c.decodeIfPresent([EventFormat].self, forKey: .hiddenFormats) ?? []
        selfAliases = try c.decodeIfPresent([String].self, forKey: .selfAliases) ?? []
        mergesSelfAliases = try c.decodeIfPresent(Bool.self, forKey: .mergesSelfAliases) ?? false
        entryNotifyBefore = try c.decodeIfPresent(Bool.self, forKey: .entryNotifyBefore) ?? true
        entryLeadMinutes = try c.decodeIfPresent(Int.self, forKey: .entryLeadMinutes)
        entryNotifyAtStart = try c.decodeIfPresent(Bool.self, forKey: .entryNotifyAtStart) ?? false

        try validate()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(theme, forKey: .theme)

        try c.encode(notificationsEnabled, forKey: .notificationsEnabled)

        try c.encode(reminderMinutes, forKey: .reminderMinutes)

        try c.encode(reminderHour, forKey: .reminderHour)

        try c.encode(reminderMinute, forKey: .reminderMinute)

        try c.encode(selfName, forKey: .selfName)

        try c.encode(onboardingCompleted, forKey: .onboardingCompleted)

        try c.encode(listCurrentMode, forKey: .listCurrentMode)

        try c.encode(submissionDays, forKey: .submissionDays)

        try c.encode(votingDays, forKey: .votingDays)

        try c.encode(submissionStartDayOffset, forKey: .submissionStartDayOffset)

        try c.encode(submissionStartHour, forKey: .submissionStartHour)

        try c.encode(submissionStartMinute, forKey: .submissionStartMinute)

        try c.encode(playerIconMode, forKey: .playerIconMode)

        try c.encode(hasShownInitialResultPrompt, forKey: .hasShownInitialResultPrompt)
        try c.encode(formatOrder, forKey: .formatOrder)
        try c.encode(hiddenFormats, forKey: .hiddenFormats)
        try c.encode(selfAliases, forKey: .selfAliases)
        try c.encode(mergesSelfAliases, forKey: .mergesSelfAliases)
        try c.encode(entryNotifyBefore, forKey: .entryNotifyBefore)
        try c.encodeIfPresent(entryLeadMinutes, forKey: .entryLeadMinutes)
        try c.encode(entryNotifyAtStart, forKey: .entryNotifyAtStart)

    }
}

struct OnlineSite: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    var url: String = ""
    var recurrence: SiteRecurrence = .irregular
    var weekday: Int = 1
    var startHour: Int = 22
    var startMinute: Int = 0
    var submissionDays: Int = 7
    var votingDays: Int = 7
    var affiliation: String = ""
    var block: String = ""
    var memo: String = ""
    var hasAffiliations: Bool = false
    var format: EventFormat = .onlineLong
    var cycleSettings: SiteCycleSettings? = nil
    var leagueChanges: [SiteLeagueChange] = []
    var leagueBaseline: String? = nil
    var ruleHistory: [SiteRuleRevision] = []
    /// しばらく参加しないサイト。一覧のカードを隠し、通知と回の自動作成を止める。
    var isPaused: Bool = false
}

extension OnlineSite {
    private enum CodingKeys: String, CodingKey {
        case id, name, url, recurrence, weekday, startHour, startMinute, submissionDays, votingDays, affiliation, block, memo, hasAffiliations, format, cycleSettings, leagueChanges, leagueBaseline, ruleHistory, isPaused
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(String.self, forKey: .id)

        name = try c.decode(String.self, forKey: .name)

        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""

        recurrence = try c.decodeIfPresent(SiteRecurrence.self, forKey: .recurrence) ?? .irregular

        weekday = try c.decodeIfPresent(Int.self, forKey: .weekday) ?? 1

        startHour = try c.decodeIfPresent(Int.self, forKey: .startHour) ?? 22

        startMinute = try c.decodeIfPresent(Int.self, forKey: .startMinute) ?? 0

        submissionDays = try c.decodeIfPresent(Int.self, forKey: .submissionDays) ?? 7

        votingDays = try c.decodeIfPresent(Int.self, forKey: .votingDays) ?? 7

        affiliation = try c.decodeIfPresent(String.self, forKey: .affiliation) ?? ""

        block = try c.decodeIfPresent(String.self, forKey: .block) ?? ""

        memo = try c.decodeIfPresent(String.self, forKey: .memo) ?? ""

        hasAffiliations = try c.decodeIfPresent(Bool.self, forKey: .hasAffiliations) ?? !affiliation.isEmpty
        format = try c.decodeIfPresent(EventFormat.self, forKey: .format) ?? .onlineLong
        cycleSettings = try c.decodeIfPresent(SiteCycleSettings.self, forKey: .cycleSettings)
        leagueChanges = try c.decodeIfPresent([SiteLeagueChange].self, forKey: .leagueChanges) ?? []
        leagueBaseline = try c.decodeIfPresent(String.self, forKey: .leagueBaseline)
        ruleHistory = try c.decodeIfPresent([SiteRuleRevision].self, forKey: .ruleHistory) ?? []
        isPaused = try c.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false

        try validate()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(id, forKey: .id)

        try c.encode(name, forKey: .name)

        try c.encode(url, forKey: .url)

        try c.encode(recurrence, forKey: .recurrence)

        try c.encode(weekday, forKey: .weekday)

        try c.encode(startHour, forKey: .startHour)

        try c.encode(startMinute, forKey: .startMinute)

        try c.encode(submissionDays, forKey: .submissionDays)

        try c.encode(votingDays, forKey: .votingDays)

        try c.encode(affiliation, forKey: .affiliation)

        try c.encode(block, forKey: .block)

        try c.encode(memo, forKey: .memo)

        try c.encode(hasAffiliations, forKey: .hasAffiliations)
        try c.encode(format, forKey: .format)
        try c.encode(cycleSettings, forKey: .cycleSettings)
        try c.encode(leagueChanges, forKey: .leagueChanges)
        try c.encode(leagueBaseline, forKey: .leagueBaseline)
        try c.encode(ruleHistory, forKey: .ruleHistory)
        try c.encode(isPaused, forKey: .isPaused)

    }
}

struct GiriTeam: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    var members: [String] = []
    var isMine: Bool = false
}

extension GiriTeam {
    private enum CodingKeys: String, CodingKey {
        case id, name, members, isMine
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(String.self, forKey: .id)

        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""

        members = try c.decodeIfPresent([String].self, forKey: .members) ?? []

        isMine = try c.decodeIfPresent(Bool.self, forKey: .isMine) ?? false

        try validate()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(id, forKey: .id)

        try c.encode(name, forKey: .name)

        try c.encode(members, forKey: .members)

        try c.encode(isMine, forKey: .isMine)

    }
}

struct TournamentStanding: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var placement: Int = 1
    var playerNames: [String] = []
    var teamName: String = ""
    var memo: String = ""
}

extension TournamentStanding {
    private enum CodingKeys: String, CodingKey {
        case id, placement, playerNames, teamName, memo
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(String.self, forKey: .id)

        placement = try c.decode(Int.self, forKey: .placement)

        playerNames = try c.decodeIfPresent([String].self, forKey: .playerNames) ?? []

        teamName = try c.decodeIfPresent(String.self, forKey: .teamName) ?? ""

        memo = try c.decodeIfPresent(String.self, forKey: .memo) ?? ""

        try validate()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(id, forKey: .id)

        try c.encode(placement, forKey: .placement)

        try c.encode(playerNames, forKey: .playerNames)

        try c.encode(teamName, forKey: .teamName)

        try c.encode(memo, forKey: .memo)

    }
}

struct GiriVenue: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    var prefecture: String = ""
    var mapUrl: String = ""
    var memo: String = ""
    var latitude: Double? = nil
    var longitude: Double? = nil
    var mapAddress: String = ""
    /// 0.14：フリガナ（並び・検索用、任意）。
    var furigana: String = ""
}

extension GiriVenue {
    private enum CodingKeys: String, CodingKey {
        case id, name, prefecture, mapUrl, memo, latitude, longitude, mapAddress, furigana
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(String.self, forKey: .id)

        name = try c.decode(String.self, forKey: .name)

        prefecture = try c.decodeIfPresent(String.self, forKey: .prefecture) ?? ""

        mapUrl = try c.decodeIfPresent(String.self, forKey: .mapUrl) ?? ""

        memo = try c.decodeIfPresent(String.self, forKey: .memo) ?? ""

        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)

        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)

        mapAddress = try c.decodeIfPresent(String.self, forKey: .mapAddress) ?? ""
        furigana = try c.decodeIfPresent(String.self, forKey: .furigana) ?? ""

        try validate()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(id, forKey: .id)

        try c.encode(name, forKey: .name)

        try c.encode(prefecture, forKey: .prefecture)

        try c.encode(mapUrl, forKey: .mapUrl)

        try c.encode(memo, forKey: .memo)

        try c.encode(latitude, forKey: .latitude)

        try c.encode(longitude, forKey: .longitude)

        try c.encode(mapAddress, forKey: .mapAddress)
        if !furigana.isEmpty { try c.encode(furigana, forKey: .furigana) }
    }
}

struct GiriDocument: Codable, Equatable {
    var schemaVersion: Int = 1
    var events: [GiriEvent] = []
    var notes: [ThoughtNote] = []
    var players: [GiriPlayer] = []
    var onlineSites: [OnlineSite] = []
    var venues: [GiriVenue] = []
    var preferences: AppPreferences = AppPreferences()
    var lastBackupAt: Date? = nil
    /// 0.10：主催する団体（プレイヤーとは別）。旧データにはないため空で読む。
    var groups: [GiriGroup] = []
    /// 0.19：最近削除した会（30日残して戻せる）。ない時はキーを書かない。
    var deletedEvents: [GiriDeletedEvent] = []
}

/// 0.19：削除した会と、その会に付いていたお題・回答（戻す時に付け直す）。
struct GiriDeletedEvent: Codable, Equatable, Identifiable {
    var event: GiriEvent
    var deletedAt: Date
    var noteLinks: [GiriDeletedNoteLink] = []
    var id: String { event.id }
}

struct GiriDeletedNoteLink: Codable, Equatable {
    var noteID: String
    var roundID: String?
}

extension GiriDeletedEvent {
    private enum CodingKeys: String, CodingKey { case event, deletedAt, noteLinks }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        event = try c.decode(GiriEvent.self, forKey: .event)
        deletedAt = try c.giriRequiredDate(forKey: .deletedAt)
        noteLinks = try c.decodeIfPresent([GiriDeletedNoteLink].self, forKey: .noteLinks) ?? []
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(event, forKey: .event)
        try c.encode(GiriDates.timestamp(deletedAt), forKey: .deletedAt)
        try c.encode(noteLinks, forKey: .noteLinks)
    }
}

/// 主催する団体。所属メンバーはプレイヤーの名前で持つ。
struct GiriGroup: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    var furigana: String = ""
    var members: [String] = []
    var url: String = ""
    var memo: String = ""
}

extension GiriGroup {
    private enum CodingKeys: String, CodingKey { case id, name, furigana, members, url, memo }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        furigana = try c.decodeIfPresent(String.self, forKey: .furigana) ?? ""
        members = try c.decodeIfPresent([String].self, forKey: .members) ?? []
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        memo = try c.decodeIfPresent(String.self, forKey: .memo) ?? ""
        try validate()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(furigana, forKey: .furigana)
        try c.encode(members, forKey: .members)
        try c.encode(url, forKey: .url)
        try c.encode(memo, forKey: .memo)
    }
}

extension GiriDocument {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, events, notes, players, onlineSites, venues, preferences, lastBackupAt, groups, deletedEvents
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)

        events = try c.decode([GiriEvent].self, forKey: .events)

        notes = try c.decode([ThoughtNote].self, forKey: .notes)

        players = try c.decodeIfPresent([GiriPlayer].self, forKey: .players) ?? []

        onlineSites = try c.decodeIfPresent([OnlineSite].self, forKey: .onlineSites) ?? []

        venues = try c.decodeIfPresent([GiriVenue].self, forKey: .venues) ?? []

        preferences = try c.decodeIfPresent(AppPreferences.self, forKey: .preferences) ?? AppPreferences()

        lastBackupAt = try c.giriDate(forKey: .lastBackupAt, required: false, calendarOnly: false)

        groups = try c.decodeIfPresent([GiriGroup].self, forKey: .groups) ?? []
        deletedEvents = try c.decodeIfPresent([GiriDeletedEvent].self, forKey: .deletedEvents) ?? []

        try validate()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(schemaVersion, forKey: .schemaVersion)

        try c.encode(events, forKey: .events)

        try c.encode(notes, forKey: .notes)

        try c.encode(players, forKey: .players)

        try c.encode(onlineSites, forKey: .onlineSites)

        try c.encode(venues, forKey: .venues)

        try c.encode(preferences, forKey: .preferences)

        try c.encode(lastBackupAt.map(GiriDates.timestamp), forKey: .lastBackupAt)

        try c.encode(groups, forKey: .groups)
        if !deletedEvents.isEmpty { try c.encode(deletedEvents, forKey: .deletedEvents) }
    }
}

// MARK: - Compatible JSON dates and validation

enum GiriDataError: LocalizedError {
    case invalid(String)
    case notLoaded
    var errorDescription: String? {
        switch self {
        case .invalid(let detail): return "保存データの形式を確認できません。\(detail)"
        case .notLoaded: return "保存データを読み込めなかったため、変更は保存していません。バックアップからの復元を確認してください。"
        }
    }
}

enum GiriDates {
    static func calendarString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func timestamp(_ date: Date) -> String {
        var seconds = floor(date.timeIntervalSince1970)
        var micros = Int(((date.timeIntervalSince1970 - seconds) * 1_000_000).rounded())
        if micros == 1_000_000 { seconds += 1; micros = 0 }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let whole = formatter.string(from: Date(timeIntervalSince1970: seconds))
        return String(whole.dropLast()) + String(format: ".%06dZ", micros)
    }
    static func parse(_ raw: String, calendarOnly: Bool = false) -> Date? {
        if calendarOnly {
            guard raw.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.isLenient = false
            guard let date = formatter.date(from: raw), formatter.string(from: date) == raw else { return nil }
            return date
        }
        // ISO8601DateFormatter may truncate to milliseconds on some OS builds.
        // Parse the fraction separately to retain Dart's six-digit microseconds.
        if let regex = try? NSRegularExpression(pattern: #"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\.(\d{1,6})(Z|[+-]\d{2}:?\d{2})?$"#),
           let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let wholeRange = Range(match.range(at: 1), in: raw), let fractionRange = Range(match.range(at: 2), in: raw),
           let fraction = Double("0." + String(raw[fractionRange])) {
            let zone = Range(match.range(at: 3), in: raw).map { String(raw[$0]) } ?? ""
            let whole = String(raw[wholeRange])
            let base: Date?
            if zone.isEmpty {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.timeZone = .current
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                formatter.isLenient = false
                base = formatter.date(from: whole)
            } else {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                base = formatter.date(from: whole + zone)
            }
            if let base { return base.addingTimeInterval(fraction) }
        }
        for fractional in [true, false] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
            if let date = formatter.date(from: raw) { return date }
        }
        // Older Dart files may contain local ISO strings without a zone.
        // Interpret them as local wall-clock time rather than appending Z.
        guard raw.range(of: #"^\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d{1,6})?)?)?$"#, options: .regularExpression) != nil else { return nil }
        for pattern in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = .current
            formatter.dateFormat = pattern
            formatter.isLenient = false
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}

extension KeyedDecodingContainer {
    func giriRequiredDate(forKey key: Key) throws -> Date {
        guard let date = try giriDate(forKey: key, required: true, calendarOnly: false) else { throw GiriDataError.invalid("日時がありません。") }
        return date
    }
    func giriDate(forKey key: Key, required: Bool, calendarOnly: Bool) throws -> Date? {
        guard let raw = try decodeIfPresent(String.self, forKey: key) else {
            if required { throw GiriDataError.invalid("\(key.stringValue) がありません。") }
            return nil
        }
        guard let date = GiriDates.parse(raw, calendarOnly: calendarOnly) else {
            throw GiriDataError.invalid("\(key.stringValue) の日時が不正です。")
        }
        return date
    }
}

enum GiriJSON {
    static func decode(_ data: Data) throws -> GiriDocument {
        try JSONDecoder().decode(GiriDocument.self, from: data)
    }
    static func encode(_ document: GiriDocument) throws -> Data {
        try document.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }
}

private func require(_ valid: Bool, _ message: String) throws {
    if !valid { throw GiriDataError.invalid(message) }
}
private func validID(_ id: String) throws { try require(!id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "IDが空です。") }
private func positive(_ value: Int?, _ name: String) throws { if let value { try require(value > 0, "\(name) は1以上にしてください。") } }
private func uniqueIDs<T: Identifiable>(_ values: [T]) throws where T.ID: Hashable {
    try require(Set(values.map(\.id)).count == values.count, "同じIDが重複しています。")
}

extension EventRound {
    func validate() throws { try validID(id); try require(promptNumber >= 1, "お題番号が不正です。") }
    var effectiveStageId: String { stageId ?? id }
    func isSubmissionOpen(_ now: Date) -> Bool {
        guard submissionEnabled, let start = submissionStart, let end = submissionEnd else { return false }
        return start <= now && now < end
    }
    func isVotingOpen(_ now: Date) -> Bool {
        guard votingRequired, let start = votingStart, let end = votingEnd else { return false }
        return start <= now && now < end
    }
}

extension ResultStage {
    func validate() throws {
        try validID(id)
        try positive(placement, "順位"); try positive(teamPlacement, "チーム順位"); try positive(individualPlacement, "個人順位")
        try require((voterCount ?? 0) >= 0 && maxPointsPerVoter >= 1, "投票人数・満点が不正です。")
        if let points { try require(points.isFinite && points >= 0, "得点が不正です。") }
        try positive(entrantCount, "人数"); try positive(advanceCount, "通過枠")
        if let borderScore { try require(borderScore.isFinite && borderScore >= 0, "通過ラインが不正です。") }
        try positive(promptCount, "お題数")
        try require(Set(laps.map(\.id)).count == laps.count, "周の記録のIDが重複しています。")
        for lap in laps {
            try positive(lap.placement, "順位")
            try require(lap.points.allSatisfy { $0.map { $0.isFinite && $0 >= 0 } ?? true } && (lap.voterCount ?? 0) >= 0, "周の得点が不正です。")
        }
    }
    /// 1人あたりの点（得点÷投票人数）。半喜利などの「187点 (1.18)」の括弧の値。
    var pointsPerVoter: Double? {
        guard let voterCount, voterCount > 0, let points, points.isFinite, points >= 0 else { return nil }
        return points / Double(voterCount)
    }
    var voteRate: Double? {
        guard let voterCount, voterCount > 0, maxPointsPerVoter > 0, let points, points.isFinite, points >= 0 else { return nil }
        return points * 100 / (Double(voterCount) * Double(maxPointsPerVoter))
    }
    var hasRecord: Bool {
        outcome != .unrecorded || placement != nil || teamPlacement != nil || individualPlacement != nil || voterCount != nil || points != nil || maxPointsPerVoter != 1 || !memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !group.isEmpty || !lineup.isEmpty || !judging.isEmpty || !opponents.isEmpty || entrantCount != nil || advanceCount != nil || scoring != nil || borderScore != nil || kind != nil ||
            promptCount != nil || !laps.isEmpty || !advancedWith.isEmpty
    }
}

extension TournamentResult {
    func validate() throws { try uniqueIDs(stages); try stages.forEach { try $0.validate() }; try positive(bestOf, "ベスト○"); try positive(finalEntrants, "決勝の人数") }
    var hasRecord: Bool { outcome != .unrecorded || stages.contains(where: \.hasRecord) || !memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

extension GiriEvent {
    func validate() throws {
        try validID(id)
        if let teamSize { try require(teamSize >= 2, "チームは2人以上にしてください。") }
        try uniqueIDs(rounds); try uniqueIDs(teams); try uniqueIDs(standings)
        try rounds.forEach { try $0.validate() }; try teams.forEach { try $0.validate() }; try standings.forEach { try $0.validate() }
        try tournamentResult?.validate()
        try positive(cyclePlacement, "順位")
        try positive(siteCycleNumber, "周期の回数")
        if let entryFee { try require(entryFee >= 0, "参加費が不正です。") }
        try require(Set(promptedResultKeys).count == promptedResultKeys.count, "結果案内のキーが重複しています。")
    }
    func isHostedBy(_ name: String) -> Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && playerSearchKey(organizer) == playerSearchKey(name) }
    var effectiveRounds: [EventRound] {
        if !rounds.isEmpty { return rounds }
        guard submissionStart != nil || submissionEnd != nil || votingStart != nil || votingEnd != nil else { return [] }
        var legacy = EventRound(id: "legacy")
        legacy.submissionStart = submissionStart; legacy.submissionEnd = submissionEnd
        legacy.votingStart = votingStart; legacy.votingEnd = votingEnd
        return [legacy]
    }
    var effectivePlacement: Int? {
        switch tournamentResult?.outcome {
        case .champion: return 1
        case .runnerUp: return 2
        case .eliminated, .advanced: return nil
        default: return placement.flatMap { $0 > 0 ? $0 : nil }
        }
    }
    var hasStructuredFinalResult: Bool {
        guard let result = tournamentResult else { return false }
        return result.outcome != .unrecorded && result.outcome != .advanced
    }
    var hasFinalResult: Bool { hasStructuredFinalResult || effectivePlacement != nil || (tournamentResult == nil && !resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    var hasRecordedResult: Bool { tournamentResult?.hasRecord == true || !resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (placement ?? 0) > 0 }
    func isSubmissionOpen(_ now: Date) -> Bool { eventFormat.hasOnlineRounds && isActualParticipant && effectiveRounds.contains { $0.isSubmissionOpen(now) } }
    func nextSubmissionEnd(_ now: Date) -> Date? {
        guard eventFormat.hasOnlineRounds && isActualParticipant else { return nil }
        return effectiveRounds.filter { $0.isSubmissionOpen(now) }.compactMap(\.submissionEnd).min()
    }
}

extension ThoughtNote {
    func validate() throws {
        try require(answerCategory == nil || ["long", "other"].contains(answerCategory ?? ""), "回答の分類が不正です。")
        try validID(id)
        try uniqueIDs(answerRecords)
        try answerRecords.forEach { try $0.validate() }
    }
}
extension GiriPlayer { func validate() throws { try validID(id); try require(!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "プレイヤー名がありません。") } }
extension GiriGroup { func validate() throws { try validID(id); try require(!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "団体名がありません。") } }
extension GiriTeam { func validate() throws { try validID(id) } }
extension TournamentStanding { func validate() throws { try validID(id); try positive(placement, "順位") } }
extension OnlineSite {
    func validate() throws {
        try cycleSettings?.validate()
        try uniqueIDs(leagueChanges)
        try uniqueIDs(ruleHistory)
        try ruleHistory.forEach { try $0.validate() }
        try validID(id)
        try require(!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (1...7).contains(weekday) && (0...23).contains(startHour) && (0...59).contains(startMinute) && submissionDays >= 1 && votingDays >= 1, "サイト設定が不正です。")
    }
}
extension GiriVenue {
    func validate() throws {
        try validID(id); try require(!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "会場名がありません。")
        try require((latitude == nil) == (longitude == nil), "緯度と経度は両方を指定してください。")
        if let latitude { try require(latitude.isFinite && (-90...90).contains(latitude), "緯度が不正です。") }
        if let longitude { try require(longitude.isFinite && (-180...180).contains(longitude), "経度が不正です。") }
    }
}
extension AppPreferences {
    func validate() throws {
        try require(["system", "light", "dark", "stair"].contains(theme) && (0...10080).contains(reminderMinutes) && (0...23).contains(reminderHour) && (0...59).contains(reminderMinute) && (1...365).contains(submissionDays) && (1...365).contains(votingDays) && (-365...365).contains(submissionStartDayOffset) && (0...23).contains(submissionStartHour) && (0...59).contains(submissionStartMinute) && ["auto", "show", "hide"].contains(playerIconMode), "設定値が不正です。")
    }
}
extension GiriDocument {
    func validate() throws {
        try require(schemaVersion == 1, "この保存形式には対応していません。")
        try uniqueIDs(events); try uniqueIDs(notes); try uniqueIDs(players); try uniqueIDs(onlineSites); try uniqueIDs(venues)
        try require(Set(players.map { playerSearchKey($0.name) }).count == players.count, "プレイヤー名が重複しています。")
        try uniqueIDs(groups); try groups.forEach { try $0.validate() }
        try require(Set(groups.map { playerSearchKey($0.name) }).count == groups.count, "団体名が重複しています。")
        try events.forEach { try $0.validate() }; try notes.forEach { try $0.validate() }; try players.forEach { try $0.validate() }; try onlineSites.forEach { try $0.validate() }; try venues.forEach { try $0.validate() }; try preferences.validate()
    }
}

func playerSearchKey(_ value: String) -> String {
    let half = Array("ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ".unicodeScalars)
    let full = Array("ヲァィゥェォャュョッーアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン".unicodeScalars)
    let unvoiced = Array("ウカキクケコサシスセソタチツテトハヒフヘホ".unicodeScalars)
    let voiced = Array("ヴガギグゲゴザジズゼゾダヂヅデドバビブベボ".unicodeScalars)
    let semi = Array("ハヒフヘホ".unicodeScalars), semiVoiced = Array("パピプペポ".unicodeScalars)
    var scalars: [UInt32] = []
    for scalar in value.unicodeScalars {
        var rune = scalar.value
        if (0xFF01...0xFF5E).contains(rune) { rune -= 0xFEE0 }
        if rune == 0x3000 { rune = 0x20 }
        if let index = half.firstIndex(where: { $0.value == rune }) { rune = full[index].value }
        let dakuten = [0xFF9E, 0x3099, 0x309B].contains(rune)
        let handakuten = [0xFF9F, 0x309A, 0x309C].contains(rune)
        if (dakuten || handakuten), var previous = scalars.last {
            if (0x3041...0x3096).contains(previous) { previous += 0x60 }
            let from = dakuten ? unvoiced : semi
            let to = dakuten ? voiced : semiVoiced
            if let index = from.firstIndex(where: { $0.value == previous }) { scalars[scalars.count - 1] = to[index].value; continue }
        }
        scalars.append(rune)
    }
    let hiragana = scalars.compactMap { UnicodeScalar((0x30A1...0x30F6).contains($0) ? $0 - 0x60 : $0) }
    return String(String.UnicodeScalarView(hiragana)).lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 0.19：組手の1つの対戦。主役側（空は主役全員）と相手側の人数は自由（1対1・2対2・3対3など）。
struct KumiteBout: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var mains: [String] = []
    var opponents: [String] = []
    /// 主役から見た勝敗（win・lose・draw、空は未入力）。
    var outcome: String = ""
    var memo: String = ""
}

extension KumiteBout {
    private enum CodingKeys: String, CodingKey { case id, mains, opponents, outcome, memo }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        mains = try c.decodeIfPresent([String].self, forKey: .mains) ?? []
        opponents = try c.decodeIfPresent([String].self, forKey: .opponents) ?? []
        outcome = try c.decodeIfPresent(String.self, forKey: .outcome) ?? ""
        memo = try c.decodeIfPresent(String.self, forKey: .memo) ?? ""
    }
}
