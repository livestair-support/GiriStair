import SwiftUI
import Charts
import Photos
import PhotosUI
import UIKit

/// Match the existing statistics boundary: actual attendance only. The date of
/// an online cycle is its last known deadline, not its registration timestamp.
func giriAnalyticsDate(_ event: GiriEvent) -> Date? {
    if event.kind == .live { return event.eventDate ?? event.startsAt }
    return event.effectiveRounds.flatMap { [$0.submissionStart, $0.submissionEnd, $0.votingStart, $0.votingEnd].compactMap { $0 } }.max()
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
            guard event.isParticipating && event.status == .attended else { return false }
            if kind != "all" && event.kind.rawValue != kind { return false }
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
                Picker("形式", selection: $kind) { Text("すべて").tag("all"); Text("生大喜利").tag("live"); Text("ネット大喜利").tag("online") }.pickerStyle(.menu).tint(.primary)
                Picker("会の種類", selection: $meeting) { Text("すべて").tag("all"); Text("通常").tag("casual"); Text("大会").tag("tournament") }.pickerStyle(.menu).tint(.primary)
            }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
            Section {
                AppCardSectionTitle(title: "参加回数", systemImage: "chart.bar", accentColor: AppSectionAccent.ticket).listRowSeparator(.hidden)
                LabeledContent("合計", value: "\(records.count)回")
                LabeledContent("生大喜利", value: "\(records.filter { $0.kind == .live }.count)回")
                LabeledContent("ネット大喜利", value: "\(records.filter { $0.kind == .online }.count)回")
                NavigationLink("参加記録を確認") { GiriStatisticsRecords(title: "参加記録", records: records) }
            }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
            Section {
                AppCardSectionTitle(title: "月別", systemImage: "calendar", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                if records.isEmpty { CenteredEmptyMessage(systemImage: "chart.bar", title: "記録がありません") }
                else { GiriMonthChart(records: records).frame(height: 200) }
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
            ranking("会場別の参加回数", "mappin.and.ellipse", .venue, giriRanks(records.filter { $0.kind == .live }.map(\.venue))) { entry in records.filter { $0.kind == .live && $0.venue == entry.name } }
            ranking("主催者別の参加回数", "person.crop.circle", .memo, giriRanks(records.map(\.organizer))) { entry in records.filter { $0.organizer == entry.name } }
            ranking("一緒に参加した人", "person.2", .artist, giriRanks(records.flatMap { Array(Set($0.participants.filter { $0 != store.preferences.selfName })) })) { entry in records.filter { $0.participants.contains(entry.name) } }
            ranking("サイト別の参加回数", "globe", .artist, giriRanks(records.filter { $0.kind == .online }.map { giriSiteName($0, sites: store.onlineSites) })) { entry in records.filter { $0.kind == .online && giriSiteName($0, sites: store.onlineSites) == entry.name } }
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
                    NavigationLink { GiriEventDetail(eventID: event.id) } label: { VStack(alignment: .leading, spacing: 4) { if let date = giriAnalyticsDate(event) { Text(date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }; Text(event.title) } }
                }
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
        }.appIndexListStyle().toolbar(.visible, for: .navigationBar).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

private struct GiriMonthlyCount: Identifiable {
    var date: Date
    var kind: String
    var count: Int
    var id: String { "\(date.timeIntervalSince1970):\(kind)" }
}
private struct GiriMonthChart: View {
    var records: [GiriEvent]
    private var values: [GiriMonthlyCount] {
        var counts: [Date: [String: Int]] = [:]
        for event in records {
            guard let date = giriAnalyticsDate(event), let month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) else { continue }
            counts[month, default: [:]][event.kind == .live ? "生大喜利" : "ネット大喜利", default: 0] += 1
        }
        return counts.keys.sorted().flatMap { date in ["生大喜利", "ネット大喜利"].map { GiriMonthlyCount(date: date, kind: $0, count: counts[date]?[$0] ?? 0) } }
    }
    var body: some View {
        Chart(values) { value in
            BarMark(x: .value("月", value.date, unit: .month), y: .value("参加回数", value.count)).foregroundStyle(by: .value("形式", value.kind))
        }.chartForegroundStyleScale(["生大喜利": AppSectionAccent.live, "ネット大喜利": AppSectionAccent.artist])
            .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.year(.twoDigits).month(.defaultDigits)) } }
    }
}

