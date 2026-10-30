import Foundation

/// Calendar arithmetic deliberately preserves wall-clock time across DST.
func addCalendarDays(_ value: Date, _ days: Int, calendar: Calendar = .current) -> Date {
    calendar.date(byAdding: .day, value: days, to: value) ?? value
}
func fiveMinuteSelection(_ value: Date, calendar: Calendar = .current) -> Date {
    var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: value)
    parts.minute = (parts.minute ?? 0) / 5 * 5
    return calendar.date(from: parts) ?? value
}
func defaultSubmissionStart(_ day: Date, preferences: AppPreferences, calendar: Calendar = .current) -> Date {
    let shifted = addCalendarDays(day, preferences.submissionStartDayOffset, calendar: calendar)
    return calendar.date(bySettingHour: preferences.submissionStartHour, minute: preferences.submissionStartMinute, second: 0, of: shifted) ?? shifted
}
func completeRoundSchedule(_ value: EventRound, submissionDays: Int = 7, votingDays: Int = 7) -> EventRound {
    guard let start = value.submissionStart else { return value }
    var round = value
    let end = round.submissionEnd ?? addCalendarDays(start, submissionDays)
    let voting = round.votingStart ?? end
    round.submissionEnd = end; round.votingStart = voting
    round.votingEnd = round.votingEnd ?? addCalendarDays(voting, votingDays)
    return round
}
func siteCycleStart(_ site: OnlineSite, weekOf: Date, weekOffset: Int = 0, calendar: Calendar = .current) -> Date {
    let offset: Int
    if site.recurrence == .weekly {
        // Dart weekday is Mon=1 ... Sun=7; Foundation is Sun=1 ... Sat=7.
        // The existing app's week boundary is Sunday, independently of locale.
        let currentWeekday = calendar.component(.weekday, from: weekOf) - 1
        offset = -currentWeekday + site.weekday % 7 + weekOffset * 7
    } else { offset = weekOffset * (site.submissionDays + site.votingDays) }
    let day = addCalendarDays(weekOf, offset, calendar: calendar)
    return calendar.date(bySettingHour: site.startHour, minute: site.startMinute, second: 0, of: day) ?? day
}
func cycleKeyFor(_ start: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    return formatter.string(from: start)
}
func nextStageName(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if let expression = try? NSRegularExpression(pattern: "^(.*?)([0-9]+)回戦$"),
       let match = expression.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
       let prefixRange = Range(match.range(at: 1), in: trimmed), let numberRange = Range(match.range(at: 2), in: trimmed),
       let number = Int(trimmed[numberRange]) { return "\(trimmed[prefixRange])\(number + 1)回戦" }
    if trimmed.contains("予選") { return "本戦1回戦" }
    if trimmed.contains("準々決勝") { return "準決勝" }
    if trimmed.contains("準決勝") { return "決勝" }
    if trimmed.contains("決勝") { return "追加日程" }
    return "予選1回戦"
}
func addNextRound(_ previous: EventRound?, id: String = UUID().uuidString, sameStage: Bool = false, tournament: Bool = true, defaultStart: Date, submissionDays: Int = 7, votingDays: Int = 7, calendar: Calendar = .current) -> EventRound {
    var round = EventRound(id: id)
    round.name = tournament ? (sameStage ? previous?.name ?? nextStageName("") : nextStageName(previous?.name ?? "")) : "投稿・投票"
    round.stageId = sameStage ? previous?.effectiveStageId ?? id : id
    round.promptNumber = sameStage ? (previous?.promptNumber ?? 0) + 1 : 1
    round.block = previous?.block ?? ""
    round.submissionStart = previous?.votingEnd ?? previous?.submissionEnd ?? defaultStart
    guard let start = round.submissionStart else { return round }
    func inherit(_ from: Date?, _ to: Date?, onto base: Date, fallbackDays: Int) -> Date {
        guard let from, let to else { return addCalendarDays(base, fallbackDays, calendar: calendar) }
        // Calendar components preserve the previous wall-clock duration across
        // DST, including an intentional gap/overlap before voting starts.
        let duration = calendar.dateComponents([.day, .hour, .minute, .second, .nanosecond], from: from, to: to)
        return calendar.date(byAdding: duration, to: base) ?? base.addingTimeInterval(to.timeIntervalSince(from))
    }
    round.submissionEnd = inherit(previous?.submissionStart, previous?.submissionEnd, onto: start, fallbackDays: submissionDays)
    if let end = round.submissionEnd {
        round.votingStart = inherit(previous?.submissionEnd, previous?.votingStart, onto: end, fallbackDays: 0)
    }
    if let voting = round.votingStart {
        round.votingEnd = inherit(previous?.votingStart, previous?.votingEnd, onto: voting, fallbackDays: votingDays)
    }
    return round
}
func nextEventRound(rounds: [EventRound], id: String = UUID().uuidString, preferences: AppPreferences, sameStage: Bool = false, tournament: Bool = true, referenceDate: Date = Date(), calendar: Calendar = .current) -> EventRound {
    addNextRound(rounds.last, id: id, sameStage: sameStage, tournament: tournament, defaultStart: defaultSubmissionStart(referenceDate, preferences: preferences, calendar: calendar), submissionDays: preferences.submissionDays, votingDays: preferences.votingDays, calendar: calendar)
}
func eventNeedsResult(_ event: GiriEvent, now: Date = Date()) -> Bool {
    guard event.eventFormat == .live, event.meetingType == .tournament, event.isActualParticipant, !event.hasFinalResult else { return false }
    if let end = event.endsAt { return now >= end }
    guard let day = event.eventDate ?? event.startsAt else { return false }
    let next = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: day)) ?? day
    return now >= next
}
