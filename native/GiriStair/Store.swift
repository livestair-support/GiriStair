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
    var groups: [GiriGroup] { document.groups }
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
        // 団体の主催はプレイヤー一覧に入れない。（型チェックを軽くするため1つずつ足す）
        var names: [String] = event.organizerIsGroup ? [] : [event.organizer]
        names += event.coOrganizers
        names += event.mcs
        names += event.judges
        names += event.reserves
        names += event.participants
        names += event.teams.flatMap(\.members)
        names += event.tournamentResult?.members ?? []
        names += event.standings.flatMap(\.playerNames)
        return names
    }

    /// 別名義の照合キー → 本名義。別名義はいつも本名義にまとめる（0.12 の「まとめて表示」の設定は使わない）。
    var mergedAliasOwners: [String: String] {
        var owners: [String: String] = [:]
        let me = preferences.selfName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !me.isEmpty {
            for alias in preferences.selfAliases where playerSearchKey(alias) != playerSearchKey(me) { owners[playerSearchKey(alias)] = me }
        }
        for player in players {
            for alias in player.aliases where playerSearchKey(alias) != playerSearchKey(player.name) && owners[playerSearchKey(alias)] == nil {
                owners[playerSearchKey(alias)] = player.name
            }
        }
        owners.removeValue(forKey: "")
        return owners
    }
    /// この人として数える名前の照合キー（本名義と、まとめて表示する別名義）。
    func nameKeys(for name: String) -> Set<String> {
        let key = playerSearchKey(name)
        guard !key.isEmpty else { return [] }
        var keys: Set<String> = [key]
        if key == playerSearchKey(preferences.selfName) { keys.formUnion(preferences.selfKeys) }
        if let player = players.first(where: { playerSearchKey($0.name) == key }) {
            keys.formUnion(player.aliases.map(playerSearchKey))
        }
        keys.remove("")
        return keys
    }
    /// 別名義の名前なら、その本名義（まとめる・それぞれ表示のどちらでも）。
    func aliasOwner(of name: String) -> String? {
        let key = playerSearchKey(name)
        guard !key.isEmpty else { return nil }
        let me = preferences.selfName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !me.isEmpty && key != playerSearchKey(me) && preferences.selfAliases.contains(where: { playerSearchKey($0) == key }) { return me }
        return players.first { player in playerSearchKey(player.name) != key && player.aliases.contains { playerSearchKey($0) == key } }?.name
    }
    /// 別名義（自分の別名義を含む）。
    func aliases(of name: String) -> [String] {
        let key = playerSearchKey(name)
        if !key.isEmpty && key == playerSearchKey(preferences.selfName) { return preferences.selfAliases }
        return players.first { playerSearchKey($0.name) == key }?.aliases ?? []
    }
    /// 自分の別名義と、その表示（設定と同じ保存先）。
    func saveSelfAliases(_ aliases: [String], merges: Bool) throws {
        var value = preferences
        value.selfAliases = aliases
        value.mergesSelfAliases = merges
        try savePreferences(value)
    }

    var playerDirectory: [GiriPlayer] {
        // 別名義をまとめて表示する人の別名義は、プレイヤー一覧に別に出さない。
        let merged = mergedAliasOwners
        var profiles = Dictionary(players.filter { merged[playerSearchKey($0.name)] == nil }.map { (playerSearchKey($0.name), $0) },
                                  uniquingKeysWith: { first, _ in first })
        var sourceNames: [String] = [preferences.selfName]
        sourceNames += preferences.selfAliases
        sourceNames += events.flatMap(referencedNames)
        sourceNames += notes.flatMap(\.referencedPeople)
        sourceNames += groups.flatMap(\.members)
        for name in sourceNames {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = playerSearchKey(trimmed)
            if !trimmed.isEmpty && profiles[key] == nil && merged[key] == nil { profiles[key] = GiriPlayer(id: "history:\(key)", name: trimmed) }
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
        return values.values.sorted {
            ($0.furigana.isEmpty ? $0.name : $0.furigana).localizedStandardCompare($1.furigana.isEmpty ? $1.name : $1.furigana) == .orderedAscending
        }
    }
    /// 会・結果・他人の回答で使われている名前。LiveStair の一覧と同じく、
    /// 記録のないプレイヤーだけを一覧から削除できるようにするために使う。
    var referencedPlayerKeys: Set<String> {
        var keys = Set(events.flatMap(referencedNames).map(playerSearchKey))
        keys.formUnion(notes.flatMap(\.referencedPeople).map(playerSearchKey))
        keys.formUnion(groups.flatMap(\.members).map(playerSearchKey))
        keys.remove("")
        return keys
    }
    /// 会で使われている会場（ID・名前）。記録のある会場は一覧から削除しない。
    var referencedVenueKeys: (ids: Set<String>, names: Set<String>) {
        var names = Set(events.map { playerSearchKey($0.venue) })
        names.remove("")
        return (Set(events.compactMap(\.venueId)), names)
    }
    /// 名前のプレイヤー。別名義をまとめて表示する人の別名義は、本名義のプレイヤーを返す。
    func playerByName(_ name: String) -> GiriPlayer? {
        let key = playerSearchKey(name)
        let directory = playerDirectory
        if let hit = directory.first(where: { playerSearchKey($0.name) == key }) { return hit }
        guard let owner = mergedAliasOwners[key] else { return nil }
        return directory.first { playerSearchKey($0.name) == playerSearchKey(owner) }
    }
    /// 団体：保存した団体と、会で「団体」の主催者として入れた名前（プレイヤー一覧とは別）。
    var groupDirectory: [GiriGroup] {
        var values = Dictionary(groups.map { (playerSearchKey($0.name), $0) }, uniquingKeysWith: { first, _ in first })
        for event in events where event.organizerIsGroup {
            let name = event.organizer.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = playerSearchKey(name)
            if !key.isEmpty && values[key] == nil { values[key] = GiriGroup(id: "history:\(key)", name: name) }
        }
        return values.values.sorted { ($0.furigana.isEmpty ? $0.name : $0.furigana).localizedStandardCompare($1.furigana.isEmpty ? $1.name : $1.furigana) == .orderedAscending }
    }
    func groupByName(_ name: String) -> GiriGroup? {
        let key = playerSearchKey(name)
        return key.isEmpty ? nil : groupDirectory.first { playerSearchKey($0.name) == key }
    }
    /// 団体が主催した会（団体として主催者に入れたもの）。
    func eventsHosted(byGroup name: String) -> [GiriEvent] {
        let key = playerSearchKey(name)
        return events.filter { $0.organizerIsGroup && !key.isEmpty && playerSearchKey($0.organizer) == key }
    }
    func venueById(_ id: String?) -> GiriVenue? { venueDirectory.first { $0.id == id } }
    func onlineSiteById(_ id: String?) -> OnlineSite? { onlineSites.first { $0.id == id } }
    func newId() -> String { UUID().uuidString }

    func suggestPlayers(_ query: String, organizer: Bool = false) -> [GiriPlayer] {
        var counts: [String: Int] = [:]
        for event in events where event.status != .canceled {
            // 主催の候補は共催も含め、参加者の候補はチームのメンバーも数える。
            var names: [String]
            if organizer {
                names = event.organizerIsGroup ? [] : [event.organizer]
                names += event.coOrganizers
            } else {
                names = event.everyone
            }
            for name in names { counts[playerSearchKey(name), default: 0] += 1 }
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
    /// keepsInTrash：画面から消した時は「最近削除した会」に30日残して戻せるようにする（自動で作った回は残さない）。
    func deleteEvent(_ id: String, keepsInTrash: Bool = false, now: Date = Date()) throws {
        try mutate { next in
            if keepsInTrash, let removed = next.events.first(where: { $0.id == id }) {
                let links = next.notes.filter { $0.eventId == id }.map { GiriDeletedNoteLink(noteID: $0.id, roundID: $0.roundId) }
                next.deletedEvents.removeAll { $0.id == id }
                next.deletedEvents.insert(GiriDeletedEvent(event: removed, deletedAt: now, noteLinks: links), at: 0)
            }
            next.deletedEvents.removeAll { now.timeIntervalSince($0.deletedAt) > giriDeletedEventRetention }
            next.events.removeAll { $0.id == id }
            // 会の中の大会は、元の会を消しても大会として残す。
            for index in next.events.indices where next.events[index].parentEventId == id { next.events[index].parentEventId = nil }
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
    /// 0.19：最近削除した会（新しい順）。
    /// 30日を過ぎた分は、次に削除した時に記録から消す（それまでは表示しない）。
    var deletedEvents: [GiriDeletedEvent] { document.deletedEvents.filter { giriDeletedEventRemainingDays($0) > 0 } }
    /// 最近削除した会を戻す（お題・回答も付け直す）。同じIDの会がもうあれば戻さない。
    func restoreDeletedEvent(_ id: String) throws {
        guard let entry = document.deletedEvents.first(where: { $0.id == id }) else { return }
        guard !events.contains(where: { $0.id == id }) else { throw GiriDataError.invalid("同じ会がすでにあります。") }
        try mutate { next in
            next.events.append(entry.event)
            for link in entry.noteLinks {
                if let index = next.notes.firstIndex(where: { $0.id == link.noteID && $0.eventId == nil }) {
                    next.notes[index].eventId = entry.event.id
                    next.notes[index].roundId = link.roundID
                }
            }
            next.deletedEvents.removeAll { $0.id == id }
        }
    }
    /// 最近削除した会から完全に消す（nil は全部）。
    func purgeDeletedEvents(_ id: String? = nil) throws {
        try mutate { next in
            if let id { next.deletedEvents.removeAll { $0.id == id } } else { next.deletedEvents.removeAll() }
        }
    }
    private static func normalizedEvent(_ candidate: GiriEvent) -> GiriEvent {
        var event = candidate
        if let format = event.format { event.kind = format == .live ? .live : .online }
        if event.isInterested { event.isParticipating = false }
        event.hashtag = giriNormalizedHashtag(event.hashtag)
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
    /// 0.16：お題をまとめて保存する（会のお題をまとめて入れる）。
    func saveNotes(_ candidates: [ThoughtNote]) throws {
        let notes = candidates.map(Self.normalizedNote)
        try notes.forEach { try $0.validate() }
        try mutate { next in for note in notes { Self.upsert(note, into: &next.notes) } }
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
        player.prefecture = player.prefecture.trimmingCharacters(in: .whitespacesAndNewlines)
        player.twitterUrl = player.twitterUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        // 別名義は空・本名義と同じ名前・重複を外す。
        var seenAliases: Set<String> = [playerSearchKey(player.name)]
        player.aliases = player.aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seenAliases.insert(playerSearchKey($0)).inserted }
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
    func saveGroup(_ candidate: GiriGroup) throws {
        var group = candidate
        group.name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        group.furigana = group.furigana.trimmingCharacters(in: .whitespacesAndNewlines)
        group.url = group.url.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        group.members = group.members.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(playerSearchKey($0)).inserted }
        try group.validate()
        let old = groupDirectory.first { $0.id == group.id }
        // 新しく団体にする名前がプレイヤーとして保存されていたら、フリガナ・メモを引き継ぐ。
        if old == nil || old?.id.hasPrefix("history:") == true,
           let player = players.first(where: { playerSearchKey($0.name) == playerSearchKey(group.name) }) {
            if group.furigana.isEmpty { group.furigana = player.furigana }
            if group.memo.isEmpty { group.memo = player.memo }
        }
        guard !groupDirectory.contains(where: { $0.id != group.id && playerSearchKey($0.name) == playerSearchKey(group.name) }) else { throw GiriDataError.invalid("同じ名前の団体が登録されています。") }
        if group.id.hasPrefix("history:") { group.id = newId() }
        let saved = group
        try mutate { next in
            Self.upsert(saved, into: &next.groups)
            // 団体として登録した名前が主催者の会は、団体の主催にする。
            let newKey = playerSearchKey(saved.name)
            for index in next.events.indices where !next.events[index].organizerIsGroup && playerSearchKey(next.events[index].organizer) == newKey {
                next.events[index].organizerIsGroup = true
            }
            // 会の保存で自動登録されたプレイヤーの記録が残らないようにする（人として使われていない時だけ）。
            self.removePlayerRecordIfUnused(newKey, in: &next)
            // 団体名を変えたら、その団体が主催した会の主催者名も変える。
            if let old, old.name != saved.name {
                let key = playerSearchKey(old.name)
                for index in next.events.indices where next.events[index].organizerIsGroup && playerSearchKey(next.events[index].organizer) == key {
                    next.events[index].organizer = saved.name
                }
            }
        }
    }
    func deleteGroup(_ id: String) throws { try mutate { $0.groups.removeAll { $0.id == id } } }
    /// 団体にしたのが間違いだった時：団体の記録を外し、主催した会をプレイヤーの主催に戻す（フリガナ・メモはプレイヤーへ移す）。
    @discardableResult
    func convertGroupToPlayer(_ id: String) throws -> String {
        guard let group = groupDirectory.first(where: { $0.id == id }) else { throw GiriDataError.invalid("団体が見つかりません。") }
        let key = playerSearchKey(group.name)
        guard !key.isEmpty else { throw GiriDataError.invalid("名前がありません。") }
        try mutate { next in
            next.groups.removeAll { $0.id == id || playerSearchKey($0.name) == key }
            for index in next.events.indices where next.events[index].organizerIsGroup && playerSearchKey(next.events[index].organizer) == key {
                next.events[index].organizerIsGroup = false
            }
            if let index = next.players.firstIndex(where: { playerSearchKey($0.name) == key }) {
                if next.players[index].furigana.isEmpty { next.players[index].furigana = group.furigana }
                if next.players[index].memo.isEmpty { next.players[index].memo = group.memo }
            } else {
                var player = GiriPlayer(name: group.name)
                player.furigana = group.furigana
                player.memo = group.memo
                next.players.append(player)
            }
        }
        return group.name
    }
    /// 主催者にプレイヤーとして入っていた名前を団体にする（その名前が主催した会を団体の主催にする）。
    /// 参加者などで使われていない時だけ、保存済みのプレイヤーの記録を外す（フリガナ・メモは団体へ移す）。
    @discardableResult
    func convertPlayerToGroup(_ name: String) throws -> GiriGroup {
        let key = playerSearchKey(name)
        guard !key.isEmpty else { throw GiriDataError.invalid("名前がありません。") }
        let player = players.first { playerSearchKey($0.name) == key }
        var group = groups.first { playerSearchKey($0.name) == key } ?? GiriGroup(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        if group.furigana.isEmpty { group.furigana = player?.furigana ?? "" }
        if group.memo.isEmpty { group.memo = player?.memo ?? "" }
        let saved = group
        try mutate { next in
            for index in next.events.indices where !next.events[index].organizerIsGroup && playerSearchKey(next.events[index].organizer) == key {
                next.events[index].organizerIsGroup = true
            }
            Self.upsert(saved, into: &next.groups)
            self.removePlayerRecordIfUnused(key, in: &next)
        }
        return saved
    }
    /// 団体になった名前の、保存済みのプレイヤーの記録を外す。参加者・共催・メモ・団体のメンバーなど
    /// 人として使われている名前や、自分の名前・別名義は残す。
    private func removePlayerRecordIfUnused(_ key: String, in next: inout GiriDocument) {
        guard !key.isEmpty, !next.preferences.selfKeys.contains(key) else { return }
        let inEvents = next.events.contains { event in referencedNames(event).contains { playerSearchKey($0) == key } }
        let inNotes = next.notes.contains { note in note.referencedPeople.contains { playerSearchKey($0) == key } }
        let inGroups = next.groups.contains { group in group.members.contains { playerSearchKey($0) == key } }
        if !inEvents && !inNotes && !inGroups { next.players.removeAll { playerSearchKey($0.name) == key } }
    }
    func savePreferences(_ candidate: AppPreferences) throws {
        var preferences = candidate
        preferences.selfName = preferences.selfName.trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.formatOrder = preferences.effectiveFormatOrder
        var seenAliases = Set([playerSearchKey(preferences.selfName)])
        preferences.selfAliases = preferences.selfAliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seenAliases.insert(playerSearchKey($0)).inserted }
        let hidden = Set(preferences.hiddenFormats)
        preferences.hiddenFormats = EventFormat.allCases.filter { hidden.contains($0) }
        guard preferences.hiddenFormats.count < EventFormat.allCases.count else { throw GiriDataError.invalid("使用する形式を1つ以上選んでください。") }
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
            // 団体の主催者名はプレイヤーの名前変更で変えない。
            if !next.events[index].organizerIsGroup { next.events[index].organizer = rename(next.events[index].organizer) }
            next.events[index].coOrganizers = next.events[index].coOrganizers.map(rename)
            next.events[index].mcs = next.events[index].mcs.map(rename)
            next.events[index].judges = next.events[index].judges.map(rename)
            next.events[index].reserves = next.events[index].reserves.map(rename)
            next.events[index].participants = next.events[index].participants.map(rename)
            for team in next.events[index].teams.indices { next.events[index].teams[team].members = next.events[index].teams[team].members.map(rename) }
            for standing in next.events[index].standings.indices { next.events[index].standings[standing].playerNames = next.events[index].standings[standing].playerNames.map(rename) }
            if var result = next.events[index].tournamentResult {
                result.members = result.members.map(rename)
                for stage in result.stages.indices { result.stages[stage].opponents = result.stages[stage].opponents.map(rename) }
                next.events[index].tournamentResult = result
            }
        }
        for index in next.groups.indices { next.groups[index].members = next.groups[index].members.map(rename) }
        for index in next.notes.indices {
            if next.notes[index].isOthersAnswer { next.notes[index].answerer = rename(next.notes[index].answerer) }
            next.notes[index].promptAuthor = rename(next.notes[index].promptAuthor)
            for record in next.notes[index].answerRecords.indices where !next.notes[index].answerRecords[record].answerer.isEmpty {
                next.notes[index].answerRecords[record].answerer = rename(next.notes[index].answerRecords[record].answerer)
            }
        }
        next.preferences.selfAliases = next.preferences.selfAliases.map(rename)
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
    /// 0.14：フリガナをまとめて保存する（キーは一覧のID）。記録の中だけにある名前は、その名前で登録する。
    func saveFurigana(players: [String: String], venues: [String: String]) throws {
        guard loaded else { throw GiriDataError.notLoaded }
        let playerList = playerDirectory
        let venueList = venueDirectory
        try mutate { next in
            for (id, raw) in players {
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if let index = next.players.firstIndex(where: { $0.id == id }) {
                    next.players[index].furigana = value
                } else if let entry = playerList.first(where: { $0.id == id }), !value.isEmpty {
                    var player = GiriPlayer(name: entry.name)
                    player.furigana = value
                    next.players.append(player)
                }
            }
            for (id, raw) in venues {
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if let index = next.venues.firstIndex(where: { $0.id == id }) {
                    next.venues[index].furigana = value
                } else if let entry = venueList.first(where: { $0.id == id }), !value.isEmpty {
                    var venue = GiriVenue(name: entry.name)
                    venue.furigana = value
                    next.venues.append(venue)
                }
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
            // 次のお題を待っていた間のルールは、再開した回より後ろに残さない（再開した回が隠れないように）。
            if !settings.waitingForNext {
                let resumed = settings.anchorStart
                site.ruleHistory.removeAll { $0.settings.waitingForNext && $0.effectiveFrom >= resumed }
            }
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
                event.siteSkipped = false
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
                event.isParticipating = true; event.isInterested = false; event.siteSkipped = false; event.status = .planned
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
        for site in onlineSites where !site.isPaused {
            if site.cycleSettings != nil {
                for descriptor in siteCycleDescriptors(site, around: now) {
                    try createSiteCycle(site.id, descriptor: descriptor, join: false)
                }
            } else if site.recurrence == .weekly {
                for offset in -1...1 { try createSiteCycle(site.id, weekOf: now, weekOffset: offset, join: false) }
            }
        }
    }
    /// 「今回は見送る」：その回を参加しない記録として残す（見送りは参加回数・通知・結果入力の対象外）。
    /// 見送りを取り消すと、まだ決めていない状態に戻る。
    @discardableResult
    func setSiteCycleSkipped(_ siteID: String, descriptor: SiteCycleDescriptor?, event: GiriEvent?, skipped: Bool) throws -> GiriEvent? {
        var target: GiriEvent
        if let event { target = events.first { $0.id == event.id } ?? event }
        else if let descriptor { target = try createSiteCycle(siteID, descriptor: descriptor, join: false) }
        else { return nil }
        target = events.first { $0.id == target.id } ?? target
        guard target.siteSkipped != skipped || (skipped && target.isParticipating) else { return target }
        target.siteSkipped = skipped
        if skipped { target.isParticipating = false; target.isInterested = false }
        try saveEvent(target)
        return target
    }
    /// 0.14：運営の都合で休みの回。その回は作らず、後ろの回の番号を詰める。
    /// まだ何も書いていない休みの回の記録は消し、参加した回・メモのある回はキャンセルにする（取り消すと戻す）。
    func setSiteCycleBreak(_ siteID: String, start: Date, isBreak: Bool, now: Date = Date()) throws {
        guard loaded else { throw GiriDataError.notLoaded }
        guard var site = onlineSiteById(siteID), let settings = site.cycleSettings else { throw GiriDataError.invalid("サイトが見つかりません。") }
        guard siteIsBreakStart(settings, start) != isBreak else { return }
        site.cycleSettings = siteSettingsTogglingBreak(settings, start: start, isBreak: isBreak)
        try saveOnlineSite(site)
        let key = cycleKeyFor(start)
        if let event = events.first(where: { $0.onlineSiteId == siteID && $0.cycleKey == key }) {
            if isBreak {
                let hasNotes = notes.contains { $0.eventId == event.id }
                if event.isParticipating || hasNotes || event.hasCycleResult {
                    var canceled = event
                    canceled.status = .canceled
                    try saveEvent(canceled)
                } else {
                    try deleteEvent(event.id)
                }
            } else if event.status == .canceled {
                var restored = event
                restored.status = .planned
                try saveEvent(restored)
            }
        }
        guard let saved = onlineSiteById(siteID) else { return }
        for descriptor in siteCycleDescriptors(saved, around: now) where descriptor.kind == .regular {
            guard var event = events.first(where: { $0.onlineSiteId == siteID && $0.cycleKey == descriptor.cycleKey }),
                  event.isActualParticipant, let number = descriptor.cycleNumber, event.siteCycleNumber != number else { continue }
            let oldName = event.siteCycleNumber.map { "第\($0)回" }
            event.siteCycleNumber = number
            event.rounds = event.rounds.map { round in
                var value = round
                if oldName != nil && value.name == oldName { value.name = "第\(number)回"; value.promptNumber = number }
                return value
            }
            try saveEvent(event)
        }
        try ensureCurrentSiteCycles(now: now)
    }
    /// 0.14：同じ日の生大喜利の会の中で行う大会を追加する。日付・時刻・会場・主催・参加者を引き継ぎ、
    /// 元の会の中の大会にする（戦績ではそれぞれの大会、集計の参加回数は会として1回）。
    @discardableResult
    func addTournament(inside parentID: String) throws -> GiriEvent {
        guard loaded else { throw GiriDataError.notLoaded }
        guard let found = events.first(where: { $0.id == parentID }) else { throw GiriDataError.invalid("元の会が見つかりません。") }
        // 会の中の大会からさらに足した時も、同じ元の会の中に並べる。
        let parent = found.parentEventId.flatMap { id in events.first { $0.id == id } } ?? found
        let siblings = events.filter { $0.parentEventId == parent.id }.count
        var child = GiriEvent()
        child.title = parent.title + " 大会\(siblings + (parent.meetingType == .tournament ? 2 : 1))"
        child.eventFormat = parent.eventFormat
        child.meetingType = .tournament
        child.parentEventId = parent.id
        child.eventDate = parent.eventDate
        child.startsAt = parent.startsAt
        child.endsAt = parent.endsAt
        child.opensAt = parent.opensAt
        child.venue = parent.venue
        child.venueId = parent.venueId
        child.venueRoom = parent.venueRoom
        child.organizer = parent.organizer
        child.organizerIsGroup = parent.organizerIsGroup
        child.coOrganizers = parent.coOrganizers
        child.mcs = parent.mcs
        child.participants = parent.participants
        child.isParticipating = parent.isParticipating
        child.isInterested = parent.isInterested
        child.status = parent.status
        child.siteUrl = parent.siteUrl
        child.selfRole = parent.selfRole
        try saveEvent(child)
        return events.first { $0.id == child.id } ?? child
    }
    /// 0.14：過去に参加した回（一覧に出ていない回）を、投稿の締切から追加する。
    /// 日程はその回の記録として残し、サイトの日程の設定は変えない。
    @discardableResult
    func addPastSiteCycle(_ siteID: String, input: SitePastCycleInput) throws -> GiriEvent {
        guard loaded else { throw GiriDataError.notLoaded }
        guard let site = onlineSiteById(siteID) else { throw GiriDataError.invalid("サイトが見つかりません。") }
        var round = EventRound()
        round.submissionEnd = input.deadline
        round.submissionStart = addCalendarDays(input.deadline, -site.submissionDays)
        round.votingStart = input.deadline
        round.votingEnd = input.votingEnd ?? addCalendarDays(input.deadline, site.votingDays)
        if let votingEnd = round.votingEnd, votingEnd < input.deadline {
            throw GiriDataError.invalid("投票の締切を投稿の締切より後にしてください。")
        }
        if input.kind != .regular { round.name = input.kind.title }
        else if let number = input.cycleNumber { round.name = "第\(number)回" }
        if let number = input.cycleNumber { round.promptNumber = max(1, number) }
        round.block = site.block
        let start = round.submissionStart ?? input.deadline
        let key = cycleKeyFor(start)
        var event = events.first { $0.onlineSiteId == siteID && $0.cycleKey == key } ?? GiriEvent()
        if event.onlineSiteId == siteID && event.isActualParticipant {
            throw GiriDataError.invalid("同じ日程の回がすでに参加履歴にあります。")
        }
        if let previous = event.rounds.first?.id { round.id = previous }
        round.stageId = round.id
        let identity = sitePastSeasonIdentity(site, input: input, events: events)
        let league = input.league.trimmingCharacters(in: .whitespacesAndNewlines)
        event.title = site.name
        event.eventFormat = site.format
        event.meetingType = .casual
        event.onlineSiteId = site.id
        event.cycleKey = key
        event.affiliation = site.hasAffiliations ? (league.isEmpty ? siteLeague(site, at: start) : league) : league
        event.block = site.block
        event.siteUrl = site.url
        event.rounds = [round]
        event.isParticipating = true
        event.isInterested = false
        event.siteSkipped = false
        event.status = .planned
        event.siteScheduleCustomized = true
        event.sitePeriodKind = input.kind
        event.siteCycleNumber = input.kind == .regular ? input.cycleNumber.map { max(1, $0) } : nil
        event.siteSeason = identity.seasonName
        event.siteSeasonID = identity.seasonID
        event.siteRuleRevisionID = identity.ruleID
        if identity.isCurrent, let settings = site.cycleSettings {
            event.siteSeasonStart = settings.seasonStart
            event.siteSeasonEnd = settings.seasonEndsAt
        }
        let name = preferences.selfName
        if !name.isEmpty && !event.participants.contains(where: { playerSearchKey($0) == playerSearchKey(name) }) {
            event.participants.append(name)
        }
        try saveEvent(event)
        return events.first { $0.id == event.id } ?? event
    }
    /// しばらく休む／再開する。サイトの日程やリーグの設定は変えない。
    func setSitePaused(_ siteID: String, paused: Bool) throws {
        guard var site = onlineSiteById(siteID), site.isPaused != paused else { return }
        site.isPaused = paused
        try site.validate()
        try mutate { Self.upsert(site, into: &$0.onlineSites) }
    }
    /// 締切が決まっていないサイトに、次の回を投稿締切だけで追加する。
    func addSiteIrregularCycle(_ siteID: String, deadline: Date, votingEnd: Date? = nil) throws {
        guard var site = onlineSiteById(siteID) else { throw GiriDataError.invalid("サイトが見つかりません。") }
        var settings = site.cycleSettings ?? SiteCycleSettings()
        settings.specialPeriods.append(siteIrregularPeriod(site, deadline: deadline, votingEnd: votingEnd))
        settings.waitingForNext = false
        site.cycleSettings = settings
        try saveOnlineSite(site)
    }
    /// シーズンの最後の回が終わった後、次のシーズンを最初の回の投稿締切から始める。
    func startNextSiteSeason(_ siteID: String, firstDeadline: Date) throws {
        guard var site = onlineSiteById(siteID) else { throw GiriDataError.invalid("サイトが見つかりません。") }
        site.cycleSettings = siteNextSeasonSettings(site, firstDeadline: firstDeadline)
        try saveOnlineSite(site)
    }
    /// 0.23：次のシーズンを始める時に、そのシーズンのルールも選ぶ（nil は前のシーズンと同じ）。
    func startNextSiteSeason(_ siteID: String, firstDeadline: Date, ruleID: String?) throws {
        guard var site = onlineSiteById(siteID) else { throw GiriDataError.invalid("サイトが見つかりません。") }
        let chosen = (ruleID ?? site.currentRuleID).flatMap { rule($0) }
        // ルールの日数で最初の回の投稿開始を数えてから、日程・リーグ・プレーオフを入れる。
        if let chosen, chosen.kind == .online {
            site.submissionDays = chosen.submissionDays
            site.votingDays = chosen.votingDays
        }
        site.cycleSettings = siteNextSeasonSettings(site, firstDeadline: firstDeadline)
        if let chosen { giriApplyRule(chosen, to: &site) }
        try saveOnlineSite(site)
    }

    // MARK: 0.23 ルール

    var rules: [GiriRule] { document.rules }
    func rule(_ id: String) -> GiriRule? { document.rules.first { $0.id == id } }
    func saveRule(_ candidate: GiriRule) throws {
        var rule = candidate
        rule.name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.leagues = rule.leagues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        rule.stages = rule.stages.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.kind != nil }
        rule.updatedAt = Date()
        try rule.validate()
        try mutate { next in Self.upsert(rule, into: &next.rules) }
    }
    /// ルールを消す。選んでいたシーズン・大会からは外す（日程などはそのまま残す）。
    func deleteRule(_ id: String) throws {
        try mutate { next in
            next.rules.removeAll { $0.id == id }
            for index in next.onlineSites.indices { next.onlineSites[index].seasonRuleIDs = next.onlineSites[index].seasonRuleIDs.filter { $0.value != id } }
            for index in next.events.indices where next.events[index].ruleID == id { next.events[index].ruleID = nil }
        }
    }
    /// サイトの今のシーズンのルールを選ぶ（nil は外す）。ルールの日程・リーグ・プレーオフをサイトに入れる。
    func setSiteSeasonRule(_ siteID: String, ruleID: String?) throws {
        guard var site = onlineSiteById(siteID) else { throw GiriDataError.invalid("サイトが見つかりません。") }
        if let ruleID, let rule = rule(ruleID) {
            giriApplyRule(rule, to: &site)
        } else {
            site.seasonRuleIDs.removeValue(forKey: giriSeasonRuleKey(site.cycleSettings?.seasonID))
        }
        try saveOnlineSite(site)
    }
    /// 次のお題を待っている間（シーズンの合間など）から、次の回の投稿締切で再開する。
    func resumeSiteCycle(_ siteID: String, firstDeadline: Date, cycleNumber: Int?) throws {
        guard var site = onlineSiteById(siteID) else { throw GiriDataError.invalid("サイトが見つかりません。") }
        site.cycleSettings = siteResumeSettings(site, firstDeadline: firstDeadline, cycleNumber: cycleNumber)
        try saveOnlineSite(site)
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

/// 0.19：最近削除した会を残す期間（LiveStair と同じ30日）。
let giriDeletedEventRetention: TimeInterval = 30 * 86400

/// 完全に削除するまでの残り日数（切り上げ。0 は期限切れ）。
func giriDeletedEventRemainingDays(_ entry: GiriDeletedEvent, now: Date = Date()) -> Int {
    let remaining = giriDeletedEventRetention - now.timeIntervalSince(entry.deletedAt)
    return remaining <= 0 ? 0 : Int((remaining / 86400).rounded(.up))
}
