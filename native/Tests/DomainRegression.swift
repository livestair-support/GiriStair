import Foundation

/// Run on macOS with the production Models/Store/Scheduling files; no mock codec.
@main
struct DomainRegression {
    @MainActor
    static func main() throws {
        var passed = 0
        func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try condition() else { throw GiriDataError.invalid("Regression: \(message)") }
            passed += 1
        }
        func reject(_ data: Data, _ message: String) throws {
            do { _ = try GiriJSON.decode(data) }
            catch { passed += 1; return }
            throw GiriDataError.invalid("Regression accepted invalid input: \(message)")
        }
        let legacy = Data(#"""
        {"schemaVersion":1,"events":[{"id":"legacy","title":"旧データ","kind":"online","meetingType":"tournament","createdAt":"2026-10-29T13:00:00.123456Z","participants":["本人","仲間"],"eventDate":"2026-10-30","submissionStart":"2026-10-29T22:00:00.000","submissionEnd":"2026-11-05T22:00:00.000","votingStart":"2026-11-05T22:00:00.000","votingEnd":"2026-11-12T22:00:00.000","resultText":"予選敗退","placement":null}],"notes":[{"id":"legacy-note","title":"考えた回答","kind":"answers","createdAt":"2026-10-29T13:00:00Z","updatedAt":"2026-10-29T13:00:00Z","body":"旧本文を保持","eventId":"legacy"}]}
        """#.utf8)
        let restored = try GiriJSON.decode(legacy)
        try check(restored.preferences.submissionStartHour == 22 && restored.preferences.submissionStartDayOffset == -1, "legacy preference defaults")
        try check(restored.events[0].effectiveRounds.first?.id == "legacy", "old single window becomes stable legacy round")
        try check(restored.notes[0].body == "旧本文を保持" && restored.notes[0].answers.isEmpty, "old note body stays unsplit")
        try check(GiriDates.calendarString(restored.events[0].eventDate ?? .distantPast) == "2026-10-30", "calendar date stays day-only")
        let encoded = try GiriJSON.encode(restored)
        let encodedString = String(decoding: encoded, as: UTF8.self)
        try check(encodedString.contains("13:00:00.123456Z"), "microsecond timestamp retained")
        let again = try GiriJSON.decode(encoded)
        try check(again == restored, "legacy document roundtrip")
        let local = GiriDates.parse("2026-10-29T22:00:00.000")
        try check(local.map { Calendar.current.component(.hour, from: $0) == 22 } ?? false, "unzoned Dart time stays local")
        try check(GiriDates.parse("2026-02-30", calendarOnly: true) == nil, "invalid calendar day refused")
        try reject(Data(#"{"schemaVersion":2,"events":[],"notes":[]}"#.utf8), "future schema")
        try reject(Data(#"{"schemaVersion":1,"events":[],"notes":[],"players":[{"id":"p","name":"名"},{"id":"p","name":"別"}]}"#.utf8), "duplicate IDs")
        try reject(Data(#"{"schemaVersion":1,"events":[],"notes":[],"venues":[{"id":"v","name":"会場","latitude":35}]}"#.utf8), "unpaired coordinates")
        try reject(Data(#"{"schemaVersion":1,"events":[],"notes":[],"preferences":{"notificationsEnabled":"false"}}"#.utf8), "invalid boolean type")
        try reject(Data(#"{"schemaVersion":1,"events":[],"notes":[],"players":[{"id":"p","name":"ひらがな"},{"id":"q","name":"ヒラガナ"}]}"#.utf8), "normalized duplicate names")

        var round = EventRound()
        round.submissionStart = GiriDates.parse("2026-10-29T22:00:00Z")
        let complete = completeRoundSchedule(round)
        try check(complete.submissionEnd == addCalendarDays(round.submissionStart ?? .distantPast, 7) && complete.votingStart == complete.submissionEnd && complete.votingEnd == addCalendarDays(round.submissionStart ?? .distantPast, 14), "7 plus 7 day derivation")
        var manual = complete
        manual.submissionEnd = GiriDates.parse("2026-11-04T20:00:00Z")
        try check(completeRoundSchedule(manual).submissionEnd == manual.submissionEnd, "manual dates never overwritten")
        let prompt = addNextRound(complete, sameStage: true, defaultStart: Date())
        let stage = addNextRound(complete, sameStage: false, defaultStart: Date())
        try check(prompt.effectiveStageId == complete.effectiveStageId && prompt.promptNumber == 2 && stage.effectiveStageId != complete.effectiveStageId, "prompt cycles independent from next stage")
        var score = ResultStage()
        score.voterCount = 10; score.points = 15; score.maxPointsPerVoter = 3
        try check(score.voteRate == 50, "score denominator uses max points")
        score.voterCount = 0
        try check(score.voteRate == nil, "zero voters have no rate")
        var event = GiriEvent()
        event.meetingType = .tournament
        var result = TournamentResult()
        result.stages = [score]; result.stages[0].outcome = .champion
        event.tournamentResult = result
        var podium = TournamentStanding()
        podium.playerNames = ["別の人"]
        event.standings = [podium]
        try check(event.effectivePlacement == nil && !event.hasFinalResult, "stage wins and podium others do not imply my win")
        event.tournamentResult?.outcome = .champion
        try check(event.effectivePlacement == 1 && event.hasFinalResult, "explicit own final winner")
        var voteOnly = complete
        voteOnly.submissionEnabled = false
        let votingNow = complete.votingStart ?? .distantPast
        try check(!voteOnly.isSubmissionOpen(votingNow) && voteOnly.isVotingOpen(votingNow), "elimination preserves required voting")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("GiriDomain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        try legacy.write(to: temp.appendingPathComponent("giristair.json"))
        let store = GiriStore(directory: temp)
        try check(store.loaded && store.events.count == 1, "loads actual Flutter filename")
        var preferences = store.preferences
        preferences.selfName = "本人"; preferences.onboardingCompleted = true
        try store.savePreferences(preferences)
        try check(try Data(contentsOf: store.migrationBackupURL) == legacy, "first native mutation preserves exact original bytes")
        try store.deleteEvent("legacy")
        try check(store.notes[0].eventId == nil && store.notes[0].roundId == nil && store.notes[0].body == "旧本文を保持", "event deletion retains notes")
        var site = OnlineSite()
        site.name = "週次サイト"; site.recurrence = .weekly; site.weekday = 7
        try store.saveOnlineSite(site)
        let sunday = GiriDates.parse("2026-11-01", calendarOnly: true) ?? Date()
        let preview = try store.createSiteCycle(site.id, weekOf: sunday, join: false)
        let joined = try store.createSiteCycle(site.id, weekOf: sunday, join: true)
        try check(!preview.isParticipating && joined.id == preview.id && store.events.count == 1 && joined.participants == ["本人"], "joining existing site preview is idempotent")
        let secondJoin = try store.createSiteCycle(site.id, weekOf: sunday)
        try check(secondJoin.id == joined.id && secondJoin.participants == ["本人"], "repeated joining does not duplicate self or cycle")
        try check(siteCycleStart(site, weekOf: sunday) == siteCycleStart(site, weekOf: addCalendarDays(sunday, 1)), "Sunday cycle boundary")
        var person = store.playerByName("本人") ?? GiriPlayer(name: "本人")
        var authored = joined
        authored.organizer = "本人"; authored.teams = [GiriTeam(members: ["本人", "仲間"], isMine: true)]
        authored.standings = [TournamentStanding(playerNames: ["本人"])]
        authored.tournamentResult = TournamentResult(members: ["本人"])
        try store.saveEvent(authored)
        person.name = "新しい名前"
        try store.savePlayer(person)
        let renamed = store.events[0]
        try check(renamed.organizer == "新しい名前" && renamed.teams[0].members[0] == "新しい名前" && renamed.standings[0].playerNames[0] == "新しい名前" && store.preferences.selfName == "新しい名前", "rename all identity relations atomically")
        let savedBytes = try Data(contentsOf: store.fileURL)
        let beforeFailedWrite = store.notes
        let blockedBackup = temp.appendingPathComponent("giristair.json.bak")
        if FileManager.default.fileExists(atPath: blockedBackup.path) { try FileManager.default.removeItem(at: blockedBackup) }
        try FileManager.default.createDirectory(at: blockedBackup, withIntermediateDirectories: true)
        var rejectedWrite = false
        do { try store.saveNote(ThoughtNote(title: "保存失敗で追加されない")) } catch { rejectedWrite = true }
        let afterFailedWrite = try Data(contentsOf: store.fileURL)
        try check(rejectedWrite && store.notes == beforeFailedWrite && afterFailedWrite == savedBytes, "durable write failure never publishes mutation")
        try FileManager.default.removeItem(at: blockedBackup)
        var rejectedRestore = false
        do { try store.restoreBackup(Data("{broken".utf8)) } catch { rejectedRestore = true }
        let afterRejectedRestore = try Data(contentsOf: store.fileURL)
        try check(rejectedRestore && afterRejectedRestore == savedBytes, "bad restore does not replace disk")
        let broken = temp.appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        let brokenFile = broken.appendingPathComponent("giristair.json")
        let invalid = Data("not JSON".utf8)
        try invalid.write(to: brokenFile)
        let failed = GiriStore(directory: broken)
        try check(!failed.loaded && failed.errorMessage != nil, "malformed load is visible")
        var rejectedSave = false
        do { try failed.saveEvent(GiriEvent()) } catch { rejectedSave = true }
        let afterRejectedSave = try Data(contentsOf: brokenFile)
        try check(rejectedSave && afterRejectedSave == invalid && !failed.loaded, "load failure disables destructive empty saves")
        try failed.restoreBackup(savedBytes)
        try check(failed.loaded && !failed.events.isEmpty, "explicit valid restore recovers failed load")
        let restoreCopies = try FileManager.default.contentsOfDirectory(atPath: broken.path).filter { $0.hasPrefix("giristair.unreadable-") }
        try check(restoreCopies.count == 1, "restore retains corrupt original separately")
        print("Native domain regressions passed: \(passed)")
    }
}
