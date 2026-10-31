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
}

extension EventRound {
    private enum CodingKeys: String, CodingKey {
        case id, name, submissionStart, submissionEnd, votingStart, votingEnd, stageId, promptNumber, block, submissionEnabled, votingRequired
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
}

extension ResultStage {
    private enum CodingKeys: String, CodingKey {
        case id, name, outcome, placement, memo, roundId, stageId, teamPlacement, individualPlacement, voterCount, points, maxPointsPerVoter
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

    }
}

struct TournamentResult: Codable, Equatable {
    var format: TournamentFormat = .individual
    var outcome: TournamentOutcome = .unrecorded
    var teamName: String = ""
    var members: [String] = []
    var stages: [ResultStage] = []
    var memo: String = ""
}

extension TournamentResult {
    private enum CodingKeys: String, CodingKey {
        case format, outcome, teamName, members, stages, memo
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        format = try c.decodeIfPresent(TournamentFormat.self, forKey: .format) ?? .individual

        outcome = try c.decodeIfPresent(TournamentOutcome.self, forKey: .outcome) ?? .unrecorded

        teamName = try c.decodeIfPresent(String.self, forKey: .teamName) ?? ""

        members = try c.decodeIfPresent([String].self, forKey: .members) ?? []

        stages = try c.decodeIfPresent([ResultStage].self, forKey: .stages) ?? []

        memo = try c.decodeIfPresent(String.self, forKey: .memo) ?? ""

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
}

extension GiriEvent {
    private enum CodingKeys: String, CodingKey {
        case id, title, kind, meetingType, createdAt, organizer, venue, participants, eventDate, startsAt, endsAt, submissionStart, submissionEnd, votingStart, votingEnd, siteUrl, memo, resultText, placement, status, rounds, tournamentResult, onlineSiteId, cycleKey, affiliation, block, teams, teamSize, myTeamId, tournamentFormat, venueId, standings, isParticipating, format, isInterested, promptedResultKeys, cycleResult, cyclePlacement, nextAffiliation, siteScheduleCustomized, siteSeason, siteSeasonID, siteRuleRevisionID, siteSeasonStart, siteSeasonEnd, legacyInferredSeasonEnd, siteCycleNumber, sitePeriodKind, leagueMovement, siteQualification, nextLeagueEffectiveDate
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
}

extension ThoughtNote {
    private enum CodingKeys: String, CodingKey {
        case id, title, kind, createdAt, updatedAt, body, eventId, roundId, prompt, answers, used, imageDataBase64, answerRecords, isOthersAnswer, answerer, usesAnswerRecords, answerCategory
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
}

extension GiriPlayer {
    private enum CodingKeys: String, CodingKey {
        case id, name, furigana, region, iconDataBase64, twitterUrl, memo
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
}

extension AppPreferences {
    private enum CodingKeys: String, CodingKey {
        case theme, notificationsEnabled, reminderMinutes, reminderHour, reminderMinute, selfName, onboardingCompleted, listCurrentMode, submissionDays, votingDays, submissionStartDayOffset, submissionStartHour, submissionStartMinute, playerIconMode, hasShownInitialResultPrompt, formatOrder
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
}

extension OnlineSite {
    private enum CodingKeys: String, CodingKey {
        case id, name, url, recurrence, weekday, startHour, startMinute, submissionDays, votingDays, affiliation, block, memo, hasAffiliations, format, cycleSettings, leagueChanges, leagueBaseline, ruleHistory
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
}

extension GiriVenue {
    private enum CodingKeys: String, CodingKey {
        case id, name, prefecture, mapUrl, memo, latitude, longitude, mapAddress
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
}

extension GiriDocument {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, events, notes, players, onlineSites, venues, preferences, lastBackupAt
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
    }
    var voteRate: Double? {
        guard let voterCount, voterCount > 0, maxPointsPerVoter > 0, let points, points.isFinite, points >= 0 else { return nil }
        return points * 100 / (Double(voterCount) * Double(maxPointsPerVoter))
    }
    var hasRecord: Bool {
        outcome != .unrecorded || placement != nil || teamPlacement != nil || individualPlacement != nil || voterCount != nil || points != nil || maxPointsPerVoter != 1 || !memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension TournamentResult {
    func validate() throws { try uniqueIDs(stages); try stages.forEach { try $0.validate() } }
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
