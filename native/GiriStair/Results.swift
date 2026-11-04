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
            $0.meetingType == .tournament && $0.isActualParticipant && $0.isSelfPlayer && $0.eventFormat == selectedFormat &&
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
    // 3位とベスト4は分けて数える（3位決定戦のある大会とない大会を混ぜない）。
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
        let summary = giriTournamentSummary(tournaments)
        statistics(summary).padding(.horizontal, 18).padding(.vertical, 6)
        if summary.completed > 0 {
            ratesCard(summary).padding(.horizontal, 18).padding(.vertical, 6)
            if !summary.furthest.isEmpty {
                furthestCard(summary).padding(.horizontal, 18).padding(.vertical, 6)
            }
            let organizers = giriOrganizerResults(tournaments)
            if !organizers.isEmpty {
                organizerCard(organizers).padding(.horizontal, 18).padding(.vertical, 6)
            }
            // ネット大喜利（長考）は段階の形式がほぼ1つなので、形式・審査方法ごとは出さない。
            if selectedFormat != .onlineLong {
                let lineups = giriStagePassRates(tournaments) { event, stage in
                    stage.lineup.isEmpty && event.knockout ? "タイマン" : stage.lineup
                }
                if !lineups.isEmpty {
                    rateListCard("形式ごとの勝ち抜き", systemImage: "person.3.sequence", rows: lineups, color: AppSectionAccent.song)
                        .padding(.horizontal, 18).padding(.vertical, 6)
                }
                let judgings = giriStagePassRates(tournaments) { event, stage in
                    giriJudgingCategory(stage.judging.isEmpty ? event.judging : stage.judging)
                }
                if !judgings.isEmpty {
                    rateListCard("審査方法ごとの勝ち抜き", systemImage: "hand.raised", rows: judgings, color: AppSectionAccent.memo)
                        .padding(.horizontal, 18).padding(.vertical, 6)
                }
            }
        }
        progressCard.padding(.horizontal, 18).padding(.vertical, 6)
    }

    /// 優勝率・決勝進出率・予選通過率（予選がない大会は最初の段階）。
    private func ratesCard(_ summary: GiriTournamentSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AppCardSectionTitle(title: "率", systemImage: "percent", accentColor: AppSectionAccent.artist,
                                infoTitle: "率について",
                                infoMessage: "終わった大会のうちの割合です。予選通過率は予選の結果が分かる大会で数え、予選がない大会は最初の段階で数えます。")
            rateRow("優勝率", summary.champions, summary.completed)
            Divider().overlay(appSeparatorColor)
            rateRow("決勝進出率", summary.finalists, summary.completed)
            Divider().overlay(appSeparatorColor)
            rateRow("予選通過率", summary.qualifierPassed, summary.qualifierKnown)
        }.padding(14).appTintedCard(accentColor: AppSectionAccent.artist)
    }

    private func rateRow(_ title: String, _ passed: Int, _ total: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(giriRateText(passed, total)).font(.body.weight(.semibold)).monospacedDigit()
            Text("\(passed)/\(total)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .frame(minWidth: 44, alignment: .trailing)
        }
    }

    /// どこまで進んだか（大会ごとの段階の数が違っても、予選〜決勝の深さで比べる）。
    private func furthestCard(_ summary: GiriTournamentSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AppCardSectionTitle(title: "どこまで進んだか", systemImage: "stairs", accentColor: AppSectionAccent.venue,
                                infoTitle: "どこまで進んだかについて",
                                infoMessage: "大会ごとに、記録のある一番先の段階で数えます。段階の種類は段階名から自動で決まり、結果の入力で変えられます。")
            let kinds = StageKind.allCases.filter { $0.depth != nil }.reversed()
            ForEach(Array(kinds.enumerated()), id: \.element) { index, kind in
                if index > 0 { Divider().overlay(appSeparatorColor) }
                summaryRow(kind.title, "\(summary.furthest[kind] ?? 0)件")
            }
        }.padding(14).appTintedCard(accentColor: AppSectionAccent.venue)
    }

    private func organizerCard(_ rows: [GiriOrganizerRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AppCardSectionTitle(title: "主催ごと", systemImage: "person.crop.rectangle", accentColor: AppSectionAccent.live)
            ForEach(Array(rows.prefix(8).enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(appSeparatorColor) }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.name).font(.subheadline).lineLimit(1)
                    Spacer(minLength: 8)
                    Text("出場\(row.entries)・決勝\(row.finals)・優勝\(row.champions)")
                        .font(.subheadline.weight(.medium)).monospacedDigit()
                }
            }
        }.padding(14).appTintedCard(accentColor: AppSectionAccent.live)
    }

    private func rateListCard(_ title: String, systemImage: String, rows: [GiriRateRow], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AppCardSectionTitle(title: title, systemImage: systemImage, accentColor: color,
                                infoTitle: title,
                                infoMessage: "結果を入れた段階のうち、通過・優勝した割合です。")
            ForEach(Array(rows.prefix(10).enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(appSeparatorColor) }
                rateRow(row.label, row.passed, row.total)
            }
        }.padding(14).appTintedCard(accentColor: color)
    }

    /// 結果の入力状況。未入力があれば大会一覧の「結果未入力」へ移れる。
    private var progressCard: some View {
        let unentered = filtered(unentered: true).count
        let entered = filtered(unentered: false).count
        return VStack(alignment: .leading, spacing: 12) {
            AppCardSectionTitle(title: "結果の入力", systemImage: "square.and.pencil", accentColor: AppSectionAccent.scan)
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
        }.padding(14).appTintedCard(accentColor: AppSectionAccent.scan)
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
    private func statistics(_ summary: GiriTournamentSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            AppCardSectionTitle(title: "最終成績", systemImage: "trophy", accentColor: AppSectionAccent.ticket)
            HStack(spacing: 0) {
                metric("優勝", summary.champions, image: "trophy.fill", color: accent)
                Divider().overlay(appSeparatorColor)
                metric("準優勝", summary.runnersUp, image: "medal.fill", color: .secondary)
                Divider().overlay(appSeparatorColor)
                metric("3位", summary.thirds, image: "3.circle.fill", color: AppSectionAccent.ticket)
                Divider().overlay(appSeparatorColor)
                metric("ベスト4", summary.bestFours, image: "rosette", color: AppSectionAccent.artist)
            }.frame(height: 72)
            Divider().overlay(appSeparatorColor)
            summaryRow("決勝進出（優勝・準優勝を含む）", "\(summary.finalists)件")
            Divider().overlay(appSeparatorColor)
            if otherPlaced > 0 {
                summaryRow("ベスト8・その他の入賞", "\(otherPlaced)件")
                Divider().overlay(appSeparatorColor)
            }
            // 個人戦とチーム戦の両方がある時だけ、優勝の内訳を出す（合計は上の数）。
            if summary.teamCount > 0 && summary.individualCount > 0 {
                summaryRow("優勝の内訳", "個人戦\(summary.individualChampions)・チーム戦\(summary.teamChampions)")
                Divider().overlay(appSeparatorColor)
            }
            summaryRow("終了した大会", "\(summary.completed)件")
        }.padding(14).appTintedCard(accentColor: AppSectionAccent.ticket)
    }
    private func metric(_ title: String, _ count: Int, image: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Label(title, systemImage: image).font(.caption.weight(.medium)).foregroundStyle(color)
            Text("\(count)").font(.system(size: appFontSize(26), weight: .bold, design: .rounded)).foregroundStyle(.primary)
        }.frame(maxWidth: .infinity)
    }
}
