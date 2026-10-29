import SwiftUI
import Foundation

struct GiriCalendarPeriod: Identifiable {
    enum Phase: String { case live, submission, voting }
    let event: GiriEvent
    let round: EventRound?
    let start: Date
    let end: Date
    let phase: Phase
    var id: String { "\(event.id)/\(round?.id ?? "live")/\(phase.rawValue)" }
    var title: String {
        switch phase { case .live: "生大喜利"; case .submission: "投稿"; case .voting: "投票" }
    }
    var color: Color {
        switch phase { case .live: AppSectionAccent.live; case .submission: AppSectionAccent.artist; case .voting: AppSectionAccent.memo }
    }
    func overlaps(_ day: Date) -> Bool {
        let from = Calendar.current.startOfDay(for: day)
        guard let to = Calendar.current.date(byAdding: .day, value: 1, to: from) else { return false }
        return start < to && end > from
    }
    static func make(events: [GiriEvent]) -> [GiriCalendarPeriod] {
        var periods: [GiriCalendarPeriod] = []
        func add(_ event: GiriEvent, _ round: EventRound?, _ start: Date?, _ end: Date?, _ phase: Phase) {
            guard let start, let end, start < end else { return }
            periods.append(GiriCalendarPeriod(event: event, round: round, start: start, end: end, phase: phase))
        }
        for event in events where event.status != .canceled {
            if event.kind == .live {
                let start = event.startsAt ?? event.eventDate
                let end = event.endsAt ?? start.flatMap {
                    Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: $0))
                }
                add(event, nil, start, end, .live)
            } else {
                for round in event.effectiveRounds {
                    if round.submissionEnabled { add(event, round, round.submissionStart, round.submissionEnd, .submission) }
                    if round.votingRequired { add(event, round, round.votingStart, round.votingEnd, .voting) }
                }
            }
        }
        return periods.sorted {
            if $0.start == $1.start { return $0.id < $1.id }
            return $0.start < $1.start
        }
    }
}

enum GiriCalendarRules {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.timeZone = .autoupdatingCurrent
        calendar.firstWeekday = 1
        return calendar
    }
    static func monthStart(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
    static func dayColor(_ day: Date, ordinary: Color = .primary) -> Color {
        let weekday = calendar.component(.weekday, from: day)
        if weekday == 1 || JapaneseHolidayCalendar.holidayName(for: day) != nil { return .red }
        if weekday == 7 { return .blue }
        return ordinary
    }
    static func gridDays(_ month: Date) -> [Date] {
        let first = monthStart(month)
        let offset = calendar.component(.weekday, from: first) - 1
        let dayCount = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let cellCount = ((offset + dayCount + 6) / 7) * 7
        return (0..<cellCount).compactMap { calendar.date(byAdding: .day, value: $0 - offset, to: first) }
    }
    static func periodLanes(_ periods: [GiriCalendarPeriod], week: [Date]) -> [[GiriCalendarPeriod]] {
        var lanes: [[GiriCalendarPeriod]] = []
        for period in periods where week.contains(where: { period.overlaps($0) }) {
            let occupied = Set(week.indices.filter { period.overlaps(week[$0]) })
            if let index = lanes.firstIndex(where: { lane in
                !lane.contains { existing in
                    week.indices.contains { occupied.contains($0) && existing.overlaps(week[$0]) }
                }
            }) { lanes[index].append(period) }
            else { lanes.append([period]) }
        }
        return lanes
    }
    static func monthID(_ date: Date) -> Int {
        calendar.component(.year, from: date) * 12 + calendar.component(.month, from: date) - 1
    }
    static func monthFromID(_ id: Int) -> Date {
        calendar.date(from: DateComponents(year: id / 12, month: id % 12 + 1, day: 1)) ?? monthStart(Date())
    }
    static func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = calendar; formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: date)
    }
}

