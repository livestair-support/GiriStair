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
        // 参加費と使わない形式は任意項目。旧JSONは未入力・全形式表示のまま読む。
        try check(restored.events[0].entryFee == nil && restored.preferences.hiddenFormats.isEmpty, "documents without fee or hidden formats keep their defaults")
        var feeDocument = restored
        feeDocument.events[0].entryFee = 1500
        feeDocument.preferences.hiddenFormats = [.hybrid]
        let feeRoundTrip = try GiriJSON.decode(GiriJSON.encode(feeDocument))
        try check(feeRoundTrip.events[0].entryFee == 1500 && feeRoundTrip.preferences.hiddenFormats == [.hybrid], "entry fee and hidden formats survive backup and restore")
        try check(feeRoundTrip.preferences.visibleFormatOrder == [.live, .onlineLong, .onlineShort], "hidden formats leave the tabs while keeping the saved order")
        var allHidden = AppPreferences(); allHidden.hiddenFormats = EventFormat.allCases
        try check(allHidden.visibleFormatOrder == EventFormat.allCases, "an all-hidden value never empties the format tabs")
        var liveHidden = AppPreferences(); liveHidden.hiddenFormats = [.live]
        try check(!liveHidden.formatChoices(including: nil).contains(.live) && liveHidden.formatChoices(including: .live).last == .live, "a record of a hidden format keeps its own format as a choice")
        var freeEvent = GiriEvent(); freeEvent.entryFee = 0
        try check((try? freeEvent.validate()) != nil, "a free event (0 yen) is valid")
        try check(restored.events[0].hashtag.isEmpty, "documents without a hashtag keep it empty")
        try check(giriNormalizedHashtag(" ＃大喜利 文化杯Ω ") == "大喜利文化杯Ω" && giriNormalizedHashtag("##吉永対策会") == "吉永対策会", "hashtags are stored without # and spaces")
        try reject(Data(#"{"schemaVersion":1,"events":[{"id":"fee","title":"負","kind":"live","meetingType":"casual","createdAt":"2026-10-29T13:00:00Z","entryFee":-1}],"notes":[]}"#.utf8), "negative entry fee")
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
        oldAnswer.usesAnswerRecords = true
        try check(oldAnswer.submittedAnswers.count == 2 && oldAnswer.answerRecords[0].voteRate == 50 && oldAnswer.answerRecords[0].pointsPerVoter == 1.5, "multiple submitted answers keep independent rank, weighted vote rate and points per voter")
        oldAnswer.isOthersAnswer = true; oldAnswer.answerer = "回答者"
        // 0.8：旧「他人の回答」メモは、その人の回答（ツボ）として読み、自分の提出には数えない。
        try check(oldAnswer.submittedAnswers.isEmpty && oldAnswer.otherAnswerRecords.count == 3 && oldAnswer.otherAnswerRecords.allSatisfy { $0.answerer == "回答者" }, "a legacy other-person note is read as that person's answers, not one's submissions")
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

        // 0.6 recurring sites: independent cadence, explicit seasonal exceptions,
        // and league decisions with dates instead of inferred site algorithms.
        do {
            let anchor = GiriDates.parse("2026-01-01T22:00:00Z") ?? Date()
            func day(_ offset: Int) -> Date { addCalendarDays(anchor, offset) }
            var serial = OnlineSite(name: "交互サイト", recurrence: .weekly)
            serial.submissionDays = 7; serial.votingDays = 7
            serial.cycleSettings = SiteCycleSettings(pattern: .alternating, anchorStart: anchor, intervalDays: 14)
            let serialVote = siteCycleDescriptors(serial, around: day(8)).filter { $0.isActive(day(8)) }
            try check(serialVote.count == 1 && serialVote[0].round.isVotingOpen(day(8)) && !serialVote[0].round.isSubmissionOpen(day(8)), "serial seven plus seven has only the previous vote in week two")
            let serialNext = siteCycleDescriptors(serial, around: day(15)).filter { $0.round.isSubmissionOpen(day(15)) }
            try check(serialNext.count == 1 && serialNext[0].cycleNumber == 2 && serialNext[0].start == day(14), "alternating cadence starts the next prompt after fourteen days")
            var overlap = serial
            overlap.id = "overlap-seven"; overlap.cycleSettings?.pattern = .overlapping; overlap.cycleSettings?.intervalDays = 7
            let overlapActive = siteCycleDescriptors(overlap, around: day(8)).filter { $0.isActive(day(8)) }
            try check(overlapActive.count == 2 && overlapActive.contains { $0.round.isSubmissionOpen(day(8)) } && overlapActive.contains { $0.round.isVotingOpen(day(8)) }, "overlap seven plus seven shows old voting and new posting together")
            overlap.votingDays = 3
            let shortVote = siteCycleDescriptors(overlap, around: day(8)).filter { $0.isActive(day(8)) }
            try check(shortVote.count == 2, "weekly posting with three-day voting still shows both active phases")
            let afterVote = siteCycleDescriptors(overlap, around: day(11)).filter { $0.isActive(day(11)) }
            try check(afterVote.count == 1 && afterVote[0].round.isSubmissionOpen(day(11)), "three-day vote ends before that week's posting ends")
            var startingNow = overlap
            startingNow.cycleSettings?.anchorStart = day(7)
            let unknownPrevious = siteCycleDescriptors(startingNow, around: day(8)).filter { $0.round.isVotingOpen(day(8)) }
            try check(unknownPrevious.count == 1 && unknownPrevious[0].cycleNumber == nil && unknownPrevious[0].title == "前の回", "nonseason registration at cycle one still retains an already ongoing preceding vote")

            var season = overlap
            season.id = "season-ten-weeks"; season.hasAffiliations = true; season.affiliation = "二部"
            season.cycleSettings = SiteCycleSettings(pattern: .overlapping, anchorStart: day(28), intervalDays: 7, anchorCycleNumber: 5, seasonName: "第12シーズン", seasonStart: anchor, seasonLengthDays: 70, regularCycleCount: 9, leagues: ["一部", "二部"], leagueChangesPerSeason: true, seasonEndsAt: day(70))
            let middle = siteCycleDescriptors(season, around: day(29)).filter { $0.round.isSubmissionOpen(day(29)) }
            try check(middle.count == 1 && middle[0].cycleNumber == 5 && middle[0].seasonName == "第12シーズン", "registering midseason retains the actual fifth cycle and season name")
            var finalPrompt = EventRound(name: "短縮された最終お題")
            finalPrompt.promptNumber = 9
            finalPrompt.submissionStart = day(56); finalPrompt.submissionEnd = day(59).addingTimeInterval(43200)
            finalPrompt.votingStart = finalPrompt.submissionEnd; finalPrompt.votingEnd = day(62).addingTimeInterval(43200)
            var playoffRound = EventRound(name: "プレーオフ")
            playoffRound.submissionStart = day(63); playoffRound.submissionEnd = day(66)
            playoffRound.votingStart = day(67); playoffRound.votingEnd = day(70)
            let shortFinal = SiteSpecialPeriod(id: "final-short", title: "最終お題", kind: .regular, round: finalPrompt)
            let playoff = SiteSpecialPeriod(id: "playoff", title: "プレーオフ", kind: .playoff, round: playoffRound)
            season.cycleSettings?.specialPeriods = [shortFinal, playoff]
            let finalPeriods = siteCycleDescriptors(season, around: day(60))
            try check(finalPeriods.filter { $0.start == day(56) }.count == 1 && finalPeriods.first { $0.cycleKey == "special:final-short" }?.cycleNumber == 9, "shortened ninth prompt replaces its regular template without duplication")
            try check(finalPeriods.first { $0.cycleKey == "special:final-short" }?.round.submissionEnd == finalPrompt.submissionEnd, "half-week custom timestamps remain exact rather than rounded to whole weeks")
            try check(!siteCycleDescriptors(season, around: day(65)).contains { $0.kind == .regular && ($0.cycleNumber ?? 0) > 9 }, "nine regular rounds do not fabricate a tenth regular round in special weeks")
            let firstPlayoff = siteCycleDescriptors(season, around: day(67)).first { $0.kind == .playoff }
            let laterPlayoff = siteCycleDescriptors(season, around: day(69)).first { $0.kind == .playoff }
            try check(firstPlayoff?.cycleKey == laterPlayoff?.cycleKey && firstPlayoff?.round.id == laterPlayoff?.round.id, "special period identities stay stable across refreshes")
            try check(firstPlayoff?.round.votingStart == day(67), "special submission and voting windows can have independent gaps")
            try check(!siteCycleDescriptors(season, around: day(75)).contains { $0.kind == .regular && $0.isActive(day(75)) }, "a finished season never silently creates regular rounds for a guessed next season")

            var replacementSeason = season
            replacementSeason.id = "six-week-site"
            replacementSeason.cycleSettings = SiteCycleSettings(pattern: .overlapping, anchorStart: anchor, intervalDays: 7, seasonName: "第3期", seasonStart: anchor, seasonLengthDays: 42, regularCycleCount: 5, leagues: ["一部", "二部"], leagueChangesPerSeason: true, seasonEndsAt: day(42))
            var replacements: [SiteSpecialPeriod] = []
            for index in 0..<3 {
                var special = EventRound(name: "入れ替え戦\(index + 1)")
                special.submissionStart = day(32 + index * 2); special.submissionEnd = day(34 + index * 2)
                special.votingStart = day(36 + index * 2); special.votingEnd = day(38 + index * 2)
                replacements.append(SiteSpecialPeriod(id: "replacement-\(index)", title: special.name, kind: .replacement, round: special))
            }
            replacementSeason.cycleSettings?.specialPeriods = replacements
            let specialWindows = siteCycleDescriptors(replacementSeason, around: day(36)).filter { $0.kind == .replacement }
            try check(specialWindows.count == 3 && Set(specialWindows.map(\.cycleKey)).count == 3, "six-week season supports three independent replacement-match posting windows")
            try check(!siteCycleDescriptors(replacementSeason, around: day(38)).contains { $0.kind == .regular && ($0.cycleNumber ?? 0) > 5 }, "replacement weeks are not mistaken for sixth regular rounds")
            try check(siteLeagueAfterMovement(season, from: "二部", movement: .promoted) == "一部" && siteLeagueAfterMovement(season, from: "一部", movement: .relegated) == "二部", "ordered league names determine the next confirmed promotion or relegation")
            try check(siteLeagueAfterMovement(season, from: "一部", movement: .promoted) == nil, "promotion above the top league does not wrap around")

            let siteDirectory = temp.appendingPathComponent("site-seasons", isDirectory: true)
            let seasonStore = GiriStore(directory: siteDirectory)
            try seasonStore.saveOnlineSite(season)
            guard let descriptor = siteCycleDescriptors(season, around: day(29)).first(where: { $0.cycleNumber == 5 }) else { throw GiriDataError.invalid("Missing season fixture") }
            let seasonPreview = try seasonStore.createSiteCycle(season.id, descriptor: descriptor, join: false)
            let seasonJoined = try seasonStore.createSiteCycle(season.id, descriptor: descriptor, join: true)
            try check(seasonPreview.id == seasonJoined.id && seasonJoined.siteSeason == "第12シーズン" && seasonJoined.siteCycleNumber == 5 && seasonJoined.affiliation == "二部", "joining preserves cycle identity and snapshots the season and league")
            try check(seasonJoined.siteSeasonEnd == day(70), "season boundary is snapshotted for later result edits")
            var qualificationOnly = seasonJoined; qualificationOnly.siteQualification = .replacement
            try seasonStore.saveCycleResult(event: qualificationOnly)
            try check(qualificationOnly.hasCycleResult && !seasonStore.onlineSites[0].leagueChanges.contains { $0.sourceEventID == seasonJoined.id } && siteLeague(seasonStore.onlineSites[0], at: day(71)) == "二部", "replacement qualification counts as a result without implying promotion")
            var promotion = qualificationOnly; promotion.leagueMovement = .promoted; promotion.nextLeagueEffectiveDate = day(70)
            try seasonStore.saveCycleResult(event: promotion, nextAffiliation: "一部")
            let promotedSite = seasonStore.onlineSites[0]
            try check(siteLeague(promotedSite, at: day(69)) == "二部" && siteLeague(promotedSite, at: day(70)) == "一部", "seasonal promotion applies at the confirmed boundary rather than immediately")
            var undo = promotion; undo.leagueMovement = .unchanged; undo.nextAffiliation = ""; undo.nextLeagueEffectiveDate = nil
            try seasonStore.saveCycleResult(event: undo)
            try check(!seasonStore.onlineSites[0].leagueChanges.contains { $0.sourceEventID == seasonJoined.id } && siteLeague(seasonStore.onlineSites[0], at: day(71)) == "二部", "undoing the only promotion removes its pending assignment and restores the baseline")
            try seasonStore.saveCycleResult(event: promotion, nextAffiliation: "一部")
            var renamedSeason = seasonStore.onlineSites[0]
            renamedSeason.cycleSettings?.seasonName = "第13シーズン"
            renamedSeason.cycleSettings?.seasonID = UUID().uuidString
            renamedSeason.cycleSettings?.seasonStart = day(70)
            renamedSeason.cycleSettings?.anchorStart = day(70); renamedSeason.cycleSettings?.anchorCycleNumber = 1
            renamedSeason.affiliation = "二部"
            try seasonStore.saveOnlineSite(renamedSeason)
            let historicalJoined = seasonStore.events.first { $0.id == seasonJoined.id }
            try check(historicalJoined?.siteSeason == "第12シーズン" && historicalJoined?.affiliation == "二部" && historicalJoined?.siteSeasonEnd == day(70), "starting another season never rewrites joined historical season and league")
            let editedDescriptor = SiteCycleDescriptor(cycleKey: descriptor.cycleKey, round: playoffRound, seasonName: "上書き禁止", cycleNumber: 99, kind: .other, title: "上書き禁止")
            let stillJoined = try seasonStore.createSiteCycle(season.id, descriptor: editedDescriptor)
            try check(stillJoined.rounds == seasonJoined.rounds && stillJoined.siteSeason == seasonJoined.siteSeason, "refreshing a joined cycle never overwrites its individually edited dates or snapshots")
            let specialPreview = try seasonStore.createSiteCycle(season.id, descriptor: firstPlayoff ?? descriptor, join: false)
            let specialJoined = try seasonStore.createSiteCycle(season.id, descriptor: laterPlayoff ?? descriptor)
            try check(specialPreview.id == specialJoined.id, "joining the same explicit special window is idempotent")
            let serialized = try seasonStore.exportBackup()
            try check(try GiriJSON.decode(serialized) == seasonStore.document, "season settings, special windows, league history and snapshots roundtrip in schema one")
            var irregular = replacementSeason; irregular.id = "irregular-site"; irregular.recurrence = .irregular
            let irregularWindows = siteCycleDescriptors(irregular, around: day(36))
            try check(irregularWindows.count == 3 && irregularWindows.allSatisfy { $0.kind == .replacement }, "irregular sites expose explicit periods without fabricating weekly regular cycles")
            guard let customDescriptor = siteCycleDescriptors(overlap, around: day(8)).first else { throw GiriDataError.invalid("Missing customized preview fixture") }
            try seasonStore.saveOnlineSite(overlap)
            var customPreview = try seasonStore.createSiteCycle(overlap.id, descriptor: customDescriptor, join: false)
            customPreview.rounds[0].votingEnd = day(30); customPreview.siteScheduleCustomized = true
            try seasonStore.saveEvent(customPreview)
            let refreshedPreview = try seasonStore.createSiteCycle(overlap.id, descriptor: customDescriptor, join: false)
            try check(refreshedPreview.rounds[0].votingEnd == day(30) && !refreshedPreview.isActualParticipant, "explicit edits to an unjoined preview survive automatic schedule refresh")
            var deletionSite = season; deletionSite.id = "delete-promotion"; deletionSite.leagueChanges = []; deletionSite.leagueBaseline = nil
            try seasonStore.saveOnlineSite(deletionSite)
            let deletionEvent = try seasonStore.createSiteCycle(deletionSite.id, descriptor: descriptor)
            var toDelete = deletionEvent; toDelete.leagueMovement = .promoted; toDelete.nextLeagueEffectiveDate = day(70)
            try seasonStore.saveCycleResult(event: toDelete, nextAffiliation: "一部")
            try seasonStore.deleteEvent(toDelete.id)
            guard let deletedResultSite = seasonStore.onlineSites.first(where: { $0.id == deletionSite.id }) else { throw GiriDataError.invalid("Missing delete site") }
            try check(!deletedResultSite.leagueChanges.contains { $0.sourceEventID == toDelete.id } && siteLeague(deletedResultSite, at: day(71)) == "二部", "deleting a result removes its scheduled promotion without clearing unrelated season history")
            var noPostsSite = season; noPostsSite.id = "season-without-posts"; noPostsSite.leagueChanges = []; noPostsSite.leagueBaseline = nil
            try seasonStore.saveOnlineSite(noPostsSite)
            noPostsSite = seasonStore.onlineSites.first { $0.id == noPostsSite.id } ?? noPostsSite
            noPostsSite.cycleSettings?.seasonID = UUID().uuidString
            noPostsSite.cycleSettings?.seasonName = "第13シーズン"; noPostsSite.cycleSettings?.seasonStart = day(70); noPostsSite.cycleSettings?.anchorStart = day(70); noPostsSite.cycleSettings?.anchorCycleNumber = 1
            noPostsSite.affiliation = "一部"
            try seasonStore.saveOnlineSite(noPostsSite)
            let noPostsHistory = seasonStore.onlineSites.first { $0.id == noPostsSite.id }?.leagueChanges ?? []
            try check(noPostsHistory.contains { $0.seasonName == "第12シーズン" && $0.toLeague == "二部" } && noPostsHistory.contains { $0.seasonName == "第13シーズン" && $0.toLeague == "一部" }, "season league history survives a new season even without any joined posts")
            var customOrder = AppPreferences(); customOrder.formatOrder = [.onlineLong, .onlineLong, .hybrid]
            try check(customOrder.effectiveFormatOrder == [.onlineLong, .hybrid, .live, .onlineShort], "format preference removes duplicates while retaining all four categories")
            try seasonStore.savePreferences(customOrder)
            try check(seasonStore.preferences.formatOrder == customOrder.effectiveFormatOrder, "saved format order is normalized")
            var hideAll = seasonStore.preferences; hideAll.hiddenFormats = EventFormat.allCases
            var refusedHideAll = false
            do { try seasonStore.savePreferences(hideAll) } catch { refusedHideAll = true }
            try check(refusedHideAll && seasonStore.preferences.hiddenFormats.isEmpty, "at least one format stays in use")
            var hideSome = seasonStore.preferences; hideSome.hiddenFormats = [.hybrid, .onlineShort, .hybrid]
            try seasonStore.savePreferences(hideSome)
            try check(seasonStore.preferences.hiddenFormats == [.onlineShort, .hybrid], "hidden formats are stored once in a stable order")
            hideSome.hiddenFormats = []
            try seasonStore.savePreferences(hideSome)
            try check(EventFormat.hybrid.rawValue == "hybrid" && EventFormat.hybrid.title == "スプシ系", "the spreadsheet category keeps the legacy hybrid raw value")
            var categorized = ThoughtNote(title: "分類", kind: .answers); categorized.answerCategory = "long"
            try seasonStore.saveNote(categorized)
            try check(try GiriJSON.decode(seasonStore.exportBackup()).notes.last?.answerCategory == "long", "standalone answer category survives backup and restore")
        }

        // 0.7 season identity and rules are independent of arbitrary names,
        // global prompt numbers and unknown historical boundaries.
        do {
            let anchor = GiriDates.parse("2026-10-29T22:00:00Z") ?? Date()
            func day(_ offset: Int) -> Date { addCalendarDays(anchor, offset) }
            var site = OnlineSite(id: "stable-season", name: "更新されたサイト", recurrence: .weekly)
            site.submissionDays = 7; site.votingDays = 3
            site.hasAffiliations = true; site.affiliation = "二部"
            site.cycleSettings = SiteCycleSettings(pattern: .overlapping, anchorStart: anchor, intervalDays: 7,
                anchorCycleNumber: 38, seasonName: "秋の陣", seasonLengthDays: 1, regularCycleCount: 8,
                leagues: ["一部", "二部"], leagueChangesPerSeason: true, trackSeasonTotals: true)
            let periods = siteCycleDescriptors(site, around: day(1))
            try check(periods.contains { $0.cycleNumber == 38 && $0.round.isSubmissionOpen(day(1)) }, "global prompt 38 is not blocked by an old eight-round cap")
            try check(!periods.contains { ($0.start ?? anchor) < anchor } && site.cycleSettings?.seasonEnd == nil, "unknown season boundaries are not reconstructed from current rules or legacy length")
            let legacySettings = SiteCycleSettings(pattern: .overlapping, anchorStart: anchor, intervalDays: 7,
                anchorCycleNumber: 38, seasonName: "秋の陣", seasonStart: day(-259), seasonLengthDays: 1, regularCycleCount: 8)
            let repairedSettings = try JSONDecoder().decode(SiteCycleSettings.self, from: JSONEncoder().encode(legacySettings))
            try check(repairedSettings.seasonStart == nil && repairedSettings.legacyInferredSeasonStart == day(-259) && repairedSettings.regularCycleCount == nil && repairedSettings.seasonLengthDays == 1, "recognizable legacy reverse-inferred date is cleared while its deprecated length is retained")
            var manualStart = legacySettings; manualStart.seasonStart = day(-200)
            let retainedStart = try JSONDecoder().decode(SiteCycleSettings.self, from: JSONEncoder().encode(manualStart))
            try check(retainedStart.seasonStart == day(-200), "explicit historical dates different from the old formula are preserved")
            var oldEvent = GiriEvent(title: "古い自動終了日")
            oldEvent.eventFormat = .onlineLong; oldEvent.siteSeasonEnd = day(70)
            let repairedEvent = try GiriJSON.decode(GiriJSON.encode(GiriDocument(events: [oldEvent]))).events[0]
            try check(repairedEvent.siteSeasonEnd == nil && repairedEvent.legacyInferredSeasonEnd == day(70), "old generated season end is retained for compatibility without becoming a confirmed promotion date")

            let directory = temp.appendingPathComponent("season-rules-07", isDirectory: true)
            let rulesStore = GiriStore(directory: directory)
            try rulesStore.saveOnlineSite(site)
            guard let saved = rulesStore.onlineSites.first, let settings = saved.cycleSettings,
                  let seasonID = settings.seasonID, let firstRuleID = settings.ruleRevisionID,
                  let first = siteCycleDescriptors(saved, around: day(1)).first(where: { $0.cycleNumber == 38 }) else {
                throw GiriDataError.invalid("Missing stable season fixture")
            }
            let joined = try rulesStore.createSiteCycle(saved.id, descriptor: first)
            try check(joined.siteSeasonID == seasonID && joined.siteRuleRevisionID == firstRuleID && joined.siteSeasonStart == nil && joined.siteSeasonEnd == nil, "joined snapshots use stable identity and preserve unknown bounds")
            var promotion = joined; promotion.leagueMovement = .promoted
            var unknownDateRejected = false
            do { try rulesStore.saveCycleResult(event: promotion, nextAffiliation: "一部") } catch { unknownDateRejected = true }
            try check(unknownDateRejected && rulesStore.events[0].leagueMovement == .unchanged, "seasonal promotion with unknown boundary requires an explicit date and cannot partially save")
            promotion.nextLeagueEffectiveDate = day(14)
            try rulesStore.saveCycleResult(event: promotion, nextAffiliation: "一部")
            try check(siteLeague(rulesStore.onlineSites[0], at: day(13)) == "二部" && siteLeague(rulesStore.onlineSites[0], at: day(14)) == "一部", "explicit league effective dates work without a season start or length")
            var changed = rulesStore.onlineSites[0]
            changed.cycleSettings?.anchorStart = day(7); changed.cycleSettings?.anchorCycleNumber = 39
            changed.submissionDays = 3; changed.votingDays = 2
            try rulesStore.saveOnlineSite(changed)
            let revised = rulesStore.onlineSites[0]
            try check(revised.cycleSettings?.seasonID == seasonID && revised.cycleSettings?.ruleRevisionID != firstRuleID && revised.ruleHistory.count == 1, "changing posting rules creates a rule revision inside the same season")
            let overlap = siteCycleDescriptors(revised, around: day(8))
            try check(overlap.contains { $0.ruleRevisionID == firstRuleID && $0.round.isVotingOpen(day(8)) && $0.round.votingEnd == day(10) }, "the previous rule's ongoing vote keeps its original duration")
            try check(overlap.contains { $0.cycleNumber == 39 && $0.round.submissionStart == day(7) && $0.round.submissionEnd == day(10) }, "the new rule applies from its known current period")
            try check(rulesStore.events.first { $0.id == joined.id }?.rounds == joined.rounds, "a midseason rule change never rewrites joined dates")
            var renamed = revised; renamed.cycleSettings?.seasonName = "紅葉大会"
            try rulesStore.saveOnlineSite(renamed)
            try check(rulesStore.onlineSites[0].cycleSettings?.seasonID == seasonID && rulesStore.onlineSites[0].ruleHistory.count == 1, "renaming an arbitrary season does not split its identity or add a timing revision")
            var nextSeason = rulesStore.onlineSites[0]
            nextSeason.cycleSettings?.seasonID = "another-season"; nextSeason.cycleSettings?.seasonName = "紅葉大会"
            nextSeason.cycleSettings?.anchorStart = day(30)
            try rulesStore.saveOnlineSite(nextSeason)
            try check(rulesStore.onlineSites[0].cycleSettings?.seasonID == "another-season" && rulesStore.events.first { $0.id == joined.id }?.siteSeasonID == seasonID, "seasons with the same display name remain distinct and retain historical results")
            try check(try GiriJSON.decode(rulesStore.exportBackup()) == rulesStore.document, "rule histories, explicit bounds and stable season identities roundtrip in schema one")

            var event = joined; event.id = "answer-stats"; event.siteSeasonID = "stats-season"; event.siteSeason = "秋の陣"
            var round = first.round; round.id = "stats-round"; event.rounds = [round]
            var result = ResultStage(roundId: round.id); result.points = 90; result.voterCount = 100
            event.tournamentResult = TournamentResult(stages: [result])
            var own = ThoughtNote(id: "own-stats", title: "お題", eventId: event.id, roundId: round.id)
            own.answerRecords = [AnswerRecord(text: "回答A", isSubmitted: true, points: 1, voterCount: 4), AnswerRecord(text: "回答B", isSubmitted: true, points: 75, voterCount: 100), AnswerRecord(text: "得票率未記録", isSubmitted: true), AnswerRecord(text: "没案", isSubmitted: false, points: 100, voterCount: 100)]
            own.usesAnswerRecords = true
            var others = own; others.id = "other-stats"; others.isOthersAnswer = true; others.answerer = "別の人"
            var canceled = event; canceled.id = "canceled-stats"; canceled.status = .canceled
            var canceledNote = own; canceledNote.id = "canceled-note"; canceledNote.eventId = canceled.id
            var future = event; future.id = "unjoined-stats"; future.isParticipating = false
            var futureNote = own; futureNote.id = "future-note"; futureNote.eventId = future.id
            var otherSeason = event; otherSeason.id = "other-season-stats"; otherSeason.siteSeasonID = "other-id"
            var otherSeasonNote = own; otherSeasonNote.id = "other-season-note"; otherSeasonNote.eventId = otherSeason.id
            let totals = giriSeasonTotals(siteID: site.id, seasonID: "stats-season", seasonName: "秋の陣", events: [event, canceled, future, otherSeason], notes: [own, others, canceledNote, futureNote, otherSeasonNote])
            try check(totals.submittedAnswerCount == 3 && totals.scoredAnswerCount == 2 && totals.legacyRoundResultCount == 0, "season totals count submitted own answers only and avoid double-counting their round result")
            try check(totals.averageVoteRate == 50, "each answer rate has equal weight regardless of its voter count and unknown scores are excluded")
            let legacyTotals = giriSeasonTotals(siteID: site.id, seasonID: "stats-season", seasonName: "秋の陣", events: [event], notes: [])
            try check(legacyTotals.submittedAnswerCount == 0 && legacyTotals.scoredAnswerCount == 0 && legacyTotals.legacyRoundResultCount == 1 && legacyTotals.averageVoteRate == 90, "legacy round rates are labelled separately without inventing an answer count")
            let emptyTotals = giriSeasonTotals(siteID: site.id, seasonID: "absent", seasonName: "別シーズン", events: [event], notes: [own])
            try check(emptyTotals.rateSampleCount == 0 && emptyTotals.averageVoteRate == nil, "unknown season rates remain unavailable rather than becoming zero")

            var chartCalendar = Calendar(identifier: .gregorian); chartCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
            var chartEvent = GiriEvent(title: "1件だけの月別")
            chartEvent.startsAt = anchor
            let chart = giriMonthlySeries(events: [chartEvent], year: 2026, calendar: chartCalendar, now: anchor)
            try check(chart.months.count == 12 && chart.values.count == 48 && chart.values.reduce(0, { $0 + $1.count }) == 1, "one-record charts still include twelve months and all four formats")
            try check(chart.maximum == 1 && chartCalendar.component(.year, from: chart.end) == 2027 && chartCalendar.component(.month, from: chart.end) == 1, "monthly chart bounds and integer maximum are stable for a single record")
            var secondChartEvent = chartEvent; secondChartEvent.id = "second-chart"; secondChartEvent.eventFormat = .onlineLong
            let mixedChart = giriMonthlySeries(events: [chartEvent, secondChartEvent], year: 2026, calendar: chartCalendar, now: anchor)
            try check(mixedChart.maximum == 2 && mixedChart.values.filter { $0.count > 0 }.count == 2, "monthly chart keeps distinct format series and a stacked integer total")
        }

        // 0.8 results, prompts with several people's answers, and self aliases.
        do {
            // A pre-0.8 "other person's answer" note reads as that person's answers.
            let legacyOther = try GiriJSON.decode(Data(#"""
            {"schemaVersion":1,"events":[],"notes":[{"id":"o","title":"お題","kind":"answers","createdAt":"2026-10-29T13:00:00Z","updatedAt":"2026-10-29T13:00:00Z","prompt":"お題","answers":["面白い回答"],"isOthersAnswer":true,"answerer":"仲間"}]}
            """#.utf8)).notes[0]
            try check(legacyOther.otherAnswerRecords.map(\.answerer) == ["仲間"] && legacyOther.ownAnswerRecords.isEmpty && legacyOther.submittedAnswers.isEmpty, "legacy other-person notes become that person's answers without counting as submitted")
            try check(legacyOther.referencedPeople == ["仲間"] && legacyOther.promptAuthor.isEmpty && legacyOther.format == nil && legacyOther.memo.isEmpty, "legacy notes keep empty author, format and memo")

            var prompt = ThoughtNote(title: "お題", kind: .answers)
            prompt.prompt = "お題"; prompt.promptAuthor = "作題者"; prompt.usesAnswerRecords = true
            prompt.answerRecords = [AnswerRecord(id: "mine", text: "自分", isSubmitted: true, points: 187, voterCount: 159),
                                    AnswerRecord(id: "draft", text: "ボツ"),
                                    AnswerRecord(id: "theirs", text: "ツボ", isSubmitted: true, answerer: "仲間")]
            try check(prompt.submittedAnswers.map(\.id) == ["mine"] && prompt.otherAnswerRecords.map(\.id) == ["theirs"], "only one's own marked answers count as submitted")
            try check(abs((prompt.answerRecords[0].pointsPerVoter ?? 0) - 187.0 / 159.0) < 0.000001 && giriScoreText(187.0 / 159.0) == "1.18", "points per voter match the site's bracketed value")
            try check(Set(prompt.referencedPeople) == ["作題者", "仲間"], "authors and answerers join the player directory")
            let promptRoundTrip = try GiriJSON.decode(GiriJSON.encode(GiriDocument(notes: [prompt]))).notes[0]
            try check(promptRoundTrip == prompt, "per-answer answerers and authors survive backup")

            // Stage text, elimination title and the final result choices.
            var tournament = GiriEvent(title: "大会")
            tournament.meetingType = .tournament
            var qualifier = ResultStage(); qualifier.name = "予選"; qualifier.outcome = .advanced; qualifier.placement = 1
            var main = ResultStage(); main.name = "本戦1回戦"; main.outcome = .eliminated
            var result = TournamentResult(); result.stages = [qualifier, main]; result.outcome = .eliminated
            tournament.tournamentResult = result
            try check(giriStageResultText(qualifier) == "予選1位通過" && tournament.eliminationTitle == "本戦1回戦敗退", "stage names make advancement and elimination labels")
            try check(tournament.resultProgressSummary == "予選1位通過・本戦1回戦敗退", "the card summary follows the stages")
            var ranked = qualifier; ranked.outcome = .eliminated; ranked.placement = 5; ranked.entrantCount = 12
            try check(giriStageResultText(ranked) == "予選敗退（12人中5位）", "an eliminated rank keeps the entrant count")
            var third = tournament; third.tournamentResult?.outcome = .placed; third.placement = 3
            var best = tournament; best.tournamentResult?.outcome = .placed; best.tournamentResult?.bestOf = 4; best.placement = nil
            try check(third.isThirdPlace && !third.isBest(4) && best.isBest(4) && !best.isThirdPlace, "third place and best four are counted separately")
            try check(third.finalResultTitle == "3位" && best.finalResultTitle == "ベスト4", "final result titles distinguish third place and best four")
            try check(GiriFinalResultChoice.current(outcome: .placed, placement: 3, bestOf: nil) == .third && GiriFinalResultChoice.current(outcome: .placed, placement: nil, bestOf: 8) == .best8, "stored outcomes map back to the final result choice")
            try check(!giriIsOtherPlacement(third) && !giriIsOtherPlacement(best), "third and best four are not counted as other placements")
            try reject(Data(#"{"schemaVersion":1,"events":[{"id":"e","title":"大会","kind":"live","meetingType":"tournament","createdAt":"2026-10-29T13:00:00Z","tournamentResult":{"stages":[{"id":"s","name":"予選","entrantCount":0}]}}],"notes":[]}"#.utf8), "zero entrants")

            // Long-format stage totals and the score needed for the border.
            var online = GiriEvent(title: "ネット大会")
            online.eventFormat = .onlineLong; online.meetingType = .tournament
            var first = EventRound(id: "r1"); first.stageId = "stage"
            var second = EventRound(id: "r2"); second.stageId = "stage"
            var third2 = EventRound(id: "r3"); third2.stageId = "stage"
            online.rounds = [first, second, third2]
            var stage = ResultStage(); stage.stageId = "stage"; stage.name = "予選"; stage.borderScore = 3.0
            func scored(_ round: String, _ values: [(Double, Int)]) -> ThoughtNote {
                var note = ThoughtNote(title: round, kind: .answers)
                note.eventId = online.id; note.roundId = round; note.usesAnswerRecords = true
                note.answerRecords = values.map { AnswerRecord(text: "回答", isSubmitted: true, points: $0.0, voterCount: $0.1) }
                return note
            }
            let notes = [scored("r1", [(100, 100), (50, 100)]), scored("r2", [(80, 100)])]
            let totalSummary = giriStageScoreSummary(event: online, stage: stage, notes: notes)
            try check(totalSummary.map { abs($0.total - 2.3) < 0.000001 && $0.scoredPrompts == 2 && $0.remainingPrompts == 1 } == true, "total scoring adds every submitted answer")
            try check(totalSummary.flatMap(\.neededPerPrompt).map { abs($0 - 0.7) < 0.000001 } == true, "the remaining prompt needs the border minus the total")
            stage.scoring = .bestPerPrompt
            let bestSummary = giriStageScoreSummary(event: online, stage: stage, notes: notes)
            try check(bestSummary.map { abs($0.total - 1.8) < 0.000001 } == true, "best-per-prompt scoring keeps the higher answer of each prompt")

            // Aliases are normalized and treated as oneself.
            var aliasPreferences = AppPreferences(); aliasPreferences.selfName = "本名"; aliasPreferences.selfAliases = ["別名", "ベツメイ"]
            try check(aliasPreferences.isSelf("べつめい") && aliasPreferences.isSelf("本名") && !aliasPreferences.isSelf("他人"), "aliases match by the player search key")
            let aliasDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("GiriAlias-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: aliasDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: aliasDirectory) }
            let aliasStore = GiriStore(directory: aliasDirectory)
            var savedAliases = aliasPreferences; savedAliases.selfAliases = [" 別名 ", "本名", "", "別名"]
            try aliasStore.savePreferences(savedAliases)
            try check(aliasStore.preferences.selfAliases == ["別名"], "aliases are trimmed and never duplicate the main name")
            try aliasStore.saveNote(prompt)
            var renamed = GiriPlayer(name: "仲間")
            renamed = aliasStore.playerByName("仲間") ?? renamed
            renamed.name = "新しい仲間"
            try aliasStore.savePlayer(renamed)
            try check(aliasStore.notes[0].answerRecords.first { $0.id == "theirs" }?.answerer == "新しい仲間", "renaming a player renames their recorded answers")
        }

        // 0.9 simple recurring sites: one current deadline, a next-prompt choice,
        // skip / pause states, automatic season numbering and light reminders.
        do {
            let anchor = GiriDates.parse("2026-11-01T13:00:00Z") ?? Date()
            func day(_ offset: Int) -> Date { addCalendarDays(anchor, offset) }
            var simple = OnlineSite(id: "simple-site", name: "週替わりのサイト", recurrence: .weekly)
            simple.submissionDays = 7; simple.votingDays = 3
            applySiteTiming(.afterVoting, to: &simple, intervalDays: 1)
            try check(simple.cycleSettings?.pattern == .alternating && simple.cycleSettings?.intervalDays == 10 && SiteNextPromptTiming.current(simple) == .afterVoting, "a prompt after the vote waits for posting plus voting")
            applySiteTiming(.interval, to: &simple, intervalDays: 14)
            try check(simple.cycleSettings?.pattern == .overlapping && simple.cycleSettings?.intervalDays == 14 && SiteNextPromptTiming.current(simple) == .interval, "a fixed interval is stored as its own cadence")
            applySiteTiming(.irregular, to: &simple, intervalDays: 7)
            try check(simple.recurrence == .irregular && SiteNextPromptTiming.current(simple) == .irregular && simple.cycleSettings?.intervalDays == 14, "undecided timing keeps the weekly values for a later return")
            applySiteTiming(.withVoting, to: &simple, intervalDays: 14)
            try check(simple.recurrence == .weekly && simple.cycleSettings?.pattern == .overlapping && simple.cycleSettings?.intervalDays == 7 && SiteNextPromptTiming.current(simple) == .withVoting, "a prompt at the voting start overlaps on the posting length")
            try check(siteAnchorStart(posting: true, deadline: day(5), submissionDays: 7, votingDays: 3) == day(-2) && siteAnchorStart(posting: false, deadline: day(5), submissionDays: 7, votingDays: 3) == day(-5), "the current posting or voting deadline determines the prompt start")
            simple.cycleSettings?.anchorStart = siteAnchorStart(posting: true, deadline: day(5), submissionDays: 7, votingDays: 3)
            let posting = siteCycleDescriptors(simple, around: day(0)).filter { $0.round.isSubmissionOpen(day(0)) }
            try check(posting.count == 1 && posting[0].round.submissionEnd == day(5) && posting[0].round.votingStart == day(5) && posting[0].round.votingEnd == day(8), "the posting deadline is the voting start and the result follows the voting days")
            let votingPhase = siteCycleDescriptors(simple, around: day(6)).filter { $0.isActive(day(6)) }
            try check(votingPhase.contains { $0.round.isVotingOpen(day(6)) && $0.round.votingEnd == day(8) } && votingPhase.contains { $0.round.isSubmissionOpen(day(6)) && $0.round.submissionEnd == day(12) }, "the next prompt opens when the vote starts")
            try check(siteNextSeasonNumber(SiteCycleSettings(seasonName: "第１２シーズン")) == 13 && siteNextSeasonNumber(SiteCycleSettings(seasonName: "第2シーズン", seasonNumber: 7)) == 8 && siteNextSeasonNumber(SiteCycleSettings()) == 1, "season numbers continue from the saved number or the old name")

            let simpleDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("GiriSimpleSites-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: simpleDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: simpleDirectory) }
            let simpleStore = GiriStore(directory: simpleDirectory)
            try simpleStore.saveOnlineSite(simple)
            guard let storedSimple = simpleStore.onlineSiteById(simple.id),
                  let skipDescriptor = siteCycleDescriptors(storedSimple, around: day(0)).first(where: { $0.round.isSubmissionOpen(day(0)) }) else { throw GiriDataError.invalid("Missing simple site fixture") }
            let skipped = try simpleStore.setSiteCycleSkipped(simple.id, descriptor: skipDescriptor, event: nil, skipped: true)
            try check(skipped?.siteSkipped == true && skipped?.isActualParticipant == false && simpleStore.events.contains { $0.id == skipped?.id && $0.siteSkipped }, "skipping keeps the prompt as a non-participation record")
            let refreshedSkip = try simpleStore.createSiteCycle(simple.id, descriptor: skipDescriptor, join: false)
            try check(refreshedSkip.siteSkipped && !refreshedSkip.isActualParticipant, "the automatic refresh keeps a skipped prompt skipped")
            let rejoined = try simpleStore.createSiteCycle(simple.id, descriptor: skipDescriptor, join: true)
            try check(rejoined.id == skipped?.id && rejoined.isActualParticipant && !rejoined.siteSkipped, "joining after skipping clears the skip on the same prompt")
            let reskipped = try simpleStore.setSiteCycleSkipped(simple.id, descriptor: nil, event: rejoined, skipped: true)
            let undone = try simpleStore.setSiteCycleSkipped(simple.id, descriptor: nil, event: reskipped, skipped: false)
            try check(reskipped?.isParticipating == false && undone?.siteSkipped == false && undone?.isActualParticipant == false, "undoing a skip returns to undecided rather than joined")

            try simpleStore.setSitePaused(simple.id, paused: true)
            let pausedCount = simpleStore.events.filter { $0.onlineSiteId == simple.id }.count
            try simpleStore.ensureCurrentSiteCycles(now: day(14))
            try check(simpleStore.onlineSiteById(simple.id)?.isPaused == true && simpleStore.events.filter { $0.onlineSiteId == simple.id }.count == pausedCount, "a paused site creates no new prompts")
            try simpleStore.setSitePaused(simple.id, paused: false)
            try simpleStore.ensureCurrentSiteCycles(now: day(14))
            try check(simpleStore.events.filter { $0.onlineSiteId == simple.id }.count > pausedCount && simpleStore.onlineSiteById(simple.id)?.cycleSettings == storedSimple.cycleSettings, "resuming creates the current prompts again without changing the schedule")

            var seasonal = simple
            seasonal.id = "simple-season"
            seasonal.cycleSettings?.anchorStart = day(0); seasonal.cycleSettings?.anchorCycleNumber = 1
            seasonal.cycleSettings?.seasonName = "第1シーズン"; seasonal.cycleSettings?.seasonNumber = 1
            seasonal.cycleSettings?.seasonStart = day(0); seasonal.cycleSettings?.regularCycleCount = 3
            seasonal.cycleSettings?.ruleRevisionID = nil
            try simpleStore.saveOnlineSite(seasonal)
            guard let firstSeason = simpleStore.onlineSiteById(seasonal.id) else { throw GiriDataError.invalid("Missing season site") }
            try check(siteSeasonLastCycleEnd(firstSeason) == day(24) && !siteCycleDescriptors(firstSeason, around: day(23)).contains { ($0.cycleNumber ?? 0) > 3 }, "the last regular prompt's vote ends the season without a fourth prompt")
            try simpleStore.startNextSiteSeason(seasonal.id, firstDeadline: day(35))
            guard let nextSeason = simpleStore.onlineSiteById(seasonal.id), let nextSettings = nextSeason.cycleSettings else { throw GiriDataError.invalid("Missing next season") }
            try check(nextSettings.seasonNumber == 2 && nextSettings.seasonName == "第2シーズン" && nextSettings.anchorCycleNumber == 1 && nextSettings.anchorStart == day(28) && nextSettings.regularCycleCount == 3 && nextSettings.seasonID != firstSeason.cycleSettings?.seasonID, "the next season starts from its first deadline with the next number and the same length")
            let newPrompt = siteCycleDescriptors(nextSeason, around: day(29)).filter { $0.round.isSubmissionOpen(day(29)) }
            try check(newPrompt.count == 1 && newPrompt[0].cycleNumber == 1 && newPrompt[0].seasonName == "第2シーズン" && newPrompt[0].round.submissionEnd == day(35), "the new season's first prompt uses the entered deadline")
            try check(siteCycleDescriptors(nextSeason, around: day(22)).first { $0.cycleNumber == 3 }?.seasonName == "第1シーズン", "the previous season's last prompt keeps its season")

            var irregularSite = OnlineSite(id: "simple-irregular", name: "不定期のサイト", recurrence: .irregular)
            irregularSite.votingDays = 3
            irregularSite.cycleSettings = SiteCycleSettings()
            try simpleStore.saveOnlineSite(irregularSite)
            let firstIrregular = siteIrregularPeriod(irregularSite, deadline: day(40), now: day(36))
            try check(firstIrregular.kind == .regular && firstIrregular.title == "第1回" && firstIrregular.round.submissionStart == day(36) && firstIrregular.round.votingStart == day(40) && firstIrregular.round.votingEnd == day(43), "an undecided site's prompt needs only its posting deadline")
            try simpleStore.addSiteIrregularCycle(irregularSite.id, deadline: day(40))
            guard let storedIrregular = simpleStore.onlineSiteById(irregularSite.id) else { throw GiriDataError.invalid("Missing irregular site") }
            let secondIrregular = siteIrregularPeriod(storedIrregular, deadline: day(50), now: day(45))
            try check(storedIrregular.cycleSettings?.specialPeriods.count == 1 && secondIrregular.title == "第2回" && secondIrregular.round.submissionStart == day(40) && secondIrregular.round.votingEnd == day(53), "the next undecided prompt continues the number after the previous deadline")
            try check(siteCycleDescriptors(storedIrregular, around: day(36)).filter { $0.kind == .regular }.count == 1, "an undecided site shows only the entered prompt")

            var reminderPreferences = AppPreferences(notificationsEnabled: true); reminderPreferences.reminderMinutes = 30
            let reminderSite = OnlineSite(id: "reminder-site", name: "週替わりのサイト", recurrence: .weekly)
            var undecided = GiriEvent(title: "週替わりのサイト")
            undecided.eventFormat = .onlineLong; undecided.onlineSiteId = reminderSite.id; undecided.isParticipating = false
            var undecidedRound = EventRound(id: "next")
            undecidedRound.submissionStart = day(1); undecidedRound.submissionEnd = day(8); undecidedRound.votingStart = day(8); undecidedRound.votingEnd = day(11)
            undecided.rounds = [undecidedRound]
            let undecidedReminders = planNativeReminders(events: [undecided], preferences: reminderPreferences, sites: [reminderSite], now: day(0))
            try check(undecidedReminders.count == 2 && undecidedReminders.contains { $0.id.hasSuffix(":site-open:next") && $0.date == day(1) } && undecidedReminders.contains { $0.id.hasSuffix(":site-submission:next") && $0.date == day(8).addingTimeInterval(-1800) }, "an undecided prompt announces the new prompt and the posting deadline but not the vote")
            try check(planNativeReminders(events: [undecided], preferences: reminderPreferences, now: day(0)).isEmpty, "undecided prompts of unknown sites are not announced")
            var pausedReminderSite = reminderSite; pausedReminderSite.isPaused = true
            try check(planNativeReminders(events: [undecided], preferences: reminderPreferences, sites: [pausedReminderSite], now: day(0)).isEmpty, "a paused site announces nothing")
            var skippedReminder = undecided; skippedReminder.siteSkipped = true
            try check(planNativeReminders(events: [skippedReminder], preferences: reminderPreferences, sites: [reminderSite], now: day(0)).isEmpty, "a skipped prompt announces nothing")
            var joinedReminder = undecided; joinedReminder.isParticipating = true
            let joinedReminders = planNativeReminders(events: [joinedReminder], preferences: reminderPreferences, sites: [reminderSite], now: day(0))
            try check(joinedReminders.count == 2 && joinedReminders.contains { $0.id.hasSuffix(":submission") } && joinedReminders.contains { $0.id.hasSuffix(":voting") } && !joinedReminders.contains { $0.id.contains(":site-open:") }, "a joined prompt reminds both posting and voting deadlines")

            var legacySiteJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(storedSimple)) as? [String: Any] ?? [:]
            legacySiteJSON.removeValue(forKey: "isPaused")
            if var legacySettings = legacySiteJSON["cycleSettings"] as? [String: Any] { legacySettings.removeValue(forKey: "seasonNumber"); legacySiteJSON["cycleSettings"] = legacySettings }
            var legacyEventJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(undecided)) as? [String: Any] ?? [:]
            legacyEventJSON.removeValue(forKey: "siteSkipped")
            let legacySite = try JSONDecoder().decode(OnlineSite.self, from: JSONSerialization.data(withJSONObject: legacySiteJSON))
            let legacyEvent = try JSONDecoder().decode(GiriEvent.self, from: JSONSerialization.data(withJSONObject: legacyEventJSON))
            try check(!legacySite.isPaused && legacySite.cycleSettings?.seasonNumber == nil && !legacyEvent.siteSkipped, "older sites and prompts decode as active, numbered by name and not skipped")
            try check(try GiriJSON.decode(simpleStore.exportBackup()) == simpleStore.document, "skip, pause and season numbers roundtrip in schema one")
        }

        // 0.10 tournaments: the registration's individual / team choice drives
        // result entry, and names already entered for the event come first.
        do {
            var formatEvent = GiriEvent(title: "チーム大会")
            formatEvent.meetingType = .tournament
            try check(giriTournamentFormatText(formatEvent) == "個人戦", "a tournament defaults to individual entry")
            formatEvent.tournamentFormat = .team
            try check(giriTournamentFormatText(formatEvent) == "チーム戦", "a team tournament without a size says only team")
            formatEvent.teamSize = 3
            try check(giriTournamentFormatText(formatEvent) == "チーム戦（3人）", "the team size follows the registration")
            formatEvent.tournamentFormat = .pair
            try check(giriTournamentFormatText(formatEvent) == "タッグ戦（2人）", "legacy pair tournaments stay readable")
            formatEvent.participants = ["やまだ", " 佐藤 ", ""]
            var mine = GiriTeam(); mine.name = "自分たち"; mine.members = ["自分", "ヤマダ"]; mine.isMine = true
            var rival = GiriTeam(); rival.name = "相手"; rival.members = ["鈴木", "佐藤"]
            formatEvent.teams = [mine, rival]
            var podium = TournamentStanding(); podium.playerNames = ["高橋", "鈴木"]
            formatEvent.standings = [podium]
            try check(formatEvent.enteredPlayerNames == ["やまだ", "佐藤", "自分", "鈴木", "高橋"], "entered names keep the event's order once each by reading")
        }

        // 0.10 result summary: stage kinds by depth, finalists without exact
        // ranks, rates, breakdowns, templates, head-to-head and brackets.
        do {
            let kinds: [(String, StageKind)] = [("予選", .qualifier), ("予選決勝", .qualifier), ("本戦1回戦", .main), ("2回戦", .main),
                ("決勝トーナメント1回戦", .main), ("準々決勝", .quarterfinal), ("準決勝", .semifinal), ("決勝", .final),
                ("グランドファイナル", .final), ("敗者復活戦", .other), ("3位決定戦", .other), ("", .other)]
            for (name, kind) in kinds { try check(giriInferredStageKind(name) == kind, "stage name \(name) infers \(kind.title)") }
            var chosen = ResultStage(); chosen.name = "ラストステージ"; chosen.kind = .final
            try check(chosen.effectiveKind == .final, "an explicitly chosen kind wins over the name")

            let base = GiriDates.parse("2026-06-01T10:00:00Z") ?? Date()
            let summaryNow = addCalendarDays(base, 30)
            func tournament(_ title: String, organizer: String = "", team: Bool = false, day: Int, _ build: (inout TournamentResult, inout GiriEvent) -> Void) -> GiriEvent {
                var event = GiriEvent(title: title)
                event.eventFormat = .live; event.meetingType = .tournament; event.organizer = organizer
                event.eventDate = addCalendarDays(base, day)
                if team { event.tournamentFormat = .team; event.teamSize = 3 }
                var result = TournamentResult()
                build(&result, &event)
                event.tournamentResult = result
                return event
            }
            func stage(_ name: String, _ outcome: TournamentOutcome, lineup: String = "", judging: String = "", opponents: [String] = [], placement: Int? = nil) -> ResultStage {
                var value = ResultStage(); value.name = name; value.outcome = outcome; value.lineup = lineup; value.judging = judging; value.opponents = opponents; value.placement = placement
                return value
            }
            // 横並び6人の決勝で6位：決勝進出（順位は添えるだけ）。
            let sixth = tournament("第3回テスト杯", organizer: "主催A", day: 1) { result, event in
                result.stages = [stage("予選", .advanced, lineup: "横並び5人", judging: "挙手（1人1票）", opponents: ["ライバル"]), stage("本戦", .advanced, lineup: "横並び5人", judging: "加点審査"), stage("決勝", .placed, lineup: "横並び6人", judging: "その他", placement: 6)]
                result.outcome = .placed; result.finalist = true; result.finalEntrants = 6
                event.placement = 6
            }
            try check(sixth.finalResultTitle == "決勝進出（6人中6位）" && sixth.reachedFinal && !giriIsOtherPlacement(sixth), "a sixth place in a six-player final reads as a finalist")
            try check(GiriFinalResultChoice.current(outcome: .placed, placement: 6, bestOf: nil, finalist: true) == .finalist && GiriFinalResultChoice.current(outcome: .placed, placement: 6, bestOf: nil) == .placed, "finalist maps back to its own choice")
            var thirdFinalist = sixth; thirdFinalist.placement = 3
            try check(thirdFinalist.finalResultTitle == "3位" && thirdFinalist.isThirdPlace, "a finalist in third place still counts as third")
            // トーナメント：準々決勝で敗退 → ベスト8 の候補。
            let quarter = tournament("タイマン杯", organizer: "主催B", day: 2) { result, _ in
                result.stages = [stage("1回戦", .advanced, lineup: "タイマン", judging: "拍手", opponents: ["ライバル"]), stage("準々決勝", .eliminated, lineup: "タイマン", judging: "拍手")]
                result.outcome = .eliminated
            }
            try check(giriSuggestedFinalChoice(quarter.tournamentResult?.stages ?? []) == .best8 && quarter.furthestStageKind == .quarterfinal && !quarter.reachedFinal, "a quarterfinal loss suggests best eight")
            var oneOnOneFinal = stage("決勝", .eliminated, lineup: "タイマン")
            try check(giriSuggestedFinalChoice([oneOnOneFinal]) == .runnerUp, "losing a one-on-one final suggests runner-up")
            oneOnOneFinal.lineup = "横並び6人"
            try check(giriSuggestedFinalChoice([oneOnOneFinal]) == .finalist, "losing a group final suggests finalist")
            // 予選敗退と、チーム戦の優勝。
            let qualifierOut = tournament("第4回テスト杯", organizer: "主催A", day: 3) { result, _ in
                result.stages = [stage("予選", .eliminated, lineup: "横並び5人", judging: "挙手（1人1票）")]
                result.outcome = .eliminated
            }
            let teamWin = tournament("チーム杯", team: true, day: 4) { result, event in
                result.outcome = .champion; event.placement = 1
            }
            try check(qualifierOut.qualifierPassed == false && qualifierOut.furthestStageKind == .qualifier, "a qualifier loss is counted as not passing")
            try check(quarter.qualifierPassed == true && sixth.qualifierPassed == true && teamWin.qualifierPassed == true, "reaching later stages or winning means the first stage was passed")
            let upcoming = tournament("未来の大会", day: 60) { result, _ in result.outcome = .unrecorded }
            let summary = giriTournamentSummary([sixth, quarter, qualifierOut, teamWin, upcoming], now: summaryNow)
            try check(summary.completed == 4 && summary.champions == 1 && summary.teamChampions == 1 && summary.individualChampions == 0 && summary.finalists == 2, "the summary counts finished tournaments, finalists and the team split")
            try check(summary.qualifierKnown == 4 && summary.qualifierPassed == 3 && giriRateText(summary.qualifierPassed, summary.qualifierKnown) == "75%" && giriRateText(0, 0) == "—", "qualifier pass rate uses tournaments whose first stage is known")
            try check(summary.furthest[.final] == 2 && summary.furthest[.quarterfinal] == 1 && summary.furthest[.qualifier] == 1, "furthest stage compares tournaments with different structures by depth")
            let lineups = giriStagePassRates([sixth, quarter, qualifierOut], now: summaryNow) { $1.lineup }
            try check(lineups.first { $0.label == "横並び5人" }.map { $0.passed == 2 && $0.total == 3 } == true && lineups.first { $0.label == "タイマン" }.map { $0.passed == 1 && $0.total == 2 } == true, "stage pass rates group by lineup")
            let judgings = giriStagePassRates([sixth], now: summaryNow) { $1.judging }
            try check(judgings.contains { $0.label == "その他" && $0.total == 1 }, "the other judging method is counted as its own row")
            let organizers = giriOrganizerResults([sixth, quarter, qualifierOut, teamWin], now: summaryNow)
            try check(organizers.first.map { $0.name == "主催A" && $0.entries == 2 && $0.finals == 1 && $0.champions == 0 } == true && organizers.count == 2, "organizer rows count entries, finals and titles")
            // 前回の段階構成と対戦の記録。
            try check(giriSeriesKey("第3回テスト杯") == giriSeriesKey("第４回 テスト杯") && giriSeriesKey("テスト杯 vol.2") == giriSeriesKey("テスト杯"), "series keys ignore edition numbers")
            var nextEdition = GiriEvent(title: "第5回テスト杯"); nextEdition.eventFormat = .live; nextEdition.meetingType = .tournament
            let source = giriStageTemplateSource(for: nextEdition, in: [sixth, quarter, qualifierOut])
            try check(source?.id == qualifierOut.id, "the latest edition of the same series is the template")
            let template = giriStageTemplate(from: sixth)
            try check(template.map(\.name) == ["予選", "本戦", "決勝"] && template.allSatisfy { $0.outcome == .unrecorded && $0.placement == nil && $0.opponents.isEmpty } && template[0].judging == "挙手（1人1票）", "a template copies the structure without results")
            let meetings = giriOpponentMeetings([sixth, quarter, upcoming], playerKey: playerSearchKey("らいばる"), now: summaryNow)
            try check(meetings.count == 2 && meetings.filter { $0.stage.passed == true }.count == 2 && meetings.first?.event.id == quarter.id, "head-to-head counts meetings by reading, newest first")
            // トーナメント表：左右の山、回戦名、隣の山の候補。
            let lines = [GiriOCRLine(text: "1回戦", midX: 0.2, midY: 0.02), GiriOCRLine(text: "Aさん", midX: 0.1, midY: 0.1), GiriOCRLine(text: "Bさん", midX: 0.1, midY: 0.3),
                         GiriOCRLine(text: "自分", midX: 0.1, midY: 0.5), GiriOCRLine(text: "Dさん", midX: 0.1, midY: 0.7),
                         GiriOCRLine(text: "Eさん", midX: 0.9, midY: 0.1), GiriOCRLine(text: "Fさん", midX: 0.9, midY: 0.3),
                         GiriOCRLine(text: "Gさん", midX: 0.9, midY: 0.5), GiriOCRLine(text: "Hさん", midX: 0.9, midY: 0.7),
                         GiriOCRLine(text: "自分", midX: 0.3, midY: 0.6), GiriOCRLine(text: "3-1", midX: 0.3, midY: 0.55), GiriOCRLine(text: "決勝", midX: 0.5, midY: 0.02)]
            let bracket = giriBracketOrder(lines)
            try check(bracket == ["Aさん", "Bさん", "自分", "Dさん", "Eさん", "Fさん", "Gさん", "Hさん"], "a two-sided bracket reads left then right without labels, scores or repeated winners")
            try check(giriBracketStageNames(8) == ["準々決勝", "準決勝", "決勝"] && giriBracketStageNames(6) == ["準々決勝", "準決勝", "決勝"] && giriBracketStageNames(16) == ["1回戦", "準々決勝", "準決勝", "決勝"], "bracket rounds are named from the final backwards")
            let me: (String) -> Bool = { $0 == "自分" }
            try check(giriBracketOpponents(bracket, round: 1, isSelf: me) == ["Dさん"] && giriBracketOpponents(bracket, round: 2, isSelf: me) == ["Aさん", "Bさん"] && giriBracketOpponents(bracket, round: 3, isSelf: me) == ["Eさん", "Fさん", "Gさん", "Hさん"], "each round's candidates are the neighbouring half")
            try check(giriBracketOpponents(["自分", "Aさん", "Bさん"], round: 2, isSelf: me) == ["Bさん"] && giriBracketOpponents(["Aさん", "Bさん", "自分"], round: 1, isSelf: me).isEmpty, "a bye has no first-round opponent")
            // 旧データと新しい版の値。
            var legacyStage = try JSONSerialization.jsonObject(with: JSONEncoder().encode(chosen)) as? [String: Any] ?? [:]
            legacyStage.removeValue(forKey: "kind")
            try check(try JSONDecoder().decode(ResultStage.self, from: JSONSerialization.data(withJSONObject: legacyStage)).kind == nil, "older stages decode without a kind")
            legacyStage["kind"] = "a-future-kind"
            try check(try JSONDecoder().decode(ResultStage.self, from: JSONSerialization.data(withJSONObject: legacyStage)).kind == nil, "an unknown kind does not stop loading")
            var legacyResult = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sixth.tournamentResult ?? TournamentResult())) as? [String: Any] ?? [:]
            for key in ["finalist", "finalEntrants"] { legacyResult.removeValue(forKey: key) }
            let decodedResult = try JSONDecoder().decode(TournamentResult.self, from: JSONSerialization.data(withJSONObject: legacyResult))
            try check(!decodedResult.finalist && decodedResult.finalEntrants == nil, "older results decode as not a finalist")
            let finalistResult = sixth.tournamentResult ?? TournamentResult()
            try check(try JSONDecoder().decode(TournamentResult.self, from: JSONEncoder().encode(finalistResult)) == finalistResult, "finalist and final size roundtrip")
        }

        // 0.10 live events: the basic info decides who plays. Team tournaments
        // list teams, impromptu teams assign participants later, and hosts,
        // MCs, judges, spectators and reserves are not counted as playing.
        do {
            var team = GiriEvent(title: "チーム大会")
            team.eventFormat = .live; team.meetingType = .tournament; team.tournamentFormat = .team; team.teamSize = 2
            team.impromptuTeams = true
            team.participants = ["自分", "やまだ", "すずき", "たなか"]
            var mine = GiriTeam(); mine.isMine = true; mine.members = ["自分", "ヤマダ"]
            var other = GiriTeam(); other.members = ["すずき", ""]
            team.teams = [mine, other]; team.myTeamId = mine.id
            try check(team.unassignedParticipants == ["たなか"], "impromptu participants not yet in a team are listed by reading")
            try check(team.everyone == ["自分", "やまだ", "すずき", "たなか"], "everyone merges participants and team members once each")
            var teamOnly = team; teamOnly.participants = []; teamOnly.impromptuTeams = false
            try check(teamOnly.everyone == ["自分", "ヤマダ", "すずき"] && teamOnly.unassignedParticipants.isEmpty, "a team tournament without participants still counts its members")

            var hosted = GiriEvent(title: "主催の会")
            hosted.eventFormat = .live; hosted.organizer = "大喜利団体"; hosted.organizerIsGroup = true
            hosted.coOrganizers = ["きょうさい"]; hosted.mcs = ["しかい"]; hosted.judges = ["しんさ"]
            try check(hosted.staffNames == ["きょうさい", "しかい", "しんさ"] && hosted.organizerText == "大喜利団体（団体）", "a group organizer is not a person among the staff")
            try check(hosted.isHosted(byKey: playerSearchKey("キョウサイ")) && !hosted.isHosted(byKey: playerSearchKey("大喜利団体")) && hosted.isMCOrJudge(byKey: playerSearchKey("シンサ")), "co-hosts count as hosting, and MCs and judges separately")
            try check(GiriSelfRole.choices(tournament: false) == [.player, .staff, .spectator] && GiriSelfRole.choices(tournament: true).contains(.reserve), "reserves exist only for tournaments")
            try check(GiriSelfRole.staff.title(tournament: false) == "主催（出ない）" && GiriSelfRole.staff.shortTitle(tournament: true) == "運営", "the staff role reads as host for casual events and operations for tournaments")

            let base = GiriDates.parse("2026-07-01T10:00:00Z") ?? Date()
            var played = GiriEvent(title: "出た大会"); played.eventFormat = .live; played.meetingType = .tournament; played.eventDate = base
            var playedResult = TournamentResult(); playedResult.outcome = .champion; played.tournamentResult = playedResult; played.placement = 1
            var watched = played; watched.id = UUID().uuidString; watched.selfRole = .spectator
            var reserve = played; reserve.id = UUID().uuidString; reserve.selfRole = .reserve
            let roleSummary = giriTournamentSummary([played, watched, reserve], now: addCalendarDays(base, 3))
            try check(roleSummary.completed == 1 && roleSummary.champions == 1 && played.countsForResults && !watched.countsForResults, "only tournaments where you played are counted as results")
            try check(!watched.isSelfPlayer && watched.endedRoundsNeedingResult(now: addCalendarDays(base, 3)).isEmpty, "non-players are not asked for their results")

            var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(hosted)) as? [String: Any] ?? [:]
            for key in ["impromptuTeams", "knockout", "judging", "coOrganizers", "mcs", "judges", "organizerIsGroup", "selfRole"] { legacyJSON.removeValue(forKey: key) }
            let legacy = try JSONDecoder().decode(GiriEvent.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
            let legacyFlags = !legacy.impromptuTeams && !legacy.knockout && !legacy.organizerIsGroup
            let legacyStaff = legacy.coOrganizers.isEmpty && legacy.mcs.isEmpty && legacy.judges.isEmpty
            try check(legacyFlags && legacyStaff && legacy.judging.isEmpty, "older events decode without staff or tournament options")
            try check(legacy.selfRole == .player, "older events decode as a player")
            legacyJSON["selfRole"] = "a-future-role"
            try check(try JSONDecoder().decode(GiriEvent.self, from: JSONSerialization.data(withJSONObject: legacyJSON)).selfRole == .player, "an unknown role reads as a player")
            var knockout = hosted; knockout.createdAt = base; knockout.knockout = true; knockout.judging = "拍手"; knockout.selfRole = .reserve; knockout.impromptuTeams = true
            try check(try JSONDecoder().decode(GiriEvent.self, from: JSONEncoder().encode(knockout)) == knockout, "roles, staff, format and judging roundtrip")
        }

        // 0.10 host groups are kept apart from players: a group directory with
        // members and host history, renames, and converting an old organizer.
        do {
            let groupDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("GiriGroups-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: groupDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: groupDirectory) }
            let groupStore = GiriStore(directory: groupDirectory)
            var byGroup = GiriEvent(title: "団体の会"); byGroup.eventFormat = .live; byGroup.organizer = "大喜利会"; byGroup.organizerIsGroup = true
            byGroup.participants = ["参加者A"]
            try groupStore.saveEvent(byGroup)
            try check(groupStore.groupDirectory.map(\.name) == ["大喜利会"] && groupStore.groupDirectory[0].id.hasPrefix("history:"), "a group organizer appears in the group directory")
            try check(!groupStore.playerDirectory.contains { $0.name == "大喜利会" } && groupStore.playerDirectory.contains { $0.name == "参加者A" }, "a group organizer stays out of the player list")
            guard var group = groupStore.groupByName("大喜利会") else { throw GiriDataError.invalid("Missing group") }
            group.members = ["メンバーB", " メンバーB ", ""]; group.furigana = "おおぎりかい"
            try groupStore.saveGroup(group)
            try check(groupStore.groups.count == 1 && groupStore.groups[0].members == ["メンバーB"] && !groupStore.groups[0].id.hasPrefix("history:"), "saving a group keeps one trimmed member list")
            try check(groupStore.playerDirectory.contains { $0.name == "メンバーB" }, "group members are players")
            var renamed = groupStore.groups[0]; renamed.name = "新しい大喜利会"
            try groupStore.saveGroup(renamed)
            try check(groupStore.events[0].organizer == "新しい大喜利会" && groupStore.eventsHosted(byGroup: "新しい大喜利会").count == 1, "renaming a group renames its hosted events")
            if var member = groupStore.playerByName("メンバーB") { member.name = "メンバーC"; try groupStore.savePlayer(member) }
            try check(groupStore.groups[0].members == ["メンバーC"] && groupStore.events[0].organizer == "新しい大喜利会", "renaming a player renames group members but not a group organizer")
            var duplicate = GiriGroup(name: "新しい大喜利会")
            var refused = false
            do { try groupStore.saveGroup(duplicate) } catch { refused = true }
            try check(refused, "group names stay unique")
            duplicate.name = "別の団体"; try groupStore.saveGroup(duplicate)
            // 以前プレイヤーとして主催者に入れた団体名を団体にする。
            try groupStore.savePlayer(GiriPlayer(name: "古い団体", furigana: "ふるいだんたい"))
            var oldStyle = GiriEvent(title: "昔の会"); oldStyle.eventFormat = .live; oldStyle.organizer = "古い団体"
            try groupStore.saveEvent(oldStyle)
            let converted = try groupStore.convertPlayerToGroup("古い団体")
            try check(converted.furigana == "ふるいだんたい" && groupStore.events.first { $0.id == oldStyle.id }?.organizerIsGroup == true && !groupStore.players.contains { $0.name == "古い団体" } && groupStore.groupByName("古い団体") != nil, "an old organizer becomes a group and leaves the player list")
            try check(try GiriJSON.decode(groupStore.exportBackup()) == groupStore.document, "groups roundtrip in schema one")
            var legacyDocument = try JSONSerialization.jsonObject(with: groupStore.exportBackup()) as? [String: Any] ?? [:]
            legacyDocument.removeValue(forKey: "groups")
            try check(try GiriJSON.decode(JSONSerialization.data(withJSONObject: legacyDocument)).groups.isEmpty, "older backups without groups decode")
        }

        // 0.10 participant lists read from a screen or pasted text: only the
        // participants column, icon misreads removed, registered names matched.
        do {
            let known = ["もちゅこ", "大川 太郎", "たまごサンドイッチ", "4321", "青空 カモメ"]
            try check(giriOCRNameKey("もちゆこ") == giriOCRNameKey("もちゅこ") && giriOCRNameKey("大川太郎") == giriOCRNameKey("大川 太郎"), "names compare without small kana or spaces")
            try check(giriMatchRegisteredName("Gもちゆこ", known: known) == "もちゅこ", "a letter read from an icon is dropped when the rest is registered")
            try check(giriMatchRegisteredName("欲たまごサンド", truncated: true, known: known) == "たまごサンドイッチ", "a cut-off name matches the registered name it starts")
            try check(giriMatchRegisteredName("青空カモノ", known: known) == "青空 カモメ", "one misread character still matches a long name")
            try check(giriMatchRegisteredName("大山", known: ["大川"]) == nil && giriMatchRegisteredName("4322", known: known) == nil, "short and numeric names need an exact match")
            try check(giriCleanParticipantText("1 4321").name == "4321" && giriCleanParticipantText("②麓").name == "麓" && giriCleanParticipantText("(新しい人").name == "新しい人", "leading icon marks are removed")
            let cut = giriCleanParticipantText("欲たまごサンド・・・")
            try check(cut.truncated && cut.name == "欲たまごサンド", "a trailing ellipsis marks a cut-off name")
            let pasted = """
            13:30
            •I1) 4G 26
            example.jp
            このイベントに参加しますか？
            まずxアカウントでログインする
            参加者（7人／定員
            7人）
            Gもちゆこ
            ・大川太郎
            欲たまごサンド・・・
            ②麓
            (新しい人
            1 4321
            ※青空カモメ
            凸参加者プロフィール
            興味あり（2人）
            見学さん
            もちゅこ
            """
            let fromText = giriParticipantCandidates(text: pasted, known: known)
            try check(fromText.filter(\.included).map(\.name) == ["もちゅこ", "大川 太郎", "たまごサンドイッチ", "麓", "新しい人", "4321", "青空 カモメ"], "pasted lists keep only the participants section with registered spellings")
            try check(fromText.first { $0.name == "見学さん" }.map { $0.section == .interested && !$0.included } == true && fromText.filter { $0.name == "もちゅこ" }.count == 1, "interested people are listed unselected and duplicates are dropped")
            try check(fromText.first { $0.name == "新しい人" }?.registered == nil && fromText.first { $0.name == "4321" }?.registered == "4321", "new and registered people are told apart")
            let screen = [GiriOCRLine(text: "13:30", midX: 0.15, midY: 0.02), GiriOCRLine(text: "example.jp", midX: 0.5, midY: 0.05),
                          GiriOCRLine(text: "参加者（3人／定員", midX: 0.18, midY: 0.30), GiriOCRLine(text: "興味あり（1人）", midX: 0.47, midY: 0.30),
                          GiriOCRLine(text: "不参加（0人）", midX: 0.77, midY: 0.30), GiriOCRLine(text: "3人）", midX: 0.08, midY: 0.33),
                          GiriOCRLine(text: "Gもちゆこ", midX: 0.15, midY: 0.36), GiriOCRLine(text: "見学さん", midX: 0.46, midY: 0.36),
                          GiriOCRLine(text: "・大川太郎", midX: 0.14, midY: 0.40), GiriOCRLine(text: "1 4321", midX: 0.12, midY: 0.44),
                          GiriOCRLine(text: "凸参加者プロフィール", midX: 0.17, midY: 0.60), GiriOCRLine(text: "コメント", midX: 0.1, midY: 0.70),
                          GiriOCRLine(text: "広告の文字", midX: 0.7, midY: 0.80)]
            let fromScreen = giriParticipantCandidates(lines: screen, known: known)
            try check(fromScreen.filter(\.included).map(\.name) == ["もちゅこ", "大川 太郎", "4321"], "a three-column screen keeps the participants column")
            try check(fromScreen.contains { $0.name == "見学さん" && $0.section == .interested } && !fromScreen.contains { $0.source == "広告の文字" }, "other columns are separated and text after the list is ignored")
            let plain = giriParticipantCandidates(text: "Aさん、Bさん\nCさん", known: [])
            try check(plain.map(\.name) == ["Aさん", "Bさん", "Cさん"] && plain.allSatisfy(\.included), "a list without headers is read as participants")
        }

        // 0.10 live series, venue rooms, doors-open time and groups found by name.
        do {
            try check(giriSeriesTitle("大喜利レート戦「三光芒」#5") == "大喜利レート戦「三光芒」" && giriSeriesTitle("第3回 ひかり杯") == "ひかり杯" && giriSeriesTitle("集まり vol.2") == "集まり", "series titles drop edition numbers")
            var fourth = GiriEvent(title: "大喜利レート戦「三光芒」#4"); fourth.eventFormat = .live
            var fifth = GiriEvent(title: "大喜利レート戦「三光芒」＃5"); fifth.eventFormat = .live
            var special = GiriEvent(title: "三光芒 番外編"); special.eventFormat = .live; special.series = "大喜利レート戦「三光芒」"
            var other = GiriEvent(title: "別の会 #5"); other.eventFormat = .live
            try check(giriSeriesEvents(of: fifth, in: [fourth, fifth, special, other]).count == 3 && fifth.seriesTitle == "大喜利レート戦「三光芒」", "editions and an explicitly named special share a series")
            try check(giriSeriesSuggestions(for: "三光芒 #6", in: [other, fourth]).first == "大喜利レート戦「三光芒」", "a series containing the new title is suggested first")
            var roomEvent = fifth; roomEvent.venue = "市民会館"; roomEvent.venueRoom = "第3会議室"
            roomEvent.opensAt = GiriDates.parse("2026-11-01T09:30:00Z"); roomEvent.createdAt = GiriDates.parse("2026-11-01T00:00:00Z") ?? Date()
            try check(try JSONDecoder().decode(GiriEvent.self, from: JSONEncoder().encode(roomEvent)) == roomEvent, "room, doors-open time and series roundtrip")
            var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(roomEvent)) as? [String: Any] ?? [:]
            for key in ["venueRoom", "opensAt", "series"] { legacyJSON.removeValue(forKey: key) }
            let legacy = try JSONDecoder().decode(GiriEvent.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
            try check(legacy.venueRoom.isEmpty && legacy.opensAt == nil && legacy.series.isEmpty, "older events decode without a room, doors-open time or series")

            let flagDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("GiriGroupFlag-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: flagDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: flagDirectory) }
            let flagStore = GiriStore(directory: flagDirectory)
            var hostedByCircle = GiriEvent(title: "サークルの会"); hostedByCircle.eventFormat = .live; hostedByCircle.organizer = "サークルX"
            try flagStore.saveEvent(hostedByCircle)
            try check(flagStore.playerDirectory.contains { $0.name == "サークルX" }, "an unregistered organizer starts as a player")
            try flagStore.saveGroup(GiriGroup(name: "サークルX"))
            try check(flagStore.events[0].organizerIsGroup && !flagStore.playerDirectory.contains { $0.name == "サークルX" }, "registering a group turns its hosted events into group hosting")
        }

        // 0.11 sites between seasons: no regular rounds while waiting, resume from the entered deadline.
        do {
            let anchor = GiriDates.parse("2026-10-01T22:00:00Z") ?? Date()
            func day(_ offset: Int) -> Date { addCalendarDays(anchor, offset) }
            var site = OnlineSite(id: "waiting-site", name: "合間のサイト", recurrence: .weekly)
            site.submissionDays = 7; site.votingDays = 3
            site.cycleSettings = SiteCycleSettings(pattern: .overlapping, anchorStart: anchor, intervalDays: 7)
            try check(siteCycleDescriptors(site, around: day(30)).contains { $0.kind == .regular && $0.isActive(day(30)) }, "a weekly site keeps generating rounds")
            var waiting = site
            waiting.cycleSettings?.waitingForNext = true
            try check(!siteCycleDescriptors(waiting, around: day(30)).contains { $0.kind == .regular }, "waiting between seasons creates no regular rounds")
            let roundtrip = try JSONDecoder().decode(SiteCycleSettings.self, from: JSONEncoder().encode(waiting.cycleSettings))
            try check(roundtrip.waitingForNext && roundtrip.notBefore == nil, "the waiting state roundtrips")
            var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(site.cycleSettings)) as? [String: Any] ?? [:]
            legacyJSON.removeValue(forKey: "waitingForNext"); legacyJSON.removeValue(forKey: "notBefore")
            let legacy = try JSONDecoder().decode(SiteCycleSettings.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
            try check(!legacy.waitingForNext && legacy.notBefore == nil, "older settings decode as not waiting")
            var resumedSite = waiting
            resumedSite.cycleSettings = siteResumeSettings(waiting, firstDeadline: day(47), cycleNumber: 5)
            let resumedRows = siteCycleDescriptors(resumedSite, around: day(41))
            try check(resumedRows.contains { $0.cycleNumber == 5 && $0.round.isSubmissionOpen(day(41)) }, "resuming starts at the entered round")
            try check(!resumedRows.contains { $0.kind == .regular && ($0.start ?? anchor) < day(40) }, "resuming does not fabricate rounds in the gap")

            var joinedCycle = GiriEvent(title: "第3回"); joinedCycle.eventFormat = .onlineLong
            joinedCycle.onlineSiteId = site.id; joinedCycle.siteCycleNumber = 3
            var unjoined = joinedCycle; unjoined.id = UUID().uuidString; unjoined.siteCycleNumber = 6; unjoined.isParticipating = false
            try check(siteSuggestedResumeCycleNumber(site, events: [joinedCycle, unjoined]) == 4 && siteSuggestedResumeCycleNumber(site, events: []) == 1, "the next round follows the last recorded round")

            let waitDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("GiriWaiting-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: waitDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: waitDirectory) }
            let waitStore = GiriStore(directory: waitDirectory)
            try waitStore.saveOnlineSite(site)
            guard var saved = waitStore.onlineSites.first, var settings = saved.cycleSettings else { throw GiriDataError.invalid("Missing waiting site") }
            // 設定画面と同じく、今の回より前で前の決まりを止めて次のお題待ちにする。
            let cutoff = siteCycleDescriptors(saved, around: day(30)).filter { $0.kind == .regular && $0.isActive(day(30)) }.compactMap(\.start).min() ?? day(30)
            settings.anchorStart = cutoff; settings.waitingForNext = true; settings.anchorCycleNumber = 5
            saved.cycleSettings = settings
            try waitStore.saveOnlineSite(saved)
            guard let paused = waitStore.onlineSites.first else { throw GiriDataError.invalid("Missing paused site") }
            try check(paused.ruleHistory.count == 1 && !siteCycleDescriptors(paused, around: day(30)).contains { $0.kind == .regular && $0.isActive(day(30)) }, "the previous rule stops before the current round while waiting")
            try waitStore.resumeSiteCycle(paused.id, firstDeadline: day(47), cycleNumber: 5)
            guard let back = waitStore.onlineSites.first else { throw GiriDataError.invalid("Missing resumed site") }
            try check(back.cycleSettings?.waitingForNext == false && siteCycleDescriptors(back, around: day(41)).contains { $0.cycleNumber == 5 && $0.round.isSubmissionOpen(day(41)) }, "resuming from the store continues at the entered round")
            try check(!siteCycleDescriptors(back, around: day(35)).contains { $0.kind == .regular && $0.isActive(day(35)) }, "nothing is open in the gap after resuming")
        }

        // 0.11 event pages: headers only from real section titles, description lines ignored,
        // basic info from the date line, labels and time notation (fictional names only).
        do {
            try check(giriParticipantHeader("キャンセル待ちはないので空きがありましたら自分で参") == nil && giriParticipantHeader("不参加 (0人)") == .other && giriParticipantHeader("興味あり (5人)") == .interested, "sentences in the description are not section headers")
            let noise = ["2025/11/18(水)18:00〜21:15", "《場所》", "500円", "みどり線「ひかり」駅 徒歩5分", ">今すぐ無料インストール", "15名(途中抜け、途中参加可能)", "[146 views]", "お題を一題お願いします。"]
            try check(noise.allSatisfy(giriIsParticipantNoise), "dates, prices, access, ads and sentences are not names")
            try check(!giriIsParticipantNoise("まな!") && !giriIsParticipantNoise("みかん星人") && !giriIsParticipantNoise("たまごサン…"), "short names are kept")
            func row(_ text: String, _ y: Double, x: Double = 0.2, h: Double = 0.007) -> GiriOCRLine { GiriOCRLine(text: text, midX: x, midY: y, height: h) }
            let page = [row("2026年11月18日[水] 夜", 0.05, h: 0.012), row("初参加歓迎", 0.08, x: 0.15, h: 0.006), row("途中参加OK", 0.08, x: 0.35, h: 0.006),
                        row("ふしぎな会", 0.10, h: 0.013), row("さくらもち", 0.13), row("[146 views]", 0.15), row("LINEで送る", 0.155, x: 0.5),
                        row("《内容》", 0.25), row("キャンセル待ちはないので空きがありましたら自分で参", 0.27), row("加に変更していただいて構いません。", 0.28),
                        row("《日時》", 0.30), row("2025/11/18(水)18:00〜21:15", 0.31), row("《場所》", 0.33), row("市民交流センター　和室", 0.34),
                        row("みどり線「ひかり」駅 徒歩5分", 0.35), row("《参加費》", 0.40), row("500円", 0.41), row("今夜は3.5秒で", 0.45),
                        row("このイベントは定員に達しました", 0.55), row("興味あり", 0.57, x: 0.35), row("不参加", 0.57, x: 0.55),
                        row("参加者 (3人／定員", 0.60, x: 0.15), row("興味あり (1人)", 0.60, x: 0.47), row("不参加 (0人)", 0.60, x: 0.77), row("3人)", 0.615, x: 0.08),
                        row("●まつぼっくり", 0.63, x: 0.15), row("●みかん星人", 0.63, x: 0.46), row("●たまごサンドイッチ", 0.65, x: 0.15), row("●新しい人", 0.67, x: 0.15),
                        row("参加者プロフィール", 0.70, x: 0.17), row("•名前をID表示に", 0.698, x: 0.5), row("コメント", 0.75, x: 0.1), row("19:30ごろ到着見込みです", 0.78)]
            let now = GiriDates.parse("2026-11-04T03:00:00Z") ?? Date()
            let draft = giriEventPageDraft(lines: page, known: ["たまごサンドイッチ"], venues: [], organizers: ["さくらもち"], now: now)
            try check(draft.participants.filter(\.included).map(\.name) == ["まつぼっくり", "たまごサンドイッチ", "新しい人"], "only the participants column is selected")
            try check(draft.participants.contains { $0.name == "みかん星人" && $0.section == .interested } && !draft.participants.contains { $0.section == .other }, "description text is not read as a cancelled list")
            try check(!draft.participants.contains { $0.name.contains("ID表示") || $0.name.contains("円") }, "buttons and prices are never names")
            let calendar = Calendar.current
            try check(draft.title == "ふしぎな会" && draft.organizer == "さくらもち", "the title is the large line after the date and the organizer is just below")
            let pageDay = draft.date.map { calendar.dateComponents([.year, .month, .day], from: $0) }
            try check(pageDay?.year == 2026 && pageDay?.month == 11 && pageDay?.day == 18, "the page date wins over a stale year in the description")
            try check(draft.start == GiriClock(hour: 18, minute: 0) && draft.end == GiriClock(hour: 21, minute: 15) && draft.opens == nil, "time ranges fill start and end")
            try check(draft.venue == "市民交流センター" && draft.venueRoom == "和室" && draft.fee == 500, "venue, room and fee come from labelled lines")
            let mixed = giriEventPageTimes("（18：15開場 21:15撤収予定）")
            try check(mixed.opens == GiriClock(hour: 18, minute: 15) && mixed.teardown == GiriClock(hour: 21, minute: 15) && mixed.start == nil, "time-first labels")
            let labelled = giriEventPageTimes("開場 18:00 / 開演 18:30")
            try check(labelled.opens == GiriClock(hour: 18, minute: 0) && labelled.start == GiriClock(hour: 18, minute: 30), "label-first times")
            try check(giriEventPageTimes("OPEN 13時半 START 14時").start == GiriClock(hour: 14, minute: 0) && giriEventPageTimes("OPEN 13時半").opens == GiriClock(hour: 13, minute: 30), "kanji clock notation")
            let numbered = giriSplitVenueRoom("みどり区民センター 306", venues: [])
            try check(numbered.venue == "みどり区民センター" && numbered.room == "306", "a room number after the facility")
            let parenthesised = giriSplitVenueRoom("ひかり市立公民館205会議室2（ひかりコラボセンター内2階）", venues: [])
            try check(parenthesised.venue == "ひかり市立公民館" && parenthesised.room == "205会議室2", "notes in brackets are dropped and the room follows the facility")
            let hall = giriSplitVenueRoom("さくらホール 小ホール", venues: [])
            let cafe = giriSplitVenueRoom("カフェ＆バー", venues: [])
            try check(hall.venue == "さくらホール" && hall.room == "小ホール" && cafe.venue == "カフェ＆バー" && cafe.room.isEmpty, "a venue is not cut inside its own name")
            let registeredVenue = giriSplitVenueRoom("つばさ会館 第2会議室", venues: ["つばさ会館"])
            try check(registeredVenue.venue == "つばさ会館" && registeredVenue.room == "第2会議室", "registered venues are matched first")
            try check(giriEventPageDate("10月18日(日)", now: now).map { calendar.component(.year, from: $0) } == 2026 && giriEventPageDate("1月5日(火)", now: now).map { calendar.component(.year, from: $0) } == 2027, "a date without a year is the nearest coming one")
            let marked = giriMarkingAlreadyAdded(draft.participants, existing: ["まつぼっくり"])
            try check(marked.first { $0.name == "まつぼっくり" }.map { $0.alreadyAdded && !$0.included } == true && giriSelectedParticipantNames(marked) == ["たまごサンドイッチ", "新しい人"], "people already in the list are not added twice")
            try check(giriJudgingCategory("挙手（1人1票）") == "印象審査" && giriJudgingCategory("超加点審査") == "超加点審査" && giriJudgingCategory("加点審査") == "加点審査", "judging categories")
            try check(giriJudgingCategory("審査員の採点") == "その他" && giriJudgingCategory("").isEmpty && giriJudgingChoices == ["印象審査", "拍手審査", "加点審査", "超加点審査", "その他"], "uncategorised judging is other")
            try check(giriJudgingCategory("拍手") == "拍手審査" && giriJudgingCategory("印象（投票）") == "印象審査", "applause judging is separate from voted impressions")
        }

        // 0.12 roles from inputs, reserves, aliases shown together or separately, regions.
        do {
            func isMe(_ name: String) -> Bool { playerSearchKey(name) == playerSearchKey("わたし") }
            var live = GiriEvent(title: "大会"); live.eventFormat = .live; live.meetingType = .tournament
            live.participants = ["わたし", "Aさん"]
            try check(live.derivedSelfRole(isSelf: isMe) == .player, "listed participants play")
            var host = live; host.participants = ["Aさん"]; host.organizer = "わたし"
            try check(host.derivedSelfRole(isSelf: isMe) == .staff, "an organizer who is not listed does not play")
            var hostPlays = host; hostPlays.participants = ["わたし", "Aさん"]
            try check(hostPlays.derivedSelfRole(isSelf: isMe) == .player, "an organizer who is listed plays")
            var reserve = host; reserve.organizer = ""; reserve.hasReserves = true; reserve.reserves = ["わたし", " "]
            try check(reserve.derivedSelfRole(isSelf: isMe) == .reserve && reserve.reserveNames == ["わたし"], "the reserve list decides the reserve role")
            var casualReserve = reserve; casualReserve.meetingType = .casual
            try check(casualReserve.derivedSelfRole(isSelf: isMe) == .player && casualReserve.reserveNames.isEmpty, "casual meetings have no reserves")
            var watching = live; watching.selfRole = .spectator
            try check(watching.derivedSelfRole(isSelf: isMe) == .spectator, "spectating is chosen in the participation status")
            var online = live; online.eventFormat = .onlineLong; online.selfRole = .spectator
            try check(online.derivedSelfRole(isSelf: isMe) == .player, "online formats always play")
            var reserveJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reserve)) as? [String: Any] ?? [:]
            try check(try JSONDecoder().decode(GiriEvent.self, from: JSONEncoder().encode(reserve)).reserves == reserve.reserves, "reserves roundtrip")
            reserveJSON.removeValue(forKey: "hasReserves"); reserveJSON.removeValue(forKey: "reserves")
            let olderEvent = try JSONDecoder().decode(GiriEvent.self, from: JSONSerialization.data(withJSONObject: reserveJSON))
            try check(!olderEvent.hasReserves && olderEvent.reserves.isEmpty, "older events decode without reserves")

            var player = GiriPlayer(name: "まるお"); player.aliases = ["マルオ2号"]; player.prefecture = "大阪府"; player.region = "近畿"
            var playerJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(player)) as? [String: Any] ?? [:]
            for key in ["aliases", "mergesAliases", "prefecture"] { playerJSON.removeValue(forKey: key) }
            let olderPlayer = try JSONDecoder().decode(GiriPlayer.self, from: JSONSerialization.data(withJSONObject: playerJSON))
            try check(olderPlayer.aliases.isEmpty && olderPlayer.mergesAliases && olderPlayer.prefecture.isEmpty && olderPlayer.region == "近畿", "older players decode without aliases or a prefecture")
            var preferencesJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppPreferences())) as? [String: Any] ?? [:]
            preferencesJSON.removeValue(forKey: "mergesSelfAliases")
            try check(!(try JSONDecoder().decode(AppPreferences.self, from: JSONSerialization.data(withJSONObject: preferencesJSON))).mergesSelfAliases, "older settings keep self aliases shown separately")

            try check(giriRegion(ofPrefecture: "大阪") == "近畿" && giriRegion(ofPrefecture: "北海道") == "北海道" && giriPrefectureName("東京") == "東京都" && giriPrefectureName("関西") == nil, "prefectures map to regions")
            try check(giriRegionText(region: "関東", prefecture: "東京都") == "関東・東京都" && giriRegionText(region: "関西", prefecture: "") == "関西", "regions show with the prefecture and keep older free text")

            let aliasDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("GiriAliases-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: aliasDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: aliasDirectory) }
            let aliasStore = GiriStore(directory: aliasDirectory)
            var evening = GiriEvent(title: "夜の会"); evening.eventFormat = .live; evening.participants = ["マルオ2号", "Bさん"]
            try aliasStore.saveEvent(evening)
            var merged = GiriPlayer(name: "まるお"); merged.aliases = [" マルオ2号 ", "まるお", ""]
            try aliasStore.savePlayer(merged)
            guard let savedMerged = aliasStore.players.first(where: { $0.name == "まるお" }) else { throw GiriDataError.invalid("Missing alias player") }
            try check(savedMerged.aliases == ["マルオ2号"], "aliases are trimmed and never repeat the main name")
            try check(!aliasStore.playerDirectory.contains { $0.name == "マルオ2号" } && aliasStore.playerByName("マルオ2号")?.name == "まるお", "merged aliases are shown as the main player")
            try check(aliasStore.nameKeys(for: "まるお") == Set([playerSearchKey("まるお"), playerSearchKey("マルオ2号")]) && aliasStore.aliasOwner(of: "マルオ2号") == "まるお", "merged aliases count as the same person")
            // 0.13：「まとめて表示」は使わず、別名義はいつも本名義にまとめる。
            var separate = savedMerged; separate.mergesAliases = false
            try aliasStore.savePlayer(separate)
            try check(!aliasStore.playerDirectory.contains { $0.name == "マルオ2号" } && aliasStore.nameKeys(for: "まるお").contains(playerSearchKey("マルオ2号")) && aliasStore.aliasOwner(of: "マルオ2号") == "まるお", "aliases are always merged into the main name")
            var settings = aliasStore.preferences; settings.selfName = "わたし"
            try aliasStore.savePreferences(settings)
            var withSelfAlias = GiriEvent(title: "昼の会"); withSelfAlias.eventFormat = .live; withSelfAlias.participants = ["わたし別名"]
            try aliasStore.saveEvent(withSelfAlias)
            try check(aliasStore.playerDirectory.contains { $0.name == "わたし別名" }, "an unregistered name is listed")
            try aliasStore.saveSelfAliases(["わたし別名"], merges: false)
            try check(aliasStore.preferences.selfAliases == ["わたし別名"] && !aliasStore.playerDirectory.contains { $0.name == "わたし別名" } && aliasStore.nameKeys(for: "わたし").contains(playerSearchKey("わたし別名")), "self aliases are always merged into the user")
        }

        // 0.13 parallel prompts in a stage, next stage blocks, prompt styles, fill-in prompts and memo-style answers.
        do {
            var first = EventRound(); first.name = "予選1回戦"; first.block = "Bブロック"
            try check(giriRoundNumberText(first, in: [first]) == nil && !giriNextRoundIsParallel([first]), "a single prompt stage has no round number")
            var parallelFirst = first; parallelFirst.promptCount = 2
            try check(giriRoundNumberText(parallelFirst, in: [parallelFirst]) == "1回目" && giriNextRoundIsParallel([parallelFirst]), "1回目 with a total marks parallel prompts")
            let second = addNextRound(parallelFirst, sameStage: true, defaultStart: Date())
            try check(second.block == "Bブロック" && second.promptNumber == 2 && second.promptCount == nil && !giriNextRoundIsParallel([parallelFirst, second]), "the parallel round keeps the block until the total is reached")
            let nextStage = addNextRound(second, sameStage: false, defaultStart: Date())
            try check(nextStage.block.isEmpty && nextStage.promptNumber == 1 && nextStage.effectiveStageId != second.effectiveStageId, "a next stage starts with a new block")
            let casual = addNextRound(first, sameStage: false, tournament: false, defaultStart: Date())
            try check(casual.block == "Bブロック", "casual site rounds keep their block")
            try check(giriRoundNumberText(second, in: [parallelFirst, second]) == "2回目", "parallel rounds are numbered")
            var roundJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(parallelFirst)) as? [String: Any] ?? [:]
            roundJSON.removeValue(forKey: "promptCount")
            try check(try JSONDecoder().decode(EventRound.self, from: JSONSerialization.data(withJSONObject: roundJSON)).promptCount == nil, "older rounds decode without a prompt total")

            var note = ThoughtNote(); note.kind = .answers
            try check(note.effectivePromptStyle == .plain, "notes without an image are plain prompts")
            note.imageDataBase64 = "AAAA"
            try check(note.effectivePromptStyle == .image, "older notes with an image are image prompts")
            note.promptStyle = "fill"
            try check(note.effectivePromptStyle == .fill, "the chosen prompt style is kept")
            var noteJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(note)) as? [String: Any] ?? [:]
            noteJSON.removeValue(forKey: "promptStyle")
            try check(try JSONDecoder().decode(ThoughtNote.self, from: JSONSerialization.data(withJSONObject: noteJSON)).promptStyle.isEmpty, "older notes decode without a prompt style")
            var markJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AnswerRecord(text: "案", mark: "△"))) as? [String: Any] ?? [:]
            try check(markJSON["mark"] as? String == "△", "answer marks are saved")
            markJSON.removeValue(forKey: "mark")
            try check(try JSONDecoder().decode(AnswerRecord.self, from: JSONSerialization.data(withJSONObject: markJSON)).mark.isEmpty, "older answers decode without a mark")

            let prompt = "明日転校する予定の女子「ちょっと男子！〇〇〇」"
            try check(giriPromptBlankCount(prompt) == 1 && giriPromptBlankCount("〇〇が××した") == 2 && giriPromptBlankCount("○を付ける") == 0, "blanks are two or more marks")
            try check(giriFilledPromptText(prompt: prompt, answer: "そのカバンの膨らみは？") == "明日転校する予定の女子「ちょっと男子！そのカバンの膨らみは？」", "a fill-in answer is shown inside the prompt")
            let twoBlanks = giriFilledPromptSegments(prompt: "〇〇が××した", answer: "犬／走")
            try check(twoBlanks.map { $0.text } == ["犬", "が", "走", "した"] && twoBlanks.map { $0.isFill } == [true, false, true, false], "two blanks are filled in order")
            try check(giriFilledPromptText(prompt: "〇〇が××した", answer: "犬") == "犬が××した", "missing parts keep the blank")

            let memo = "・そのカバンの膨らみは何を示してるんだろうね\n△・外国人がカタコトとかじゃなく水って言ってた\n\n3・一番動いたやつが次の柱になる\n○新聞紙を開いた瞬間に全員の嘘がバレた\n3人で行った"
            let lines = giriAnswerLines(memo)
            try check(lines.map(\.mark) == ["", "△", "3", "〇", ""] && lines[1].text == "外国人がカタコトとかじゃなく水って言ってた" && lines[4].text == "3人で行った", "memo lines keep marks and plain answers")
            var submitted = AnswerRecord(text: "一番動いたやつが次の柱になる", isSubmitted: true, points: 12)
            let kept = giriReconcileAnswers(lines, previous: [AnswerRecord(text: "そのカバンの膨らみは何を示してるんだろうね"), submitted])
            try check(kept.count == 5 && kept[2].id == submitted.id && kept[2].isSubmitted && kept[2].points == 12 && kept[2].mark == "3", "rewriting the memo keeps the submitted answer and its result")
            submitted.text = "古い文"
            let edited = giriReconcileAnswers([GiriAnswerLine(mark: "", text: "直した文")], previous: [submitted])
            try check(edited.first?.id == submitted.id && edited.first?.isSubmitted == true, "an edited line keeps its place")
            try check(giriAnswerMemo(kept).components(separatedBy: "\n")[1] == "△・外国人がカタコトとかじゃなく水って言ってた", "answers return to the memo with their marks")

            let tiled = giriMergeTileLines([GiriOCRLine(text: "参加者 (3人)", midX: 0.2, midY: 0.400, height: 0.004),
                                            GiriOCRLine(text: "参加者 (3人)", midX: 0.2, midY: 0.401, height: 0.004),
                                            GiriOCRLine(text: "参加者 (3人)", midX: 0.2, midY: 0.700, height: 0.004)])
            try check(tiled.count == 2, "lines read twice in overlapping parts are merged")
            func row(_ text: String, _ y: Double, h: Double = 0.006) -> GiriOCRLine { GiriOCRLine(text: text, midX: 0.3, midY: y, height: h) }
            let noHeader = giriEventPageDraft(lines: [row("2026年10月18日[日] 13:00", 0.02, h: 0.010), row("ひかり杯", 0.04, h: 0.010), row("詳細", 0.10),
                                                      row("印象形式の大会！", 0.12, h: 0.012), row("【参加費】", 0.20), row("1000円(中高生500円)", 0.21)],
                                              known: [], venues: [])
            try check(noHeader.participants.isEmpty && noHeader.title == "ひかり杯" && noHeader.fee == 1000, "without a participants header nothing is read as a participant")
            try check(giriIsEventPageSectionStart("【第一回優勝者】") && giriIsEventPageSectionStart("詳細") && !giriIsEventPageSectionStart("ひかり杯"), "description headings end the title search")
        }

        // 0.13.1 OCR names: icon letters removed automatically, cut-off names matched against frequent players,
        // groups turned back into players.
        do {
            let known = ["かにスープ", "たくめシャーマン", "たくみ", "守"]
            let screen = ["参加者（4人）", "2守", "2すり身", "すり身", "たくめシャー…", "Kou"].enumerated().map { index, text in
                GiriOCRLine(text: text, midX: 0.2, midY: 0.1 + Double(index) * 0.05, height: 0.01)
            }
            let read = giriParticipantCandidates(lines: screen, known: known)
            try check(read.map(\.name) == ["守", "すり身", "たくめシャーマン", "Kou"] && read.allSatisfy { $0.suspiciousPrefix == nil }, "icon letters are removed from a screen and duplicates merged")
            try check(giriParticipantCandidates(text: "Aさん\n2守", known: []).map(\.name) == ["Aさん", "2守"], "pasted text keeps names that start with a letter")
            try check(read.first { $0.name == "守" }?.registered == "守" && read.first { $0.name == "すり身" }?.registered == nil, "registered and new people are told apart after removing the icon")
            try check(giriMatchRegisteredName("たくめ", truncated: true, known: ["たくめシャーマン", "たくめ長い名前"]) == "たくめシャーマン", "a cut-off name picks the first (most frequent) match")
            try check(giriMatchRegisteredName("たくぬシャ", truncated: true, known: ["たくめシャーマン"]) == "たくめシャーマン", "a cut-off name with a misread still matches")

            let groupDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("GiriGroupBack-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: groupDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: groupDirectory) }
            let groupStore = GiriStore(directory: groupDirectory)
            var hosted = GiriEvent(title: "まちがいの会"); hosted.eventFormat = .live; hosted.organizer = "さかなくん"
            try groupStore.saveEvent(hosted)
            let group = try groupStore.convertPlayerToGroup("さかなくん")
            try check(groupStore.events[0].organizerIsGroup && !groupStore.playerDirectory.contains { $0.name == "さかなくん" }, "a player can become a group")
            guard let saved = groupStore.groupDirectory.first(where: { $0.name == group.name }) else { throw GiriDataError.invalid("Missing group") }
            try groupStore.convertGroupToPlayer(saved.id)
            try check(!groupStore.events[0].organizerIsGroup && groupStore.groups.isEmpty && groupStore.playerDirectory.contains { $0.name == "さかなくん" }, "a group made by mistake goes back to a player")
        }

        // 0.13.1 企画 is stored as a casual meeting with a flag; optional application dates notify before the start.
        do {
            var project = GiriEvent(title: "企画の会"); project.eventFormat = .live; project.isProject = true
            try check(project.isProjectEvent && project.meetingTitle == "企画" && project.meetingFilterKey == "project" && project.meetingType == .casual, "企画 is a casual meeting with a flag")
            var tournamentProject = project; tournamentProject.meetingType = .tournament
            var onlineProject = project; onlineProject.eventFormat = .onlineLong
            try check(!tournamentProject.isProjectEvent && !onlineProject.isProjectEvent && EventFormat.hybrid.allowsProject, "企画 is only for casual live and spreadsheet events")
            var projectJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any] ?? [:]
            try check(projectJSON["meetingType"] as? String == "casual", "older readers still see a casual meeting")
            for key in ["isProject", "entryStart", "entryEnd"] { projectJSON.removeValue(forKey: key) }
            let olderProject = try JSONDecoder().decode(GiriEvent.self, from: JSONSerialization.data(withJSONObject: projectJSON))
            try check(!olderProject.isProject && olderProject.entryStart == nil && olderProject.entryEnd == nil, "older events decode without 企画 or application dates")
            let entryNow = GiriDates.parse("2026-11-05T00:00:00Z") ?? Date()
            var applying = GiriEvent(title: "応募のある会"); applying.eventFormat = .live; applying.isInterested = true
            applying.entryStart = entryNow.addingTimeInterval(86400); applying.entryEnd = entryNow.addingTimeInterval(3 * 86400)
            var entryPreferences = AppPreferences(notificationsEnabled: true); entryPreferences.reminderMinutes = 30
            let entryReminders = planNativeReminders(events: [applying], preferences: entryPreferences, now: entryNow)
            try check(entryReminders.contains { $0.id.hasSuffix(":entry-start") && $0.date == entryNow.addingTimeInterval(86400 - 1800) }, "the application start is notified before it opens")
            var canceledEntry = applying; canceledEntry.status = .canceled
            try check(!planNativeReminders(events: [canceledEntry], preferences: entryPreferences, now: entryNow).contains { $0.id.hasSuffix(":entry-start") }, "canceled events are not notified")
            let roundtrip = try JSONDecoder().decode(GiriEvent.self, from: JSONEncoder().encode(applying))
            try check(roundtrip.entryStart == applying.entryStart && roundtrip.entryEnd == applying.entryEnd, "application dates roundtrip")
        }

        // 0.14 break weeks announced by a site, past rounds added from the history, quick answers.
        do {
            let anchor = GiriDates.parse("2026-10-01T22:00:00Z") ?? Date()
            func day(_ offset: Int) -> Date { addCalendarDays(anchor, offset) }
            var site = OnlineSite(id: "break-site", name: "休みのあるサイト", recurrence: .weekly)
            site.submissionDays = 7; site.votingDays = 3
            site.cycleSettings = SiteCycleSettings(pattern: .overlapping, anchorStart: anchor, intervalDays: 7, anchorCycleNumber: 3)
            guard let plainSettings = site.cycleSettings else { throw GiriDataError.invalid("Missing break settings") }
            let settings = siteSettingsTogglingBreak(plainSettings, start: day(14), isBreak: true)
            var breakSite = site
            breakSite.cycleSettings = settings
            let rows = siteCycleDescriptors(breakSite, around: day(22)).filter { $0.kind == .regular }
            try check(!rows.contains { $0.start == day(14) }, "a break week creates no round")
            try check(rows.first { $0.start == day(21) }?.cycleNumber == 5 && rows.first { $0.start == day(7) }?.cycleNumber == 4, "rounds after a break are renumbered and earlier ones keep their numbers")
            try check(siteRegularCycleStart(settings, number: 5) == day(21) && siteRegularCycleStart(settings, number: 2) == day(-7), "a round number skips break weeks")
            let earlierBreak = siteSettingsTogglingBreak(settings, start: day(-7), isBreak: true)
            try check(siteRegularCycleStart(earlierBreak, number: 2) == day(-14) && siteRegularCycleNumber(earlierBreak, slotStart: day(-14), offset: -2) == 2, "breaks before the anchor are counted backwards")
            try check(siteSettingsTogglingBreak(settings, start: day(14), isBreak: false).breakStarts.isEmpty, "a break can be undone")
            try check(siteCurrentBreak(breakSite, now: day(15)) != nil && siteCurrentBreak(breakSite, now: day(22)) == nil, "the card shows a break only during its posting period")
            var capped = breakSite; capped.cycleSettings?.regularCycleCount = 5
            var lastRound = EventRound(); lastRound.submissionStart = day(21)
            lastRound = completeRoundSchedule(lastRound, submissionDays: 7, votingDays: 3)
            try check(siteSeasonLastCycleEnd(capped) == lastRound.votingEnd, "the season end moves back by a break week")
            let breakRoundtrip = try JSONDecoder().decode(SiteCycleSettings.self, from: JSONEncoder().encode(settings))
            try check(siteIsBreakStart(breakRoundtrip, day(14)) && breakRoundtrip.breakStarts.count == 1, "break weeks roundtrip")
            let plainJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plainSettings)) as? [String: Any] ?? [:]
            try check(plainJSON["breakStarts"] == nil, "settings without breaks keep the older JSON shape")
            let plainDecoded = try JSONDecoder().decode(SiteCycleSettings.self, from: JSONSerialization.data(withJSONObject: plainJSON))
            try check(plainDecoded.breakStarts.isEmpty, "older settings decode without breaks")
            try check(siteNextSeasonSettings(breakSite, firstDeadline: day(70)).breakStarts.isEmpty, "a new season starts without breaks")

            let breakDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("GiriBreak-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: breakDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: breakDirectory) }
            let breakStore = GiriStore(directory: breakDirectory)
            try breakStore.saveOnlineSite(site)
            guard let savedSite = breakStore.onlineSites.first else { throw GiriDataError.invalid("Missing break site") }
            let descriptors = siteCycleDescriptors(savedSite, around: day(22))
            guard let later = descriptors.first(where: { $0.start == day(21) }), let slot = descriptors.first(where: { $0.start == day(14) }) else {
                throw GiriDataError.invalid("Missing break descriptors")
            }
            try check(later.cycleNumber == 6, "without a break the later round is 6")
            let joined = try breakStore.createSiteCycle(savedSite.id, descriptor: later, join: true)
            try breakStore.createSiteCycle(savedSite.id, descriptor: slot, join: false)
            try breakStore.setSiteCycleBreak(savedSite.id, start: day(14), isBreak: true, now: day(22))
            let renumbered = breakStore.events.first { $0.id == joined.id }
            try check(renumbered?.siteCycleNumber == 5 && renumbered?.effectiveRounds.first?.name == "第5回", "a joined later round is renumbered after a break")
            try check(!breakStore.events.contains { $0.onlineSiteId == savedSite.id && $0.cycleKey == slot.cycleKey }, "the empty record of the break week is removed")
            try breakStore.setSiteCycleBreak(savedSite.id, start: day(14), isBreak: false, now: day(22))
            try check(breakStore.events.first { $0.id == joined.id }?.siteCycleNumber == 6, "undoing a break restores the numbers")

            var pastInput = SitePastCycleInput(deadline: day(-60))
            pastInput.cycleNumber = 1
            let past = try breakStore.addPastSiteCycle(savedSite.id, input: pastInput)
            try check(past.isActualParticipant && past.siteScheduleCustomized && past.siteCycleNumber == 1 && past.effectiveRounds.first?.submissionEnd == day(-60), "a past round is added from its deadline")
            var duplicateRejected = false
            do { _ = try breakStore.addPastSiteCycle(savedSite.id, input: pastInput) } catch { duplicateRejected = true }
            try check(duplicateRejected && breakStore.events.filter { $0.id == past.id }.count == 1, "the same past round is not added twice")
            try breakStore.ensureCurrentSiteCycles(now: day(22))
            try check(breakStore.events.contains { $0.id == past.id && $0.isActualParticipant }, "a past round survives the automatic rounds")

            var seasonSite = savedSite
            seasonSite.hasAffiliations = true
            seasonSite.cycleSettings?.seasonName = "第3シーズン"; seasonSite.cycleSettings?.seasonID = "s3"; seasonSite.cycleSettings?.ruleRevisionID = "r3"
            try check(siteHasComplexRules(seasonSite, events: []) && !siteHasComplexRules(site, events: []), "only league sites ask about rule changes")
            let current = sitePastSeasonIdentity(seasonSite, input: SitePastCycleInput(seasonName: "第3シーズン", deadline: day(0)), events: [])
            try check(current.isCurrent && current.seasonID == "s3" && current.ruleID == "r3", "the current season name joins the current season")
            var older = SitePastCycleInput(seasonName: "第2シーズン", deadline: day(-100))
            older.sameRulesAsCurrent = false
            let different = sitePastSeasonIdentity(seasonSite, input: older, events: [])
            try check(!different.isCurrent && different.seasonID?.hasPrefix("past-season:") == true && different.ruleID?.hasPrefix("past-rule:") == true, "a past season with different rules gets its own rule")
            older.sameRulesAsCurrent = true
            var recordedOlder = GiriEvent(title: "前のシーズン"); recordedOlder.onlineSiteId = seasonSite.id; recordedOlder.siteSeason = "第2シーズン"; recordedOlder.siteSeasonID = "s2"
            let same = sitePastSeasonIdentity(seasonSite, input: older, events: [recordedOlder])
            try check(same.seasonID == "s2" && same.ruleID == "r3", "a recorded past season is reused and the same rules keep the current rule")

            var note = ThoughtNote(title: "お題", kind: .answers)
            note.answerRecords = [AnswerRecord(id: "first", text: "最初の回答", isSubmitted: true)]
            note.usesAnswerRecords = true
            guard let added = giriNoteAddingAnswers(note, text: "〇 二つ目\n三つ目") else { throw GiriDataError.invalid("No answers added") }
            try check(added.answerRecords.map(\.text) == ["最初の回答", "二つ目", "三つ目"] && added.answerRecords[1].mark == "〇" && added.answerRecords[0].isSubmitted, "answers are added on the page without losing earlier ones")
            try check(giriNoteAddingAnswers(note, text: "  \n ") == nil, "blank input adds nothing")
            var round = EventRound(); round.submissionStart = day(0)
            round = completeRoundSchedule(round, submissionDays: 7, votingDays: 3)
            try check(giriThoughtCurrentDeadline(round, now: day(1)) == round.submissionEnd && giriThoughtCurrentDeadline(round, now: day(8)) == round.votingEnd, "the folded schedule shows the next deadline")
        }

        // 0.14 live tournament stages: laps in different blocks, prompts, automatic results, brackets, inner tournaments, furigana.
        do {
            try check(giriEditorNextStage("予選") == "本戦" && giriEditorNextStage("本戦") == "決勝" && giriEditorNextStage("本戦", live: false) == "準々決勝", "after the qualifier comes the main stage, then the final (live) or quarterfinal (net)")
            try check(nextStageName("予選") == "本戦" && nextStageName("準々決勝") == "準決勝" && nextStageName("2回戦") == "3回戦", "net tournaments use the same next stage names")
            try check(giriOpponentSlotCount("横並び5人") == 4 && giriOpponentSlotCount("横並び５人") == 4 && giriOpponentSlotCount("タイマン") == 1 && giriOpponentSlotCount("総当たり") == nil, "the lineup decides how many opponents there are")
            let candidates = giriOpponentCandidates(attendees: ["わたし", "はるか", "ゆう", "はるか", ""], chosen: ["ゆう"], isSelf: { $0 == "わたし" })
            try check(candidates == ["はるか"], "opponents come only from the attendees, without the user or people already chosen")

            var legacy = ResultStage(); legacy.name = "予選"; legacy.group = "Aブロック"; legacy.opponents = ["はるか"]; legacy.points = 7
            let migrated = giriNormalizedLaps(legacy, lapCount: 1)
            try check(migrated.count == 1 && migrated[0].group == "Aブロック" && migrated[0].opponents == ["はるか"] && migrated[0].points == [7], "an older stage becomes its first lap")
            var stage = legacy; stage.promptCount = 2; stage.votesPerPrompt = true; stage.judging = "印象審査"
            stage.laps = giriNormalizedLaps(stage, lapCount: 3)
            try check(stage.laps.count == 3 && stage.laps.allSatisfy { $0.points.count == 2 }, "three laps with a vote per prompt have two scores each")
            stage.laps[0].points = [3, 4]; stage.laps[1].points = [5, nil]; stage.laps[1].group = "Cブロック"; stage.laps[1].opponents = ["ゆう"]
            try check(giriStageTotal(stage) == 12 && giriLapTotal(stage.laps[1]) == 5, "lap and stage totals add the prompts")
            stage.borderScore = 10
            try check(giriSuggestedStageOutcome(stage) == nil, "nothing is decided before every lap has a score")
            stage.laps[2].points = [1, 0]
            try check(giriSuggestedStageOutcome(stage) == .advanced, "the total against the border decides advancement")
            let synced = giriStageSyncedFromLaps(stage)
            try check(synced.opponents == ["はるか", "ゆう"] && synced.group == "Aブロック・Cブロック" && synced.points == 13, "the stage keeps the union of opponents for player history")
            var single = stage; single.votesPerPrompt = false
            single.laps = giriNormalizedLaps(single, lapCount: 3)
            try check(single.laps[0].points == [7], "switching to one vote for all prompts keeps the lap total")
            var final = stage; final.name = "決勝"
            try check(giriSuggestedStageOutcome(final) == nil && giriStageOutcomeChoices(.final).contains(.champion) && !giriStageOutcomeChoices(.qualifier).contains(.champion), "finals are chosen by placement, other stages by advancement")
            var lap = StageLap(); lap.points = [6]; lap.others = [StageOtherScore(name: "はるか", points: 8), StageOtherScore(name: "ゆう", points: 2)]
            try check(giriLapPlacement(lap) == 2, "other people's scores give the block placement")
            var lost = ResultStage(); lost.name = "予選"; lost.outcome = .eliminated
            try check(giriSuggestedFinalChoice([lost]) == .eliminated, "a qualifier loss is the final result")

            let bracket = ["わたし", "はるか", "ゆう", "まこ"]
            var semi = ResultStage(); semi.name = "準決勝"; semi.lineup = "タイマン"; semi.outcome = .advanced
            let next = giriNextBracketStage([semi], bracket: bracket, isSelf: { $0 == "わたし" })
            try check(next?.name == "決勝" && next?.lineup == "タイマン" && next?.opponents.isEmpty == true, "winning a bracket round adds the next round")
            try check(giriNextBracketStage([semi, next ?? ResultStage()], bracket: bracket, isSelf: { $0 == "わたし" }) == nil, "the next round is added only once")

            func block(_ text: String, _ x: Double, _ y: Double) -> GiriOCRLine { GiriOCRLine(text: text, midX: x, midY: y, height: 0.01) }
            let table = giriBlockTable([block("Aブロック", 0.2, 0.1), block("Bブロック", 0.7, 0.1), block("わたし", 0.2, 0.2), block("はるか", 0.2, 0.25),
                                        block("ゆう", 0.7, 0.2), block("まこ", 0.7, 0.25)])
            try check(table == [GiriBlockEntry(name: "Aブロック", members: ["わたし", "はるか"]), GiriBlockEntry(name: "Bブロック", members: ["ゆう", "まこ"])], "a block table is read by headings and columns")
            try check(giriBlockHeading("第2組") != nil && giriBlockHeading("ブロックC") != nil && giriBlockHeading("はるか") == nil, "block headings")

            var lapStage = stage
            lapStage.advancedWith = ["はるか"]
            let stageJSON = try JSONEncoder().encode(lapStage)
            try check(try JSONDecoder().decode(ResultStage.self, from: stageJSON) == lapStage, "laps, prompts and advancing players roundtrip")
            let plainJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any] ?? [:]
            try check(plainJSON["laps"] == nil && plainJSON["promptCount"] == nil && plainJSON["advancedWith"] == nil, "stages without laps keep the older JSON shape")
            try check(try JSONDecoder().decode(ResultStage.self, from: JSONSerialization.data(withJSONObject: plainJSON)).laps.isEmpty, "older stages decode without laps")

            let innerDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("GiriInner-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: innerDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: innerDirectory) }
            let innerStore = GiriStore(directory: innerDirectory)
            var day = GiriEvent(title: "ひかりの会"); day.eventFormat = .live; day.venue = "ひかりホール"; day.participants = ["わたし", "はるか"]
            day.eventDate = GiriDates.parse("2026-11-01T00:00:00Z")
            try innerStore.saveEvent(day)
            let inner = try innerStore.addTournament(inside: day.id)
            try check(inner.parentEventId == day.id && inner.meetingType == .tournament && inner.venue == "ひかりホール" && inner.participants == day.participants && inner.eventDate == innerStore.events.first(where: { $0.id == day.id })?.eventDate, "a tournament inside the day copies its basics")
            let again = try innerStore.addTournament(inside: inner.id)
            try check(again.parentEventId == day.id && again.title == "ひかりの会 大会2", "more tournaments stay inside the same day")
            let eventJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(day)) as? [String: Any] ?? [:]
            try check(eventJSON["parentEventId"] == nil, "events without a parent keep the older JSON shape")
            try innerStore.deleteEvent(day.id)
            try check(innerStore.events.allSatisfy { $0.parentEventId == nil } && innerStore.events.count == 2, "deleting the day keeps its tournaments")

            try check(giriFuriganaCandidate("カタカナ") == "かたかな" && giriFuriganaCandidate("Kou").isEmpty, "furigana candidates are hiragana and skip latin names")
            let reading = giriFuriganaCandidate("山田")
            try check(!reading.isEmpty && reading.range(of: #"^[\p{Hiragana}ー]+$"#, options: .regularExpression) != nil, "kanji names get a hiragana reading candidate")
            let player = innerStore.playerDirectory.first { $0.name == "はるか" }
            try innerStore.saveFurigana(players: [player?.id ?? "": "はるか"], venues: [innerStore.venueDirectory.first?.id ?? "": "ひかりほーる"])
            try check(innerStore.playerDirectory.first { $0.name == "はるか" }?.furigana == "はるか" && innerStore.venueDirectory.first?.furigana == "ひかりほーる", "furigana is saved in bulk, also for names only in records")
            var venue = GiriVenue(name: "古い会場")
            let venueJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(venue)) as? [String: Any] ?? [:]
            try check(venueJSON["furigana"] == nil, "venues without furigana keep the older JSON shape")
            venue.furigana = "ふるいかいじょう"
            try check(try JSONDecoder().decode(GiriVenue.self, from: JSONEncoder().encode(venue)).furigana == "ふるいかいじょう", "venue furigana roundtrips")
        }

        print("Native domain regressions passed: \(passed)")
    }
}
