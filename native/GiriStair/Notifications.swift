import Foundation
import UserNotifications

struct GiriNativeReminder: Identifiable {
    let id: String
    let eventID: String
    let title: String
    let body: String
    let date: Date
}

/// One planner for native iPhone reminders. A stage result never removes a
/// later voting obligation; only submissionEnabled / votingRequired do that.
func planNativeReminders(events: [GiriEvent], preferences: AppPreferences, sites: [OnlineSite] = [], now: Date = Date(), limit: Int = 64) -> [GiriNativeReminder] {
    guard preferences.notificationsEnabled, limit > 0 else { return [] }
    var reminders: [GiriNativeReminder] = []
    // 0.23：通知の種類ごとの何分前（未設定は以前の版と同じく reminderMinutes）。
    let deadlineLead = max(0, preferences.deadlineLeadMinutes ?? preferences.reminderMinutes)
    let beforeLead = max(0, preferences.beforeMinutes ?? preferences.reminderMinutes)
    func append(_ event: GiriEvent, _ key: String, _ body: String, _ date: Date) {
        if date > now { reminders.append(GiriNativeReminder(id: event.id + ":" + key, eventID: event.id, title: event.title, body: body, date: date)) }
    }
    // 通常サイトでまだ参加を決めていない回：新しいお題と投稿締切だけを知らせる。
    // 見送った回・休止中のサイト・興味あり／キャンセルは知らせない。
    let activeSiteIDs = Set(sites.filter { !$0.isPaused }.map(\.id))
    for event in events where !event.isActualParticipant && !event.siteSkipped && !event.isInterested && event.status != .canceled {
        guard let siteID = event.onlineSiteId, activeSiteIDs.contains(siteID) else { continue }
        for round in event.effectiveRounds {
            if let start = round.submissionStart {
                append(event, "site-open:" + round.id, "新しいお題が出ました", start)
            }
            if preferences.deadlineBeforeNotify, round.submissionEnabled, let deadline = round.submissionEnd {
                append(event, "site-submission:" + round.id, deadlineLead == 0 ? "投稿の締切です（参加・見送りを選べます）" : "投稿締切の" + giriLeadText(deadlineLead) + "前です（参加・見送りを選べます）", deadline.addingTimeInterval(-TimeInterval(deadlineLead * 60)))
            }
        }
    }
    // エントリー開始・締切（任意。0.28 で「募集」から名前を変えた）：参加・興味ありのどちらでも、キャンセルした会以外に知らせる。
    // 0.19：LiveStair のチケット通知と同じく、開始前の通知と開始時の通知を分けて設定する。
    for event in events where event.status != .canceled && event.onlineSiteId == nil {
        let leadMinutes = preferences.entryLeadMinutes ?? preferences.reminderMinutes
        // 0.28：エントリー締切の前（ネットの大会など）。締切の時刻だけ入れた会にも出す。
        if preferences.entryEndNotify, let end = event.entryEnd {
            append(event, "entry-end", leadMinutes > 0 ? "エントリー締切の" + giriLeadText(leadMinutes) + "前です" : "エントリー締切の時刻です",
                   end.addingTimeInterval(-TimeInterval(leadMinutes * 60)))
        }
        guard let start = event.entryStart else { continue }
        if preferences.entryNotifyBefore && leadMinutes > 0 {
            append(event, "entry-start", "エントリー開始の" + giriLeadText(leadMinutes) + "前です", start.addingTimeInterval(-TimeInterval(leadMinutes * 60)))
        } else if preferences.entryNotifyBefore && !preferences.entryNotifyAtStart {
            append(event, "entry-start", "エントリー開始の時刻です", start)
        }
        if preferences.entryNotifyAtStart { append(event, "entry-open", "エントリーが始まりました", start) }
    }
    for event in events where event.isActualParticipant {
        if event.eventFormat.hasLiveTiming {
            let venue = event.venue.isEmpty ? "" : "・" + event.venue
            // 会の前の通知：基準（開始・開場）の何分前。開場が分からない時は開始を基準にする。
            let usesOpen = preferences.beforeBase == "open" && event.opensAt != nil
            if preferences.beforeNotify, let base = usesOpen ? event.opensAt : event.startsAt {
                let name = usesOpen ? "開場" : "開始"
                append(event, "start", (beforeLead == 0 ? name + "時刻です" : name + "の" + giriLeadText(beforeLead) + "前です") + venue, base.addingTimeInterval(-TimeInterval(beforeLead * 60)))
            }
            // 当日通知：会の日の決まった時刻（時刻未定の会も）。始まる時刻がそれより早い時は出さない。
            if preferences.dayNotify, let day = event.eventDate ?? event.startsAt,
               let date = Calendar.current.date(bySettingHour: preferences.reminderHour, minute: preferences.reminderMinute, second: 0, of: day),
               (event.opensAt ?? event.startsAt).map({ date < $0 }) ?? true {
                append(event, "day", "今日は参加予定の日です" + venue, date)
            }
        }
        if event.eventFormat.hasOnlineRounds {
            for round in event.effectiveRounds {
                let escapedID = round.id.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.!~*'()"))) ?? round.id
                let prefix = event.rounds.isEmpty ? "" : "round:\(escapedID):"
                var labels: [String] = []
                if event.meetingType == .tournament && !event.rounds.isEmpty && !round.name.isEmpty { labels.append(round.name) }
                // 大会は並列のお題がある段階だけ「N回目」を付ける。
                if !event.rounds.isEmpty {
                    if event.meetingType != .tournament { labels.append("\(round.promptNumber)回目") }
                    else if let number = giriRoundNumberText(round, in: event.effectiveRounds) { labels.append(number) }
                }
                for label in [event.affiliation, event.block, round.block] where !label.isEmpty && !labels.contains(label) { labels.append(label) }
                let label = labels.isEmpty ? "" : labels.joined(separator: "・") + "・"
                let lead = TimeInterval(deadlineLead * 60)
                if round.submissionEnabled, let deadline = round.submissionEnd {
                    if preferences.deadlineBeforeNotify && (deadlineLead > 0 || !preferences.deadlineAtNotify) {
                        append(event, prefix + "submission", label + (deadlineLead == 0 ? "投稿の締切です" : "投稿締切の" + giriLeadText(deadlineLead) + "前です"), deadline.addingTimeInterval(-lead))
                    }
                    if preferences.deadlineAtNotify { append(event, prefix + "submission-at", label + "投稿の締切になりました", deadline) }
                }
                if round.votingRequired, let deadline = round.votingEnd {
                    if preferences.deadlineBeforeNotify && (deadlineLead > 0 || !preferences.deadlineAtNotify) {
                        append(event, prefix + "voting", label + (deadlineLead == 0 ? "投票の締切です" : "投票締切の" + giriLeadText(deadlineLead) + "前です"), deadline.addingTimeInterval(-lead))
                    }
                    if preferences.deadlineAtNotify { append(event, prefix + "voting-at", label + "投票の締切になりました", deadline) }
                }
            }
        }
    }
    return Array(reminders.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }.prefix(min(64, limit)))
}