struct GiriSharingView: View {
    @EnvironmentObject private var store: GiriStore
    private var listMode: Bool
    @State private var year = 0
    @State private var monthPeriod = 0
    @State private var status = "attended"
    @State private var kind = "all"
    @State private var showVenues = true
    @State private var showResults = true
    @State private var showParticipants = false
    @State private var showOrganizers = true
    @State private var background = "cream"
    @State private var textColor = "auto"
    @State private var photoItem: PhotosPickerItem?
    @State private var backgroundPhoto: UIImage?
    @State private var page = 0
    @State private var exporting = false
    @State private var shareURLs: [URL] = []
    @State private var sharing = false
    @State private var savedAlert = false
    init(initialList: Bool = false) { listMode = initialList }
    private var records: [GiriEvent] {
        store.events.filter { event in
            guard event.isParticipating && event.status != .canceled else { return false }
            if status != "all" && event.status.rawValue != status { return false }
            if kind != "all" && event.kind.rawValue != kind { return false }
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

    var body: some View {
        Form {
            Section {
                AppCardSectionTitle(title: "表示・絞り込み", systemImage: "line.3.horizontal.decrease", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                Picker("参加状況", selection: $status) { Text("すべて").tag("all"); Text("参加予定").tag("planned"); Text("参加済み").tag("attended") }.pickerStyle(.segmented)
                Picker("年", selection: $year) { Text("全期間").tag(0); ForEach(years, id: \.self) { Text("\($0)年").tag($0) } }.pickerStyle(.menu).tint(.primary)
                Picker("期間", selection: $monthPeriod) { Text("すべて").tag(0); Text("上半期").tag(101); Text("下半期").tag(102); ForEach(201...204, id: \.self) { quarter in Text("\((quarter - 201) * 3 + 1)〜\((quarter - 200) * 3)月").tag(quarter) }; ForEach(1...12, id: \.self) { Text("\($0)月").tag($0) } }.pickerStyle(.menu).tint(.primary)
                Picker("形式", selection: $kind) { Text("すべて").tag("all"); Text("生大喜利").tag("live"); Text("ネット大喜利").tag("online") }.pickerStyle(.menu).tint(.primary)
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            Section {
                AppCardSectionTitle(title: "表示設定", systemImage: "paintpalette", accentColor: AppSectionAccent.photo).listRowSeparator(.hidden)
                Picker("背景", selection: $background) {
                    Text("GiriStair").tag("cream"); Text("白").tag("white"); Text("黒").tag("black"); Text("ピンク").tag("pink"); Text("ネイビー").tag("navy"); Text("GiriStairグラデ").tag("creamGradient"); Text("ピンクグラデ").tag("pinkGradient"); Text("ネイビーグラデ").tag("navyGradient"); Text("青白グラデ").tag("blueGradient"); Text("写真").tag("photo")
                }.pickerStyle(.menu).tint(.primary)
                if background == "photo" { PhotosPicker("背景の写真を選ぶ", selection: $photoItem, matching: .images) }
                Picker("文字色", selection: $textColor) { Text("自動").tag("auto"); Text("黒").tag("black"); Text("白").tag("white"); Text("ピンク").tag("pink") }.pickerStyle(.menu).tint(.primary)
                Toggle("会場", isOn: $showVenues).tint(AppSectionAccent.photo)
                Toggle("戦績", isOn: $showResults).tint(AppSectionAccent.photo)
                Toggle("主催者", isOn: $showOrganizers).tint(AppSectionAccent.photo)
                Toggle("一緒に参加した人", isOn: $showParticipants).tint(AppSectionAccent.photo)
            }.appSectionCardStyle(accentColor: AppSectionAccent.photo)
            Section {
                if listMode && pageCount > 1 { Picker("ページ", selection: $page) { ForEach(0..<pageCount, id: \.self) { Text("\($0 + 1) / \(pageCount)").tag($0) } }.pickerStyle(.menu) }
                GeometryReader { geometry in
                    paper(page: min(page, pageCount - 1)).frame(width: 595).scaleEffect(geometry.size.width / 595, anchor: .topLeading)
                }.frame(height: listMode ? 710 : 630).listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
        }.appEditorFormStyle().toolbar(.visible, for: .navigationBar).navigationTitle(listMode ? "Giri List" : "Giri Summary").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItemGroup(placement: .topBarTrailing) {
                if exporting { ProgressView() }
                Button { Task { await export(saveToPhotos: false) } } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("画像を共有").disabled(exporting)
                Button { Task { await export(saveToPhotos: true) } } label: { Image(systemName: "square.and.arrow.down") }.accessibilityLabel("写真に保存").disabled(exporting)
            } }
            .onChange(of: photoItem) { _, item in Task { await loadBackground(item) } }
            .onChange(of: pageCount) { _, count in if page >= count { page = count - 1 } }
            .sheet(isPresented: $sharing) { GiriShareSheet(items: shareURLs) }
            .alert("写真に保存しました", isPresented: $savedAlert) { Button("閉じる", role: .cancel) {} }
    }

    private func paper(page: Int) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .bottom) {
                Image("BrandWordmark").resizable().scaledToFit().frame(width: 190, height: 48).padding(8).background(.white).clipShape(RoundedRectangle(cornerRadius: 8))
                Spacer()
                Text(periodTitle).font(.system(size: 21, weight: .bold, design: .rounded))
            }
            Text(listMode ? "Giri List" : "Giri Summary").font(.system(size: 38, weight: .bold, design: .rounded))
            if !store.preferences.selfName.isEmpty { Text(store.preferences.selfName).font(.system(size: 20, weight: .semibold)) }
            if listMode { listPaper(page: page) } else { summaryPaper }
            Spacer(minLength: 6)
            HStack { Text("GiriStair"); Spacer(); Text(listMode ? "\(page + 1) / \(pageCount)" : periodTitle) }.font(.system(size: 12, weight: .medium)).opacity(0.6)
        }.foregroundStyle(foreground).padding(32).frame(width: 595, alignment: .leading).frame(minHeight: 842, alignment: .top)
            .background { paperBackground }.clipped().environment(\.colorScheme, .light)
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
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline, spacing: 12) { Text("\(records.count)").font(.system(size: 92, weight: .bold, design: .rounded)); Text("回参加").font(.system(size: 24, weight: .semibold)) }
            HStack(spacing: 24) { paperCount("生大喜利", records.filter { $0.kind == .live }.count, AppSectionAccent.live); paperCount("ネット大喜利", records.filter { $0.kind == .online }.count, AppSectionAccent.artist) }
            if showResults {
                let tournaments = records.filter { $0.meetingType == .tournament }
                HStack(spacing: 20) { paperCount("優勝", tournaments.filter { $0.effectivePlacement == 1 }.count, AppSectionAccent.ticket); paperCount("準優勝", tournaments.filter { $0.effectivePlacement == 2 }.count, AppSectionAccent.ticket); paperCount("大会参加", tournaments.count, foreground) }
            }
            GiriMonthChart(records: records).frame(height: 150)
            if showVenues { paperRanking("会場", giriRanks(records.filter { $0.kind == .live }.map(\.venue))) }
            paperRanking("サイト", giriRanks(records.filter { $0.kind == .online }.map { giriSiteName($0, sites: store.onlineSites) }))
            if showOrganizers { paperRanking("主催者", giriRanks(records.map(\.organizer))) }
            if showParticipants { paperRanking("一緒に参加した人", giriRanks(records.flatMap { Array(Set($0.participants.filter { $0 != store.preferences.selfName })) })) }
        }
    }
    private func paperCount(_ title: String, _ count: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 15, weight: .semibold)); Text("\(count)").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(color) }
    }
    private func paperRanking(_ title: String, _ entries: [GiriRankEntry]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 17, weight: .bold))
            if entries.isEmpty { Text("—").font(.system(size: 14)).opacity(0.5) }
            ForEach(Array(entries.prefix(5))) { entry in HStack { Text(entry.name).lineLimit(1); Spacer(); Text("\(entry.count)回") }.font(.system(size: 15)) }
            if entries.count > 5 { Text("ほか\(entries.count - 5)件").font(.system(size: 12)).opacity(0.6) }
        }
    }
    private func listPaper(page: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(records.dropFirst(page * 15).prefix(15))) { event in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(giriAnalyticsDate(event)?.formatted(.dateTime.year().month(.defaultDigits).day().weekday(.abbreviated)) ?? "日付未定").font(.system(size: 14, weight: .bold))
                        Spacer()
                        Text(event.kind == .live ? "生大喜利" : "ネット大喜利").font(.system(size: 12, weight: .semibold)).foregroundStyle(event.kind == .live ? AppSectionAccent.live : AppSectionAccent.artist)
                    }
                    Text(event.title).font(.system(size: 19, weight: .bold)).lineLimit(2)
                    if showVenues && !event.venue.isEmpty { Text(event.venue).font(.system(size: 13)) }
                    if showOrganizers && !event.organizer.isEmpty { Text("主催　" + event.organizer).font(.system(size: 12)).opacity(0.7) }
                    if showParticipants && !event.participants.isEmpty { Text(event.participants.joined(separator: " / ")).font(.system(size: 12)).lineLimit(2).opacity(0.7) }
                    if showResults {
                        if let rank = event.effectivePlacement { Text(rank == 1 ? "優勝" : rank == 2 ? "準優勝" : "\(rank)位").font(.system(size: 13, weight: .bold)).foregroundStyle(AppSectionAccent.ticket) }
                        else if !event.resultText.isEmpty { Text(event.resultText).font(.system(size: 12)).lineLimit(2) }
                    }
                    Rectangle().fill(foreground.opacity(0.18)).frame(height: 0.5).padding(.top, 6)
                }
            }
            if records.isEmpty { Text("記録がありません").padding(.vertical, 40) }
        }
    }
    @MainActor private func export(saveToPhotos: Bool) async {
        exporting = true
        defer { exporting = false }
        do {
            if saveToPhotos {
                let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard permission == .authorized || permission == .limited else { throw GiriShareError.photoPermission }
            }
            var urls: [URL] = []
            for index in 0..<pageCount {
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
    @MainActor private func loadBackground(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw GiriShareError.render }
            backgroundPhoto = image
        } catch { store.errorMessage = error.localizedDescription }
    }
}
private enum GiriShareError: LocalizedError {
    case render, photoPermission
    var errorDescription: String? { switch self { case .render: "画像を作成できませんでした。表示する記録を絞り込んで、もう一度お試しください。"; case .photoPermission: "写真への保存が許可されていません。端末の「設定」からGiriStairの写真へのアクセスを確認してください。" } }
}
