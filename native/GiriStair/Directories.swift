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
    var body: some View {
        List {
            Section {
                AppCardSectionTitle(title: "ネット大喜利サイト", systemImage: "globe", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                if store.onlineSites.isEmpty { CenteredEmptyMessage(systemImage: "globe", title: "サイトがありません") }
                ForEach(store.onlineSites) { site in
                    NavigationLink { GiriSiteDetail(siteID: site.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(site.name).font(.headline.weight(.semibold))
                            Text(site.format.title).font(.caption).foregroundStyle(.secondary)
                            let labels = [site.hasAffiliations ? site.affiliation : "", site.block].filter { !$0.isEmpty }
                            if !labels.isEmpty { Text(labels.joined(separator: "・")).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
        }.appIndexListStyle().toolbar(.visible, for: .navigationBar).navigationTitle("ネット大喜利サイト一覧").navigationBarTitleDisplayMode(.inline)
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
    @State private var resultEvent: GiriEvent?
    @State private var timelineStart = Date()

    private var site: OnlineSite? { store.onlineSites.first { $0.id == siteID } }
    private var history: [GiriEvent] {
        store.events.filter { $0.onlineSiteId == siteID && $0.isActualParticipant }
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

    var body: some View {
        Group {
            if let site {
                Form {
                    Section {
                        AppCardSectionTitle(title: "現在の状況", systemImage: "globe", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                        TimelineView(.periodic(from: timelineStart, by: 60)) { context in
                            GiriSitePeriodActions(site: site, now: context.date)
                        }
                    }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
                    siteSection(site)
                    if let settings = site.cycleSettings, settings.trackSeasonTotals, currentSeasonKey != nil {
                        Section {
                            AppCardSectionTitle(title: "シーズンの合計成績", systemImage: "chart.bar", accentColor: AppSectionAccent.ticket).listRowSeparator(.hidden)
                            if !settings.seasonName.isEmpty { Text(settings.seasonName).font(.headline) }
                            seasonTotalsRows(site: site, seasonID: settings.seasonID, seasonName: settings.seasonName)
                        }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
                    }
                    if site.hasAffiliations && !site.leagueChanges.isEmpty {
                        Section {
                            AppCardSectionTitle(title: "シーズン・リーグの履歴", systemImage: "list.number", accentColor: AppSectionAccent.memo).listRowSeparator(.hidden)
                            ForEach(site.leagueChanges.sorted { $0.effectiveFrom > $1.effectiveFrom }) { change in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(change.seasonName.isEmpty ? "リーグ変更" : change.seasonName).font(.subheadline.weight(.semibold))
                                        Spacer(minLength: 8)
                                        Text(change.toLeague).font(.body.weight(.semibold))
                                    }
                                    Text((change.effectiveFrom > Date() ? "反映予定　" : "適用　") + GiriDateText.dateTime(change.effectiveFrom))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
                    }
                    if history.isEmpty {
                        Section { Text("参加した回の履歴がありません").foregroundStyle(.secondary) }
                            .appSectionCardStyle(accentColor: AppSectionAccent.artist)
                    }
                    ForEach(seasonGroups) { group in
                        Section {
                            AppCardSectionTitle(title: group.displayName, systemImage: "clock", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                            if site.cycleSettings?.trackSeasonTotals == true, group.id != currentSeasonKey,
                               group.seasonID != nil || !group.name.isEmpty {
                                seasonTotalsRows(site: site, seasonID: group.seasonID, seasonName: group.name)
                            }
                            ForEach(group.events) { event in
                                Button { navigation.openThoughts(eventID: event.id) } label: { historyRow(event) }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        if event.hasEnded() { Button("結果を記録", systemImage: "square.and.pencil") { resultEvent = event } }
                                    }
                            }
                        }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
                    }
                }.appEditorFormStyle()
            } else { CenteredEmptyMessage(systemImage: "globe", title: "サイトが見つかりません") }
        }
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle(site?.name ?? "サイト").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { if let site { NavigationLink("編集") { GiriSiteEditor(site: site) } } }
            ToolbarItem(placement: .topBarTrailing) {
                Menu { Button("サイトの登録を削除", systemImage: "trash", role: .destructive) { deleting = true } }
                    label: { Image(systemName: "ellipsis") }.accessibilityLabel("サイトの操作")
            }
        }
        .confirmationDialog("サイトを削除しますか？過去の参加記録とメモは残ります。", isPresented: $deleting, titleVisibility: .visible) {
            Button("削除", role: .destructive) { store.run { try store.deleteOnlineSite(siteID); playLiveStairDeleteFeedback(); dismiss() } }
            Button("キャンセル", role: .cancel) {}
        }
        .sheet(item: $resultEvent) { event in NavigationStack { GiriCycleResultEditor(eventID: event.id) } }
    }

    @ViewBuilder private func seasonTotalsRows(site: OnlineSite, seasonID: String?, seasonName: String) -> some View {
        let totals = giriSeasonTotals(siteID: site.id, seasonID: seasonID, seasonName: seasonName, events: store.events, notes: store.notes)
        LabeledContent("提出した回答", value: "\(totals.submittedAnswerCount)回答")
        LabeledContent("得票率の記録済み", value: "\(totals.scoredAnswerCount)回答")
        LabeledContent("平均得票率", value: totals.averageVoteRate.map { $0.formatted(.number.precision(.fractionLength(2))) + "%" } ?? "未記録")
        if totals.legacyRoundResultCount > 0 {
            Text("平均には回単位で残した得票率\(totals.legacyRoundResultCount)件も含みます。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func siteSection(_ site: OnlineSite) -> some View {
        Section {
            AppCardSectionTitle(title: "サイト", systemImage: "slider.horizontal.3", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
            GiriProfileInfoRow(title: "形式", value: site.format.title)
            if let url = giriWebURL(site.url) { Link("サイトを開く", destination: url) }
            if site.hasAffiliations { GiriProfileInfoRow(title: "現在のリーグ", value: siteLeague(site)) }
            if let settings = site.cycleSettings {
                GiriProfileInfoRow(title: "繰り返し", value: settings.pattern.title)
                if !settings.seasonName.isEmpty { GiriProfileInfoRow(title: "シーズン", value: settings.seasonName) }
                if let start = settings.seasonStart { GiriProfileInfoRow(title: "シーズン開始", value: GiriDateText.dateTime(start)) }
                if let end = settings.seasonEndsAt { GiriProfileInfoRow(title: "シーズン終了", value: GiriDateText.dateTime(end)) }
            }
            if !site.block.isEmpty { GiriProfileInfoRow(title: "ブロック", value: site.block) }
            if !site.memo.isEmpty { Text(site.memo).textSelection(.enabled) }
        }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    private func historyRow(_ event: GiriEvent) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(event.siteCycleNumber.map { "第\($0)回" } ?? GiriDateText.day(event.participationStartDate ?? event.eventDate))
                    .font(.headline).foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(event.participationState().title).font(.caption).foregroundStyle(.secondary)
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
            HStack(spacing: 4) {
                Image(systemName: "text.bubble")
                Text("お題・提出した回答・没案")
                Spacer()
                Image(systemName: "chevron.right")
            }.font(.caption).foregroundStyle(AppSectionAccent.memo)
        }.padding(.vertical, 4).contentShape(Rectangle())
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
    private var onSaved: ((OnlineSite) -> Void)?
    init(site: OnlineSite? = nil, onSaved: ((OnlineSite) -> Void)? = nil) {
        let value = site ?? OnlineSite()
        _draft = State(initialValue: value); _original = State(initialValue: value)
        isNew = site == nil; self.onSaved = onSaved
    }
    private var changed: Bool { draft != original }
    var body: some View {
        Form {
            Section {
                AppCardSectionTitle(title: "サイト", systemImage: "globe", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                TextField("サイト名", text: $draft.name)
                TextField("URL", text: $draft.url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("形式", selection: $draft.format) {
                    ForEach(store.preferences.formatChoices(including: draft.format).filter { $0.hasOnlineRounds }) { format in Text(format.title).tag(format) }
                }.pickerStyle(.menu).tint(.primary)
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            if initialized { GiriSiteCycleSettingsForm(site: $draft, isNew: isNew) }
            Section { TextField("メモ", text: $draft.memo, axis: .vertical).lineLimit(3...8) }
                .appSectionCardStyle(accentColor: AppSectionAccent.memo)
        }
        .appEditorFormStyle().toolbar(.visible, for: .navigationBar)
        .navigationTitle(isNew ? "サイトを登録" : "サイトを編集").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(changed)
        .interactiveDismissDisabled(changed)
        .onAppear {
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { if changed { Button { discard = true } label: { Image(systemName: "chevron.left") }.accessibilityLabel("戻る") } }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
        .confirmationDialog("変更を保存せず戻りますか？", isPresented: $discard, titleVisibility: .visible) {
            Button("変更を破棄", role: .destructive) { dismiss() }
        }
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