struct GiriCalendarView: View {
    @EnvironmentObject private var store: GiriStore
    let events: [GiriEvent]
    @State private var month = GiriCalendarRules.monthStart(Date())
    @State private var selected = Calendar.current.startOfDay(for: Date())
    @State private var showsMonthPicker = false
    @State private var scrollMonthID: Int? = GiriCalendarRules.monthID(Date())
    @State private var pickerYear = Calendar.current.component(.year, from: Date())
    @State private var pickerMonth = Calendar.current.component(.month, from: Date())
    private let accent = AppSectionAccent.artist
    private var periods: [GiriCalendarPeriod] { GiriCalendarPeriod.make(events: events) }
    private var currentMonthPeriods: [GiriCalendarPeriod] {
        guard let end = GiriCalendarRules.calendar.date(byAdding: .month, value: 1, to: month) else { return [] }
        return periods.filter { $0.start < end && $0.end > month }
    }
    private func weeks(for displayedMonth: Date) -> [[Date]] {
        let days = GiriCalendarRules.gridDays(displayedMonth)
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }
    private var gridHeight: CGFloat {
        weeks(for: month).reduce(CGFloat(0)) { height, week in
            height + max(72, 48 + CGFloat(GiriCalendarRules.periodLanes(periods, week: week).count) * 18) + 2
        }
    }
    private var selectedPeriods: [GiriCalendarPeriod] { periods.filter { $0.overlaps(selected) } }
    private var showingToday: Bool {
        GiriCalendarRules.calendar.isDate(month, equalTo: Date(), toGranularity: .month) &&
        GiriCalendarRules.calendar.isDateInToday(selected)
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                monthHeader
                VStack(spacing: 0) {
                    weekdays
                    pagedMonthGrid
                }
                .opacity(showsMonthPicker ? 0 : 1)
                .allowsHitTesting(!showsMonthPicker)
                .accessibilityHidden(showsMonthPicker)
                .overlay {
                    if showsMonthPicker { monthPicker.transition(.opacity) }
                }
            }
            .padding(.top, 10).padding(.bottom, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(appSeparatorColor).frame(height: 1) }
            selectedDayHeader
            if selectedPeriods.isEmpty {
                CenteredEmptyMessage(systemImage: "calendar", title: "この日の予定はありません")
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .appTintedCard(accentColor: accent).padding(.horizontal, 16)
            } else {
                ForEach(selectedPeriods) { period in
                    GiriCalendarPeriodLink(period: period) {
                        periodCard(period)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16).padding(.bottom, 12)
                }
            }
        }
        .padding(.bottom, 16)
        .onChange(of: month) { _, newMonth in
            let id = GiriCalendarRules.monthID(newMonth)
            if scrollMonthID != id { scrollMonthID = id }
        }
    }
    private var pagedMonthGrid: some View {
        let currentYear = GiriCalendarRules.calendar.component(.year, from: Date())
        return GeometryReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(((currentYear - 20) * 12)...((currentYear + 21) * 12 - 1), id: \.self) { id in
                        let displayedMonth = GiriCalendarRules.monthFromID(id)
                        VStack(spacing: 2) {
                            ForEach(Array(weeks(for: displayedMonth).enumerated()), id: \.offset) { _, week in
                                GiriCalendarWeek(days: week, month: displayedMonth, selected: $selected,
                                                 periods: periods, siteNames: siteNames)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(width: proxy.size.width, alignment: .top)
                        .id(id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrollMonthID)
            .onChange(of: scrollMonthID) { _, id in
                guard let id else { return }
                let newMonth = GiriCalendarRules.monthFromID(id)
                if !GiriCalendarRules.calendar.isDate(month, equalTo: newMonth, toGranularity: .month) {
                    month = newMonth
                }
            }
        }
        .frame(height: gridHeight)
    }
    private var siteNames: [String: String] {
        Dictionary(uniqueKeysWithValues: store.onlineSites.map { ($0.id, $0.name) })
    }
    private var monthHeader: some View {
        HStack(spacing: 8) {
            Button {
                pickerYear = GiriCalendarRules.calendar.component(.year, from: month)
                pickerMonth = GiriCalendarRules.calendar.component(.month, from: month)
                withAnimation(.easeInOut(duration: 0.18)) { showsMonthPicker.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Text(GiriCalendarRules.monthTitle(month))
                        .font(.system(size: appFontSize(21), weight: .bold, design: .rounded)).foregroundStyle(.primary)
                    Image(systemName: showsMonthPicker ? "chevron.up" : "chevron.down")
                        .font(.system(size: appFontSize(14), weight: .bold)).foregroundStyle(accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityHint("年月を選んで移動します")
            Text("\(Set(currentMonthPeriods.map { $0.event.id }).count)件")
                .font(.caption.weight(.bold)).foregroundStyle(accent)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(accent.opacity(0.12)).clipShape(Capsule())
            Spacer(minLength: 0)
            Button {
                showsMonthPicker = false
                selected = GiriCalendarRules.calendar.startOfDay(for: Date())
                withAnimation(.smooth(duration: 0.28)) { month = GiriCalendarRules.monthStart(Date()) }
            } label: {
                Text("今日").font(.system(size: appFontSize(13), weight: .semibold, design: .rounded))
                    .foregroundStyle(showingToday ? accent : .primary)
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(accent.opacity(showingToday ? 0.14 : 0.07)).clipShape(Capsule())
                    .overlay { Capsule().stroke(accent.opacity(showingToday ? 0.32 : 0.16), lineWidth: 1) }
            }
            .buttonStyle(.plain)
            monthArrow(-1)
            monthArrow(1)
        }
        .padding(.horizontal, 14)
    }
    private func monthArrow(_ offset: Int) -> some View {
        Button {
            guard let next = GiriCalendarRules.calendar.date(byAdding: .month, value: offset, to: month) else { return }
            let currentYear = GiriCalendarRules.calendar.component(.year, from: Date())
            guard abs(GiriCalendarRules.calendar.component(.year, from: next) - currentYear) <= 20 else { return }
            withAnimation(.smooth(duration: 0.28)) { month = GiriCalendarRules.monthStart(next) }
        } label: {
            Image(systemName: offset < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: appFontSize(21), weight: .bold)).foregroundStyle(.primary)
                .frame(width: 36, height: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(showsMonthPicker).opacity(showsMonthPicker ? 0.35 : 1)
        .accessibilityLabel(offset < 0 ? "前月" : "翌月")
    }
    private var weekdays: some View {
        HStack(spacing: 3) {
            ForEach(Array(["日", "月", "火", "水", "木", "金", "土"].enumerated()), id: \.offset) { index, title in
                Text(title).font(.caption.weight(.semibold))
                    .foregroundStyle(index == 0 ? Color.red : index == 6 ? Color.blue : Color.secondary)
                    .frame(maxWidth: .infinity).frame(height: 20)
            }
        }
        .padding(.horizontal, 10)
    }
    private var monthPicker: some View {
        let currentYear = GiriCalendarRules.calendar.component(.year, from: Date())
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Picker("年", selection: $pickerYear) {
                    ForEach((currentYear - 20)...(currentYear + 20), id: \.self) { year in
                        Text(verbatim: "\(year)年").tag(year)
                    }
                }
                .pickerStyle(.wheel).frame(maxWidth: .infinity).clipped()
                Picker("月", selection: $pickerMonth) {
                    ForEach(1...12, id: \.self) { month in Text(verbatim: "\(month)月").tag(month) }
                }
                .pickerStyle(.wheel).frame(maxWidth: .infinity).clipped()
            }
            .frame(height: 170).clipped()
            Button {
                let target = GiriCalendarRules.calendar.date(from: DateComponents(year: pickerYear, month: pickerMonth, day: 1))
                withAnimation(.easeInOut(duration: 0.18)) {
                    if let target { month = target }
                    showsMonthPicker = false
                }
            } label: {
                Text("この年月を表示").font(.headline.bold()).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(accent).clipShape(Capsule())
            }
            .buttonStyle(.plain).padding(.horizontal, 24).padding(.top, 12)
        }
        .padding(.horizontal, 10).frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var selectedDayHeader: some View {
        HStack(spacing: 8) {
            Text(GiriEventPresentation.day(selected))
                .font(.system(size: appFontSize(18), weight: .bold, design: .rounded))
                .foregroundStyle(GiriCalendarRules.dayColor(selected))
            if let holiday = JapaneseHolidayCalendar.holidayName(for: selected) {
                Text(holiday).font(.caption).foregroundStyle(.red)
            }
            Spacer()
            Text("\(selectedPeriods.count)件").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 10)
    }
    private func periodCard(_ period: GiriCalendarPeriod) -> some View {
        GiriListCard(accentColor: period.color) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(siteNames[period.event.onlineSiteId ?? ""] ?? period.event.title)
                        .font(.system(size: appFontSize(16), weight: .bold, design: .rounded)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    GiriListBadge(text: period.title, color: period.color)
                }
                if let round = period.round {
                    Text(GiriEventPresentation.roundTitle(round, event: period.event))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if period.phase == .live {
                    Text(period.event.startsAt == nil ? "時刻未定" : "\(GiriEventPresentation.time(period.event.startsAt)) / \(GiriEventPresentation.time(period.event.endsAt))")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("\(GiriEventPresentation.dateTime(period.start)) 〜 \(GiriEventPresentation.dateTime(period.end))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !period.event.isParticipating {
                    Text("未参加").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            .padding(.trailing, 18)
        }
    }
}

private struct GiriCalendarWeek: View {
    let days: [Date]
    let month: Date
    @Binding var selected: Date
    let periods: [GiriCalendarPeriod]
    let siteNames: [String: String]
    private var lanes: [[GiriCalendarPeriod]] { GiriCalendarRules.periodLanes(periods, week: days) }
    var body: some View {
        VStack(spacing: 1) {
            HStack(alignment: .top, spacing: 2) {
                ForEach(days, id: \.self) { date in
                    Button { selected = GiriCalendarRules.calendar.startOfDay(for: date) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            ZStack {
                                if GiriCalendarRules.calendar.isDate(date, inSameDayAs: selected) {
                                    Circle().fill(AppSectionAccent.artist).frame(width: 23, height: 23)
                                } else if GiriCalendarRules.calendar.isDateInToday(date) {
                                    Circle().stroke(AppSectionAccent.artist, lineWidth: 1.4).frame(width: 23, height: 23)
                                }
                                Text("\(GiriCalendarRules.calendar.component(.day, from: date))")
                                    .font(.system(size: appFontSize(13), weight: .medium, design: .rounded))
                                    .foregroundStyle(GiriCalendarRules.calendar.isDate(date, inSameDayAs: selected) ? .white : GiriCalendarRules.dayColor(date))
                            }
                            .frame(width: 24, height: 24)
                            if let holiday = JapaneseHolidayCalendar.holidayName(for: date) {
                                Text(holiday).font(.system(size: appFontSize(7), weight: .medium)).foregroundStyle(.red)
                                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                        .opacity(GiriCalendarRules.calendar.isDate(date, equalTo: month, toGranularity: .month) ? 1 : 0.30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(GiriEventPresentation.day(date))
                }
            }
            ForEach(Array(lanes.enumerated()), id: \.offset) { _, lane in
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        ForEach(lane) { period in
                            let indices = days.indices.filter { period.overlaps(days[$0]) }
                            if let first = indices.first, let last = indices.last {
                                let cell = proxy.size.width / 7
                                GiriCalendarPeriodLink(period: period) {
                                    Text("\(siteNames[period.event.onlineSiteId ?? ""] ?? period.event.title)・\(period.title)")
                                        .font(.system(size: appFontSize(8), weight: .semibold)).foregroundStyle(period.color)
                                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 3).frame(height: 17)
                                        .background(period.color.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                .buttonStyle(.plain)
                                .frame(width: max(1, cell * CGFloat(last - first + 1) - 2))
                                .offset(x: cell * CGFloat(first))
                            }
                        }
                    }
                }
                .frame(height: 17)
            }
            if lanes.isEmpty { Color.clear.frame(height: 24) }
            Divider().overlay(appSeparatorColor).padding(.top, 3)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .top)
    }
}

private struct GiriCalendarPeriodLink<Content: View>: View {
    let period: GiriCalendarPeriod
    @ViewBuilder var content: () -> Content
    var body: some View {
        NavigationLink {
            if let round = period.round, period.event.isParticipating {
                GiriRoundWorkspace(eventID: period.event.id, roundID: round.id)
            } else {
                GiriEventDetail(eventID: period.event.id)
            }
        } label: { content() }
    }
}

// Holiday rules copied unchanged from LiveStair at 074206d2.

// MARK: - 日本の祝日（祝日法のルールから計算する）

// 祝日法（国民の祝日に関する法律）のルールで、その年の祝日を計算する（通信や取り込みは不要）。
// 1955年〜2025年は、内閣府の祝日CSVとすべて同じ日付になることを確かめている。
// 祝日の名前は内閣府の祝日CSVを基準に、振替休日は区別できる名前で表示する。
// 国民の休日はCSVに合わせて「休日」とする。
// 祝日法が変わったときや、一度きりの祝日ができたときは、ここを直す
enum JapaneseHolidayCalendar {
    private static let lock = NSLock()

    // 年ごとの祝日（キーは 1970年1月1日からの日数）。一度計算した年は覚えておく
    private static var holidaysByYear: [Int: [Int: String]] = [:]

    // 端末の時刻のタイムゾーンで、日付（年・月・日）を出す
    private static let gregorianCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.autoupdatingCurrent
        return calendar
    }()

    // 一度きりの祝日（皇室の行事など）
    private static let specialHolidays: [(year: Int, month: Int, day: Int, name: String)] = [
        (1959, 4, 10, "結婚の儀"),
        (1989, 2, 24, "大喪の礼"),
        (1990, 11, 12, "即位礼正殿の儀"),
        (1993, 6, 9, "結婚の儀"),
        (2019, 5, 1, "休日（祝日扱い）"),
        (2019, 10, 22, "休日（祝日扱い）")
    ]

    static func holidayName(
        for date: Date
    ) -> String? {
        let components =
        gregorianCalendar.dateComponents(
            [.year, .month, .day],
            from: date
        )

        guard
            let year = components.year,
            let month = components.month,
            let day = components.day
        else {
            return nil
        }

        return holidays(in: year)[
            daysFromCivil(
                year: year,
                month: month,
                day: day
            )
        ]
    }

    private static func holidays(
        in year: Int
    ) -> [Int: String] {
        lock.lock()

        if let cached = holidaysByYear[year] {
            lock.unlock()
            return cached
        }

        lock.unlock()

        let calculated =
        makeHolidays(
            year: year
        )

        lock.lock()
        holidaysByYear[year] = calculated
        lock.unlock()

        return calculated
    }

    // MARK: 祝日の計算

    private static func makeHolidays(
        year: Int
    ) -> [Int: String] {
        // 祝日法は1948年7月20日から
        guard year >= 1948 else {
            return [:]
        }

        var nationalHolidays: [Int: String] = [:]

        func add(
            _ month: Int,
            _ day: Int,
            _ name: String
        ) {
            nationalHolidays[
                daysFromCivil(
                    year: year,
                    month: month,
                    day: day
                )
            ] = name
        }

        add(1, 1, "元日")

        if year >= 2000 {
            add(1, nthMonday(year: year, month: 1, nth: 2), "成人の日")
        } else {
            add(1, 15, "成人の日")
        }

        if year >= 1967 {
            add(2, 11, "建国記念の日")
        }

        if year >= 2020 {
            add(2, 23, "天皇誕生日")
        }

        add(3, vernalEquinoxDay(year: year), "春分の日")

        if year >= 2007 {
            add(4, 29, "昭和の日")
        } else if year >= 1989 {
            add(4, 29, "みどりの日")
        } else {
            add(4, 29, "天皇誕生日")
        }

        add(5, 3, "憲法記念日")

        if year >= 2007 {
            add(5, 4, "みどりの日")
        }

        add(5, 5, "こどもの日")

        // 海の日（2020・2021年は東京オリンピック・パラリンピックで移動）
        if year == 2020 {
            add(7, 23, "海の日")
        } else if year == 2021 {
            add(7, 22, "海の日")
        } else if year >= 2003 {
            add(7, nthMonday(year: year, month: 7, nth: 3), "海の日")
        } else if year >= 1996 {
            add(7, 20, "海の日")
        }

        // 山の日（2020・2021年は移動）
        if year == 2020 {
            add(8, 10, "山の日")
        } else if year == 2021 {
            add(8, 8, "山の日")
        } else if year >= 2016 {
            add(8, 11, "山の日")
        }

        if year >= 2003 {
            add(9, nthMonday(year: year, month: 9, nth: 3), "敬老の日")
        } else if year >= 1966 {
            add(9, 15, "敬老の日")
        }

        add(9, autumnalEquinoxDay(year: year), "秋分の日")

        // スポーツの日（2019年までは体育の日。2020・2021年は移動）
        if year == 2020 {
            add(7, 24, "スポーツの日")
        } else if year == 2021 {
            add(7, 23, "スポーツの日")
        } else if year >= 2022 {
            add(10, nthMonday(year: year, month: 10, nth: 2), "スポーツの日")
        } else if year == 2019 {
            add(10, nthMonday(year: year, month: 10, nth: 2), "体育の日（スポーツの日）")
        } else if year >= 2000 {
            add(10, nthMonday(year: year, month: 10, nth: 2), "体育の日")
        } else if year >= 1966 {
            add(10, 10, "体育の日")
        }

        add(11, 3, "文化の日")
        add(11, 23, "勤労感謝の日")

        if year >= 1989,
           year <= 2018 {
            add(12, 23, "天皇誕生日")
        }

        for special in specialHolidays
        where special.year == year {
            add(special.month, special.day, special.name)
        }

        // 1948年は、祝日法ができた7月20日からの祝日だけ
        if year == 1948 {
            let lawStart =
            daysFromCivil(
                year: 1948,
                month: 7,
                day: 20
            )

            nationalHolidays =
            nationalHolidays.filter {
                $0.key >= lawStart
            }
        }

        var holidays =
        nationalHolidays

        // 振替休日（1973年4月12日から）：祝日が日曜日のとき。
        // 2006年までは翌日、2007年からは祝日でない一番近い日
        let substituteStart =
        daysFromCivil(
            year: 1973,
            month: 4,
            day: 12
        )

        for day in nationalHolidays.keys.sorted()
        where day >= substituteStart &&
        weekday(ofDays: day) == 0 {
            var nextDay =
            day + 1

            if year >= 2007 {
                while nationalHolidays[nextDay] != nil {
                    nextDay += 1
                }
            } else if nationalHolidays[nextDay] != nil {
                continue
            }

            if holidays[nextDay] == nil {
                holidays[nextDay] = "振替休日"
            }
        }

        // 国民の休日（1986年から）：前の日と次の日が祝日の日（2006年までは日曜日を除く）
        if year >= 1986 {
            let firstDay =
            daysFromCivil(
                year: year,
                month: 1,
                day: 1
            )

            let lastDay =
            daysFromCivil(
                year: year,
                month: 12,
                day: 31
            )

            for day in (firstDay + 1)..<lastDay
            where holidays[day] == nil {
                if year < 2007,
                   weekday(ofDays: day) == 0 {
                    continue
                }

                if nationalHolidays[day - 1] != nil,
                   nationalHolidays[day + 1] != nil {
                    holidays[day] = "休日"
                }
            }
        }

        return holidays
    }

    // 春分の日（3月の日にち。1980年より前は、割り算の端数を 0 の方へ切る式）
    private static func vernalEquinoxDay(
        year: Int
    ) -> Int {
        let base: Double
        let leapAdjustment: Int

        if year <= 1979 {
            base = 20.8357
            leapAdjustment = (year - 1983) / 4
        } else if year <= 2099 {
            base = 20.8431
            leapAdjustment = (year - 1980) / 4
        } else {
            base = 21.8510
            leapAdjustment = (year - 1980) / 4
        }

        return Int(
            floor(
                base +
                0.242194 * Double(year - 1980) -
                Double(leapAdjustment)
            )
        )
    }

    // 秋分の日（9月の日にち）
    private static func autumnalEquinoxDay(
        year: Int
    ) -> Int {
        let base: Double
        let leapAdjustment: Int

        if year <= 1979 {
            base = 23.2588
            leapAdjustment = (year - 1983) / 4
        } else if year <= 2099 {
            base = 23.2488
            leapAdjustment = (year - 1980) / 4
        } else {
            base = 24.2488
            leapAdjustment = (year - 1980) / 4
        }

        return Int(
            floor(
                base +
                0.242194 * Double(year - 1980) -
                Double(leapAdjustment)
            )
        )
    }

    // その月の n 回目の月曜日（日にち）
    private static func nthMonday(
        year: Int,
        month: Int,
        nth: Int
    ) -> Int {
        let firstWeekday =
        weekday(
            ofDays:
                daysFromCivil(
                    year: year,
                    month: month,
                    day: 1
                )
        )

        let offset =
        (1 - firstWeekday + 7) % 7

        return 1 + offset + (nth - 1) * 7
    }

    // MARK: 日付の計算（グレゴリオ暦）

    // 1970年1月1日からの日数
    private static func daysFromCivil(
        year: Int,
        month: Int,
        day: Int
    ) -> Int {
        let adjustedYear =
        month <= 2
        ? year - 1
        : year

        let era =
        (adjustedYear >= 0 ? adjustedYear : adjustedYear - 399) / 400

        let yearOfEra =
        adjustedYear - era * 400

        let dayOfYear =
        (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1

        let dayOfEra =
        yearOfEra * 365 +
        yearOfEra / 4 -
        yearOfEra / 100 +
        dayOfYear

        return era * 146097 + dayOfEra - 719468
    }

    // 曜日（0 が日曜日）。1970年より前は日数がマイナスになるので、0〜6 にそろえる
    private static func weekday(
        ofDays days: Int
    ) -> Int {
        ((days + 4) % 7 + 7) % 7
    }
}

// 以前の「祝日CSVを取り込む」で保存していた祝日データ（今は使わないので消す）
private let legacyImportedJapaneseHolidaysKey =
"japaneseHolidaysDictionary"

func removeLegacyImportedJapaneseHolidays() {
    UserDefaults.standard.removeObject(
        forKey: legacyImportedJapaneseHolidaysKey
    )
}

