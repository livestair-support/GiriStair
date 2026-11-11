import SwiftUI
import PhotosUI
import MapKit
import UIKit

struct GiriPlayerAvatar: View {
    @EnvironmentObject private var store: GiriStore
    var name: String
    var size: CGFloat = 32
    var body: some View {
        if store.showPlayerIcons {
            Group {
                if let player = store.playerDirectory.first(where: { $0.name == name }),
                   let data = Data(base64Encoded: player.iconDataBase64), let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else { Image(systemName: "person.fill").resizable().scaledToFit().padding(size * 0.2).foregroundStyle(AppSectionAccent.artist).background(AppSectionAccent.artist.opacity(0.12)) }
            }.frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
        }
    }
}

struct GiriSitesView: View {
    @EnvironmentObject private var store: GiriStore
    @State private var query = ""
    @State private var isHeaderCollapsed = false
    private var sites: [OnlineSite] {
        store.onlineSites.filter { query.isEmpty || [$0.name, $0.affiliation, $0.block, $0.memo].joined(separator: " ").localizedStandardContains(query) }
    }
    /// 形式（長考・短考・スプシ系）ごとに、設定の並び順でまとめる。
    private var sections: [GiriIndexSection<OnlineSite>] {
        let order = store.preferences.effectiveFormatOrder
        let groups = Dictionary(grouping: sites, by: \.format)
        return order.filter { groups[$0] != nil }
            .map { GiriIndexSection(id: $0.rawValue, title: $0.title, items: groups[$0] ?? []) }
    }
    var body: some View {
        let values = sections
        List {
            if values.isEmpty {
                Section {
                    CenteredEmptyMessage(systemImage: "globe", title: query.isEmpty ? "サイトがありません" : "該当するサイトがありません")
                }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            }
            ForEach(values) { section in
                Section {
                    AppIndexSectionTitle(title: section.title, count: section.items.count, systemImage: "globe", accentColor: AppSectionAccent.artist)
                        .listRowSeparator(.hidden)
                    ForEach(section.items) { site in
                        NavigationLink { GiriSiteDetail(siteID: site.id) } label: {
                            HStack(spacing: 12) {
                                AppIndexItemBadge(systemImage: "globe", color: AppSectionAccent.artist)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(site.name).font(.headline.weight(.semibold)).lineLimit(1)
                                        if site.isPaused {
                                            Text("休止中").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                                .padding(.horizontal, 7).padding(.vertical, 3)
                                                .background(Color.secondary.opacity(0.12)).clipShape(Capsule())
                                        }
                                    }
                                    let labels = [site.hasAffiliations ? siteLeague(site) : "", site.block].filter { !$0.isEmpty }
                                    if !labels.isEmpty { Text(labels.joined(separator: "・")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }.layoutPriority(1)
                                Spacer(minLength: 8)
                            }.frame(minHeight: 48).padding(.vertical, 2)
                        }
                    }
                }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            }
        }
        .appIndexListStyle()
        .safeAreaInset(edge: .top, spacing: 0) {
            GiriIndexHeader(accentColor: AppSectionAccent.artist, count: sites.count, search: $query,
                            placeholder: "サイト名・リーグ・ブロックで検索", isCollapsed: $isHeaderCollapsed)
        }
        .navigationTitle("ネット大喜利サイト一覧").navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
        .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { GiriSiteEditor() } label: { Image(systemName: "plus") }.accessibilityLabel("サイトを追加") } }
    }
}

/// Site settings and each joined cycle keep independent historical snapshots.
struct GiriSiteDetail: View {
    @EnvironmentObject private var store: GiriStore
    @EnvironmentObject private var navigation: GiriNavigation
    @Environment(\.dismiss) private var dismiss
    let siteID: String
    @State private var deleting = false
    /// 日程の設定・結果の入力は、この詳細の上に積んで開く（シートにしない）。
    @State private var route: GiriSiteRoute?
    @State private var timelineStart = Date()

