import SwiftUI

/// 戦績タブの小タブ。まとめ（数・率）と大会一覧（結果記入済／未入力）を分ける。
private enum GiriResultsMode: String, CaseIterable, Identifiable {
    case summary = "まとめ"
    case list = "大会一覧"
    var id: String { rawValue }
}

struct GiriResultsView: View {
    @EnvironmentObject private var store: GiriStore
    @EnvironmentObject private var navigation: GiriNavigation
    @State private var selectedFormat: EventFormat = .live
    @State private var didInitializeFormat = false
    @State private var mode: GiriResultsMode = .summary
    @State private var showsUnentered = false
    @State private var year = "all"
    @State private var collapsed = false
    /// 結果入力はこのタブで開く（大会の詳細は一覧タブ）。
    @State private var entryRequest: GiriResultRequest?
    private var accent: Color { GiriEventPresentation.accent(selectedFormat) }
    private var tournaments: [GiriEvent] {
        store.events.filter {
            $0.meetingType == .tournament && $0.isActualParticipant && $0.eventFormat == selectedFormat &&
            (year == "all" || String(Calendar(identifier: .gregorian).component(.year, from: GiriEventPresentation.date($0) ?? $0.createdAt)) == year)
        }
    }
    private var years: [String] {
        Array(Set(store.events.filter { $0.meetingType == .tournament && $0.eventFormat == selectedFormat }.map {
            String(Calendar(identifier: .gregorian).component(.year, from: GiriEventPresentation.date($0) ?? $0.createdAt))
        })).sorted(by: >)
    }
    private func filtered(unentered: Bool) -> [GiriEvent] {
        let now = Date()
        return tournaments.filter {
            unentered ? ($0.hasEnded(now: now) && !$0.hasFinalResult) : $0.hasFinalResult
        }.sorted { (GiriEventPresentation.date($0) ?? $0.createdAt) > (GiriEventPresentation.date($1) ?? $1.createdAt) }
    }
    private var filtered: [GiriEvent] { filtered(unentered: showsUnentered) }
    private var headerCount: Int { mode == .list ? filtered.count : completed.count }
    // Intermediate advancement, upcoming events, and other players' podiums
    // never become one's own completed participation or final placement.
    private var completed: [GiriEvent] { tournaments.filter { $0.isCountableParticipation() } }
    private var champions: Int { completed.filter { $0.effectivePlacement == 1 }.count }
    private var runnersUp: Int { completed.filter { $0.effectivePlacement == 2 }.count }
    // 3位とベスト4は分けて数える（3位決定戦のある大会とない大会を混ぜない）。
    private var thirds: Int { completed.filter(\.isThirdPlace).count }
    private var bestFours: Int { completed.filter { $0.isBest(4) }.count }
    private var otherPlaced: Int { completed.filter(giriIsOtherPlacement).count }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            VStack(spacing: 0) {
                filterHeader
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if mode == .summary { summaryContent } else { listContent }
                    }.padding(.bottom, 104)
                }
            }
        }
        .background(appBackgroundColor)
        .safeAreaInset(edge: .top, spacing: 0) { AppPageHeader(title: "戦績", systemImage: "trophy", accentColor: accent) }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $entryRequest) { request in
            GiriResultEntry(eventID: request.eventID, initialRoundID: request.roundID, initialStageID: request.stageID)
        }
        .onAppear {
            if !didInitializeFormat {
                selectedFormat = store.preferences.visibleFormatOrder.first ?? .live
                didInitializeFormat = true
            }
            consumeResultRequest()
        }
        .onChange(of: navigation.resultRequest) { _, _ in consumeResultRequest() }
        .onChange(of: store.preferences.visibleFormatOrder) { previous, next in
            if selectedFormat == previous.first || !next.contains(selectedFormat) { selectedFormat = next.first ?? .live }
        }
        .onChange(of: selectedFormat) { _, _ in year = "all" }
    }

    /// 詳細やお題/回答から「結果」を押した時に、このタブで結果入力を開く。入力中の内容は消さない。
    private func consumeResultRequest() {
        guard let request = navigation.resultRequest else { return }
        navigation.resultRequest = nil
        if entryRequest?.eventID == request.eventID { return }
        if entryRequest != nil, let unsaved = navigation.unsavedResultEventID, unsaved != request.eventID {
            store.errorMessage = "入力中の結果があります。保存するか破棄してから、もう一度開いてください。"
            return
        }
        entryRequest = request
    }

    // MARK: まとめ

    @ViewBuilder private var summaryContent: some View {
        statistics.padding(.horizontal, 18).padding(.vertical, 6)
        progressCard.padding(.horizontal, 18).padding(.vertical, 6)
    }

    /// 結果の入力状況。未入力があれば大会一覧の「結果未入力」へ移れる。
    private var progressCard: some View {
        let unentered = filtered(unentered: true).count
        let entered = filtered(unentered: false).count
        return VStack(alignment: .leading, spacing: 12) {
            AppCardSectionTitle(title: "結果の入力", systemImage: "square.and.pencil", accentColor: accent)
            summaryRow("結果記入済", "\(entered)件")
            Divider().overlay(appSeparatorColor)
            Button {
                showsUnentered = true
                mode = .list
            } label: {
                HStack {
                    Text("結果未入力").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(unentered)件").font(.body.weight(.medium)).foregroundStyle(.primary)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(unentered == 0)
        }.padding(14).appTintedCard(accentColor: accent)
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.weight(.medium))
        }
    }

    // MARK: 大会一覧

    @ViewBuilder private var listContent: some View {
        Picker("大会の記録", selection: $showsUnentered) {
            Text("結果記入済").tag(false)
            Text("結果未入力").tag(true)
        }
        .pickerStyle(.segmented).tint(accent)
        .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 4)
        HStack {
            Text(showsUnentered ? "結果未入力の大会" : "結果記入済の大会")
                .font(.system(size: appFontSize(18), weight: .bold, design: .rounded))
            Spacer()
            Text("\(filtered.count)件").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 8)
        if filtered.isEmpty {
            CenteredEmptyMessage(systemImage: "trophy", title: showsUnentered ? "結果未入力の大会はありません" : "結果を記入した大会がありません")
                .frame(maxWidth: .infinity, minHeight: 145)
                .appTintedCard(accentColor: accent).padding(.horizontal, 18)
        }
        ForEach(filtered) { event in
            resultRow(event)
                .padding(.horizontal, 18).padding(.vertical, 6)
        }
    }

    private func resultRow(_ event: GiriEvent) -> some View {
        Button { entryRequest = GiriResultRequest(eventID: event.id) } label: {
            GiriEventCard(event: event, showsResult: true, resultActionTitle: showsUnentered ? "結果を入力する" : nil)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { entryRequest = GiriResultRequest(eventID: event.id) } label: { Label("結果を記録", systemImage: "square.and.pencil") }
            Button { navigation.openEventDetail(event.id) } label: { Label("詳細", systemImage: "info.circle") }
        }
    }

    private var filterHeader: some View {
        VStack(spacing: 5) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3").font(.system(size: appFontSize(16), weight: .semibold)).foregroundStyle(accent).frame(width: 22)
                Text("表示・絞り込み").font(.system(size: appFontSize(18), weight: .bold, design: .rounded))
                Spacer()
                Text("\(headerCount)件").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                AppHeaderCollapseButton(isCollapsed: $collapsed, tintColor: accent)
            }
            GiriFormatPicker(selection: $selectedFormat, formats: store.preferences.visibleFormatOrder)
            Picker("表示", selection: $mode) {
                ForEach(GiriResultsMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).tint(accent)
            if !collapsed {
                Divider().overlay(appSeparatorColor)
                GiriListFilterMenu(title: "年", selection: $year,
                    options: [("all", "全期間")] + years.map { ($0, $0 + "年") })
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
        .appTintedCard(accentColor: accent, cornerRadius: 20, railVerticalInset: 14, lightTintOpacity: 0.065)
        .padding(.horizontal, 18).padding(.bottom, 12)
    }
    private var statistics: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppCardSectionTitle(title: "最終成績", systemImage: "trophy", accentColor: accent)
            HStack(spacing: 0) {
                metric("優勝", champions, image: "trophy.fill", color: accent)
                Divider().overlay(appSeparatorColor)
                metric("準優勝", runnersUp, image: "medal.fill", color: .secondary)
                Divider().overlay(appSeparatorColor)
                metric("3位", thirds, image: "3.circle.fill", color: AppSectionAccent.ticket)
                Divider().overlay(appSeparatorColor)
                metric("ベスト4", bestFours, image: "rosette", color: AppSectionAccent.artist)
            }.frame(height: 72)
            Divider().overlay(appSeparatorColor)
            if otherPlaced > 0 {
                summaryRow("ベスト8・その他の入賞", "\(otherPlaced)件")
                Divider().overlay(appSeparatorColor)
            }
            summaryRow("終了した大会", "\(completed.count)件")
        }.padding(14).appTintedCard(accentColor: accent)
    }
    private func metric(_ title: String, _ count: Int, image: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Label(title, systemImage: image).font(.caption.weight(.medium)).foregroundStyle(color)
            Text("\(count)").font(.system(size: appFontSize(26), weight: .bold, design: .rounded)).foregroundStyle(.primary)
        }.frame(maxWidth: .infinity)
    }
}
