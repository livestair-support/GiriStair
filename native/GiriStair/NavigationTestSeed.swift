#if DEBUG
import Foundation

/// UI regressions use an isolated container and never read or replace the
/// user's Documents/giristair.json. This code is absent from release builds.
@MainActor
enum GiriNavigationTestSeed {
    static func makeStore() -> GiriStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GiriNavigationTest-\(UUID().uuidString)", isDirectory: true)
        let store = GiriStore(directory: directory)
        do {
            var preferences = store.preferences
            preferences.onboardingCompleted = true
            preferences.selfName = "テスト本人"
            preferences.hasShownInitialResultPrompt = true
            try store.savePreferences(preferences)
            let now = Date()
            let minimal = ProcessInfo.processInfo.arguments.contains("--uitest-minimal-navigation")
            let formats: [EventFormat] = minimal ? [.live] : EventFormat.allCases
            for format in formats {
                for tournament in minimal ? [false] : [false, true] {
                    var event = GiriEvent(title: "\(format.title)・\(tournament ? "大会" : "通常")")
                    event.id = "navigation-\(format.rawValue)-\(tournament ? "tournament" : "casual")"
                    event.eventFormat = format
                    event.meetingType = tournament ? .tournament : .casual
                    event.organizer = "主催者"
                    event.participants = ["テスト本人", "たくめシャーマン", "3104", "ところざわ", "あると", "永森"]
                    if format.hasLiveTiming {
                        event.eventDate = Calendar.current.startOfDay(for: now)
                        event.startsAt = now.addingTimeInterval(3600)
                        event.endsAt = now.addingTimeInterval(7200)
                    }
                    if format.hasOnlineRounds {
                        var round = EventRound(name: "予選1回戦")
                        round.submissionStart = now.addingTimeInterval(-86400)
                        round.submissionEnd = now.addingTimeInterval(86400)
                        round.votingStart = round.submissionEnd
                        round.votingEnd = now.addingTimeInterval(86400 * 4)
                        event.rounds = [round]
                    }
                    try store.saveEvent(event)
                }
            }
            if !minimal {
            var completed = GiriEvent(title: "共有グラフの1件")
            completed.id = "navigation-completed"
            completed.eventFormat = .live
            completed.meetingType = .casual
            completed.startsAt = now.addingTimeInterval(-86400 * 2)
            completed.endsAt = now.addingTimeInterval(-86400)
            completed.eventDate = Calendar.current.startOfDay(for: completed.startsAt ?? now)
            try store.saveEvent(completed)
            }
            if !ProcessInfo.processInfo.arguments.contains("--uitest-without-sites") {
            var site = OnlineSite(name: "大喜利天文台", recurrence: .weekly)
            site.hasAffiliations = true
            site.affiliation = "一部"
            // Match the user's 0.6 configuration: the current absolute round
            // number exceeds the short season template. Tab navigation must
            // remain responsive even for this valid legacy combination.
            site.cycleSettings = SiteCycleSettings(pattern: .overlapping,
                anchorStart: now, intervalDays: 7, anchorCycleNumber: 38,
                seasonName: "シーズン1", seasonLengthDays: 1,
                regularCycleCount: 8, leagues: ["一部", "二部"])
            try store.saveOnlineSite(site)
            try store.ensureCurrentSiteCycles()
            }
        } catch {
            preconditionFailure("Could not prepare isolated navigation fixture: \(error)")
        }
        return store
    }
}
#endif
