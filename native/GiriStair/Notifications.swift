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
func planNativeReminders(events: [GiriEvent], preferences: AppPreferences, now: Date = Date(), limit: Int = 64) -> [GiriNativeReminder] {
    guard preferences.notificationsEnabled, limit > 0 else { return [] }
    var reminders: [GiriNativeReminder] = []
    func append(_ event: GiriEvent, _ key: String, _ body: String, _ date: Date) {
        if date > now { reminders.append(GiriNativeReminder(id: event.id + ":" + key, eventID: event.id, title: event.title, body: body, date: date)) }
    }
    for event in events where event.isParticipating && event.status != .canceled {
        let lead = TimeInterval(preferences.reminderMinutes * 60)
        if event.kind == .live {
            guard event.status == .planned else { continue }
            let venue = event.venue.isEmpty ? "" : "・" + event.venue
            if let start = event.startsAt {
                append(event, "start", (preferences.reminderMinutes == 0 ? "開始時刻です" : "開始\(preferences.reminderMinutes)分前です") + venue, start.addingTimeInterval(-lead))
            } else if let day = event.eventDate,
                      let date = Calendar.current.date(bySettingHour: preferences.reminderHour, minute: preferences.reminderMinute, second: 0, of: day) {
                append(event, "day", "今日は参加予定の日です" + venue, date)
            }
        } else {
            for round in event.effectiveRounds {
                let escapedID = round.id.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.!~*'()"))) ?? round.id
                let prefix = event.rounds.isEmpty ? "" : "round:\(escapedID):"
                var labels: [String] = []
                if event.meetingType == .tournament && !event.rounds.isEmpty && !round.name.isEmpty { labels.append(round.name) }
                if !event.rounds.isEmpty { labels.append("お題\(round.promptNumber)") }
                for label in [event.affiliation, event.block, round.block] where !label.isEmpty && !labels.contains(label) { labels.append(label) }
                let label = labels.isEmpty ? "" : labels.joined(separator: "・") + "・"
                if event.status == .planned && round.submissionEnabled, let deadline = round.submissionEnd {
                    append(event, prefix + "submission", label + (preferences.reminderMinutes == 0 ? "投稿の締切です" : "投稿締切の\(preferences.reminderMinutes)分前です"), deadline.addingTimeInterval(-lead))
                }
                if round.votingRequired, let deadline = round.votingEnd {
                    append(event, prefix + "voting", label + (preferences.reminderMinutes == 0 ? "投票の締切です" : "投票締切の\(preferences.reminderMinutes)分前です"), deadline.addingTimeInterval(-lead))
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
                for reminder in planNativeReminders(events: events, preferences: preferences) {
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
