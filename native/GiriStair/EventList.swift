import SwiftUI
import UIKit

// Adapted from LiveStair ContentView.swift and LiveListEventCard.swift at
// 074206d2d92cefdf6e1a076900ed7af807ae1eb8. Native text, Menu and card metrics
// are shared with the reference; only GiriStair's fields and routes differ.
struct GiriListView: View {
    @EnvironmentObject private var store: GiriStore
    @State private var search = ""
    @State private var attended = false
    @State private var year = "all"
    @State private var kind = "all"
    @State private var meeting = "all"
    @State private var status = "all"
    @State private var venue = "all"
    @State private var player = "all"
    @State private var site = "all"
    @State private var ascending: Bool?
    @State private var isCollapsed = false
    @State private var destinationID: String?
    @State private var deletingEvent: GiriEvent?

    private let accent = AppSectionAccent.artist
    private var isCalendar: Bool { store.preferences.listCurrentMode }
    private var searchableEvents: [GiriEvent] {
        store.events.filter { $0.onlineSiteId == nil || $0.isParticipating }
    }
    private var years: [String] {
        Array(Set(searchableEvents.compactMap {
            GiriEventPresentation.date($0).map { String(Calendar.current.component(.year, from: $0)) }
        })).sorted(by: >)
    }
    private var venueNames: [String] {
        Array(Set(searchableEvents.map(\.venue).filter { !$0.isEmpty })).sorted()
    }
    private var playerNames: [String] {
        Array(Set(searchableEvents.flatMap(\.participants))).sorted { first, second in
            let firstReading = store.players.first { $0.name == first }?.furigana ?? first
            let secondReading = store.players.first { $0.name == second }?.furigana ?? second
            return firstReading.localizedStandardCompare(secondReading) == .orderedAscending
        }
    }
    private var filteredEvents: [GiriEvent] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return searchableEvents.filter { event in
            if kind != "all" && event.kind.rawValue != kind { return false }
            if meeting != "all" && event.meetingType.rawValue != meeting { return false }
            if status != "all" {
                if event.status.rawValue != status { return false }
            } else if (event.status == .attended) != attended { return false }
            if year != "all" {
                guard let date = GiriEventPresentation.date(event),
                      String(Calendar.current.component(.year, from: date)) == year else { return false }
            }
            if venue != "all" && event.venue != venue { return false }
            if player != "all" && !event.participants.contains(player) { return false }
            if site != "all" && event.onlineSiteId != site { return false }
            let venueRecord = store.venues.first { $0.id == event.venueId || $0.name == event.venue }
            let siteRecord = store.onlineSites.first { $0.id == event.onlineSiteId }
            let text = ([event.title, event.organizer, event.venue, event.memo,
                         event.affiliation, event.block, venueRecord?.prefecture ?? "",
                         siteRecord?.name ?? ""] + event.participants).joined(separator: " ")
            return query.isEmpty || text.localizedStandardContains(query)
        }.sorted { a, b in
            let ad = GiriEventPresentation.date(a), bd = GiriEventPresentation.date(b)
            if ad == nil && bd == nil { return a.createdAt > b.createdAt }
            guard let ad else { return false }
            guard let bd else { return true }
            if ad == bd { return a.title.localizedStandardCompare(b.title) == .orderedAscending }
            return (ascending ?? !attended) ? ad < bd : ad > bd
        }
    }
    private var visibleSites: [OnlineSite] {
        guard !attended, kind != "live", meeting != "tournament", status != "canceled" else { return [] }
        return store.onlineSites.filter { record in
            (site == "all" || site == record.id) &&
            (search.isEmpty || [record.name, record.affiliation, record.block, record.memo]
                .joined(separator: " ").localizedStandardContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isCalendar {
                ScrollView { GiriCalendarView(events: store.events) }
            } else {
                filterHeader
                eventList
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(appBackgroundColor)
        .safeAreaInset(edge: .top, spacing: 0) { pageHeader }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: Binding(
            get: { destinationID != nil },
            set: { if !$0 { destinationID = nil } }
        )) {
            if let id = destinationID { GiriEventDetail(eventID: id) }
        }
        .confirmationDialog("この記録を削除しますか？", isPresented: Binding(
            get: { deletingEvent != nil }, set: { if !$0 { deletingEvent = nil } }
        ), titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                guard let event = deletingEvent else { return }
                store.run { try store.deleteEvent(event.id); playLiveStairDeleteFeedback() }
                deletingEvent = nil
            }
            Button("キャンセル", role: .cancel) { deletingEvent = nil }
        }
    }

    // ContentView.liveListEventList / liveListCardList: conditions stay above
    // the native list; row gutters and swipe behaviour follow the source.
    private var eventList: some View {
        ZStack {
            if filteredEvents.isEmpty && visibleSites.isEmpty {
                CenteredEmptyMessage(
                    systemImage: "calendar.badge.exclamationmark",
                    title: searchableEvents.isEmpty ? "記録がありません" : "該当する記録がありません"
                )
            } else {
                List {
                    ForEach(visibleSites) { record in
                        siteCard(record)
                            .listRowInsets(EdgeInsets(top: record.id == visibleSites.first?.id ? 2 : 6, leading: 18, bottom: 6, trailing: 18))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(filteredEvents) { event in
                        Button { destinationID = event.id } label: { GiriEventCard(event: event) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { destinationID = event.id } label: { Label("詳細", systemImage: "info.circle") }
                                Button(role: .destructive) { deletingEvent = event } label: { Label("削除", systemImage: "trash") }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { deletingEvent = event } label: { Label("削除", systemImage: "trash") }
                            }
                            .listRowInsets(EdgeInsets(top: visibleSites.isEmpty && event.id == filteredEvents.first?.id ? 2 : 6, leading: 18, bottom: 6, trailing: 18))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 104, for: .scrollContent)
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appBackgroundColor)
    }

    private var pageHeader: some View {
        AppPageHeader(title: "一覧", systemImage: "list.bullet.rectangle", accentColor: accent)
            .overlay(alignment: .trailing) {
                HStack(spacing: 10) {
                    Button {
                        var preferences = store.preferences
                        preferences.listCurrentMode.toggle()
                        store.run { try store.savePreferences(preferences) }
                    } label: {
                        headerIcon(isCalendar ? "list.bullet" : "calendar")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCalendar ? "一覧表示に切り替える" : "カレンダー表示に切り替える")
                    if !isCalendar {
                        AppMenu {
                            Button { ascending = true } label: {
                                Label("日付の早い順", systemImage: (ascending ?? !attended) ? "checkmark" : "")
                            }
                            Button { ascending = false } label: {
                                Label("日付の遅い順", systemImage: !(ascending ?? !attended) ? "checkmark" : "")
                            }
                        } label: { headerIcon("arrow.up.arrow.down") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("並び順")
                    }
                }
                .padding(.trailing, 18)
            }
    }
    private func headerIcon(_ image: String) -> some View {
        Image(systemName: image)
            .font(.system(size: appFontSize(19), weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .background(appCardColor)
            .clipShape(Circle())
            .overlay { Circle().stroke(Color.primary.opacity(0.10), lineWidth: 1) }
    }
    private var filterHeader: some View {
        VStack(spacing: 5) {
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: appFontSize(16), weight: .semibold))
                        .foregroundStyle(accent).frame(width: 22)
                    Text("表示・絞り込み")
                        .font(.system(size: appFontSize(18), weight: .bold, design: .rounded))
                    Spacer()
                    Text("\(filteredEvents.count)件").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    AppHeaderCollapseButton(isCollapsed: $isCollapsed, tintColor: accent)
                }
                if !isCollapsed {
                    AppSearchField(text: $search, placeholder: "会・大会名・会場・主催者・参加者・メモ")
                        .padding(.bottom, 2)
                }
                Picker("表示", selection: Binding(
                    get: { attended }, set: { attended = $0; status = "all" }
                )) {
                    Text("参加予定").tag(false)
                    Text("参加済").tag(true)
                }
                .pickerStyle(.segmented).tint(accent)
                if !isCollapsed {
                    separator
                    HStack(spacing: 0) {
                        GiriListFilterMenu(title: "年", selection: $year,
                                           options: [("all", "全期間")] + years.map { ($0, $0) }, valueWidth: 64)
                        Divider().overlay(appSeparatorColor).frame(height: 30).padding(.horizontal, 9)
                        GiriListFilterMenu(title: "形式", selection: $kind, options: [
                            ("all", "全形式"), ("live", "生大喜利"), ("online", "ネット大喜利")], valueWidth: 88)
                    }
                    separator
                    GiriListFilterMenu(title: "会の種類", selection: $meeting,
                                       options: [("all", "すべて"), ("casual", "通常"), ("tournament", "大会")])
                    separator
                    GiriListFilterMenu(title: "参加者", selection: $player,
                                       options: [("all", "全参加者")] + playerNames.map { ($0, $0) })
                    separator
                    GiriListFilterMenu(title: "会場", selection: $venue,
                                       options: [("all", "全会場")] + venueNames.map { ($0, $0) })
                    separator
                    GiriListFilterMenu(title: "サイト", selection: $site,
                                       options: [("all", "全サイト")] + store.onlineSites.map { ($0.id, $0.name) })
                    separator
                    GiriListFilterMenu(title: "参加状況", selection: $status, options: [
                        ("all", "すべて"), ("planned", "参加予定"), ("attended", "参加済"), ("canceled", "キャンセル")])
                } else {
                    let conditions = [year == "all" ? "" : year,
                                      kind == "all" ? "" : kind == "live" ? "生大喜利" : "ネット大喜利",
                                      meeting == "all" ? "" : meeting == "casual" ? "通常" : "大会",
                                      venue == "all" ? "" : venue, player == "all" ? "" : player,
                                      search.isEmpty ? "" : "検索「\(search)」"]
                        .filter { !$0.isEmpty }
                    if !conditions.isEmpty {
                        AppHeaderConditionSummary(conditions: conditions)
                    }
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .appTintedCard(accentColor: accent, cornerRadius: 20, railVerticalInset: 14, lightTintOpacity: 0.065)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }
    private var separator: some View { Divider().overlay(appSeparatorColor) }
    private func siteCard(_ record: OnlineSite) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "globe").foregroundStyle(accent)
                Text(record.name).font(.system(size: appFontSize(18), weight: .bold, design: .rounded))
                Spacer()
                NavigationLink { GiriSitesView() } label: {
                    Image(systemName: "ellipsis").font(.body.weight(.semibold)).frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("サイトを編集")
            }
            if !record.affiliation.isEmpty || !record.block.isEmpty {
                Text([record.affiliation, record.block].filter { !$0.isEmpty }.joined(separator: "・"))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                siteCycleButton(record, offset: 0)
                siteCycleButton(record, offset: 1)
            }
        }
        .padding(14)
        .appTintedCard(accentColor: accent)
        .padding(.horizontal, 18).padding(.vertical, 6)
    }
    private func siteCycleButton(_ record: OnlineSite, offset: Int) -> some View {
        Button {
            store.run {
                let event = try store.createSiteCycle(record.id, weekOffset: offset, join: false)
                destinationID = event.id
            }
        } label: {
            Text(record.recurrence == .weekly ? (offset == 0 ? "今週" : "来週") : (offset == 0 ? "今回" : "次の回"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered).tint(accentActionColor)
    }
}

// 計測と描画に同じ幅・フォントを使い、全文分の高さを SwiftUI の行にも確保する。
private enum LiveListFilterTextMeasurement {
    static let minimumScale: CGFloat = 0.75

    struct Result {
        let font: UIFont
        let size: CGSize
        let lines: Int
    }

    static func measure(
        _ text: String,
        pointSize: CGFloat,
        width: CGFloat,
        scale: CGFloat
    ) -> Result {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        let font = UIFont.systemFont(ofSize: pointSize * scale, weight: .medium)
        label.font = font
        let size = label.sizeThatFits(
            CGSize(width: max(1, width), height: CGFloat.greatestFiniteMagnitude)
        )
        // UILabel の高さはピクセル単位に丸められるので、ceil で行数を増やさない。
        let lines = max(1, Int((size.height / font.lineHeight).rounded()))
        return Result(
            font: font,
            size: CGSize(width: max(1, width), height: ceil(size.height) + 2),
            lines: lines
        )
    }

    // 1行縮小 → 2行通常 → 2行縮小 → 3行…の順で、最少行数かつ最大の文字サイズ。
    static func fitted(_ text: String, pointSize: CGFloat, width: CGFloat) -> Result {
        let full = measure(text, pointSize: pointSize, width: width, scale: 1)
        let minimum = measure(text, pointSize: pointSize, width: width, scale: minimumScale)
        if full.lines <= minimum.lines {
            return full
        }
        var lower = minimumScale
        var upper: CGFloat = 1
        var best = minimum
        for _ in 0..<12 {
            let scale = (lower + upper) / 2
            let candidate = measure(text, pointSize: pointSize, width: width, scale: scale)
            if candidate.lines <= minimum.lines {
                lower = scale
                best = candidate
            } else {
                upper = scale
            }
        }
        return best
    }
}

private struct LiveListFilterValueText: UIViewRepresentable {
    let text: String
    let pointSize: CGFloat

    func makeUIView(context: Context) -> FittingLabel {
        let label = FittingLabel()
        label.textColor = .label
        label.textAlignment = .right
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.adjustsFontSizeToFitWidth = false
        label.adjustsFontForContentSizeCategory = false
        label.clipsToBounds = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ uiView: FittingLabel, context: Context) {
        uiView.text = text
        uiView.basePointSize = pointSize
        uiView.invalidateIntrinsicContentSize()
        uiView.setNeedsLayout()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: FittingLabel,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite else {
            let font = UIFont.systemFont(ofSize: pointSize, weight: .medium)
            let naturalSize = (text as NSString).size(withAttributes: [.font: font])
            return CGSize(width: ceil(naturalSize.width), height: ceil(naturalSize.height) + 2)
        }
        // 高さの提案で文字を圧縮せず、親の Layout と同じ幅から全文の高さを返す。
        return LiveListFilterTextMeasurement.fitted(text, pointSize: pointSize, width: width).size
    }

    final class FittingLabel: UILabel {
        var basePointSize: CGFloat = 17

        override func layoutSubviews() {
            let fittedFont = LiveListFilterTextMeasurement.fitted(
                text ?? "", pointSize: basePointSize, width: bounds.width
            ).font
            if font != fittedFont {
                font = fittedFont
            }
            super.layoutSubviews()
        }
    }
}

private struct LiveListFullWidthFilterLabel: View {
    let title: String
    let value: String
    let symbolName: String
    let tintColor: Color

    @ScaledMetric(relativeTo: .body)
    private var pointSize: CGFloat = 17

    var body: some View {
        LiveListFullWidthFilterLayout(value: value, pointSize: pointSize) {
            ZStack(alignment: .leading) {
                Text("アーティスト").hidden().accessibilityHidden(true)
                Text(title)
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)

            LiveListFilterValueText(text: value, pointSize: pointSize)

            Image(systemName: symbolName)
                .font(.caption2.weight(.bold))
                .foregroundColor(tintColor)
                .frame(width: 14)
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)：\(value)")
    }
}

// Button/Menu 内の HStack に高さを任せず、実際の値幅で全文を計測して配置する。
private struct LiveListFullWidthFilterLayout: Layout {
    let value: String
    let pointSize: CGFloat

    private struct Metrics {
        let width: CGFloat
        let height: CGFloat
        let titleSize: CGSize
        let arrowSize: CGSize
        let valueSize: CGSize
        let isStacked: Bool
        let valueTop: CGFloat
    }

    private func metrics(width proposedWidth: CGFloat?, subviews: Subviews) -> Metrics {
        let naturalTitleSize = subviews[0].sizeThatFits(.unspecified)
        let arrowSize = subviews[2].sizeThatFits(.unspecified)
        let naturalValueSize = subviews[1].sizeThatFits(.unspecified)
        let naturalWidth = naturalTitleSize.width + 12 + naturalValueSize.width + 6 + arrowSize.width
        let width = max(1, proposedWidth.flatMap { $0.isFinite ? $0 : nil } ?? naturalWidth)
        let inlineWidth = max(1, width - naturalTitleSize.width - 12 - arrowSize.width - 6)
        let minimum = LiveListFilterTextMeasurement.measure(
            value, pointSize: pointSize, width: inlineWidth,
            scale: LiveListFilterTextMeasurement.minimumScale
        )
        // 2行で0.75まで縮めても入らなければ、見出しを上へ移して値の幅を広げる。
        let isStacked = minimum.lines > 2 || naturalTitleSize.width + 12 + arrowSize.width + 6 >= width
        let titleSize = isStacked
            ? subviews[0].sizeThatFits(ProposedViewSize(width: min(width, naturalTitleSize.width), height: nil))
            : naturalTitleSize
        let valueWidth = isStacked ? max(1, width - arrowSize.width - 6) : inlineWidth
        let valueSize = LiveListFilterTextMeasurement.fitted(
            value, pointSize: pointSize, width: valueWidth
        ).size
        let contentHeight = max(valueSize.height, arrowSize.height)
        let valueTop: CGFloat = isStacked ? 4 + titleSize.height + 4 : 4
        let height = max(32, isStacked
            ? valueTop + contentHeight + 4
            : max(titleSize.height, contentHeight) + 8)
        return Metrics(
            width: width, height: height, titleSize: titleSize, arrowSize: arrowSize,
            valueSize: valueSize, isStacked: isStacked, valueTop: valueTop
        )
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = metrics(width: proposal.width, subviews: subviews)
        return CGSize(width: sizes.width, height: sizes.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = metrics(width: bounds.width, subviews: subviews)
        let titleY = sizes.isStacked ? bounds.minY + 4 : bounds.midY - sizes.titleSize.height / 2
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: titleY), anchor: .topLeading,
            proposal: ProposedViewSize(sizes.titleSize)
        )
        let contentHeight = max(sizes.valueSize.height, sizes.arrowSize.height)
        let valueY = sizes.isStacked
            ? bounds.minY + sizes.valueTop + (contentHeight - sizes.valueSize.height) / 2
            : bounds.midY - sizes.valueSize.height / 2
        subviews[1].place(
            at: CGPoint(x: bounds.maxX - sizes.arrowSize.width - 6 - sizes.valueSize.width, y: valueY),
            anchor: .topLeading, proposal: ProposedViewSize(sizes.valueSize)
        )
        let arrowY = sizes.isStacked
            ? bounds.minY + sizes.valueTop + (contentHeight - sizes.arrowSize.height) / 2
            : bounds.midY - sizes.arrowSize.height / 2
        subviews[2].place(
            at: CGPoint(x: bounds.maxX - sizes.arrowSize.width, y: arrowY), anchor: .topLeading,
            proposal: ProposedViewSize(sizes.arrowSize)
        )
    }
}

struct GiriListFilterMenu: View {
    let title: String
    @Binding var selection: String
    let options: [(String, String)]
    var valueWidth: CGFloat? = nil
    private var selectedLabel: String { options.first { $0.0 == selection }?.1 ?? options.first?.1 ?? "すべて" }

    var body: some View {
        if let valueWidth {
            HStack(spacing: 6) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 6)
                AppMenu { choices } label: {
                    HStack(spacing: 6) {
                        Text(selectedLabel).font(.body.weight(.medium)).foregroundStyle(.primary)
                            .lineLimit(1).minimumScaleFactor(0.86).allowsTightening(true)
                            .frame(width: valueWidth, alignment: .trailing)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
                            .foregroundStyle(AppSectionAccent.artist).frame(width: 14)
                    }
                    .frame(minHeight: 38, alignment: .trailing)
                    .contentShape(Rectangle())
                    .transaction { $0.animation = nil }
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        } else {
            AppMenu { choices } label: {
                LiveListFullWidthFilterLabel(title: title, value: selectedLabel,
                                            symbolName: "chevron.up.chevron.down",
                                            tintColor: AppSectionAccent.artist)
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
        }
    }
    @ViewBuilder private var choices: some View {
        ForEach(options, id: \.0) { option in
            Button { selection = option.0 } label: {
                if option.0 == selection { Label(option.1, systemImage: "checkmark") }
                else { Text(option.1) }
            }
        }
    }
}

struct GiriEventCard: View {
    @EnvironmentObject private var store: GiriStore
    let event: GiriEvent
    var showsResult = false
    private var accent: Color { GiriEventPresentation.accent(event) }
    private var date: Date? { GiriEventPresentation.date(event) }
    private var venueRecord: GiriVenue? {
        store.venues.first { $0.id == event.venueId || $0.name == event.venue }
    }
    private var venueText: String {
        let name = event.venue.isEmpty ? "会場未設定" : event.venue
        guard let prefecture = venueRecord?.prefecture, !prefecture.isEmpty else { return name }
        return "\(name)（\(prefecture)）"
    }
    var body: some View {
        GiriListCard(accentColor: accent, contentOpacity: event.status == .canceled ? 0.55 : 1) {
            VStack(alignment: .leading, spacing: 7) {
                topArea
                if event.kind == .live { liveDetails }
                else { onlineDetails }
                if showsResult {
                    Divider().overlay(appSeparatorColor)
                    Text(GiriEventPresentation.resultSummary(event))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(event.hasRecordedResult ? Color.primary : accentActionColor)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
    private var topArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    dateLabel(compact: false).fixedSize(horizontal: true, vertical: false)
                    dateLabel(compact: true).fixedSize(horizontal: true, vertical: false)
                    dateLabel(compact: true).minimumScaleFactor(0.78)
                }
                .frame(minWidth: 92, maxWidth: .infinity, alignment: .leading).layoutPriority(3)
                if event.kind == .live {
                    HStack(spacing: 3) {
                        Image(systemName: "clock").font(.caption2.weight(.semibold))
                        ZStack(alignment: .leading) {
                            Text("00:00 / 00:00").hidden()
                            Text(GiriEventPresentation.timeRange(event.startsAt, event.endsAt))
                        }
                        .font(.caption.weight(.semibold)).monospacedDigit().lineLimit(1)
                    }
                    .foregroundStyle(.secondary).fixedSize(horizontal: true, vertical: false)
                    .accessibilityElement(children: .combine)
                }
                GiriListBadge(text: GiriEventPresentation.kindTitle(event.kind), color: accent, fitsColumn: true)
                    .frame(width: 70, alignment: .leading).offset(x: 2)
            }
            HStack(alignment: .top, spacing: 6) {
                Text(event.title.isEmpty ? "会・大会名未設定" : event.title)
                    .font(.system(size: appFontSize(16), weight: .bold, design: .rounded))
                    .foregroundStyle(.primary).multilineTextAlignment(.leading).lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if event.status != .attended {
                    GiriListBadge(text: GiriEventPresentation.statusTitle(event.status), color: accent)
                        .frame(width: 70, alignment: .leading)
                }
            }
        }
    }
    private func dateLabel(compact: Bool) -> some View {
        Text(GiriEventPresentation.day(date, compact: compact))
            .font(.system(size: appFontSize(14), weight: .bold, design: .rounded))
            .foregroundStyle(date.map { GiriCalendarRules.dayColor($0, ordinary: .secondary) } ?? .secondary)
            .lineLimit(1).allowsTightening(true)
    }
    private var liveDetails: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: "mappin").font(.caption2.weight(.semibold))
                    .foregroundStyle(accent).frame(width: 15)
                ViewThatFits(in: .horizontal) {
                    venueLabel(fontSize: 15, lineLimit: 1, intrinsicWidth: true)
                    venueLabel(fontSize: 13.5, lineLimit: 1, intrinsicWidth: true)
                    venueLabel(fontSize: 13.5, lineLimit: 2, intrinsicWidth: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(2)
            }
            if !event.participants.isEmpty {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "person.2").font(.caption2.weight(.semibold))
                        .foregroundStyle(accent).frame(width: 15).padding(.top, 2)
                    Text(event.participants.joined(separator: " / ")).font(.caption)
                        .foregroundStyle(.primary).lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.trailing, 18)
    }
    private func venueLabel(fontSize: CGFloat, lineLimit: Int, intrinsicWidth: Bool) -> some View {
        Text(venueText)
            .font(.system(size: appFontSize(fontSize), weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(lineLimit).truncationMode(.tail).allowsTightening(true)
            .fixedSize(horizontal: intrinsicWidth, vertical: lineLimit > 1)
    }
    private var onlineDetails: some View {
        let round = GiriEventPresentation.previewRound(event)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: "globe").font(.caption2.weight(.semibold)).foregroundStyle(accent).frame(width: 15)
                Text(store.onlineSites.first { $0.id == event.onlineSiteId }?.name ?? event.title)
                    .font(.system(size: appFontSize(15), weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            if let round {
                Text(GiriEventPresentation.roundTitle(round, event: event))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if round.submissionEnabled, let end = round.submissionEnd {
                    Text("投稿締切 \(GiriEventPresentation.dateTime(end))").font(.caption).foregroundStyle(.secondary)
                }
                if round.votingRequired, let end = round.votingEnd {
                    Text("投票締切 \(GiriEventPresentation.dateTime(end))").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.trailing, 18)
    }
}

// Same card wrapper as LiveListEventCard, with a distinct module name.
struct GiriListCard<Content: View>: View {
    let accentColor: Color
    var contentOpacity: Double = 1
    var showsDisclosureIndicator = true
    private let content: Content
    init(accentColor: Color, contentOpacity: Double = 1, showsDisclosureIndicator: Bool = true,
         @ViewBuilder content: () -> Content) {
        self.accentColor = accentColor
        self.contentOpacity = contentOpacity
        self.showsDisclosureIndicator = showsDisclosureIndicator
        self.content = content()
    }
    var body: some View {
        content.opacity(contentOpacity)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appTintedCard(accentColor: accentColor, cornerRadius: 16, railVerticalInset: 10, lightTintOpacity: 0.075)
            .overlay(alignment: .trailing) {
                if showsDisclosureIndicator {
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                        .padding(.trailing, 12)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct GiriListBadge: View {
    let text: String
    let color: Color
    var fitsColumn = false
    var body: some View {
        Text(text).font(.caption2.weight(.bold))
            .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.80).allowsTightening(true)
            .fixedSize(horizontal: !fitsColumn, vertical: false)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.12)).clipShape(Capsule())
    }
}

enum GiriEventPresentation {
    static func kindTitle(_ kind: EventKind) -> String { kind == .live ? "生大喜利" : "ネット大喜利" }
    static func statusTitle(_ status: EventStatus) -> String {
        switch status { case .planned: "参加予定"; case .attended: "参加済"; case .canceled: "キャンセル" }
    }
    static func accent(_ event: GiriEvent) -> Color { event.kind == .live ? AppSectionAccent.live : AppSectionAccent.artist }
    static func date(_ event: GiriEvent, now: Date = Date()) -> Date? {
        if event.kind == .live { return event.eventDate ?? event.startsAt }
        let dates = event.effectiveRounds.flatMap { round -> [Date] in
            var dates: [Date] = []
            if round.submissionEnabled, let date = round.submissionEnd { dates.append(date) }
            if round.votingRequired, let date = round.votingEnd { dates.append(date) }
            return dates
        }.sorted()
        return dates.first { $0 >= now } ?? dates.last
    }
    static func previewRound(_ event: GiriEvent) -> EventRound? {
        let next = date(event)
        return event.effectiveRounds.first { $0.submissionEnd == next || $0.votingEnd == next } ?? event.effectiveRounds.first
    }
    static func day(_ date: Date?, compact: Bool = false) -> String {
        GiriDateText.day(date, compact: compact)
    }
    static func dateTime(_ date: Date?) -> String {
        GiriDateText.dateTime(date)
    }
    static func time(_ date: Date?) -> String {
        GiriDateText.time(date)
    }
    static func timeRange(_ first: Date?, _ second: Date?) -> String {
        GiriDateText.timeRange(first, second)
    }
    static func roundTitle(_ round: EventRound, event: GiriEvent) -> String {
        var parts = [event.meetingType == .tournament ? round.name : "投稿・投票"]
        if event.meetingType == .tournament || round.promptNumber > 1 { parts.append("お題\(round.promptNumber)") }
        if !round.block.isEmpty { parts.append(round.block) }
        return parts.joined(separator: "・")
    }
    static func outcomeTitle(_ outcome: TournamentOutcome) -> String {
        switch outcome {
        case .unrecorded: "未入力"; case .champion: "優勝"; case .runnerUp: "準優勝"; case .placed: "入賞"
        case .eliminated: "敗退"; case .advanced: "通過"; case .other: "その他"
        }
    }
    static func resultSummary(_ event: GiriEvent) -> String {
        var parts: [String] = []
        if let result = event.tournamentResult, result.outcome != .unrecorded {
            parts.append(outcomeTitle(result.outcome))
        }
        if let rank = event.effectivePlacement,
           event.tournamentResult?.outcome != .champion && event.tournamentResult?.outcome != .runnerUp {
            parts.append("\(rank)位")
        }
        if !event.resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(event.resultText) }
        if parts.isEmpty, let result = event.tournamentResult {
            if !result.stages.isEmpty { parts.append("\(result.stages.count)段階の記録") }
            else if !result.memo.isEmpty { parts.append(result.memo) }
        }
        return parts.isEmpty ? "結果を入力する" : parts.joined(separator: "・")
    }
}
