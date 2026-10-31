import Foundation
import Combine

/// Shares the shipping Flutter file and publishes mutations only after durable
/// writes. A malformed document leaves saving disabled instead of becoming empty.
@MainActor
final class GiriStore: ObservableObject {
    @Published private(set) var document = GiriDocument()
    @Published var errorMessage: String?
    @Published private(set) var loaded = false
    let directory: URL
    private var originalData: Data?
    private var isWriting = false

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true)
        reload()
    }

    var events: [GiriEvent] { document.events }
    var notes: [ThoughtNote] { document.notes }
    var players: [GiriPlayer] { document.players }
    var venues: [GiriVenue] { document.venues }
    var onlineSites: [OnlineSite] { document.onlineSites }
    var preferences: AppPreferences { document.preferences }
    var lastBackupAt: Date? { document.lastBackupAt }
    var showPlayerIcons: Bool { preferences.playerIconMode == "show" || (preferences.playerIconMode == "auto" && players.contains { !$0.iconDataBase64.isEmpty }) }
    var fileURL: URL { directory.appendingPathComponent("giristair.json") }
    var migrationBackupURL: URL { directory.appendingPathComponent("giristair.flutter-v1.json") }

    func reload() {
        do {
            let primary = fileURL
            let backup = directory.appendingPathComponent("giristair.json.bak")
            let source: URL? = FileManager.default.fileExists(atPath: primary.path) ? primary : (FileManager.default.fileExists(atPath: backup.path) ? backup : nil)
            let data = try source.map { try Data(contentsOf: $0) }
            let restored = try data.map(GiriJSON.decode) ?? GiriDocument()
            document = restored
            originalData = data
            loaded = true
            errorMessage = nil
        } catch {
            loaded = false
            errorMessage = "保存データを読み込めませんでした。元のファイルは変更していません。\n\(error.localizedDescription)"
        }
    }

    func run(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }

    private func mutate(_ change: (inout GiriDocument) throws -> Void) throws {
        guard loaded else { throw GiriDataError.notLoaded }
        guard !isWriting else { throw GiriDataError.invalid("前の保存が完了していません。") }
        isWriting = true
        defer { isWriting = false }
        var next = document
        try change(&next)
        let data = try GiriJSON.encode(next)
        try persist(data)
        document = next
    }

    private func persist(_ data: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // This immutable copy is made before the first native write. It permits
        // restoring the exact Flutter bytes independently of rolling .bak files.
        if let originalData, !FileManager.default.fileExists(atPath: migrationBackupURL.path) {
            try originalData.write(to: migrationBackupURL, options: .atomic)
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let previous = try Data(contentsOf: fileURL)
            try previous.write(to: directory.appendingPathComponent("giristair.json.bak"), options: .atomic)
        }
        try data.write(to: fileURL, options: .atomic)
    }

    private func referencedNames(_ event: GiriEvent) -> [String] {
        [event.organizer] + event.participants + event.teams.flatMap(\.members) + (event.tournamentResult?.members ?? []) + event.standings.flatMap(\.playerNames)
    }

    var playerDirectory: [GiriPlayer] {
        var profiles = Dictionary(players.map { (playerSearchKey($0.name), $0) }, uniquingKeysWith: { first, _ in first })
        for name in [preferences.selfName] + events.flatMap(referencedNames) + notes.filter(\.isOthersAnswer).map(\.answerer) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = playerSearchKey(trimmed)
            if !trimmed.isEmpty && profiles[key] == nil { profiles[key] = GiriPlayer(id: "history:\(key)", name: trimmed) }
        }
        return profiles.values.sorted {
            let first = playerSearchKey($0.furigana.isEmpty ? $0.name : $0.furigana)
            let second = playerSearchKey($1.furigana.isEmpty ? $1.name : $1.furigana)
            return first == second ? $0.name < $1.name : first < second
        }
    }
    var venueDirectory: [GiriVenue] {
        var values = Dictionary(venues.map { (playerSearchKey($0.name), $0) }, uniquingKeysWith: { first, _ in first })
        for event in events {
            let name = event.venue.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = playerSearchKey(name)
            if !name.isEmpty && values[key] == nil { values[key] = GiriVenue(id: "history:\(key)", name: name) }
        }
        return values.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func playerByName(_ name: String) -> GiriPlayer? { playerDirectory.first { playerSearchKey($0.name) == playerSearchKey(name) } }
    func venueById(_ id: String?) -> GiriVenue? { venueDirectory.first { $0.id == id } }
    func onlineSiteById(_ id: String?) -> OnlineSite? { onlineSites.first { $0.id == id } }
    func newId() -> String { UUID().uuidString }

    func suggestPlayers(_ query: String, organizer: Bool = false) -> [GiriPlayer] {
        var counts: [String: Int] = [:]
        for event in events where event.status != .canceled {
            for name in organizer ? [event.organizer] : Array(Set(event.participants)) { counts[playerSearchKey(name), default: 0] += 1 }
        }
        let key = playerSearchKey(query)
        return playerDirectory.filter { key.isEmpty || playerSearchKey($0.name).contains(key) || playerSearchKey($0.furigana).contains(key) }.sorted {
            let first = counts[playerSearchKey($0.name), default: 0]
            let second = counts[playerSearchKey($1.name), default: 0]
            return first == second ? playerSearchKey($0.furigana.isEmpty ? $0.name : $0.furigana) < playerSearchKey($1.furigana.isEmpty ? $1.name : $1.furigana) : first > second
        }
    }

    func saveEvent(_ candidate: GiriEvent) throws {
        let event = Self.normalizedEvent(candidate)
        try event.validate()
        let names = referencedNames(event)
        try mutate { next in
            Self.upsert(event, into: &next.events)
            var known = Set(next.players.map { playerSearchKey($0.name) })
            for name in names {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && known.insert(playerSearchKey(trimmed)).inserted { next.players.append(GiriPlayer(name: trimmed)) }
            }
        }
    }
    func deleteEvent(_ id: String) throws {
        try mutate { next in
            next.events.removeAll { $0.id == id }
            for index in next.onlineSites.indices where next.onlineSites[index].leagueChanges.contains(where: { $0.sourceEventID == id }) {
                if next.onlineSites[index].leagueBaseline == nil { next.onlineSites[index].leagueBaseline = next.onlineSites[index].leagueChanges.sorted { $0.effectiveFrom < $1.effectiveFrom }.first?.fromLeague ?? next.onlineSites[index].affiliation }
                next.onlineSites[index].leagueChanges.removeAll { $0.sourceEventID == id }
                next.onlineSites[index].affiliation = siteLeague(next.onlineSites[index])
                let site = next.onlineSites[index]
                for eventIndex in next.events.indices where next.events[eventIndex].onlineSiteId == site.id && !next.events[eventIndex].isActualParticipant {
                    let date = next.events[eventIndex].participationStartDate ?? next.events[eventIndex].createdAt
                    next.events[eventIndex].affiliation = siteLeague(site, at: date)
                }
            }
            for index in next.notes.indices where next.notes[index].eventId == id { next.notes[index].eventId = nil; next.notes[index].roundId = nil }
        }
    }
    private static func normalizedEvent(_ candidate: GiriEvent) -> GiriEvent {
        var event = candidate
        if let format = event.format { event.kind = format == .live ? .live : .online }
        if event.isInterested { event.isParticipating = false }
        return event
    }
    private static func normalizedNote(_ candidate: ThoughtNote) -> ThoughtNote {
        var note = candidate
        if note.usesAnswerRecords || !note.answerRecords.isEmpty {
            note.usesAnswerRecords = true
            note.answers = note.answerRecords.map(\.text)
        }
        return note
    }
    func saveNote(_ candidate: ThoughtNote) throws {
        let note = Self.normalizedNote(candidate)
        try note.validate()
        try mutate { Self.upsert(note, into: &$0.notes) }
    }
    /// Own result and per-answer scores form one durable document mutation.
    func saveResult(event candidate: GiriEvent, notes candidates: [ThoughtNote]) throws {
        let event = Self.normalizedEvent(candidate)
        let notes = candidates.map(Self.normalizedNote)
        try event.validate()
        try notes.forEach { try $0.validate() }
        guard Set(notes.map(\.id)).count == notes.count else { throw GiriDataError.invalid("回答メモのIDが重複しています。") }
        try mutate { next in
            Self.upsert(event, into: &next.events)
            for note in notes { Self.upsert(note, into: &next.notes) }
        }
    }
    func markResultPrompted(eventID: String, key: String) throws {
        guard !key.isEmpty, let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        guard !events[index].promptedResultKeys.contains(key) else { return }
        try mutate { $0.events[index].promptedResultKeys.append(key) }
    }
    /// A qualification is a historical result, not an inferred promotion.
    /// Future-season league changes are stored with their effective date.
    func saveCycleResult(event candidate: GiriEvent, nextAffiliation: String? = nil) throws {
        var event = Self.normalizedEvent(candidate)
        if let nextAffiliation { event.nextAffiliation = nextAffiliation.trimmingCharacters(in: .whitespacesAndNewlines) }
        try event.validate()
        if let target = nextAffiliation?.trimmingCharacters(in: .whitespacesAndNewlines),
           !target.isEmpty, target != event.affiliation,
           let site = onlineSiteById(event.onlineSiteId), site.cycleSettings?.leagueChangesPerSeason == true,
           event.nextLeagueEffectiveDate == nil, event.siteSeasonEnd == nil, site.cycleSettings?.seasonEnd == nil {
            throw GiriDataError.invalid("シーズン終了が未定です。リーグ変更の適用日を入力してください。")
        }
        try mutate { next in
            Self.upsert(event, into: &next.events)
            guard event.isActualParticipant, let siteID = event.onlineSiteId,
                  let siteIndex = next.onlineSites.firstIndex(where: { $0.id == siteID }),
                  next.onlineSites[siteIndex].hasAffiliations else { return }
            let reference = event.participationStartDate ?? event.createdAt
            var site = next.onlineSites[siteIndex]
            if site.cycleSettings != nil {
                let date = siteLeagueEffectiveDate(site, after: event)
                let hasExistingChange = site.leagueChanges.contains { $0.sourceEventID == event.id }
                let explicitClear = event.nextAffiliation.isEmpty && event.leagueMovement == .unchanged
                guard nextAffiliation != nil || (hasExistingChange && explicitClear) else { return }
                if site.leagueBaseline == nil { site.leagueBaseline = site.leagueChanges.sorted { $0.effectiveFrom < $1.effectiveFrom }.first?.fromLeague ?? site.affiliation }
                site.leagueChanges.removeAll { $0.sourceEventID == event.id }
                if let affiliation = nextAffiliation?.trimmingCharacters(in: .whitespacesAndNewlines), !affiliation.isEmpty && affiliation != event.affiliation {
                    let change = SiteLeagueChange(id: "league:" + event.id, sourceEventID: event.id, fromLeague: event.affiliation, toLeague: affiliation, effectiveFrom: date, seasonName: event.siteSeason)
                    site.leagueChanges.append(change)
                }
                site.affiliation = siteLeague(site)
            } else {
                // Preserve the 0.5 legacy per-cycle affiliation behaviour.
                guard let nextAffiliation else { return }
                let laterJoined = next.events.contains { $0.id != event.id && $0.onlineSiteId == siteID && $0.isActualParticipant && ($0.participationStartDate ?? $0.createdAt) > reference }
                guard !laterJoined else { return }
                site.affiliation = nextAffiliation.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            next.onlineSites[siteIndex] = site
            for index in next.events.indices where next.events[index].onlineSiteId == siteID && !next.events[index].isParticipating && !next.events[index].isInterested && (next.events[index].participationStartDate ?? next.events[index].createdAt) > reference {
                let date = next.events[index].participationStartDate ?? next.events[index].createdAt
                next.events[index].affiliation = site.cycleSettings == nil ? site.affiliation : siteLeague(site, at: date)
            }
        }
    }
    func deleteNote(_ id: String) throws { try mutate { $0.notes.removeAll { $0.id == id } } }
    func savePlayer(_ candidate: GiriPlayer) throws {
        var player = candidate
        player.name = player.name.trimmingCharacters(in: .whitespacesAndNewlines)
        player.furigana = player.furigana.trimmingCharacters(in: .whitespacesAndNewlines)
        player.region = player.region.trimmingCharacters(in: .whitespacesAndNewlines)
        player.twitterUrl = player.twitterUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        try player.validate()
        let old = playerDirectory.first { $0.id == player.id }
        guard !playerDirectory.contains(where: { $0.id != player.id && playerSearchKey($0.name) == playerSearchKey(player.name) }) else { throw GiriDataError.invalid("同じ名前のプレイヤーが登録されています。") }
        if player.id.hasPrefix("history:") { player.id = newId() }
        let saved = player
        try mutate { next in
            Self.upsert(saved, into: &next.players)
            if let old, old.name != saved.name { Self.renamePlayer(from: old.name, to: saved.name, in: &next) }
        }
    }
    func deletePlayer(_ id: String) throws { try mutate { $0.players.removeAll { $0.id == id } } }
    func savePreferences(_ candidate: AppPreferences) throws {
        var preferences = candidate
        preferences.selfName = preferences.selfName.trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.formatOrder = preferences.effectiveFormatOrder
        try preferences.validate()
        let oldName = self.preferences.selfName
        try mutate { next in
            if !oldName.isEmpty && !preferences.selfName.isEmpty && oldName != preferences.selfName,
               let index = next.players.firstIndex(where: { playerSearchKey($0.name) == playerSearchKey(oldName) }) {
                let selfID = next.players[index].id
                guard !next.players.contains(where: { $0.id != selfID && playerSearchKey($0.name) == playerSearchKey(preferences.selfName) }) else { throw GiriDataError.invalid("同じ名前のプレイヤーが登録されています。") }
                next.players[index].name = preferences.selfName
                Self.renamePlayer(from: oldName, to: preferences.selfName, in: &next)
            }
            next.preferences = preferences
            if !preferences.selfName.isEmpty && !next.players.contains(where: { playerSearchKey($0.name) == playerSearchKey(preferences.selfName) }) { next.players.append(GiriPlayer(name: preferences.selfName)) }
        }
    }
    private static func renamePlayer(from old: String, to name: String, in next: inout GiriDocument) {
        let key = playerSearchKey(old)
        func rename(_ value: String) -> String { playerSearchKey(value) == key ? name : value }
        for index in next.events.indices {
            next.events[index].organizer = rename(next.events[index].organizer)
            next.events[index].participants = next.events[index].participants.map(rename)
            for team in next.events[index].teams.indices { next.events[index].teams[team].members = next.events[index].teams[team].members.map(rename) }
            for standing in next.events[index].standings.indices { next.events[index].standings[standing].playerNames = next.events[index].standings[standing].playerNames.map(rename) }
            if var result = next.events[index].tournamentResult { result.members = result.members.map(rename); next.events[index].tournamentResult = result }
        }
        for index in next.notes.indices where next.notes[index].isOthersAnswer { next.notes[index].answerer = rename(next.notes[index].answerer) }
        if playerSearchKey(next.preferences.selfName) == key { next.preferences.selfName = name }
    }

    func saveVenue(_ candidate: GiriVenue) throws {
        try candidate.validate()
        let old = venueById(candidate.id)
        guard !venueDirectory.contains(where: { $0.id != candidate.id && playerSearchKey($0.name) == playerSearchKey(candidate.name) }) else { throw GiriDataError.invalid("同じ会場名が登録されています。") }
        var venue = candidate
        if venue.id.hasPrefix("history:") { venue.id = newId() }
        let saved = venue
        try mutate { next in
            Self.upsert(saved, into: &next.venues)
            if let old {
                for index in next.events.indices where next.events[index].venueId == old.id || playerSearchKey(next.events[index].venue) == playerSearchKey(old.name) { next.events[index].venue = saved.name; next.events[index].venueId = saved.id }
            }
        }
    }
    func deleteVenue(_ id: String) throws {
        try mutate { next in
            next.venues.removeAll { $0.id == id }
            for index in next.events.indices where next.events[index].venueId == id { next.events[index].venueId = nil }
        }
    }
    func saveOnlineSite(_ candidate: OnlineSite) throws {
        var site = candidate
        let previous = onlineSites.first { $0.id == site.id }
        let previousSettings = previous?.cycleSettings
        let previousSeasonID: String? = previousSettings.flatMap { settings in
            guard settings.seasonID != nil || !settings.seasonName.isEmpty || settings.trackSeasonTotals || settings.seasonStart != nil || settings.seasonEndsAt != nil else { return nil }
            return settings.seasonID ?? "legacy-season:\(site.id):\(settings.seasonName)"
        }
        if var settings = site.cycleSettings {
            let hasSeason = settings.seasonID != nil || !settings.seasonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || settings.trackSeasonTotals || settings.seasonStart != nil || settings.seasonEndsAt != nil
            if hasSeason && settings.seasonID == nil { settings.seasonID = previousSeasonID ?? UUID().uuidString }
            if !hasSeason { settings.seasonID = nil }
            if let cap = settings.regularCycleCount, cap < settings.anchorCycleNumber { settings.regularCycleCount = nil }
            let changedRules = previousSettings.map { old in
                settings.anchorStart != old.anchorStart || settings.anchorCycleNumber != old.anchorCycleNumber ||
                settings.pattern != old.pattern || settings.intervalDays != old.intervalDays ||
                settings.seasonID != previousSeasonID || site.submissionDays != previous?.submissionDays ||
                site.votingDays != previous?.votingDays || site.recurrence != previous?.recurrence ||
                (settings.ruleRevisionID != nil && settings.ruleRevisionID != old.ruleRevisionID)
            } ?? false
            if let previous, var old = previousSettings, changedRules {
                let oldID = old.ruleRevisionID ?? "legacy-rule:\(site.id):\(cycleKeyFor(old.anchorStart))"
                old.ruleRevisionID = oldID
                if old.seasonID == nil && !old.seasonName.isEmpty { old.seasonID = previousSeasonID }
                if !site.ruleHistory.contains(where: { $0.id == oldID }) {
                    site.ruleHistory.append(SiteRuleRevision(id: oldID, settings: old,
                        submissionDays: previous.submissionDays, votingDays: previous.votingDays,
                        recurrence: previous.recurrence))
                }
                // A new rule applies from the actual period the user knows.
                // It cannot reconstruct dates preceding that anchor.
                if settings.ruleRevisionID == nil || settings.ruleRevisionID == previousSettings?.ruleRevisionID {
                    settings.ruleRevisionID = UUID().uuidString
                }
            }
            if settings.ruleRevisionID == nil { settings.ruleRevisionID = previousSettings?.ruleRevisionID ?? UUID().uuidString }
            site.cycleSettings = settings
        }
        try site.validate()
        if let previous {
            let newSeason = site.cycleSettings?.seasonID != previousSeasonID
            let namedNewSeason = newSeason && site.hasAffiliations && !(site.cycleSettings?.seasonName.isEmpty ?? true)
            if (site.affiliation != siteLeague(previous) || namedNewSeason), previous.cycleSettings != nil || !previous.leagueChanges.isEmpty {
                if site.leagueBaseline == nil { site.leagueBaseline = previous.leagueBaseline ?? previous.leagueChanges.sorted { $0.effectiveFrom < $1.effectiveFrom }.first?.fromLeague ?? previous.affiliation }
                let noJoinedHistory = !events.contains { $0.onlineSiteId == site.id && $0.isActualParticipant }
                let effective = (newSeason || noJoinedHistory) ? (site.cycleSettings?.seasonStart ?? site.cycleSettings?.anchorStart ?? Date()) : Date()
                let change = SiteLeagueChange(sourceEventID: "site-setting:" + UUID().uuidString, fromLeague: siteLeague(previous, at: effective), toLeague: site.affiliation, effectiveFrom: effective, seasonName: site.cycleSettings?.seasonName ?? "")
                site.leagueChanges.append(change)
                site.affiliation = siteLeague(site)
            }
        } else if site.hasAffiliations, let settings = site.cycleSettings, !settings.seasonName.isEmpty, !site.affiliation.isEmpty {
            site.leagueBaseline = site.affiliation
            site.leagueChanges.append(SiteLeagueChange(id: "season-start:" + site.id, sourceEventID: "season-start:" + site.id, fromLeague: site.affiliation, toLeague: site.affiliation, effectiveFrom: settings.seasonStart ?? settings.anchorStart, seasonName: settings.seasonName))
        }
        try mutate { next in
            Self.upsert(site, into: &next.onlineSites)
            // Give old same-season snapshots a stable identity once. A rename
            // or a rule revision then cannot fragment season totals.
            if let oldName = previousSettings?.seasonName, let previousSeasonID {
                for index in next.events.indices where next.events[index].onlineSiteId == site.id && next.events[index].siteSeasonID == nil && next.events[index].siteSeason == oldName {
                    next.events[index].siteSeasonID = previousSeasonID
                }
            }
        }
    }
    func deleteOnlineSite(_ id: String) throws {
        try mutate { next in
            next.onlineSites.removeAll { $0.id == id }
            for index in next.events.indices where next.events[index].onlineSiteId == id { next.events[index].onlineSiteId = nil }
        }
    }

    @discardableResult
    func createSiteCycle(_ siteID: String, weekOf: Date = Date(), weekOffset: Int = 0, join: Bool = true, submissionStart: Date? = nil) throws -> GiriEvent {
        guard loaded else { throw GiriDataError.notLoaded }
        guard let site = onlineSiteById(siteID) else { throw GiriDataError.invalid("サイトが見つかりません。") }
        let start = submissionStart ?? siteCycleStart(site, weekOf: weekOf, weekOffset: weekOffset)
        let key = cycleKeyFor(start)
        if var event = events.first(where: { $0.onlineSiteId == siteID && $0.cycleKey == key }) {
            if join && !event.isActualParticipant {
                event.isParticipating = true
                event.isInterested = false
                event.status = .planned
                event.eventFormat = site.format
                event.affiliation = site.hasAffiliations ? site.affiliation : ""
                let name = preferences.selfName
                if !name.isEmpty && !event.participants.contains(where: { playerSearchKey($0) == playerSearchKey(name) }) { event.participants.append(name) }
                try saveEvent(event)
            }
            return event
        }
        var round = EventRound()
        round.stageId = round.id; round.block = site.block; round.submissionStart = start
        round = completeRoundSchedule(round, submissionDays: site.submissionDays, votingDays: site.votingDays)
        var event = GiriEvent()
        event.title = site.name; event.eventFormat = site.format; event.meetingType = .casual
        event.onlineSiteId = site.id; event.cycleKey = key; event.affiliation = site.hasAffiliations ? site.affiliation : ""; event.block = site.block
        event.siteUrl = site.url; event.memo = site.memo; event.rounds = [round]; event.isParticipating = join
        if join && !preferences.selfName.isEmpty { event.participants = [preferences.selfName] }
        try saveEvent(event)
        return event
    }
    @discardableResult
    func createSiteCycle(_ siteID: String, descriptor: SiteCycleDescriptor, join: Bool = true) throws -> GiriEvent {
        guard loaded else { throw GiriDataError.notLoaded }
        guard let site = onlineSiteById(siteID) else { throw GiriDataError.invalid("サイトが見つかりません。") }
        if var event = events.first(where: { $0.onlineSiteId == siteID && $0.cycleKey == descriptor.cycleKey }) {
            // A saved participation and its edited dates/results are snapshots.
            guard !event.isActualParticipant else { return event }
            if !event.isInterested && event.status != .canceled && !event.siteScheduleCustomized {
                let previousRoundID = event.effectiveRounds.first?.id
                var round = descriptor.round
                if let previousRoundID { round.id = previousRoundID; round.stageId = previousRoundID }
                event.rounds = [round]
                event.siteSeason = descriptor.seasonName
                event.siteSeasonID = descriptor.seasonID ?? (descriptor.seasonName == site.cycleSettings?.seasonName ? site.cycleSettings?.seasonID : nil)
                event.siteRuleRevisionID = descriptor.ruleRevisionID ?? (descriptor.seasonName == site.cycleSettings?.seasonName ? site.cycleSettings?.ruleRevisionID : nil)
                event.siteSeasonStart = descriptor.seasonStart
                event.siteSeasonEnd = descriptor.seasonEnd
                event.siteCycleNumber = descriptor.cycleNumber
                event.sitePeriodKind = descriptor.kind
            }
            if join {
                event.isParticipating = true; event.isInterested = false; event.status = .planned
                event.eventFormat = site.format
                if event.siteSeasonID == nil && event.siteSeason == descriptor.seasonName {
                    event.siteSeasonID = descriptor.seasonID ?? site.cycleSettings?.seasonID
                    event.siteRuleRevisionID = descriptor.ruleRevisionID ?? site.cycleSettings?.ruleRevisionID
                }
                event.affiliation = site.hasAffiliations ? siteLeague(site, at: descriptor.start ?? Date()) : ""
                let name = preferences.selfName
                if !name.isEmpty && !event.participants.contains(where: { playerSearchKey($0) == playerSearchKey(name) }) { event.participants.append(name) }
            }
            // Avoid rewriting unchanged preview bytes at every foreground.
            if let original = events.first(where: { $0.id == event.id }), event != original { try saveEvent(event) }
            return event
        }
        var event = GiriEvent()
        event.title = site.name; event.eventFormat = site.format; event.meetingType = .casual
        event.onlineSiteId = siteID; event.cycleKey = descriptor.cycleKey
        event.affiliation = site.hasAffiliations ? siteLeague(site, at: descriptor.start ?? Date()) : ""
        event.siteSeason = descriptor.seasonName
        event.siteSeasonID = descriptor.seasonID ?? (descriptor.seasonName == site.cycleSettings?.seasonName ? site.cycleSettings?.seasonID : nil)
        event.siteRuleRevisionID = descriptor.ruleRevisionID ?? (descriptor.seasonName == site.cycleSettings?.seasonName ? site.cycleSettings?.ruleRevisionID : nil)
        event.siteSeasonStart = descriptor.seasonStart
        event.siteSeasonEnd = descriptor.seasonEnd
        event.siteCycleNumber = descriptor.cycleNumber
        event.sitePeriodKind = descriptor.kind
        event.block = site.block; event.siteUrl = site.url; event.memo = site.memo
        event.rounds = [descriptor.round]; event.isParticipating = join
        if join && !preferences.selfName.isEmpty { event.participants = [preferences.selfName] }
        try saveEvent(event)
        return event
    }
    func ensureCurrentSiteCycles(now: Date = Date()) throws {
        for site in onlineSites {
            if site.cycleSettings != nil {
                for descriptor in siteCycleDescriptors(site, around: now) {
                    try createSiteCycle(site.id, descriptor: descriptor, join: false)
                }
            } else if site.recurrence == .weekly {
                for offset in -1...1 { try createSiteCycle(site.id, weekOf: now, weekOffset: offset, join: false) }
            }
        }
    }
    func exportBackup() throws -> Data { guard loaded else { throw GiriDataError.notLoaded }; return try GiriJSON.encode(document) }
    func recordBackupExported() throws { try mutate { $0.lastBackupAt = Date() } }
    func restoreBackup(_ data: Data) throws {
        let restored = try GiriJSON.decode(data)
        // An explicitly confirmed restore is allowed to recover a failed load;
        // preserve corrupt bytes as a separate recovery copy before replacement.
        if !loaded && FileManager.default.fileExists(atPath: fileURL.path) {
            let recovery = directory.appendingPathComponent("giristair.unreadable-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: fileURL, to: recovery)
        }
        try persist(try GiriJSON.encode(restored))
        document = restored; loaded = true; errorMessage = nil
    }
    private static func upsert<T: Identifiable>(_ value: T, into values: inout [T]) where T.ID: Equatable {
        if let index = values.firstIndex(where: { $0.id == value.id }) { values[index] = value } else { values.append(value) }
    }
}
