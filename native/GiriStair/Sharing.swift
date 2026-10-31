import SwiftUI
import Charts
import Photos
import PhotosUI
import UIKit
import ImageIO

private func giriStatisticsFormatColor(_ format: EventFormat) -> Color {
    switch format {
    case .live: return AppSectionAccent.live
    case .onlineLong: return AppSectionAccent.artist
    case .onlineShort: return AppSectionAccent.song
    case .hybrid: return AppSectionAccent.venue
    }
}
private struct GiriRankEntry: Identifiable { var name: String; var count: Int; var id: String { name } }
private func giriRanks(_ names: [String]) -> [GiriRankEntry] {
    var counts: [String: Int] = [:]
    for name in names where !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { counts[name, default: 0] += 1 }
    return counts.map { GiriRankEntry(name: $0.key, count: $0.value) }.sorted { $0.count == $1.count ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.count > $1.count }
}
private func giriSiteName(_ event: GiriEvent, sites: [OnlineSite]) -> String {
    if let id = event.onlineSiteId, let site = sites.first(where: { $0.id == id }) { return site.name }
    return URL(string: event.siteUrl)?.host ?? event.title
}

struct GiriStatisticsView: View {
    @EnvironmentObject private var store: GiriStore
    @State private var year = 0
    @State private var month = 0
    @State private var kind = "all"
    @State private var meeting = "all"
    private var records: [GiriEvent] {
        store.events.filter { event in
            guard event.isCountableParticipation() else { return false }
            if kind != "all" && event.eventFormat.rawValue != kind { return false }
            if meeting != "all" && event.meetingType.rawValue != meeting { return false }
            let date = giriAnalyticsDate(event)
            if year != 0 && date.map({ Calendar.current.component(.year, from: $0) }) != year { return false }
            if month != 0 && date.map({ Calendar.current.component(.month, from: $0) }) != month { return false }
            return true
        }
    }
    private var years: [Int] { Set(store.events.compactMap(giriAnalyticsDate).map { Calendar.current.component(.year, from: $0) }).sorted(by: >) }
    var body: some View {
        List {
            Section {
                AppCardSectionTitle(title: "表示・絞り込み", systemImage: "line.3.horizontal.decrease", accentColor: AppSectionAccent.ticket).listRowSeparator(.hidden)
                Picker("年", selection: $year) { Text("全期間").tag(0); ForEach(years, id: \.self) { Text("\($0)年").tag($0) } }.pickerStyle(.menu).tint(.primary)
                Picker("月", selection: $month) { Text("すべて").tag(0); ForEach(1...12, id: \.self) { Text("\($0)月").tag($0) } }.pickerStyle(.menu).tint(.primary)
                Picker("形式", selection: $kind) {
                    Text("すべて").tag("all")
                    ForEach(EventFormat.allCases) { format in Text(format.title).tag(format.rawValue) }
                }.pickerStyle(.menu).tint(.primary)
                Picker("会の種類", selection: $meeting) { Text("すべて").tag("all"); Text("通常").tag("casual"); Text("大会").tag("tournament") }.pickerStyle(.menu).tint(.primary)
            }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
            Section {
                AppCardSectionTitle(title: "参加回数", systemImage: "chart.bar", accentColor: AppSectionAccent.ticket).listRowSeparator(.hidden)
                LabeledContent("合計", value: "\(records.count)回")
                ForEach(EventFormat.allCases) { format in
                    LabeledContent(format.title, value: "\(records.filter { $0.eventFormat == format }.count)回")
                }
                NavigationLink("参加記録を確認") { GiriStatisticsRecords(title: "参加記録", records: records) }
            }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
            Section {
                AppCardSectionTitle(title: "月別", systemImage: "calendar", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                if records.isEmpty { CenteredEmptyMessage(systemImage: "chart.bar", title: "記録がありません") }
                else { GiriMonthChart(records: records, year: year == 0 ? nil : year).frame(height: 220) }
                let undated = records.filter { giriAnalyticsDate($0) == nil }.count
                if undated > 0 { LabeledContent("日付未定", value: "\(undated)回") }
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            Section {
                AppCardSectionTitle(title: "大会の最終成績", systemImage: "trophy", accentColor: AppSectionAccent.ticket).listRowSeparator(.hidden)
                let tournaments = records.filter { $0.meetingType == .tournament }
                LabeledContent("大会参加", value: "\(tournaments.count)回")
                LabeledContent("優勝", value: "\(tournaments.filter { $0.effectivePlacement == 1 }.count)回")
                LabeledContent("準優勝", value: "\(tournaments.filter { $0.effectivePlacement == 2 }.count)回")
                LabeledContent("入賞", value: "\(tournaments.filter { $0.effectivePlacement != 1 && $0.effectivePlacement != 2 && ($0.effectivePlacement == 3 || $0.tournamentResult?.outcome == .placed) }.count)回")
            }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
            ranking("会場別の参加回数", "mappin.and.ellipse", .venue, giriRanks(records.filter { $0.eventFormat.hasLiveTiming }.map(\.venue))) { entry in records.filter { $0.eventFormat.hasLiveTiming && $0.venue == entry.name } }
            ranking("主催者別の参加回数", "person.crop.circle", .memo, giriRanks(records.map(\.organizer))) { entry in records.filter { $0.organizer == entry.name } }
            ranking("一緒に参加した人", "person.2", .artist, giriRanks(records.flatMap { Array(Set($0.participants.filter { $0 != store.preferences.selfName })) })) { entry in records.filter { $0.participants.contains(entry.name) } }
            ranking("サイト別の参加回数", "globe", .artist, giriRanks(records.filter { $0.eventFormat.hasOnlineRounds }.map { giriSiteName($0, sites: store.onlineSites) })) { entry in records.filter { $0.eventFormat.hasOnlineRounds && giriSiteName($0, sites: store.onlineSites) == entry.name } }
        }.appIndexListStyle().toolbar(.visible, for: .navigationBar).navigationTitle("集計").navigationBarTitleDisplayMode(.inline)
    }
    private enum RankingAccent { case venue, memo, artist; var color: Color { switch self { case .venue: AppSectionAccent.venue; case .memo: AppSectionAccent.memo; case .artist: AppSectionAccent.artist } } }
    private func ranking(_ title: String, _ icon: String, _ accent: RankingAccent, _ entries: [GiriRankEntry], events: @escaping (GiriRankEntry) -> [GiriEvent]) -> some View {
        Section {
            AppCardSectionTitle(title: title, systemImage: icon, accentColor: accent.color).listRowSeparator(.hidden)
            if entries.isEmpty { Text("記録がありません").foregroundStyle(.secondary) }
            ForEach(entries) { entry in
                NavigationLink { GiriStatisticsRecords(title: entry.name, records: events(entry)) } label: { HStack { Text(entry.name); Spacer(); Text("\(entry.count)回").foregroundStyle(.secondary) } }
            }
        }.appSectionCardStyle(accentColor: accent.color)
    }
}
private struct GiriStatisticsRecords: View {
    var title: String
    var records: [GiriEvent]
    var body: some View {
        List {
            Section {
                AppCardSectionTitle(title: title, systemImage: "clock", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                ForEach(records.sorted { (giriAnalyticsDate($0) ?? .distantPast) > (giriAnalyticsDate($1) ?? .distantPast) }) { event in
                    NavigationLink { GiriEventDetail(eventID: event.id) } label: { VStack(alignment: .leading, spacing: 4) { if let date = giriAnalyticsDate(event) { Text(GiriDateText.day(date)).font(.caption).foregroundStyle(.secondary) }; Text(event.title) } }
                }
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
        }.appIndexListStyle().toolbar(.visible, for: .navigationBar).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

/// Source-style month chart with a complete calendar axis. A single record
/// retains a narrow bar rather than becoming a full-width coloured rectangle.
private struct GiriMonthChart: View {
    var records: [GiriEvent]
    var year: Int? = nil
    var ink: Color = .primary
    private var series: GiriMonthlySeries { giriMonthlySeries(events: records, year: year) }
    private var yStep: Int { max(1, Int(ceil(Double(max(1, series.maximum)) / 4))) }
    private var yUpper: Int { max(3, ((series.maximum + yStep - 1) / yStep) * yStep) }
    private var xTicks: [Date] {
        let step = max(1, Int(ceil(Double(series.months.count) / 12)))
        return series.months.enumerated().compactMap { $0.offset % step == 0 ? $0.element : nil }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Chart(series.values) { value in
                BarMark(x: .value("月", value.date, unit: .month), y: .value("参加回数", value.count),
                        width: .fixed(max(3, min(14, 300 / CGFloat(max(1, series.months.count)) * 0.65))))
                    .foregroundStyle(by: .value("形式", value.format.title))
            }
            .chartForegroundStyleScale([
                EventFormat.live.title: AppSectionAccent.live,
                EventFormat.onlineLong.title: AppSectionAccent.artist,
                EventFormat.onlineShort.title: AppSectionAccent.song,
                EventFormat.hybrid.title: AppSectionAccent.venue,
            ])
            .chartLegend(.hidden)
            .chartXScale(domain: series.start...series.end)
            .chartYScale(domain: 0...yUpper)
            .chartXAxis {
                AxisMarks(values: xTicks) { value in
                    AxisTick().foregroundStyle(ink.opacity(0.18))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            let month = Calendar.current.component(.month, from: date)
                            Text(series.months.count > 12 && month == 1 ? String(Calendar.current.component(.year, from: date)) : "\(month)月")
                                .font(.system(size: 9, weight: .medium)).foregroundStyle(ink.opacity(0.65))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: Array(stride(from: 0, through: yUpper, by: yStep))) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2])).foregroundStyle(ink.opacity(0.13))
                    AxisValueLabel {
                        if let count = value.as(Int.self) { Text("\(count)").font(.system(size: 9)).foregroundStyle(ink.opacity(0.65)) }
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 5) {
                ForEach(EventFormat.allCases) { format in
                    HStack(spacing: 5) {
                        Circle().fill(giriStatisticsFormatColor(format)).frame(width: 6, height: 6)
                        Text(format.title).font(.system(size: 9, weight: .medium)).foregroundStyle(ink.opacity(0.7)).lineLimit(1)
                    }
                }
            }
        }
    }
}

@MainActor
struct GiriSharingView: View {
    @EnvironmentObject private var store: GiriStore
    private var listMode: Bool
    @State private var year = 0
    @State private var monthPeriod = 0
    @State private var status = "completed"
    @State private var kind = "all"
    @AppStorage private var showVenues: Bool
    @AppStorage private var showResults: Bool
    @AppStorage private var showParticipants: Bool
    @AppStorage private var showOrganizers: Bool
    @AppStorage private var background: String
    @AppStorage private var textColor: String
    @State private var photoItem: PhotosPickerItem?
    @State private var backgroundPhoto: UIImage?
    @State private var loadedPhotoItem: PhotosPickerItem?
    @State private var page = 0
    @State private var exporting = false
    @State private var shareURLs: [URL] = []
    @State private var sharing = false
    @State private var savedAlert = false
    @State private var previewImage: UIImage?
    @State private var renderingPreview = false
    @State private var loadingPhoto = false

    init(initialList: Bool = false) {
        listMode = initialList
        let prefix = initialList ? "giri.share.list" : "giri.share.summary"
        _showVenues = AppStorage(wrappedValue: true, prefix + ".venues")
        _showResults = AppStorage(wrappedValue: true, prefix + ".results")
        _showParticipants = AppStorage(wrappedValue: false, prefix + ".participants")
        _showOrganizers = AppStorage(wrappedValue: true, prefix + ".organizers")
        _background = AppStorage(wrappedValue: "cream", prefix + ".background")
        _textColor = AppStorage(wrappedValue: "auto", prefix + ".textColor")
    }
    private var records: [GiriEvent] {
        store.events.filter { event in
            guard event.isActualParticipant else { return false }
            let phase = event.participationState()
            if status == "completed" && !event.isCountableParticipation() { return false }
            if status == "active" && phase != .upcoming && phase != .ongoing { return false }
            if kind != "all" && event.eventFormat.rawValue != kind { return false }
            let date = giriAnalyticsDate(event)
            if year != 0 && date.map({ Calendar.current.component(.year, from: $0) }) != year { return false }
            if monthPeriod != 0 {
                guard let date else { return false }
                let month = Calendar.current.component(.month, from: date)
                if monthPeriod <= 12 && month != monthPeriod { return false }
                if monthPeriod == 101 && month > 6 { return false }
                if monthPeriod == 102 && month < 7 { return false }
                if monthPeriod >= 201 && monthPeriod <= 204 && (month - 1) / 3 + 201 != monthPeriod { return false }
            }
            return true
        }.sorted { (giriAnalyticsDate($0) ?? .distantFuture) < (giriAnalyticsDate($1) ?? .distantFuture) }
    }
    private var years: [Int] { Set(store.events.compactMap(giriAnalyticsDate).map { Calendar.current.component(.year, from: $0) }).sorted(by: >) }
    private var pageCount: Int { listMode ? max(1, (records.count + 14) / 15) : 1 }
    private var foreground: Color { if textColor == "white" { return .white }; if textColor == "black" { return Color(red: 0.18, green: 0.16, blue: 0.14) }; if textColor == "pink" { return AppSectionAccent.live }; return background == "black" || background == "navy" || background == "navyGradient" ? .white : Color(red: 0.18, green: 0.16, blue: 0.14) }
    private var periodTitle: String { (year == 0 ? "全期間" : "\(year)年") + (monthPeriod == 0 ? "" : monthPeriod <= 12 ? " \(monthPeriod)月" : monthPeriod == 101 ? " 上半期" : monthPeriod == 102 ? " 下半期" : " \((monthPeriod - 201) * 3 + 1)〜\((monthPeriod - 200) * 3)月") }

    private var paperWidth: CGFloat { listMode ? 595 : 390 }
    private var shareTitle: String { listMode ? "Giri List" : "Giri Summary" }
    private var previewRequest: GiriSharePreviewRequest {
        GiriSharePreviewRequest(records: records, page: min(page, pageCount - 1), year: year, monthPeriod: monthPeriod,
            name: store.preferences.selfName, background: background, textColor: textColor,
            showVenues: showVenues, showResults: showResults, showParticipants: showParticipants,
            showOrganizers: showOrganizers, photo: backgroundPhoto)
    }

    // ScreenshotView / LiveListShareView keep the preview and palette settings
    // on different navigation pages. The preview is a stable rendered image;
    // no live scaled paper is measured inside a grouped Form row.
    var body: some View {
        VStack(spacing: 0) {
            pageHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    AppCardSectionTitle(title: "プレビュー", systemImage: "rectangle.on.rectangle", accentColor: AppSectionAccent.live)
                    periodControls
                    if listMode && pageCount > 1 { pageControls }
                    preview
                }
                .padding(12)
                .appTintedCard(accentColor: AppSectionAccent.ticket, cornerRadius: 20, railVerticalInset: 14, lightTintOpacity: 0.065)
                .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 30)
            }.scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(appBackgroundColor)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(appHeaderColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .accessibilityIdentifier(listMode ? "sharing.list.preview" : "sharing.summary.preview")
        .task(id: previewRequest) { await renderPreview() }
        .task(id: photoItem) { await loadBackground(photoItem) }
        .task(id: background) { loadSavedBackground() }
        .onChange(of: pageCount) { _, count in if page >= count { page = count - 1 } }
        .sheet(isPresented: $sharing) { GiriShareSheet(items: shareURLs) }
        .alert("写真に保存しました", isPresented: $savedAlert) { Button("閉じる", role: .cancel) {} }
    }

    private var pageHeader: some View {
        HStack(spacing: 10) {
            Text(shareTitle).font(.system(size: 28, weight: .heavy, design: .rounded)).tracking(-0.5)
                .lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
            NavigationLink { displaySettings } label: { headerIcon("paintpalette.fill") }
                .accessibilityLabel(shareTitle + "表示設定").accessibilityIdentifier("sharing.settings")
            Button { Task { await export(saveToPhotos: false) } } label: {
                if exporting { ProgressView().frame(width: 36, height: 36) }
                else { headerIcon("square.and.arrow.up") }
            }.accessibilityLabel("画像を共有").accessibilityIdentifier("sharing.share")
            Button { Task { await export(saveToPhotos: true) } } label: { headerIcon("square.and.arrow.down") }
                .accessibilityLabel("写真に保存").accessibilityIdentifier("sharing.save")
        }
        .buttonStyle(.plain).disabled(exporting || loadingPhoto)
        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 10).background(appBackgroundColor)
    }
    private func headerIcon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 17, weight: .semibold)).foregroundStyle(.primary)
            .frame(width: 36, height: 36).background(appCardColor).clipShape(Circle())
            .overlay { Circle().stroke(Color.primary.opacity(0.10), lineWidth: 1) }
    }
    private var periodControls: some View {
        VStack(spacing: 10) {
            Picker("入れる記録", selection: $status) {
                Text("すべて").tag("all")
                Text("参加中・予定").tag("active")
                Text("参加済").tag("completed")
            }.pickerStyle(.segmented)
            HStack(spacing: 10) {
                Text("年").font(.subheadline).foregroundStyle(.secondary)
                Picker("年", selection: $year) {
                    Text("全期間").tag(0)
                    ForEach(years, id: \.self) { Text("\($0)年").tag($0) }
                }.labelsHidden().pickerStyle(.menu).tint(.primary)
                Spacer(minLength: 4)
                Text("月").font(.subheadline).foregroundStyle(.secondary)
                Picker("月", selection: $monthPeriod) {
                    Text("すべて").tag(0)
                    Text("上半期").tag(101); Text("下半期").tag(102)
                    ForEach(201...204, id: \.self) { quarter in Text("\((quarter - 201) * 3 + 1)〜\((quarter - 200) * 3)月").tag(quarter) }
                    ForEach(1...12, id: \.self) { Text("\($0)月").tag($0) }
                }.labelsHidden().pickerStyle(.menu).tint(.primary)
            }
        }.disabled(exporting)
    }
    private var pageControls: some View {
        HStack {
            Button { page -= 1 } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                .disabled(page == 0 || exporting).accessibilityLabel("前のページ")
            Spacer()
            Text("\(page + 1) / \(pageCount)").font(.subheadline.weight(.semibold)).monospacedDigit()
            Spacer()
            Button { page += 1 } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
                .disabled(page + 1 >= pageCount || exporting).accessibilityLabel("次のページ")
        }.buttonStyle(.plain).tint(.primary)
    }
    private var preview: some View {
        Group {
            if let previewImage {
                Image(uiImage: previewImage).resizable().scaledToFit()
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topTrailing) { if renderingPreview { ProgressView().padding(12) } }
                    .accessibilityLabel(shareTitle + "の共有画像")
            } else {
                ProgressView("プレビューを作成中").frame(maxWidth: .infinity, minHeight: 220)
            }
        }
    }
    private var displaySettings: some View {
        Form {
            Section {
                AppCardSectionTitle(title: "背景と文字", systemImage: "paintpalette", accentColor: AppSectionAccent.photo).listRowSeparator(.hidden)
                Picker("背景", selection: $background) {
                    Text("GiriStair").tag("cream"); Text("白").tag("white"); Text("黒").tag("black")
                    Text("ピンク").tag("pink"); Text("ネイビー").tag("navy")
                    Text("GiriStairグラデ").tag("creamGradient"); Text("ピンクグラデ").tag("pinkGradient")
                    Text("ネイビーグラデ").tag("navyGradient"); Text("青白グラデ").tag("blueGradient")
                    Text("写真").tag("photo")
                }.pickerStyle(.menu).tint(.primary)
                if background == "photo" {
                    PhotosPicker("背景の写真を選ぶ", selection: $photoItem, matching: .images)
                    if loadingPhoto { ProgressView() }
                    if let backgroundPhoto { Image(uiImage: backgroundPhoto).resizable().scaledToFit().frame(maxHeight: 160) }
                }
                Picker("文字色", selection: $textColor) {
                    Text("自動").tag("auto"); Text("黒").tag("black"); Text("白").tag("white"); Text("ピンク").tag("pink")
                }.pickerStyle(.menu).tint(.primary)
            }.appSectionCardStyle(accentColor: AppSectionAccent.photo)
            Section {
                AppCardSectionTitle(title: "表示する項目", systemImage: "slider.horizontal.3", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                Picker("形式", selection: $kind) {
                    Text("すべて").tag("all")
                    ForEach(EventFormat.allCases) { format in Text(format.title).tag(format.rawValue) }
                }.pickerStyle(.menu).tint(.primary)
                Toggle("会場", isOn: $showVenues).tint(AppSectionAccent.artist)
                Toggle("戦績", isOn: $showResults).tint(AppSectionAccent.artist)
                Toggle("主催者", isOn: $showOrganizers).tint(AppSectionAccent.artist)
                Toggle("一緒に参加した人", isOn: $showParticipants).tint(AppSectionAccent.artist)
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
        }
        .appEditorFormStyle().navigationTitle(shareTitle + "表示設定").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: photoItem) { await loadBackground(photoItem) }
        .task(id: background) { loadSavedBackground() }
    }
    private func renderPreview() async {
        renderingPreview = true
        defer { renderingPreview = false }
        await Task.yield()
        guard !Task.isCancelled else { return }
        let renderer = ImageRenderer(content: paper(page: min(page, pageCount - 1)))
        renderer.scale = 1
        if let image = renderer.uiImage { previewImage = image }
        else { store.errorMessage = GiriShareError.render.localizedDescription }
    }

    private func paper(page: Int) -> some View {
        VStack(alignment: .leading, spacing: listMode ? 22 : 12) {
            if listMode { listHeader(page: page) }
            else { summaryHeader }
            if !store.preferences.selfName.isEmpty {
                Text(store.preferences.selfName).font(.system(size: listMode ? 18 : 13, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            if listMode { listPaper(page: page) } else { summaryPaper }
            Spacer(minLength: listMode ? 6 : 0)
            HStack { Text("GiriStair"); Spacer(); Text(listMode ? "\(page + 1) / \(pageCount)" : periodTitle) }
                .font(.system(size: listMode ? 12 : 9, weight: .medium)).opacity(0.55)
        }
        .foregroundStyle(foreground)
        .padding(listMode ? 32 : 14)
        .frame(width: paperWidth, alignment: .leading)
        .frame(minHeight: listMode ? 842 : 0, alignment: .top)
        .background { paperBackground }
        .clipShape(RoundedRectangle(cornerRadius: listMode ? 0 : 26, style: .continuous))
        .overlay { if !listMode { RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(foreground.opacity(0.10), lineWidth: 1) } }
        .environment(\.colorScheme, .light)
    }
    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("GIRI SUMMARY").font(.system(size: 28, weight: .black)).tracking(-1).lineLimit(1)
                    Text("MY OGIRI ARCHIVE").font(.system(size: 8, weight: .semibold)).tracking(1.8).opacity(0.58)
                }
                Spacer(minLength: 8)
                BrandWordmark().frame(width: 72, height: 28).opacity(0.9)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("集計期間").font(.system(size: 11, weight: .bold)).foregroundStyle(accentActionColor)
                    Text(periodTitle).font(.system(size: 15, weight: .semibold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("参加回数").font(.system(size: 10, weight: .bold)).foregroundStyle(accentActionColor)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(records.count)").font(.system(size: 40, weight: .black, design: .rounded)).monospacedDigit()
                        Text("回").font(.system(size: 13, weight: .bold))
                    }
                }
            }
            Rectangle().fill(accentActionColor.opacity(0.30)).frame(height: 0.8)
        }
    }
    @ViewBuilder private var paperBackground: some View {
        if background == "photo", let backgroundPhoto { GeometryReader { geometry in Image(uiImage: backgroundPhoto).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped().overlay(.black.opacity(textColor == "white" ? 0.25 : 0)) } }
        else if background.hasSuffix("Gradient") {
            let colors: [Color] = background == "navyGradient" ? [Color(red: 0.08, green: 0.14, blue: 0.24), Color(red: 0.21, green: 0.31, blue: 0.45)] : background == "pinkGradient" ? [Color(red: 1, green: 0.86, blue: 0.90), .white] : background == "blueGradient" ? [Color(red: 0.82, green: 0.91, blue: 1), .white] : [Color(red: 0.96, green: 0.93, blue: 0.85), .white]
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            (background == "white" ? Color.white : background == "black" ? Color.black : background == "pink" ? Color(red: 1, green: 0.91, blue: 0.94) : background == "navy" ? Color(red: 0.09, green: 0.15, blue: 0.25) : Color(red: 245 / 255, green: 241 / 255, blue: 232 / 255))
        }
    }
    private var summaryPaper: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 10) {
                ForEach(EventFormat.allCases) { format in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Circle().fill(giriStatisticsFormatColor(format)).frame(width: 5, height: 5)
                        Text(format.title).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                        Spacer(minLength: 2)
                        Text("\(records.filter { $0.eventFormat == format }.count)").font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                    }
                }
            }
            if showResults {
                let tournaments = records.filter { $0.meetingType == .tournament && $0.isCountableParticipation() }
                HStack(spacing: 14) {
                    paperCount("優勝", tournaments.filter { $0.effectivePlacement == 1 }.count, AppSectionAccent.ticket)
                    paperCount("準優勝", tournaments.filter { $0.effectivePlacement == 2 }.count, AppSectionAccent.ticket)
                    paperCount("大会参加", tournaments.count, foreground)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("月別の参加回数").font(.system(size: 12, weight: .bold))
                GiriMonthChart(records: records, year: year == 0 ? nil : year, ink: foreground).frame(height: 185)
            }
            Rectangle().fill(foreground.opacity(0.12)).frame(height: 0.7)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    if showVenues { paperRanking("会場", giriRanks(records.filter { $0.eventFormat.hasLiveTiming }.map(\.venue))) }
                    paperRanking("サイト", giriRanks(records.filter { $0.eventFormat.hasOnlineRounds }.map { giriSiteName($0, sites: store.onlineSites) }))
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    if showOrganizers { paperRanking("主催者", giriRanks(records.map(\.organizer))) }
                    if showParticipants { paperRanking("一緒に参加した人", giriRanks(records.flatMap { Array(Set($0.participants.filter { $0 != store.preferences.selfName })) })) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func paperCount(_ title: String, _ count: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 10, weight: .semibold)); Text("\(count)").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(color) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func paperRanking(_ title: String, _ entries: [GiriRankEntry]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .bold))
            if entries.isEmpty { Text("—").font(.system(size: 11)).opacity(0.5) }
            ForEach(Array(entries.prefix(5))) { entry in HStack { Text(entry.name).lineLimit(1); Spacer(); Text("\(entry.count)回") }.font(.system(size: 11)) }
            if entries.count > 5 { Text("ほか\(entries.count - 5)件").font(.system(size: 9)).opacity(0.6) }
        }
    }

    // LiveListShareView.header uses default-design black type with deliberate
    // tracking, a trailing96×34 wordmark and a baseline-aligned period/count row.
    private func listHeader(page: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("GIRI LIST")
                        .font(.system(size: 36, weight: .black)).tracking(-1.2).lineLimit(1)
                    Text("MY OGIRI HISTORY & SCHEDULE")
                        .font(.system(size: 9, weight: .semibold)).tracking(2)
                        .foregroundStyle(foreground.opacity(0.58))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    BrandWordmark().frame(width: 96, height: 34, alignment: .trailing)
                    if pageCount > 1 {
                        Text("\(page + 1) / \(pageCount)")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .monospacedDigit().foregroundStyle(foreground.opacity(0.6))
                    }
                }.padding(.top, 2)
            }
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("期間").font(.system(size: 11, weight: .bold)).foregroundStyle(accentActionColor)
                    Text(periodTitle).font(.system(size: 17, weight: .semibold))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: -2) {
                    Text("記録").font(.system(size: 11, weight: .bold)).foregroundStyle(accentActionColor)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(records.count)").font(.system(size: 30, weight: .black)).monospacedDigit()
                        Text("回").font(.system(size: 12, weight: .bold))
                    }.foregroundStyle(accentActionColor)
                }.fixedSize()
            }
        }
    }

    private func listPaper(page: Int) -> some View {
        let pageRecords = Array(records.dropFirst(page * 15).prefix(15))
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(pageRecords.enumerated()), id: \.element.id) { index, event in
                let date = giriAnalyticsDate(event)
                let previousDate = index > 0 ? giriAnalyticsDate(pageRecords[index - 1]) : nil
                if let date,
                   previousDate == nil || Calendar(identifier: .gregorian).component(.year, from: date) != Calendar(identifier: .gregorian).component(.year, from: previousDate ?? date) {
                    HStack(spacing: 8) {
                        Text(String(Calendar(identifier: .gregorian).component(.year, from: date)) + "年")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(accentActionColor)
                        Rectangle().fill(accentActionColor.opacity(0.22)).frame(height: 0.8)
                    }
                    .padding(.top, 12).padding(.bottom, 2)
                }
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(date == nil ? "未定" : GiriDateText.monthDay(date))
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        Text(GiriDateText.weekdayBadge(date))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(foreground.opacity(0.6))
                    }.frame(width: 64, alignment: .leading)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(event.title).font(.system(size: 14.5, weight: .bold))
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        Text(event.eventFormat.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(giriStatisticsFormatColor(event.eventFormat))
                        if showVenues && !event.venue.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 9.5, weight: .semibold)).foregroundStyle(accentActionColor)
                                Text(event.venue).font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(foreground.opacity(0.7)).lineLimit(1)
                            }
                        }
                        if showOrganizers && !event.organizer.isEmpty { Text("主催　" + event.organizer).font(.system(size: 12)).opacity(0.7) }
                        if showParticipants && !event.participants.isEmpty { Text(event.participants.joined(separator: " / ")).font(.system(size: 12)).lineLimit(2).opacity(0.7) }
                        if showResults && event.isCountableParticipation() {
                            if let rank = event.effectivePlacement { Text(rank == 1 ? "優勝" : rank == 2 ? "準優勝" : "\(rank)位").font(.system(size: 13, weight: .bold)).foregroundStyle(AppSectionAccent.ticket) }
                            else if !event.resultText.isEmpty { Text(event.resultText).font(.system(size: 12)).lineLimit(2) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Rectangle().fill(foreground.opacity(0.18)).frame(height: 0.5).padding(.top, 6)
            }
            if records.isEmpty { Text("記録がありません").padding(.vertical, 40) }
        }
    }
    @MainActor private func export(saveToPhotos: Bool) async {
        guard !exporting else { return }
        exporting = true
        let pagesToExport = pageCount
        defer { exporting = false }
        do {
            if saveToPhotos {
                let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard permission == .authorized || permission == .limited else { throw GiriShareError.photoPermission }
            }
            var urls: [URL] = []
            for index in 0..<pagesToExport {
                let url = try autoreleasepool { () throws -> URL in
                    let renderer = ImageRenderer(content: paper(page: index))
                    renderer.scale = 2
                    guard let image = renderer.uiImage, let data = image.pngData() else { throw GiriShareError.render }
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Giri\(listMode ? "List" : "Summary")-\(UUID().uuidString)-\(index + 1).png")
                    try data.write(to: url, options: .atomic)
                    return url
                }
                if saveToPhotos { try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url) } }
                urls.append(url)
                await Task.yield()
            }
            if saveToPhotos { savedAlert = true } else { shareURLs = urls; sharing = true }
        } catch { store.errorMessage = error.localizedDescription }
    }
    private var backgroundPhotoURL: URL {
        store.directory.appendingPathComponent(listMode ? "giri-list-background.png" : "giri-summary-background.png")
    }
    private func loadSavedBackground() {
        guard background == "photo", backgroundPhoto == nil,
              let data = try? Data(contentsOf: backgroundPhotoURL), let image = UIImage(data: data) else { return }
        backgroundPhoto = image
    }
    @MainActor private func loadBackground(_ item: PhotosPickerItem?) async {
        guard let item, item != loadedPhotoItem else { return }
        loadingPhoto = true
        defer { loadingPhoto = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), !Task.isCancelled,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2048,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary) else {
                if Task.isCancelled { return }
                throw GiriShareError.render
            }
            guard item == photoItem else { return }
            let image = UIImage(cgImage: thumbnail)
            guard let encoded = image.pngData() else { throw GiriShareError.render }
            try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
            try encoded.write(to: backgroundPhotoURL, options: .atomic)
            backgroundPhoto = image
            loadedPhotoItem = item
        } catch is CancellationError {
            // Keep the previously selected background.
        } catch { store.errorMessage = error.localizedDescription }
    }

}
private enum GiriShareError: LocalizedError {
    case render, photoPermission
    var errorDescription: String? { switch self { case .render: "画像を作成できませんでした。表示する記録を絞り込んで、もう一度お試しください。"; case .photoPermission: "写真への保存が許可されていません。端末の「設定」からGiriStairの写真へのアクセスを確認してください。" } }
}

/// Changes produce one cancellable render, without layout callbacks writing
/// measured heights back into the enclosing preview hierarchy.
private struct GiriSharePreviewRequest: Equatable {
    var records: [GiriEvent]
    var page: Int
    var year: Int
    var monthPeriod: Int
    var name: String
    var background: String
    var textColor: String
    var showVenues: Bool
    var showResults: Bool
    var showParticipants: Bool
    var showOrganizers: Bool
    var photo: UIImage?
}
