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
        for name in [preferences.selfName] + events.flatMap(referencedNames) {
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

    func saveEvent(_ event: GiriEvent) throws {
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
            for index in next.notes.indices where next.notes[index].eventId == id { next.notes[index].eventId = nil; next.notes[index].roundId = nil }
        }
    }
    func saveNote(_ note: ThoughtNote) throws { try note.validate(); try mutate { Self.upsert(note, into: &$0.notes) } }
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
    func saveOnlineSite(_ site: OnlineSite) throws { try site.validate(); try mutate { Self.upsert(site, into: &$0.onlineSites) } }
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
            if join && !event.isParticipating {
                event.isParticipating = true
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
        event.title = site.name; event.kind = .online; event.meetingType = .casual
        event.onlineSiteId = site.id; event.cycleKey = key; event.affiliation = site.affiliation; event.block = site.block
        event.siteUrl = site.url; event.memo = site.memo; event.rounds = [round]; event.isParticipating = join
        if join && !preferences.selfName.isEmpty { event.participants = [preferences.selfName] }
        try saveEvent(event)
        return event
    }
    func ensureCurrentSiteCycles(now: Date = Date()) throws {
        for site in onlineSites where site.recurrence == .weekly { for offset in -1...1 { try createSiteCycle(site.id, weekOf: now, weekOffset: offset, join: false) } }
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
