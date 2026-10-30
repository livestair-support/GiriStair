import Foundation

/// Display-only adapters for LiveStair 074206d2. Keep JSON dates in GiriDates.
/// CommonUI.swift: liveDateDisplayText / liveDateWeekdayBadgeText;
/// ContentView.swift: liveListCompactDateText / liveListTimeText / month title;
/// TicketScheduleViews.swift: ticketScheduleDateText.
enum GiriDateText {
    static func day(_ date: Date?, compact: Bool = false) -> String {
        guard let date else { return "日付未定" }
        return render(date, format: compact ? "yyyy/M/d" : "yyyy年M月d日") + weekdayBadge(date)
    }

    static func month(_ date: Date) -> String {
        render(date, format: "yyyy年M月")
    }

    static func monthDay(_ date: Date?) -> String {
        guard let date else { return "日付未定" }
        return render(date, format: "M/d")
    }

    static func calendarDay(_ date: Date?) -> String {
        guard let date else { return "日付未定" }
        return render(date, format: "M月d日") + weekdayBadge(date)
    }

    static func weekday(_ date: Date?) -> String {
        guard let date else { return "" }
        let day = Calendar(identifier: .gregorian).component(.weekday, from: date)
        return ["日", "月", "火", "水", "木", "金", "土"][max(0, min(day - 1, 6))]
    }

    static func weekdayBadge(_ date: Date?) -> String {
        guard let date else { return "" }
        let suffix = JapaneseHolidayCalendar.holidayName(for: date) == nil ? "" : "祝"
        return "(\(weekday(date))\(suffix))"
    }

    static func time(_ date: Date?) -> String {
        guard let date else { return "--:--" }
        return render(date, format: "H:mm")
    }

    static func timeRange(_ start: Date?, _ end: Date?) -> String {
        let values = [start, end].compactMap { $0 }.map { time($0) }
        return values.isEmpty ? "--:--" : values.joined(separator: " / ")
    }

    static func dateTime(_ date: Date?, includesYear: Bool = false) -> String {
        guard let date else { return "未定" }
        return render(date, format: includesYear ? "yyyy年M月d日(E) H:mm" : "M/d(E) H:mm")
    }

    /// SettingsView.swift uses Japanese medium date + short time for backups.
    static func backupDateTime(_ date: Date?) -> String {
        guard let date else { return "未定" }
        let formatter = makeFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func render(_ date: Date, format: String) -> String {
        let formatter = makeFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private static func makeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        return formatter
    }
}