    private var site: OnlineSite? { store.onlineSites.first { $0.id == siteID } }
    // 参加した回と、見送りにした回（見送りは参加回数・成績に数えない）。
    private var history: [GiriEvent] {
        store.events.filter { $0.onlineSiteId == siteID && ($0.isActualParticipant || $0.siteSkipped) }
            .sorted { ($0.participationStartDate ?? $0.createdAt) > ($1.participationStartDate ?? $1.createdAt) }
    }
    private var seasonGroups: [GiriSiteSeasonGroup] {
        var groups: [GiriSiteSeasonGroup] = []
        for event in history {
            let key = seasonKey(id: event.siteSeasonID, name: event.siteSeason)
            if let index = groups.firstIndex(where: { $0.id == key }) {
                groups[index].events.append(event)
            } else {
                let displayName = key == currentSeasonKey ? (site?.cycleSettings?.seasonName ?? event.siteSeason) : event.siteSeason
                groups.append(GiriSiteSeasonGroup(id: key, seasonID: event.siteSeasonID, name: displayName, events: [event]))
            }
        }
        return groups
    }
    private var currentSeasonKey: String? {
        guard let settings = site?.cycleSettings, settings.seasonID != nil || !settings.seasonName.isEmpty else { return nil }
        return seasonKey(id: settings.seasonID, name: settings.seasonName)
    }
    private func seasonKey(id: String?, name: String) -> String { id.map { "season:" + $0 } ?? "legacy:" + name }

    @State private var page = 0