@MainActor enum NotificationsCoordinator {
    private static var pending: Task<Void, Never>?
    private static var generation = 0

    static func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func sync(store: GiriStore) async {
        generation += 1
        let currentGeneration = generation
        let events = store.events
        let preferences = store.preferences
        let sites = store.onlineSites
        let previous = pending
        let task = Task { @MainActor in
            if let previous { await previous.value }
            guard currentGeneration == generation else { return }
            let center = UNUserNotificationCenter.current()
            // Remove Flutter-era numeric IDs as well as native IDs. This app's
            // entire notification schedule is owned by the same local planner.
            center.removeAllPendingNotificationRequests()
            guard preferences.notificationsEnabled else { return }
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                store.errorMessage = "通知が許可されていません。端末の「設定」でGiriStairの通知を確認してください。"
                return
            }
            do {
                for reminder in planNativeReminders(events: events, preferences: preferences, sites: sites) {
                    let content = UNMutableNotificationContent()
                    content.title = reminder.title
                    content.body = reminder.body
                    content.sound = .default
                    content.userInfo = ["eventID": reminder.eventID]
                    var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.date)
                    components.calendar = Calendar.current
                    components.timeZone = TimeZone.current
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
                }
            } catch { store.errorMessage = "通知を予約できませんでした。\(error.localizedDescription)" }
        }
        pending = task
        await task.value
        if currentGeneration == generation { pending = nil }
    }
}

/// 「60分」「2時間」「1日」などの通知の前の時間。
func giriLeadText(_ minutes: Int) -> String {
    if minutes >= 1440 && minutes % 1440 == 0 { return "\(minutes / 1440)日" }
    if minutes >= 60 && minutes % 60 == 0 { return "\(minutes / 60)時間" }
    return "\(minutes)分"
}
