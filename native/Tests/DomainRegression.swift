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
        // UI dates keep LiveStair's Gregorian Japanese roles and local day.
        do {
        // Build local fixtures in the same calendar/timezone as the UI. On
        // macOS, changing NSTimeZone.default does not change TimeZone.current.
        let displayCalendar = Calendar(identifier: .gregorian)
        guard let cultureDay = displayCalendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9, minute: 5)),
              let yearBoundary = displayCalendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 0, minute: 5)) else {
            throw GiriDataError.invalid("Could not create local display date fixtures")
        }
        try check(GiriDateText.day(cultureDay) == "2026年11月3日(火祝)", "full date and holiday badge match LiveStair")
        try check(GiriDateText.day(cultureDay, compact: true) == "2026/11/3(火祝)", "narrow list dates retain the year")
        try check(GiriDateText.time(cultureDay) == "9:05", "display hours do not add a leading zero")
        try check(GiriDateText.dateTime(cultureDay) == "11/3(火) 9:05", "deadline text follows ticket schedule format")
        try check(GiriDateText.month(cultureDay) == "2026年11月", "month header uses Japanese year and month")
        try check(GiriDateText.calendarDay(cultureDay) == "11月3日(火祝)", "selected calendar day omits the year")
        try check(GiriDateText.timeRange(nil, cultureDay) == "9:05" && GiriDateText.timeRange(nil, nil) == "--:--", "missing times never become fictitious midnight or duplicated placeholders")
        try check(GiriDateText.day(nil) == "日付未定" && GiriDateText.dateTime(nil) == "未定", "undated records keep their placeholder")
        try check(GiriDateText.day(yearBoundary) == "2027年1月1日(金祝)", "local Gregorian year rollover retains the holiday marker")
        let ordinaryDay = cultureDay.addingTimeInterval(86400)
        try check(GiriDateText.day(ordinaryDay) == "2026年11月4日(水)", "ordinary weekdays have no holiday marker")
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
        // Feature additions remain optional in schema 1 and retain old values.
        try check(restored.events[0].eventFormat == .onlineLong && !restored.events[0].isInterested && restored.events[0].promptedResultKeys.isEmpty, "old online records default to long think without losing participation")
        try check(!restored.preferences.hasShownInitialResultPrompt && !restored.notes[0].isOthersAnswer && !restored.notes[0].usesAnswerRecords, "old preferences and thoughts decode feature defaults")
        try check(EventFormat.allCases.count == 4 && Set(EventFormat.allCases.map(\.rawValue)).count == 4, "four distinct formats remain independently identifiable")
        var feature = GiriEvent(title: "機能検証")
        feature.eventFormat = .onlineShort
        try check(feature.kind == .online && feature.eventFormat == .onlineShort && feature.eventFormat.hasLiveTiming, "short think retains legacy kind and single event timing")
        feature.eventFormat = .hybrid
        try check(feature.eventFormat.hasLiveTiming && feature.eventFormat.hasOnlineRounds, "hybrid supports both its actual schedule parts")
        let now = Date()
        feature.startsAt = now.addingTimeInterval(-3600); feature.endsAt = now.addingTimeInterval(3600)
        try check(feature.participationState(now: now) == .ongoing, "active hybrid is participating now without raw attended")
        feature.isInterested = true
        try check(feature.participationState(now: now) == .interested && !feature.isActualParticipant && !feature.isCountableParticipation(now: now), "interest never counts as attendance")
        feature.isInterested = false; feature.endsAt = now.addingTimeInterval(-60)
        try check(feature.isCountableParticipation(now: now), "participating records automatically become countable after their schedule")
        feature.status = .canceled
        try check(!feature.isActualParticipant && !feature.isCountableParticipation(now: now), "canceled records are excluded from automatic counts")
        var windows = EventRound(name: "予選1回戦")
        windows.submissionStart = now
        windows.submissionEnd = addCalendarDays(now, 3)
        windows.votingStart = addCalendarDays(now, 4)
        windows.votingEnd = addCalendarDays(now, 6)
        let inherited = addNextRound(windows, sameStage: true, defaultStart: .distantPast, submissionDays: 20, votingDays: 30)
        try check(inherited.submissionStart == windows.votingEnd && inherited.submissionEnd == addCalendarDays(windows.votingEnd ?? now, 3), "next cycle inherits actual three-day submission instead of defaults")
        try check(inherited.votingStart == addCalendarDays(windows.votingEnd ?? now, 4) && inherited.votingEnd == addCalendarDays(windows.votingEnd ?? now, 6), "actual vote gap and two-day duration are inherited")
        try check(inherited.effectiveStageId == windows.effectiveStageId && inherited.promptNumber == 2, "same stage cycle increases its occurrence only")
        if let losAngeles = TimeZone(identifier: "America/Los_Angeles") {
            var dstCalendar = Calendar(identifier: .gregorian); dstCalendar.timeZone = losAngeles
            if let before = dstCalendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 22)) {
                var dst = EventRound(); dst.submissionStart = before
                dst.submissionEnd = addCalendarDays(before, 7, calendar: dstCalendar)
                dst.votingStart = dst.submissionEnd
                dst.votingEnd = addCalendarDays(before, 14, calendar: dstCalendar)
                let shifted = addNextRound(dst, defaultStart: before, calendar: dstCalendar)
                try check(shifted.submissionEnd.map { dstCalendar.component(.hour, from: $0) == 22 } ?? false, "weekly durations preserve clock time across daylight saving instead of copying 169 hours")
            }
        }
        var progress = GiriEvent(title: "継続中の大会")
        progress.eventFormat = .onlineLong; progress.meetingType = .tournament
        var endedRound = windows
        endedRound.submissionStart = now.addingTimeInterval(-86400 * 6)
        endedRound.submissionEnd = now.addingTimeInterval(-86400 * 3)
        endedRound.votingStart = endedRound.submissionEnd
        endedRound.votingEnd = now.addingTimeInterval(-60)
        progress.rounds = [endedRound]
        try check(progress.hasEnded(now: now) && progress.endedRoundsNeedingResult(now: now).count == 1, "ended online vote offers the one pending result")
        progress.tournamentResult = TournamentResult(stages: [ResultStage(name: endedRound.name, outcome: .advanced, roundId: endedRound.id, stageId: endedRound.effectiveStageId)])
        try check(!progress.hasEnded(now: now) && progress.participationState(now: now) == .ongoing, "advancement stays ongoing while the next stage is only an unsaved draft")
        var repeated = progress
        var secondRound = endedRound
        secondRound.id = "second-cycle"; secondRound.stageId = endedRound.effectiveStageId; secondRound.promptNumber = 2
        repeated.rounds.append(secondRound)
        repeated.tournamentResult = TournamentResult(stages: [ResultStage(name: endedRound.name, placement: 3, stageId: endedRound.effectiveStageId)])
        try check(repeated.endedRoundsNeedingResult(now: now).count == 2, "a stage-wide rank never suppresses scores for separate repeated rounds")
        repeated.tournamentResult?.stages.append(ResultStage(name: endedRound.name, placement: 2, roundId: endedRound.id, stageId: endedRound.effectiveStageId))
        try check(repeated.endedRoundsNeedingResult(now: now).map(\.id) == [secondRound.id], "a recorded first cycle does not mark its second cycle recorded")
        let roundsBeforeDraft = progress.rounds
        _ = nextEventRound(rounds: progress.rounds, preferences: AppPreferences(), referenceDate: now)
        try check(progress.rounds == roundsBeforeDraft, "preparing an inherited next-stage draft never mutates the saved rounds")
        var oldAnswer = ThoughtNote(id: "old-answer", title: "お題", body: "旧回答A\n旧回答B", answers: ["旧回答A", "旧回答B"])
        let bridged = oldAnswer.effectiveAnswerRecords
        try check(bridged.map(\.text) == oldAnswer.answers && bridged.map(\.id) == oldAnswer.effectiveAnswerRecords.map(\.id), "legacy answer text receives stable editor identities without mutation")
        oldAnswer.answerRecords = [AnswerRecord(id: "submitted-a", text: "提出A", isSubmitted: true, placement: 2, points: 15, voterCount: 10, maxPointsPerVoter: 3), AnswerRecord(id: "submitted-b", text: "提出B", isSubmitted: true), AnswerRecord(id: "rejected", text: "没回答")]
        oldAnswer.usesAnswerRecords = true; oldAnswer.isOthersAnswer = true; oldAnswer.answerer = "回答者"
        try check(oldAnswer.submittedAnswers.count == 2 && oldAnswer.answerRecords[0].voteRate == 50, "multiple submitted answers keep independent rank and weighted vote rate")
        let featureDirectory = temp.appendingPathComponent("features", isDirectory: true)
        let featureStore = GiriStore(directory: featureDirectory)
        try featureStore.saveNote(oldAnswer)
        let savedAnswer = featureStore.notes[0]
        try check(savedAnswer.answers == ["提出A", "提出B", "没回答"] && savedAnswer.isOthersAnswer && savedAnswer.answerer == "回答者", "structured answers synchronize legacy strings and preserve attribution")
        var cleared = savedAnswer; cleared.answerRecords = []
        try featureStore.saveNote(cleared)
        try check(featureStore.notes[0].answers.isEmpty && featureStore.notes[0].effectiveAnswerRecords.isEmpty && featureStore.notes[0].body == oldAnswer.body, "clearing structured answers does not resurrect or delete legacy memo body")
        try featureStore.saveEvent(progress)
        try featureStore.markResultPrompted(eventID: progress.id, key: endedRound.resultPromptKey)
        try featureStore.markResultPrompted(eventID: progress.id, key: endedRound.resultPromptKey)
        var featurePreferences = featureStore.preferences; featurePreferences.hasShownInitialResultPrompt = true
        try featureStore.savePreferences(featurePreferences)
        let reopenedFeatures = GiriStore(directory: featureDirectory)
        try check(reopenedFeatures.preferences.hasShownInitialResultPrompt && reopenedFeatures.events[0].promptedResultKeys == [endedRound.resultPromptKey], "startup and round prompt decisions survive restart without duplicate keys")
        let beforeAtomicResult = try reopenedFeatures.exportBackup()
        var changedResult = progress; changedResult.resultText = "保存されない結果"
        var invalidAnswer = savedAnswer; invalidAnswer.answerRecords[0].placement = 0
        var atomicRejected = false
        do { try reopenedFeatures.saveResult(event: changedResult, notes: [invalidAnswer]) } catch { atomicRejected = true }
        let afterAtomicResult = try reopenedFeatures.exportBackup()
        try check(atomicRejected && afterAtomicResult == beforeAtomicResult, "invalid answer result cannot partially save the event result")
        let rankingSite = OnlineSite(name: "所属の変わるサイト", recurrence: .weekly, affiliation: "一部", hasAffiliations: true)
        try reopenedFeatures.saveOnlineSite(rankingSite)
        let currentCycle = try reopenedFeatures.createSiteCycle(rankingSite.id, weekOf: now)
        let nextPreview = try reopenedFeatures.createSiteCycle(rankingSite.id, weekOf: now, weekOffset: 1, join: false)
        var rankedCycle = currentCycle; rankedCycle.cyclePlacement = 3; rankedCycle.cycleResult = "昇格"
        try reopenedFeatures.saveCycleResult(event: rankedCycle, nextAffiliation: "上位部")
        try check(reopenedFeatures.events.first { $0.id == currentCycle.id }?.affiliation == "一部" && reopenedFeatures.onlineSites.first { $0.id == rankingSite.id }?.affiliation == "上位部", "cycle result preserves historical affiliation while updating next default")
        try check(reopenedFeatures.events.first { $0.id == nextPreview.id }?.affiliation == "上位部", "unjoined next-week preview receives the changed affiliation")
        let joinedNext = try reopenedFeatures.createSiteCycle(rankingSite.id, weekOf: now, weekOffset: 1)
        try reopenedFeatures.saveCycleResult(event: rankedCycle, nextAffiliation: "古い結果の変更")
        try check(reopenedFeatures.events.first { $0.id == joinedNext.id }?.affiliation == "上位部" && reopenedFeatures.onlineSites.first { $0.id == rankingSite.id }?.affiliation == "上位部", "editing an older result cannot rewrite later joined affiliation or current default")
        let featureRoundtrip = try GiriJSON.decode(reopenedFeatures.exportBackup())
        try check(featureRoundtrip == reopenedFeatures.document, "new optional fields roundtrip with schema one and all legacy values")
        var remindersPreferences = AppPreferences(notificationsEnabled: true)
        remindersPreferences.reminderMinutes = 0
        var remindersEvent = GiriEvent(title: "ハイブリッド通知")
        remindersEvent.eventFormat = .hybrid; remindersEvent.startsAt = now.addingTimeInterval(10800)
        var reminderRound = EventRound(); reminderRound.submissionEnd = now.addingTimeInterval(86400); reminderRound.votingEnd = now.addingTimeInterval(172800)
        remindersEvent.rounds = [reminderRound]
        let allReminders = planNativeReminders(events: [remindersEvent], preferences: remindersPreferences, now: now)
        try check(allReminders.count == 3 && allReminders.contains { $0.id.hasSuffix(":start") } && allReminders.contains { $0.id.hasSuffix(":submission") } && allReminders.contains { $0.id.hasSuffix(":voting") }, "hybrid schedules its start plus posting and voting reminders")
        remindersEvent.isInterested = true
        try check(planNativeReminders(events: [remindersEvent], preferences: remindersPreferences, now: now).isEmpty, "interested events never schedule participant reminders")
        remindersEvent.isInterested = false; remindersEvent.rounds[0].submissionEnabled = false
        let voteReminders = planNativeReminders(events: [remindersEvent], preferences: remindersPreferences, now: now)
        try check(voteReminders.count == 2 && voteReminders.contains { $0.id.hasSuffix(":voting") } && !voteReminders.contains { $0.id.hasSuffix(":submission") }, "elimination retains required voting and removes posting reminder")
        let nearestReminder = planNativeReminders(events: [remindersEvent], preferences: remindersPreferences, now: now, limit: 1)
        try check(nearestReminder.count == 1 && nearestReminder[0].id.hasSuffix(":start"), "notification cap retains the nearest eligible item")

        print("Native domain regressions passed: \(passed)")
    }
}