    // LiveStair VenueDetailView と同じ形：名前の見出し → 表示の切り替え → カード。
    var body: some View {
        Group {
            if let site {
                VStack(spacing: 0) {
                    GiriProfileNameHeader(name: site.name, kind: .venue)
                    Picker("表示", selection: $page) {
                        Text("サイト").tag(0)
                        Text("参加履歴").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .tint(page == 0 ? AppSectionAccent.artist : AppSectionAccent.memo)
                    .labelsHidden()
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
                    TabView(selection: $page) {
                        statusPage(site).tag(0)
                        historyPage(site).tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            } else {
                CenteredEmptyMessage(systemImage: "globe", title: "サイトが見つかりません")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background { appBackgroundColor.ignoresSafeArea() }
        .navigationTitle("サイト詳細").navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
        .toolbar {
            // LiveDetailView と同じ並び：ほかの操作 → 削除
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let site {
                    Menu {
                        Button(site.isPaused ? "参加を再開する" : "しばらく休む", systemImage: site.isPaused ? "play.circle" : "pause.circle") {
                            let resuming = site.isPaused
                            store.run {
                                try store.setSitePaused(siteID, paused: !resuming)
                                if resuming { try store.ensureCurrentSiteCycles() }
                                playLiveStairSaveFeedback()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(accentActionColor).frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("ほかの操作")
                }
                Button(role: .destructive) { deleting = true } label: {
                    Image(systemName: "trash").foregroundStyle(accentActionColor)
                }.accessibilityLabel("サイトの登録を削除")
            }
        }
        .giriDeleteAlert("サイトを削除しますか？", isPresented: $deleting,
                         message: "「\(site?.name ?? "")」の登録を削除します。過去の参加記録とお題・回答は残ります。") {
            store.run { try store.deleteOnlineSite(siteID); playLiveStairDeleteFeedback(); dismiss() }
        }
        .navigationDestination(item: $route) { GiriSiteRouteView(route: $0) }
    }

    private func statusPage(_ site: OnlineSite) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                if site.isPaused {
                    GiriDetailCard(title: "休止中", systemImage: "pause.circle", accentColor: AppSectionAccent.memo, kind: .venue) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("一覧のカード・通知・新しい回の作成を止めています。").font(.subheadline).foregroundStyle(.secondary)
                            Button("参加を再開する", systemImage: "play.circle") {
                                store.run { try store.setSitePaused(siteID, paused: false); try store.ensureCurrentSiteCycles(); playLiveStairSaveFeedback() }
                            }
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.borderless)
                            .tint(accentActionColor)
                        }
                    }
                }
                // 0.23：お題の出る週がずれた時などは「編集」から今の状態と締切を直す。
                GiriDetailCard(title: "現在の状況", systemImage: "clock", accentColor: AppSectionAccent.artist, kind: .venue, trailing: {
                    Button("編集") { route = .status(site.id) }
                        .font(.subheadline)
                        .foregroundStyle(accentActionColor)
                }) {
                    TimelineView(.periodic(from: timelineStart, by: 60)) { context in
                        GiriSitePeriodActions(site: site, now: context.date, onRoute: { route = $0 })
                    }
                }
                siteCard(site)
                if let url = giriWebURL(site.url) {
                    GiriDetailCard(title: "リンク", systemImage: "link", accentColor: AppSectionAccent.memo, kind: .venue) {
                        GiriProfileLinkRow(title: "サイト", displayText: "", url: url, iconName: "safari")
                    }
                }
                if let settings = site.cycleSettings, settings.trackSeasonTotals, currentSeasonKey != nil {
                    GiriDetailCard(title: "シーズンの合計成績", systemImage: "chart.bar", accentColor: AppSectionAccent.ticket, kind: .venue, trailing: {
                        // 合計は回ごとの回答の点数から出す。点数を入れる回の一覧（参加履歴）へ移る。
                        Button("点数を入れる") { withAnimation { page = 1 } }
                            .font(.subheadline)
                            .foregroundStyle(accentActionColor)
                    }) {
                        VStack(alignment: .leading, spacing: 6) {
                            if !settings.seasonName.isEmpty { Text(settings.seasonName).font(.subheadline.weight(.semibold)) }
                            seasonTotalsRows(site: site, seasonID: settings.seasonID, seasonName: settings.seasonName)
                            Text("参加履歴の各回の「お題・回答」で、提出した回答の点数を入れると集計されます。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if site.hasAffiliations && !site.leagueChanges.isEmpty {
                    GiriDetailCard(title: "シーズン・リーグの履歴", systemImage: "list.number", accentColor: AppSectionAccent.memo, kind: .venue) {
                        VStack(spacing: 0) {
                            let changes = site.leagueChanges.sorted { $0.effectiveFrom > $1.effectiveFrom }
                            ForEach(changes) { change in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(change.seasonName.isEmpty ? "リーグ変更" : change.seasonName).font(.subheadline.weight(.semibold))
                                        Spacer(minLength: 8)
                                        Text(change.toLeague).font(.body.weight(.semibold))
                                    }
                                    Text((change.effectiveFrom > Date() ? "反映予定　" : "適用　") + GiriDateText.dateTime(change.effectiveFrom))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                                if change.id != changes.last?.id { Divider().overlay(appSeparatorColor) }
                            }
                        }
                    }
                }
                GiriDetailCard(title: "メモ", systemImage: "note.text", accentColor: AppSectionAccent.memo, kind: .venue) {
                    if site.memo.isEmpty {
                        Text("未設定").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
                    } else {
                        Text(site.memo).font(.subheadline).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
    }

    private func historyPage(_ site: OnlineSite) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                // 一覧に出ていない過去の回は、ここから追加する。
                GiriDetailCard(title: "参加履歴", systemImage: "clock", accentColor: AppSectionAccent.memo, kind: .venue) {
                    VStack(alignment: .leading, spacing: 8) {
                        if history.isEmpty {
                            Text("参加した回の履歴がありません").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Button { route = .pastCycle(site.id) } label: {
                            Label("参加した回を追加", systemImage: "plus.circle.fill").font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                        .tint(accentActionColor)
                        Text("一覧に出ていない過去の回を、投稿の締切から追加します。").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                ForEach(seasonGroups) { group in
                    GiriDetailCard(title: group.displayName, systemImage: "clock", accentColor: AppSectionAccent.memo, kind: .venue) {
                        VStack(alignment: .leading, spacing: 0) {
                            if let rule = pastRuleLabel(site: site, group: group) {
                                Text(rule).font(.caption).foregroundStyle(.secondary).padding(.bottom, 6)
                            }
                            if site.cycleSettings?.trackSeasonTotals == true, group.id != currentSeasonKey,
                               group.seasonID != nil || !group.name.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    seasonTotalsRows(site: site, seasonID: group.seasonID, seasonName: group.name)
                                }
                                .padding(.bottom, 8)
                            }
                            ForEach(group.events) { event in
                                historyRow(event)
                                if event.id != group.events.last?.id { Divider().overlay(appSeparatorColor) }
                            }
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
    }

    /// 0.14：過去の回を追加した時に「今のシーズンとルールが同じか」を選んだシーズンだけ出す（ルールが複雑なサイト）。
    private func pastRuleLabel(site: OnlineSite, group: GiriSiteSeasonGroup) -> String? {
        guard group.id != currentSeasonKey, siteHasComplexRules(site, events: store.events) else { return nil }
        if group.events.contains(where: { $0.siteRuleRevisionID?.hasPrefix("past-rule:") == true }) { return "ルールは今のシーズンと違う" }
        let current = site.cycleSettings?.ruleRevisionID
        if current != nil, group.events.contains(where: { $0.siteScheduleCustomized && $0.siteRuleRevisionID == current }) { return "ルールは今のシーズンと同じ" }
        return nil
    }

    @ViewBuilder private func seasonTotalsRows(site: OnlineSite, seasonID: String?, seasonName: String) -> some View {
        // 0.23：シーズンのルールが「規定回答数の上位の平均」なら、上位の規定回答数分だけで平均する。
        let rule = site.ruleID(forSeason: seasonID).flatMap { store.rule($0) }
        // 0.28：リーグごとに「上から○回答の平均」が決まっている時は、その数で平均する（タッグもリーグの数を使う）。
        let league = seasonLeague(site: site, seasonID: seasonID)
        let isTag = site.division == "tag" && rule?.tagDivision != nil
        let leagueTop = league.flatMap { rule?.leagueDetail($0, tag: isTag).topAnswerCount }
        let required = leagueTop ?? (rule?.scoring == .topRequired ? rule?.requiredAnswerCount : nil)
        let totals = giriSeasonTotals(siteID: site.id, seasonID: seasonID, seasonName: seasonName, events: store.events, notes: store.notes,
                                      requiredAnswerCount: required)
        if let rule { seasonTotalRow("ルール", rule.displayName) }
        if isTag, let tag = rule?.tagDivision {
            seasonTotalRow(tag.name, site.tagPartner.isEmpty ? "相手未設定" : "相手：" + site.tagPartner)
        }
        seasonTotalRow("提出した回答", "\(totals.submittedAnswerCount)回答")
        seasonTotalRow("点数の記録済み", "\(totals.scoredAnswerCount)回答")
        if let required {
            seasonTotalRow("規定回答数", totals.rateSampleCount >= required ? "\(required)回答（達成）" : "\(required)回答（あと\(required - totals.rateSampleCount)）")
        }
        // 0.28：上から○回答に届かない時の扱い（最下位・集計対象外）。
        if let league, let rule, let top = leagueTop, totals.rateSampleCount < top {
            let detail = rule.leagueDetail(league, tag: isTag)
            if detail.unqualifiedRanksLast || detail.unqualifiedExcluded {
                Text("\(top)回答に届かない時は" + (detail.unqualifiedRanksLast ? "最下位扱い" : "集計対象外") + "になります。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        // 0.27：リーグの規定数（○回以上・結果お題数の1/2以上など）に届いているか。
        if let rule, let league,
           let needed = rule.leagueDetail(league, tag: isTag).requiredAnswers(cycleCount: rule.regularCycleCount) {
            seasonTotalRow("規定数（\(league)）", totals.answeredCycleCount >= needed ? "\(needed)回（達成）" : "\(needed)回（あと\(needed - totals.answeredCycleCount)）")
        }
        // 0.27：回ごとに勝ち抜けを決めるルールは、平均を出さない。
        if rule?.scoring != .perRound {
            seasonTotalRow(required == nil ? "平均（1人あたり）" : "上位\(required ?? 0)回答の平均（1人あたり）", totals.averagePointsPerVoter.map(giriScoreText) ?? "未記録")
            if leagueTop != nil {
                seasonTotalRow("H得票率（上位\(required ?? 0)回答）", totals.averageVoteRate.map { String(format: "%.1f%%", $0) } ?? "未記録")
            }
            if isTag, let tag = rule?.tagDivision {
                tagTotalRows(site: site, seasonID: seasonID, seasonName: seasonName, tag: tag, top: leagueTop, totals: totals)
            }
        }
        if totals.droppedLowerSamples {
            Text("得票率の低い\(totals.rateSampleCount - (required ?? 0))回答は平均に入れていません。")
                .font(.caption).foregroundStyle(.secondary)
        }
        if totals.legacyRoundResultCount > 0 {
            Text("平均には回単位で残した点数\(totals.legacyRoundResultCount)件も含みます。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// 0.28：タッグの相手の得票率（記録した回答から。なければ手で入れた値）と、2人の合計。
    @ViewBuilder private func tagTotalRows(site: OnlineSite, seasonID: String?, seasonName: String, tag: GiriRuleTagDivision,
                                           top: Int?, totals: GiriSeasonTotals) -> some View {
        let partner = site.tagPartner.trimmingCharacters(in: .whitespacesAndNewlines)
        let recorded = giriPersonSeasonRate(name: partner, siteID: site.id, seasonID: seasonID, seasonName: seasonName,
                                            events: store.events, notes: store.notes, topCount: top)
        let manual = site.tagPartnerRates[giriSeasonRuleKey(seasonID)]
        let partnerRate = recorded.averageVoteRate ?? manual
        let total = giriTagSeasonRate(own: totals.averageVoteRate, ownCount: totals.rateSampleCount,
                                      partner: partnerRate, partnerCount: recorded.averageVoteRate == nil ? nil : recorded.sampleCount,
                                      topCount: top, scoring: tag.teamScoring, shortfallZero: tag.memberShortfallZero)
        if !partner.isEmpty {
            seasonTotalRow("相手（" + partner + "）", partnerRate.map { String(format: "%.1f%%", $0) + (recorded.averageVoteRate == nil ? "（手入力）" : "（\(recorded.sampleCount)回答）") } ?? "未記録")
        }
        seasonTotalRow("タッグの成績（" + tag.scoringTitle + "）", total.map { String(format: "%.1f%%", $0) } ?? "未記録")
        NavigationLink {
            GiriTagPartnerRateEditor(siteID: site.id, seasonKey: giriSeasonRuleKey(seasonID), partner: partner)
        } label: {
            Label(recorded.averageVoteRate == nil ? "相手の得票率を入れる" : "相手の得票率（手入力）を直す", systemImage: "square.and.pencil")
                .font(.subheadline)
        }
        .tint(accentActionColor)
        Text("相手の回答を「他人の回答」として得票率付きで記録すると、上から○回答の平均を自動で出します。記録がないシーズンは手で入れた値を使います。")
            .font(.caption).foregroundStyle(.secondary)
    }

    /// 0.27：そのシーズンに入っていたリーグ（記録した回の所属。なければ今のリーグ）。
    private func seasonLeague(site: OnlineSite, seasonID: String?) -> String? {
        guard site.hasAffiliations else { return nil }
        let recorded = store.events.first { $0.onlineSiteId == site.id && $0.siteSeasonID == seasonID && !$0.affiliation.isEmpty }?.affiliation
        let league = recorded ?? siteLeague(site)
        return league.isEmpty ? nil : league
    }

    /// 合計成績の1行（本文より小さく、値は右に寄せる）。
    private func seasonTotalRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(value == "未記録" ? Color.secondary : Color.primary)
        }
    }

    private func siteCard(_ site: OnlineSite) -> some View {
        GiriDetailCard(title: "サイト", systemImage: "slider.horizontal.3", accentColor: AppSectionAccent.artist, kind: .venue, trailing: {
            NavigationLink("編集") { GiriSiteEditor(site: site) }
                .font(.subheadline)
                .foregroundStyle(accentActionColor)
        }) {
            VStack(spacing: 0) {
                GiriProfileInfoRow(title: "形式", value: site.format.title, labelWidth: 80, verticalPadding: 8)
                if let rule = site.currentRuleID.flatMap({ store.rule($0) }) {
                    Divider().overlay(appSeparatorColor)
                    GiriProfileInfoRow(title: "ルール", value: rule.displayName, labelWidth: 80, verticalPadding: 8)
                }
                if site.hasAffiliations {
                    Divider().overlay(appSeparatorColor)
                    GiriProfileInfoRow(title: "現在のリーグ", value: siteLeague(site), labelWidth: 80, verticalPadding: 8)
                }
                if site.division == "tag" {
                    Divider().overlay(appSeparatorColor)
                    GiriProfileInfoRow(title: "部門", value: site.tagPartner.isEmpty ? "タッグ" : "タッグ（" + site.tagPartner + "）", labelWidth: 80, verticalPadding: 8)
                }
                if let settings = site.cycleSettings {
                    Divider().overlay(appSeparatorColor)
                    GiriProfileInfoRow(title: "繰り返し", value: settings.pattern.title, labelWidth: 80, verticalPadding: 8)
                    if !settings.seasonName.isEmpty {
                        Divider().overlay(appSeparatorColor)
                        GiriProfileInfoRow(title: "シーズン", value: settings.seasonName, labelWidth: 80, verticalPadding: 8)
                    }
                    if let start = settings.seasonStart {
                        Divider().overlay(appSeparatorColor)
                        GiriProfileInfoRow(title: "開始", value: GiriDateText.dateTime(start), labelWidth: 80, verticalPadding: 8)
                    }
                    if let end = settings.seasonEndsAt {
                        Divider().overlay(appSeparatorColor)
                        GiriProfileInfoRow(title: "終了", value: GiriDateText.dateTime(end), labelWidth: 80, verticalPadding: 8)
                    }
                }
                if !site.block.isEmpty {
                    Divider().overlay(appSeparatorColor)
                    GiriProfileInfoRow(title: "ブロック", value: site.block, labelWidth: 80, verticalPadding: 8)
                }
            }
        }
    }

    /// 1回分の履歴：見出し（お題・回答を開く）→ その回のお題ごとのリンク → 操作。
    private func historyRow(_ event: GiriEvent) -> some View {
        let prompts = store.notes.filter { $0.eventId == event.id && $0.kind == .answers && !$0.isOthersAnswer }
            .sorted { $0.createdAt < $1.createdAt }
        return VStack(alignment: .leading, spacing: 6) {
            Button { openPrompts(event) } label: { historyHeader(event) }
                .buttonStyle(.plain)
            ForEach(prompts) { note in
                Button { navigation.openThought(noteID: note.id) } label: { historyPromptRow(note) }
                    .buttonStyle(.plain)
            }
            HStack(spacing: 16) {
                Button { openPrompts(event) } label: {
                    Label(prompts.isEmpty ? "お題・回答を入れる" : "お題を追加", systemImage: "text.bubble")
                }
                if event.hasEnded() && !event.siteSkipped {
                    Button { route = .cycleResult(event.id) } label: {
                        Label(event.hasCycleResult ? "結果を直す" : "結果を記録", systemImage: "square.and.pencil")
                    }
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)
            .tint(accentActionColor)
        }
        .padding(.vertical, 6)
    }

    private func historyHeader(_ event: GiriEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(event.siteCycleNumber.map { "第\($0)回" } ?? GiriDateText.day(event.participationStartDate ?? event.eventDate))
                    .font(.headline).foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(event.siteSkipped ? "見送り" : event.participationState().title).font(.caption).foregroundStyle(.secondary)
            }
            if event.siteCycleNumber != nil { Text(GiriDateText.day(event.participationStartDate)).font(.caption).foregroundStyle(.secondary) }
            if !event.affiliation.isEmpty { Text(event.affiliation).font(.subheadline).foregroundStyle(.secondary) }
            if event.sitePeriodKind != .regular { Text(event.sitePeriodKind.title).font(.subheadline).foregroundStyle(.secondary) }
            HStack(spacing: 8) {
                if let rank = event.cyclePlacement { Text("\(rank)位") }
                if event.leagueMovement != .unchanged { Text(event.leagueMovement.title) }
                if event.siteQualification != .none { Text(event.siteQualification.title) }
            }.font(.subheadline.weight(.semibold)).foregroundStyle(AppSectionAccent.ticket)
            if !event.cycleResult.isEmpty { Text(event.cycleResult).font(.subheadline).foregroundStyle(.primary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// お題1つ：お題の文（小さめ）と、提出した回答（さらに小さく）。押すとそのお題を開く。
    private func historyPromptRow(_ note: ThoughtNote) -> some View {
        let submitted = note.submittedAnswers.map(\.text).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let promptText = note.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.bubble").font(.caption2).foregroundStyle(AppSectionAccent.memo).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(promptText.isEmpty ? (note.imageDataBase64.isEmpty ? "お題（未入力）" : "画像のお題") : promptText)
                    .font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                if submitted.isEmpty {
                    Text("回答 \(note.ownAnswerRecords.count)件・提出なし").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("提出：" + submitted.joined(separator: " ／ ")).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 2)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(AppSectionAccent.memo.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }

    private func openPrompts(_ event: GiriEvent) {
        if let round = event.effectiveRounds.first { navigation.openThoughts(eventID: event.id, roundID: round.id) }
        else { navigation.openThoughts(eventID: event.id) }
    }
}

private struct GiriSiteSeasonGroup: Identifiable {
    let id: String
    let seasonID: String?
    let name: String
    var events: [GiriEvent]
    var displayName: String { name.isEmpty ? (seasonID == nil ? "参加履歴" : "シーズン名未設定") : name }
}

struct GiriSiteEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: OnlineSite
    @State private var original: OnlineSite
    @State private var initialized = false
    @State private var discard = false
    private var isNew: Bool
    /// 0.23：現在の状況（今の状態・締切・次のお題）だけを直す。
    private var statusOnly: Bool
    private var onSaved: ((OnlineSite) -> Void)?
    init(site: OnlineSite? = nil, statusOnly: Bool = false, onSaved: ((OnlineSite) -> Void)? = nil) {
        let value = site ?? OnlineSite()
        _draft = State(initialValue: value); _original = State(initialValue: value)
        isNew = site == nil; self.statusOnly = statusOnly && site != nil; self.onSaved = onSaved
    }
    private var changed: Bool { draft != original }
    var body: some View {
        Form {
            if !statusOnly { siteSection }
            if initialized { GiriSiteCycleSettingsForm(site: $draft, isNew: isNew, statusOnly: statusOnly) }
            if !statusOnly {
                Section { TextField("メモ", text: $draft.memo, axis: .vertical).lineLimit(3...8) }
                    .appSectionCardStyle(accentColor: AppSectionAccent.memo)
            }
        }
        .appEditorFormStyle().giriNavigationBarStyle()
        .navigationTitle(statusOnly ? "現在の状況を編集" : isNew ? "サイトを登録" : "サイトを編集").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(changed)
        .interactiveDismissDisabled(changed)
        .onAppear(perform: initialize)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { if changed { Button { discard = true } label: { Image(systemName: "chevron.left") }.accessibilityLabel("戻る") } }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
        .giriDiscardChangesAlert(isPresented: $discard) { dismiss() }
    }
    private var siteSection: some View {
            Section {
                AppCardSectionTitle(title: "サイト", systemImage: "globe", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                TextField("サイト名", text: $draft.name)
                TextField("URL", text: $draft.url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("形式", selection: $draft.format) {
                    ForEach(store.preferences.formatChoices(including: draft.format).filter { $0.hasOnlineRounds }) { format in Text(format.title).tag(format) }
                }.pickerStyle(.menu).tint(.primary)
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }
    private func initialize() {
            guard !initialized else { return }
            if isNew {
                draft.startHour = store.preferences.submissionStartHour
                draft.startMinute = store.preferences.submissionStartMinute
                draft.submissionDays = store.preferences.submissionDays
                draft.votingDays = store.preferences.votingDays
            }
            if draft.hasAffiliations { draft.affiliation = siteLeague(draft) }
            original = draft
            initialized = true
    }
    private func save() {
        var value = draft
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if var settings = value.cycleSettings {
            settings.leagues = settings.leagues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            value.cycleSettings = settings
        }
        store.run { try store.saveOnlineSite(value); onSaved?(value); playLiveStairSaveFeedback(); dismiss() }
    }
}

private enum DirectoryError: LocalizedError { case image; var errorDescription: String? { "画像を読み込めませんでした。別の写真を選んでください。" } }
func giriWebURL(_ string: String) -> URL? { guard let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }; return url }

// ArtistDetailView.infoRow / VenueDetailView.venueInfoRow from LiveStair.
struct GiriProfileInfoRow: View {
    let title: String
    let value: String
    var labelWidth: CGFloat = 104
    var verticalPadding: CGFloat = 10
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
                .frame(width: labelWidth, alignment: .leading)
            Spacer(minLength: 12)
            Text(value.isEmpty ? "未設定" : value).font(.subheadline)
                .foregroundStyle(value.isEmpty || value == "未設定" ? Color.secondary : Color.primary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, verticalPadding)
    }
}


/// 0.28：タッグの相手のシーズンの得票率を手で入れる（相手の回答を記録していない時）。
struct GiriTagPartnerRateEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    let siteID: String
    let seasonKey: String
    let partner: String
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                AppCardSectionTitle(title: "相手の得票率", systemImage: "person.2", accentColor: AppSectionAccent.favorite,
                                    infoTitle: "相手の得票率", infoMessage: "サイトに出ている相手の得票率（H得票率など）を入れます。相手の回答を記録すると、そちらを優先します。")
                    .listRowSeparator(.hidden)
                HStack(spacing: 12) {
                    GiriEditorLabel(partner.isEmpty ? "相手" : partner)
                    TextField("例：12.5", text: $text).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    Text("%").foregroundStyle(.secondary)
                }
                if store.onlineSiteById(siteID)?.tagPartnerRates[seasonKey] != nil {
                    Button("手入力の値を消す", role: .destructive) { save(nil) }
                }
            }.appSectionCardStyle(accentColor: AppSectionAccent.favorite)
        }
        .appEditorFormStyle()
        .giriNavigationBarStyle()
        .navigationTitle("相手の得票率").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save(Double(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines))) }
                    .fontWeight(.bold)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let value = store.onlineSiteById(siteID)?.tagPartnerRates[seasonKey] { text = String(format: "%g", value) }
        }
    }

    private func save(_ value: Double?) {
        guard var site = store.onlineSiteById(siteID) else { return }
        if let value, !(value.isFinite && value >= 0) { store.errorMessage = "得票率は0以上の数で入れてください。"; return }
        site.tagPartnerRates[seasonKey] = value
        store.run {
            try store.saveOnlineSite(site)
            playLiveStairSaveFeedback()
            dismiss()
        }
    }
}
