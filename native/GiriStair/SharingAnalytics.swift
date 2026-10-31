import Foundation

/// Sharing and statistics use the same date. An online record belongs to its
/// last known deadline rather than the time it was entered into the app.
func giriAnalyticsDate(_ event: GiriEvent) -> Date? {
    if event.eventFormat == .live { return event.eventDate ?? event.startsAt }
    return event.participationEndDate ?? event.eventDate ?? event.startsAt
}

struct GiriMonthCount: Identifiable, Equatable {
    let date: Date
    let format: EventFormat
    let count: Int
    var id: String { "\(date.timeIntervalSince1970):\(format.rawValue)" }
}

struct GiriMonthlySeries: Equatable {
    let months: [Date]
    let values: [GiriMonthCount]
    /// The maximum stacked monthly total, used for an integer count axis.
    let maximum: Int
    let start: Date
    /// Exclusive end: the first day of the year after the final displayed year.
    let end: Date
}

/// Callers supply their already-filtered records. Include empty months so a
/// single record keeps the same twelve-month scale as a populated year.
func giriMonthlySeries(
    events: [GiriEvent],
    year: Int? = nil,
    calendar: Calendar = .current,
    now: Date = Date()
) -> GiriMonthlySeries {
    let dated = events.compactMap { event -> (GiriEvent, Date)? in
        guard let date = giriAnalyticsDate(event) else { return nil }
        return (event, date)
    }
    let availableYears = dated.map { calendar.component(.year, from: $0.1) }
    let currentYear = calendar.component(.year, from: now)
    let selectedYear = year.flatMap { $0 > 0 ? $0 : nil }
    let firstYear = selectedYear ?? availableYears.min() ?? currentYear
    let lastYear = selectedYear ?? availableYears.max() ?? currentYear
    let start = calendar.date(from: DateComponents(year: firstYear, month: 1, day: 1))
        ?? calendar.dateInterval(of: .year, for: now)?.start
        ?? now
    let end = calendar.date(byAdding: .year, value: lastYear - firstYear + 1, to: start)
        ?? calendar.date(byAdding: .year, value: 1, to: start)
        ?? start

    var months: [Date] = []
    var cursor = start
    while cursor < end {
        months.append(cursor)
        guard let next = calendar.date(byAdding: .month, value: 1, to: cursor), next > cursor else { break }
        cursor = next
    }

    var counts: [Date: [EventFormat: Int]] = [:]
    for (event, date) in dated where date >= start && date < end {
        guard let month = calendar.dateInterval(of: .month, for: date)?.start else { continue }
        counts[month, default: [:]][event.eventFormat, default: 0] += 1
    }
    let values = months.flatMap { month in
        EventFormat.allCases.map { format in
            GiriMonthCount(date: month, format: format, count: counts[month]?[format] ?? 0)
        }
    }
    let maximum = months.map { month in counts[month]?.values.reduce(0, +) ?? 0 }.max() ?? 0
    return GiriMonthlySeries(months: months, values: values, maximum: maximum, start: start, end: end)
}
