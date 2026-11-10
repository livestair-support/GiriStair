import SwiftUI

/// サイトの詳細・編集・結果入力は、下から出すシートではなく、そのタブの中で遷移する。
enum GiriSiteRoute: Hashable, Identifiable {
    case detail(String)
    case editor(String)
    case cycleResult(String)
    /// 0.14：過去に参加した回を追加する（サイトのID）。
    case pastCycle(String)
    /// 0.23：現在の状況（今の状態・締切・次のお題）だけを直す（サイトのID）。
    case status(String)
    var id: String {
        switch self {
        case .detail(let id): return "detail:" + id
        case .editor(let id): return "editor:" + id
        case .cycleResult(let id): return "result:" + id
        case .pastCycle(let id): return "past:" + id
        case .status(let id): return "status:" + id
        }
    }
}

struct GiriSiteRouteView: View {
    @EnvironmentObject private var store: GiriStore
    let route: GiriSiteRoute
    var body: some View {
        switch route {
        case .detail(let id): GiriSiteDetail(siteID: id)
        case .editor(let id):
            if let site = store.onlineSiteById(id) { GiriSiteEditor(site: site) }
            else { CenteredEmptyMessage(systemImage: "globe", title: "サイトが見つかりません") }
        case .cycleResult(let id): GiriCycleResultEditor(eventID: id)
        case .pastCycle(let id): GiriSitePastCycleEditor(siteID: id)
        case .status(let id):
            if let site = store.onlineSiteById(id) { GiriSiteEditor(site: site, statusOnly: true) }
            else { CenteredEmptyMessage(systemImage: "globe", title: "サイトが見つかりません") }
        }
    }
}

/// 0.14：一覧に出ていない、過去に参加した回を追加する。投稿の締切が分かれば作れる。
/// ルールが複雑なサイトでは、違うシーズンの回に「今のシーズンとルールが同じか」も残す。
struct GiriSitePastCycleEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    let siteID: String
    @State private var seasonName = ""
    @State private var cycleNumber: Int?
    @State private var kind: SitePeriodKind = .regular
    @State private var deadline: Date?
    @State private var votingEnd: Date?
    @State private var league = ""
    @State private var sameRules = true
    @State private var initialized = false
    @State private var discard = false
    @State private var initialSeason = ""

    private var site: OnlineSite? { store.onlineSiteById(siteID) }
    private var changed: Bool { deadline != nil || cycleNumber != nil || seasonName != initialSeason || !league.isEmpty }
    private var usesSeasons: Bool { site.map(siteUsesSeasons) ?? false }
    /// 今のシーズンと違うシーズンで、ルールが複雑なサイトの時だけルールを聞く。
    private var asksRules: Bool {
        guard let site, usesSeasons, siteHasComplexRules(site, events: store.events) else { return false }
        let name = seasonName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && playerSearchKey(name) != playerSearchKey(site.cycleSettings?.seasonName ?? "")
    }
    /// 記録済みのシーズン名（新しい順）。
    private var knownSeasons: [String] {
        var names: [String] = []
        if let current = site?.cycleSettings?.seasonName, !current.isEmpty { names.append(current) }
        let past = store.events.filter { $0.onlineSiteId == siteID && !$0.siteSeason.isEmpty }
            .sorted { ($0.participationStartDate ?? $0.createdAt) > ($1.participationStartDate ?? $1.createdAt) }
        for event in past where !names.contains(where: { playerSearchKey($0) == playerSearchKey(event.siteSeason) }) {
            names.append(event.siteSeason)
        }
        return names
    }

    var body: some View {
        Form {
            cycleSection
            if asksRules { rulesSection }
        }
        .appEditorFormStyle()
        .navigationTitle("参加した回を追加").navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
        .navigationBarBackButtonHidden(changed)
        .interactiveDismissDisabled(changed)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if changed { Button { discard = true } label: { Image(systemName: "chevron.left") }.accessibilityLabel("戻る") }
            }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).fontWeight(.bold).disabled(deadline == nil) }
        }
        .giriDiscardChangesAlert(isPresented: $discard) { dismiss() }
        .onAppear(perform: load)
    }

    private var cycleSection: some View {
        Section {
            AppCardSectionTitle(title: "参加した回", systemImage: "clock.arrow.circlepath", accentColor: AppSectionAccent.artist,
                                infoTitle: "参加した回の追加",
                                infoMessage: "一覧に出ていない過去の回を、投稿の締切から追加します。お題・回答と結果はあとから入れられます。")
                .listRowSeparator(.hidden)
            if usesSeasons { seasonRow }
            Picker("日程", selection: $kind) {
                ForEach(SitePeriodKind.allCases) { value in Text(value.title).tag(value) }
            }.pickerStyle(.menu).tint(Color.primary)
            if kind == .regular {
                HStack(spacing: 12) {
                    GiriEditorLabel("回")
                    Spacer(minLength: 8)
                    Text("第").foregroundStyle(.secondary)
                    TextField("任意", value: $cycleNumber, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 72)
                    Text("回").foregroundStyle(.secondary)
                }
            }
            OptionalDateRow(title: "投稿の締切", selection: Binding(get: { deadline }, set: { value in
                deadline = value
                if let value, let site { votingEnd = addCalendarDays(value, site.votingDays) }
            }))
            OptionalDateRow(title: "投票の締切", selection: $votingEnd)
            if site?.hasAffiliations == true {
                HStack(spacing: 12) {
                    GiriEditorLabel("リーグ")
                    TextField("その回のリーグ", text: $league).multilineTextAlignment(.trailing)
                }
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    private var seasonRow: some View {
        HStack(spacing: 12) {
            GiriEditorLabel("シーズン")
            TextField("シーズン名", text: $seasonName).multilineTextAlignment(.trailing)
            if knownSeasons.count > 1 {
                Menu {
                    ForEach(knownSeasons, id: \.self) { name in Button(name) { seasonName = name } }
                } label: {
                    Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .accessibilityLabel("記録済みのシーズンから選ぶ")
            }
        }
    }

    private var rulesSection: some View {
        Section {
            AppCardSectionTitle(title: "ルール", systemImage: "list.bullet.rectangle", accentColor: AppSectionAccent.memo)
                .listRowSeparator(.hidden)
            Picker("今のシーズンと", selection: $sameRules) {
                Text("同じ").tag(true)
                Text("違う").tag(false)
            }.pickerStyle(.menu).tint(Color.primary)
        }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
    }

    private func load() {
        guard !initialized, let site else { return }
        initialized = true
        seasonName = site.cycleSettings?.seasonName ?? ""
        initialSeason = seasonName
    }

    private func save() {
        guard let deadline else { return }
        var input = SitePastCycleInput(deadline: deadline)
        input.seasonName = seasonName
        input.cycleNumber = kind == .regular ? cycleNumber : nil
        input.kind = kind
        input.votingEnd = votingEnd
        input.league = league
        input.sameRulesAsCurrent = asksRules ? sameRules : true
        store.run {
            try store.addPastSiteCycle(siteID, input: input)
            playLiveStairSaveFeedback()
            dismiss()
        }
    }
}

/// Site status has one card boundary and one disclosure. Posting and voting
/// can refer to different cycles, so neither is reduced to an ambiguous week.
struct GiriSiteStatusCard: View {
    @EnvironmentObject private var navigation: GiriNavigation
    let site: OnlineSite
    let now: Date
    /// 一覧のタブで詳細などへ遷移する（一覧側の NavigationStack に積む）。
    var onRoute: ((GiriSiteRoute) -> Void)? = nil
    @State private var showingSite = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { if let onRoute { onRoute(.detail(site.id)) } else { showingSite = true } } label: {
                HStack(spacing: 9) {
                    Image(systemName: "globe").foregroundStyle(AppSectionAccent.artist)
                    Text(site.name).font(.headline).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            let league = siteLeague(site)
            if site.hasAffiliations && !league.isEmpty {
                Text(league).font(.subheadline).foregroundStyle(.secondary)
            }
            GiriSitePeriodActions(site: site, now: now, onRoute: onRoute)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appTintedCard(accentColor: AppSectionAccent.artist)
        .sheet(isPresented: $showingSite) {
            NavigationStack {
                GiriSiteDetail(siteID: site.id)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { showingSite = false } } }
            }
        }
        .onChange(of: navigation.selectedTab) { _, tab in if tab == 3 { showingSite = false } }
    }
}

private struct SiteVisibleCycle: Identifiable {
    let descriptor: SiteCycleDescriptor?
    let event: GiriEvent?
    let round: EventRound
    let title: String
    var id: String { (event?.id ?? descriptor?.cycleKey ?? "site") + ":" + round.id }
}

/// The same status/action rows are used by the index card and site detail.
/// 投稿中の回は「参加する／今回は見送る」、投票中は参加した回だけ、終わった回は結果。
/// 締切が決まっていないサイトとシーズンの終わりは、次の締切を1つ入れるだけで進める。
struct GiriSitePeriodActions: View {
    @EnvironmentObject private var store: GiriStore
    @EnvironmentObject private var navigation: GiriNavigation
    let site: OnlineSite
    let now: Date
    /// 日程の設定・結果の入力をタブの中で開く。ない時は従来どおりシートで開く。
    var onRoute: ((GiriSiteRoute) -> Void)? = nil
    @State private var showingSetup = false
    @State private var resultEvent: GiriEvent?
    @State private var deadlineRequest: GiriSiteDeadlineRequest?
    /// 運営の都合で休みにする回（確認を出す）。
    @State private var breakCycle: SiteVisibleCycle?
    /// 次のシーズンでルールが変わる時、締切の保存のあとに日程・ルールの設定を開く。
    @State private var setupAfterDeadline = false

    var body: some View {
        // The page owns its clock. A List cell must not create a second
        // TimelineView while it is being inserted by the format picker.
        periodRows(now: now)
        .confirmationDialog(breakDialogTitle, isPresented: breakDialogShown, titleVisibility: .visible, presenting: breakCycle) { cycle in
            Button("休みにする") { markBreak(cycle) }
            Button("キャンセル", role: .cancel) {}
        } message: { _ in
            Text("この回は作らず、次の回から番号を1つずつ詰めます。あとで取り消せます。")
        }
        .sheet(isPresented: $showingSetup) { NavigationStack { GiriSiteEditor(site: site) } }
        .sheet(item: $resultEvent) { event in NavigationStack { GiriCycleResultEditor(eventID: event.id) } }
        .sheet(item: $deadlineRequest, onDismiss: {
            guard setupAfterDeadline else { return }
            setupAfterDeadline = false
            openSetup()
        }) { request in
            NavigationStack {
                GiriSiteDeadlineSheet(site: site, request: request) { setupAfterDeadline = true }
            }
        }
    }

    private func cycles(now: Date) -> [SiteVisibleCycle] {
        let events = store.events.filter { $0.onlineSiteId == site.id }
        let descriptors = site.cycleSettings == nil ? [] : siteCycleDescriptors(site, around: now)
        var values = descriptors.map { descriptor -> SiteVisibleCycle in
            let event = events.first { $0.cycleKey == descriptor.cycleKey }
            let round = event?.isActualParticipant == true ? event?.effectiveRounds.first ?? descriptor.round : descriptor.round
            return SiteVisibleCycle(descriptor: descriptor, event: event, round: round, title: cycleTitle(descriptor: descriptor))
        }
        for event in events where event.isActualParticipant {
            for round in event.effectiveRounds where !values.contains(where: { $0.event?.id == event.id && $0.round.id == round.id }) {
                let title = [event.siteCycleNumber.map { "第\($0)回" } ?? "", event.sitePeriodKind == .regular ? "" : event.sitePeriodKind.title]
                    .filter { !$0.isEmpty }.joined(separator: "・")
                values.append(SiteVisibleCycle(descriptor: nil, event: event, round: round, title: title.isEmpty ? event.title : title))
            }
        }
        return values.sorted { ($0.round.submissionStart ?? $0.round.votingStart ?? .distantPast) > ($1.round.submissionStart ?? $1.round.votingStart ?? .distantPast) }
    }

    /// 「第3回（全8回）」・特別週は名前。
    private func cycleTitle(descriptor: SiteCycleDescriptor) -> String {
        guard descriptor.kind == .regular, let number = descriptor.cycleNumber else { return descriptor.title }
        if let last = site.cycleSettings?.regularCycleCount, site.recurrence == .weekly { return "第\(number)回（全\(last)回）" }
        return "第\(number)回"
    }

    @ViewBuilder private func periodRows(now: Date) -> some View {
        let values = cycles(now: now)
        let posting = values.filter { $0.round.isSubmissionOpen(now) }
        // 投票中は、参加した回だけ（見送った回・決めていない回の投票は出さない）。
        let voting = values.filter { $0.round.isVotingOpen(now) && $0.event?.isActualParticipant == true }
        let seasonEnded = seasonFinished(now: now, values: values)
        VStack(alignment: .leading, spacing: 10) {
            if let seasonLabel = currentSeasonLabel { Text(seasonLabel).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            ForEach(posting) { cycle in postingRow(cycle) }
            if posting.isEmpty, let pause = siteCurrentBreak(site, now: now) { breakRow(pause) }
            ForEach(voting) { cycle in votingRow(cycle) }
            if posting.isEmpty && voting.isEmpty && !seasonEnded {
                if site.cycleSettings == nil {
                    Text("投稿・投票の日程を設定してください").font(.subheadline).foregroundStyle(.secondary)
                    Button("日程を設定", systemImage: "calendar.badge.clock") { openSetup() }
                        .font(.subheadline.weight(.semibold)).buttonStyle(.borderless).tint(accentActionColor)
                } else if site.cycleSettings?.waitingForNext == true {
                    Text("次のお題を待っています").font(.subheadline).foregroundStyle(.secondary)
                } else if let next = values.filter({ ($0.round.submissionStart ?? .distantPast) > now }).min(by: { ($0.round.submissionStart ?? .distantFuture) < ($1.round.submissionStart ?? .distantFuture) }), let date = next.round.submissionStart {
                    Text("次のお題　" + GiriDateText.dateTime(date) + " から").font(.subheadline).foregroundStyle(.secondary)
                } else if let date = site.cycleSettings?.notBefore, date > now {
                    Text("次のお題　" + GiriDateText.dateTime(date) + " から").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("今は投稿・投票の期間外です").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if site.recurrence == .irregular && posting.isEmpty {
                actionButton("次の回の締切を入れる", systemImage: "calendar.badge.plus") { deadlineRequest = .nextCycle }
            } else if site.cycleSettings?.waitingForNext == true && posting.isEmpty && !seasonEnded {
                // シーズンの合間など：次のお題が分かったら締切を入れて再開する。
                HStack(spacing: 16) {
                    actionButton("次のお題の締切を入れる", systemImage: "calendar.badge.plus") { deadlineRequest = .resume }
                    if usesSeasons { actionButton("次のシーズンを始める", systemImage: "arrow.right.circle") { deadlineRequest = .nextSeason } }
                }
            }
            if seasonEnded {
                Text((site.cycleSettings?.seasonName.isEmpty == false ? site.cycleSettings?.seasonName ?? "" : "シーズン") + "の通常回が終わりました")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    actionButton("次のシーズンを始める", systemImage: "arrow.right.circle") { deadlineRequest = .nextSeason }
                    actionButton("特別週を追加", systemImage: "plus.circle") { openSetup() }
                }
            }
            if let pending = pendingResult(now: now) {
                Divider().overlay(appSeparatorColor)
                Button { if let onRoute { onRoute(.cycleResult(pending.id)) } else { resultEvent = pending } } label: {
                    HStack {
                        Image(systemName: "square.and.pencil")
                        Text("終わった回の結果を記録")
                        Spacer(minLength: 8)
                        if let number = pending.siteCycleNumber { Text("第\(number)回").foregroundStyle(.secondary) }
                    }.font(.subheadline)
                }.buttonStyle(.plain).tint(accentActionColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var usesSeasons: Bool {
        guard let settings = site.cycleSettings else { return false }
        return settings.seasonID != nil || !settings.seasonName.isEmpty || settings.trackSeasonTotals
    }

    private var currentSeasonLabel: String? {
        guard let settings = site.cycleSettings, !settings.seasonName.isEmpty else { return nil }
        let league = site.hasAffiliations ? siteLeague(site) : ""
        return [settings.seasonName, league].filter { !$0.isEmpty }.joined(separator: "・")
    }

    /// シーズンの最後の通常回の投票が終わり、まだ次の回が来ていない。
    private func seasonFinished(now: Date, values: [SiteVisibleCycle]) -> Bool {
        guard let end = siteSeasonLastCycleEnd(site), end <= now else { return false }
        return !values.contains { ($0.round.submissionStart ?? .distantPast) > now || $0.round.isSubmissionOpen(now) }
    }

    private func pendingResult(now: Date) -> GiriEvent? {
        store.events.filter { $0.onlineSiteId == site.id && $0.isActualParticipant && $0.hasEnded(now: now) && !$0.hasCycleResult && !$0.promptedResultKeys.contains("cycle-result-skipped") }
            .max { ($0.participationEndDate ?? .distantPast) < ($1.participationEndDate ?? .distantPast) }
    }

    private func openSetup() {
        if let onRoute { onRoute(.editor(site.id)) } else { showingSetup = true }
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderless)
        .tint(accentActionColor)
    }

    private func postingRow(_ cycle: SiteVisibleCycle) -> some View {
        let joined = cycle.event?.isActualParticipant == true
        let skipped = cycle.event?.siteSkipped == true
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("投稿中", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(skipped ? Color.secondary : accentActionColor)
                Spacer(minLength: 8)
                if !cycle.title.isEmpty { Text(cycle.title).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
                if canBreak(cycle) {
                    Menu {
                        Button("運営の都合で休み", systemImage: "moon.zzz") { breakCycle = cycle }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.subheadline).foregroundStyle(.secondary)
                            .frame(width: 26, height: 22).contentShape(Rectangle())
                    }
                    .accessibilityLabel("この回のその他")
                }
            }
            Text("締切 " + GiriDateText.dateTime(cycle.round.submissionEnd)).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                if joined {
                    actionButton("回答を考える", systemImage: "text.bubble") { open(cycle, join: true) }
                    actionButton("今回は投稿しない", systemImage: "forward") { skip(cycle) }
                } else if skipped {
                    Text("見送り").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    actionButton("やっぱり参加する", systemImage: "arrow.uturn.backward") { open(cycle, join: true) }
                } else {
                    actionButton("参加する", systemImage: "person.badge.plus") { open(cycle, join: true) }
                    actionButton("今回は見送る", systemImage: "forward") { skip(cycle) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 運営の都合で休みの回：投稿期間のあいだ、カードに出して取り消せるようにする。
    private func breakRow(_ round: EventRound) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("今回はお休み", systemImage: "moon.zzz")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("運営の都合で休み（次の回から番号を詰めています）").font(.caption).foregroundStyle(.secondary)
            if let start = round.submissionStart {
                actionButton("休みを取り消す", systemImage: "arrow.uturn.backward") { unmarkBreak(start) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 決まった間隔で出る通常の回だけ、休みにできる。
    private func canBreak(_ cycle: SiteVisibleCycle) -> Bool {
        guard site.recurrence == .weekly, let descriptor = cycle.descriptor else { return false }
        return descriptor.kind == .regular && !descriptor.cycleKey.hasPrefix("special:") && descriptor.round.submissionStart != nil
    }

    private var breakDialogTitle: String {
        guard let cycle = breakCycle else { return "運営の都合で休みにしますか？" }
        return (cycle.descriptor?.cycleNumber.map { "第\($0)回を" } ?? "この回を") + "運営の都合で休みにしますか？"
    }

    private var breakDialogShown: Binding<Bool> {
        Binding(get: { breakCycle != nil }, set: { if !$0 { breakCycle = nil } })
    }

    private func markBreak(_ cycle: SiteVisibleCycle) {
        guard let start = cycle.descriptor?.round.submissionStart else { return }
        store.run {
            try store.setSiteCycleBreak(site.id, start: start, isBreak: true)
            playLiveStairSaveFeedback()
        }
        breakCycle = nil
    }

    private func unmarkBreak(_ start: Date) {
        store.run {
            try store.setSiteCycleBreak(site.id, start: start, isBreak: false)
            playLiveStairSaveFeedback()
        }
    }

    private func votingRow(_ cycle: SiteVisibleCycle) -> some View {
        Button { open(cycle, join: false) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label("投票中", systemImage: "checkmark.bubble")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppSectionAccent.artist)
                    Spacer(minLength: 8)
                    if !cycle.title.isEmpty { Text(cycle.title).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("結果発表 " + GiriDateText.dateTime(cycle.round.votingEnd)).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text("お題・回答を開く").font(.caption.weight(.semibold)).foregroundStyle(accentActionColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func skip(_ cycle: SiteVisibleCycle) {
        store.run {
            try store.setSiteCycleSkipped(site.id, descriptor: cycle.descriptor, event: cycle.event, skipped: true)
            playLiveStairSaveFeedback()
        }
    }

    private func open(_ cycle: SiteVisibleCycle, join: Bool) {
        store.run {
            let event: GiriEvent
            if let descriptor = cycle.descriptor {
                event = try store.createSiteCycle(site.id, descriptor: descriptor, join: join || cycle.event?.isActualParticipant == true)
            } else if var existing = cycle.event {
                if join && !existing.isActualParticipant {
                    existing.isParticipating = true; existing.isInterested = false; existing.siteSkipped = false; existing.status = .planned
                    try store.saveEvent(existing)
                }
                event = existing
            } else { return }
            guard let round = event.effectiveRounds.first(where: { $0.id == cycle.round.id }) ?? event.effectiveRounds.first else { return }
            navigation.openThoughts(eventID: event.id, roundID: round.id)
        }
    }
}

/// 一覧のカードから入れる日付の種類。
enum GiriSiteDeadlineRequest: String, Identifiable {
    /// resume：次のお題を待っている間（シーズンの合間など）から再開する。
    case nextCycle, nextSeason, resume
    var id: String { rawValue }
}

/// 次の回（締切が決まっていないサイト）や次のシーズンの最初の回を、投稿締切1つで追加する。
struct GiriSiteDeadlineSheet: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    let site: OnlineSite
    let request: GiriSiteDeadlineRequest
    /// 次のシーズンでルールが変わる時（保存のあとに設定を開く）。
    var onRulesChange: (() -> Void)? = nil
    @State private var deadline: Date? = nil
    @State private var votingEnd: Date? = nil
    @State private var cycleNumber = 1
    @State private var rulesChange = false
    /// 0.23：次のシーズンのルール（nil は前のシーズンと同じ）。
    @State private var seasonRuleID: String?
    @State private var creatingRule: GiriRule?

    /// シーズン明けのルール変更は、ルールが複雑なサイトだけ聞く。
    private var asksRules: Bool { request == .nextSeason && siteHasComplexRules(site, events: store.events) }

    private var pageTitle: String {
        switch request {
        case .nextSeason: return "次のシーズン"
        case .resume: return "次のお題"
        case .nextCycle: return "次の回"
        }
    }

    private var sectionTitle: String {
        switch request {
        case .nextSeason: return "第\(nextSeasonNumber)シーズン"
        case .resume: return "次のお題"
        case .nextCycle: return "次の回"
        }
    }

    var body: some View {
        Form {
            Section {
                AppCardSectionTitle(title: sectionTitle, systemImage: "calendar.badge.plus", accentColor: AppSectionAccent.artist,
                                    infoTitle: "締切について",
                                    infoMessage: "サイトに書いてある投稿の締切を入れます。投票の締切は投票期間から自動で入ります。")
                    .listRowSeparator(.hidden)
                OptionalDateRow(title: request == .nextSeason ? "最初の回の投稿締切" : "投稿の締切", selection: Binding(get: { deadline }, set: { value in
                    deadline = value
                    if let value { votingEnd = addCalendarDays(value, site.votingDays) }
                }))
                if request == .nextCycle {
                    OptionalDateRow(title: "投票の締切", selection: $votingEnd)
                }
                if request == .resume {
                    Stepper(value: $cycleNumber, in: 1...max(9999, cycleNumber)) {
                        HStack {
                            GiriEditorLabel("回")
                            Spacer()
                            Text("第\(cycleNumber)回").font(.body.weight(.semibold))
                        }
                    }
                }
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            if request == .nextSeason {
                // 0.23：シーズンごとのルール。同じ・別のルール・新しく作るから選ぶ。
                Section {
                    AppCardSectionTitle(title: "このシーズンのルール", systemImage: "list.bullet.rectangle", accentColor: AppSectionAccent.memo,
                                        infoTitle: "ルールについて",
                                        infoMessage: "選んだルールの日程・リーグ・1シーズンの回数を入れ、プレーオフ・入れ替え戦の日程も作ります。")
                        .listRowSeparator(.hidden)
                    HStack(spacing: 8) {
                        GiriEditorLabel("ルール")
                        Spacer(minLength: 8)
                        GiriRuleMenuPicker(kind: .online, selectedID: seasonRuleID ?? site.currentRuleID,
                                           noneTitle: site.currentRuleID == nil ? "選ばない" : "前のシーズンと同じ",
                                           onSelect: { seasonRuleID = $0 },
                                           onCreate: {
                                               var rule = site.currentRuleID.flatMap { store.rule($0) } ?? giriRule(from: site)
                                               rule.id = UUID().uuidString
                                               rule.name = [site.name, "第\(nextSeasonNumber)シーズン"].joined(separator: " ")
                                               creatingRule = rule
                                           })
                    }
                }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
            }
            if asksRules && store.rules.filter({ $0.kind == .online }).isEmpty {
                Section {
                    AppCardSectionTitle(title: "ルール", systemImage: "list.bullet.rectangle", accentColor: AppSectionAccent.memo,
                                        infoTitle: "ルールの変更",
                                        infoMessage: "変更がある時は、保存のあとに日程・リーグの設定を開きます。")
                        .listRowSeparator(.hidden)
                    Picker("前のシーズンから", selection: $rulesChange) {
                        Text("変更なし").tag(false)
                        Text("変更あり").tag(true)
                    }.pickerStyle(.menu).tint(Color.primary)
                }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
            }
        }
        .appEditorFormStyle()
        .sheet(item: $creatingRule) { rule in
            NavigationStack { GiriRuleEditor(rule: rule, isNew: true) { saved in seasonRuleID = saved.id } }
        }
        .navigationTitle(pageTitle).navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).fontWeight(.bold).disabled(deadline == nil) }
        }
        .onAppear {
            guard deadline == nil else { return }
            cycleNumber = siteSuggestedResumeCycleNumber(site, events: store.events)
            let start = fiveMinuteSelection(Date())
            deadline = addCalendarDays(start, site.submissionDays)
            votingEnd = deadline.map { addCalendarDays($0, site.votingDays) }
        }
    }

    private var nextSeasonNumber: Int { siteNextSeasonNumber(site.cycleSettings ?? SiteCycleSettings()) }

    private func save() {
        guard let deadline else { return }
        store.run {
            if request == .nextSeason {
                try store.startNextSiteSeason(site.id, firstDeadline: deadline, ruleID: seasonRuleID)
            } else if request == .resume {
                try store.resumeSiteCycle(site.id, firstDeadline: deadline, cycleNumber: cycleNumber)
            } else {
                if let votingEnd, votingEnd < deadline { throw GiriEditorValidationError.schedule("投票の締切を投稿の締切より後にしてください。") }
                try store.addSiteIrregularCycle(site.id, deadline: deadline, votingEnd: votingEnd)
            }
            try store.ensureCurrentSiteCycles()
            playLiveStairSaveFeedback()
            if asksRules && rulesChange && store.rules.filter({ $0.kind == .online }).isEmpty { onRulesChange?() }
            dismiss()
        }
    }
}

private enum SiteSetupPhase: String, CaseIterable, Identifiable {
    /// waiting：投稿中でも投票中でもない（シーズンの合間など）。
    case posting, voting, waiting
    var id: String { rawValue }
    var title: String {
        switch self {
        case .posting: return "投稿中"
        case .voting: return "投票中"
        case .waiting: return "次のお題待ち"
        }
    }
}

/// 登録と設定で共通の、通常サイトのかんたん設定。必要なのは「今の状態と締切」と
/// 「次のお題の出方」だけで、次の回からは自動で進める。リーグとシーズンは使うサイトだけ。
struct GiriSiteCycleSettingsForm: View {
    @EnvironmentObject private var store: GiriStore
    @Binding var site: OnlineSite
    var isNew = false
    /// 0.23：サイト詳細の「現在の状況」の編集では、投稿・投票（今の状態・締切・次のお題）だけを出す。
    var statusOnly = false
    @State private var initialized = false
    @State private var timing: SiteNextPromptTiming = .withVoting
    @State private var phase: SiteSetupPhase = .posting
    @State private var deadline: Date = fiveMinuteSelection(Date())
    @State private var intervalDays = 7
    @State private var currentCycle = 1
    @State private var seasons = false
    @State private var specialExpanded = false
    @State private var editingSpecial: SiteSpecialPeriod?
    @State private var initialPeriodID = UUID().uuidString
    /// 次のお題待ち：分かっていれば次のお題の開始。
    @State private var nextStart: Date?
    /// 次のお題待ちにした時、前の決まりで作る回をここまでにする（今の回より前）。
    @State private var waitingCutoff = Date()
    /// 0.23：今のサイトの設定から作るルール（シートで開く）。
    @State private var creatingRule: GiriRule?

    private var settings: Binding<SiteCycleSettings> {
        Binding(get: { site.cycleSettings ?? SiteCycleSettings() }, set: { site.cycleSettings = $0 })
    }

    var body: some View {
        Group {
            if !statusOnly { ruleSection }
            scheduleSection
            if !statusOnly {
                leagueSection
                seasonSection
                specialSection
            }
        }
        .onAppear(perform: initialize)
        .sheet(item: $creatingRule) { rule in
            NavigationStack { GiriRuleEditor(rule: rule, isNew: true) { saved in selectRule(saved.id, saved: saved) } }
        }
        .sheet(item: $editingSpecial) { period in
            NavigationStack {
                GiriSiteSpecialPeriodEditor(period: period) { saved in
                    var value = settings.wrappedValue
                    if let index = value.specialPeriods.firstIndex(where: { $0.id == saved.id }) { value.specialPeriods[index] = saved }
                    else { value.specialPeriods.append(saved) }
                    settings.wrappedValue = value
                }
            }
        }
    }

    /// 0.23：シーズンごとのルール。選ぶと日程・リーグ・回数・プレーオフをルールに合わせる。
    private var ruleSection: some View {
        Section {
            AppCardSectionTitle(title: "ルール", systemImage: "list.bullet.rectangle", accentColor: AppSectionAccent.memo,
                                infoTitle: "ルールについて",
                                infoMessage: "保存したルールを選ぶと、日程・リーグ・1シーズンの回数・プレーオフなどをまとめて入れます。シーズンごとに選べます。")
                .listRowSeparator(.hidden)
            HStack(spacing: 8) {
                GiriEditorLabel(seasons ? "今のシーズンのルール" : "ルール")
                Spacer(minLength: 8)
                GiriRuleMenuPicker(kind: .online, selectedID: site.currentRuleID,
                                   onSelect: { selectRule($0) },
                                   onCreate: { creatingRule = giriRule(from: site) })
            }
            if let rule = site.currentRuleID.flatMap({ store.rule($0) }) {
                Text(rule.summary).font(.caption).foregroundStyle(.secondary)
            } else {
                Button("今の設定からルールを作る", systemImage: "square.and.arrow.down") { creatingRule = giriRule(from: site) }
                    .buttonStyle(.borderless).tint(accentActionColor)
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
    }

    private func selectRule(_ id: String?, saved: GiriRule? = nil) {
        if let id, let rule = saved ?? store.rule(id) {
            // 今の状態と締切（サイトに書いてある値）はそのままにして、日数・出方・回数・リーグをルールに合わせる。
            let kept = (phase: phase, deadline: deadline, nextStart: nextStart, cycle: currentCycle)
            giriApplyRule(rule, to: &site)
            initialized = false
            initialize()
            phase = kept.phase; deadline = kept.deadline; nextStart = kept.nextStart; currentCycle = kept.cycle
            timing = rule.timing
            if rule.timing == .interval { intervalDays = rule.intervalDays }
            updateSchedule()
            // 締切から数え直した最後の回に合わせて、プレーオフなどの日程を作り直す。
            let planned = giriRulePlanPeriods(rule, site: site)
            site.cycleSettings?.specialPeriods = planned
        } else {
            site.seasonRuleIDs.removeValue(forKey: giriSeasonRuleKey(site.cycleSettings?.seasonID))
        }
    }

    private var scheduleSection: some View {
        Section {
            AppCardSectionTitle(title: "投稿・投票", systemImage: "arrow.triangle.2.circlepath", accentColor: AppSectionAccent.artist,
                                infoTitle: "投稿・投票について",
                                infoMessage: "投稿締切＝投票開始、投票締切＝結果発表として扱い、次の回からは自動で進めます。")
                .listRowSeparator(.hidden)
            if editsCurrentDeadline {
                Picker(selection: Binding(get: { phase }, set: changePhase)) {
                    ForEach(SiteSetupPhase.allCases) { Text($0.title).tag($0) }
                } label: { GiriEditorLabel("今の状態") }
                .pickerStyle(.menu).tint(.primary)
                if phase == .waiting {
                    OptionalDateRow(title: "次のお題の開始",
                                    selection: Binding(get: { nextStart }, set: { nextStart = $0; updateSchedule() }))
                } else {
                    OptionalDateRow(title: phase == .posting ? "投稿の締切" : "投票の締切",
                                    selection: Binding(get: { deadline }, set: { if let date = $0 { deadline = date; updateSchedule() } }))
                }
            }
            Picker(selection: Binding(get: { timing }, set: { timing = $0; updateSchedule() })) {
                ForEach(SiteNextPromptTiming.allCases) { Text($0.title).tag($0) }
            } label: { GiriEditorLabel("次のお題") }
            .pickerStyle(.menu).tint(.primary)
            Stepper("投稿期間　\(site.submissionDays)日", value: Binding(get: { site.submissionDays }, set: { site.submissionDays = $0; updateSchedule() }), in: 1...365)
            Stepper("投票期間　\(site.votingDays)日", value: Binding(get: { site.votingDays }, set: { site.votingDays = $0; updateSchedule() }), in: 1...365)
            if timing == .interval {
                Stepper("お題の間隔　\(intervalDays)日", value: Binding(get: { intervalDays }, set: { intervalDays = $0; updateSchedule() }), in: 1...365)
            }
            Text(summaryText).font(.caption).foregroundStyle(.secondary)
        }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    /// 締切が決まっていないサイトは、最初の1回だけここで入れる（次からは一覧のカードから）。
    private var editsCurrentDeadline: Bool {
        let periods = settings.wrappedValue.specialPeriods
        return timing != .irregular || isNew || periods.isEmpty || periods.contains { $0.id == initialPeriodID }
    }

    private var summaryText: String {
        if phase == .waiting && editsCurrentDeadline {
            if let nextStart { return "次のお題 " + GiriDateText.dateTime(nextStart) + " から、次の回からは自動で進めます。" }
            return "次のお題が分かったら、一覧のカードから締切を入れます。"
        }
        if timing == .irregular {
            return "締切が過ぎたら、一覧のカードから次の回の締切を入れます。"
        }
        let value = settings.wrappedValue
        var round = EventRound()
        round.submissionStart = value.anchorStart
        round = completeRoundSchedule(round, submissionDays: site.submissionDays, votingDays: site.votingDays)
        let next = addCalendarDays(value.anchorStart, value.intervalDays)
        return "この回の結果発表 " + GiriDateText.dateTime(round.votingEnd) + "・次のお題 " + GiriDateText.dateTime(next) + " から"
    }

    private var leagueSection: some View {
        Section {
            AppCardSectionTitle(title: "リーグ・ブロック", systemImage: "list.number", accentColor: AppSectionAccent.memo,
                                infoTitle: "リーグについて",
                                infoMessage: "1部・2部のように所属が変わるサイトで使います。結果を記録する時に昇格・降格を選びます。")
                .listRowSeparator(.hidden)
            Toggle("リーグがある", isOn: $site.hasAffiliations).tint(AppSectionAccent.memo)
            if site.hasAffiliations {
                ForEach(Array(settings.wrappedValue.leagues.indices), id: \.self) { index in
                    HStack(spacing: 8) {
                        Text("\(index + 1)").font(.caption).foregroundStyle(.secondary).frame(width: 18)
                        TextField("上位からリーグ名", text: leagueName(index))
                        if index > 0 {
                            Button { moveLeague(index, by: -1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.borderless).accessibilityLabel("上位へ")
                        }
                        if index + 1 < settings.wrappedValue.leagues.count {
                            Button { moveLeague(index, by: 1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.borderless).accessibilityLabel("下位へ")
                        }
                        Button(role: .destructive) { var value = settings.wrappedValue; value.leagues.remove(at: index); settings.wrappedValue = value } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                Button("リーグ名を追加", systemImage: "plus.circle") { var value = settings.wrappedValue; value.leagues.append(""); settings.wrappedValue = value }.buttonStyle(.borderless)
                Picker(selection: $site.affiliation) {
                    Text("未設定").tag("")
                    ForEach(Array(settings.wrappedValue.leagues.enumerated()), id: \.offset) { _, name in
                        if !name.isEmpty { Text(name).tag(name) }
                    }
                    if !site.affiliation.isEmpty && !settings.wrappedValue.leagues.contains(site.affiliation) { Text(site.affiliation).tag(site.affiliation) }
                } label: { GiriEditorLabel("今のリーグ") }
                .pickerStyle(.menu).tint(.primary)
                if seasons {
                    Picker(selection: settings.leagueChangesPerSeason) {
                        Text("毎回").tag(false)
                        Text("シーズンごと").tag(true)
                    } label: { GiriEditorLabel("入れ替え") }
                    .pickerStyle(.menu).tint(.primary)
                }
            }
            HStack(spacing: 12) {
                GiriEditorLabel("ブロック")
                TextField("任意", text: $site.block).multilineTextAlignment(.trailing)
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
    }

    private var seasonSection: some View {
        Section {
            AppCardSectionTitle(title: "シーズン", systemImage: "flag.checkered", accentColor: AppSectionAccent.artist,
                                infoTitle: "シーズンについて",
                                infoMessage: "○回で1シーズンのサイトで使います。最後の回が終わると、一覧のカードから次のシーズンを始められます。")
                .listRowSeparator(.hidden)
            Toggle("シーズンがある", isOn: Binding(get: { seasons }, set: changeSeason))
                .tint(AppSectionAccent.artist)
            if seasons {
                Stepper(value: Binding(get: { settings.wrappedValue.seasonNumber ?? 1 }, set: { number in
                    var value = settings.wrappedValue
                    value.seasonNumber = number
                    value.seasonName = "第\(number)シーズン"
                    settings.wrappedValue = value
                }), in: 1...9999) {
                    HStack {
                        GiriEditorLabel("今のシーズン")
                        Spacer()
                        Text("第\(settings.wrappedValue.seasonNumber ?? 1)シーズン").font(.body.weight(.semibold))
                    }
                }
                if timing != .irregular {
                    Stepper(value: Binding(get: { currentCycle }, set: { currentCycle = $0; updateSchedule() }), in: 1...max(9999, currentCycle)) {
                        HStack {
                            GiriEditorLabel(phase == .waiting ? "次のお題" : "今のお題")
                            Spacer()
                            Text("第\(currentCycle)回").font(.body.weight(.semibold))
                        }
                    }
                    Toggle("1シーズンの回数が決まっている", isOn: Binding(get: { settings.wrappedValue.regularCycleCount != nil }, set: { enabled in
                        var value = settings.wrappedValue
                        value.regularCycleCount = enabled ? max(currentCycle, 8) : nil
                        settings.wrappedValue = value
                    }))
                    .tint(AppSectionAccent.artist)
                    if let last = settings.wrappedValue.regularCycleCount {
                        Stepper(value: Binding(get: { last }, set: { var value = settings.wrappedValue; value.regularCycleCount = $0; settings.wrappedValue = value }), in: currentCycle...max(9999, currentCycle)) {
                            HStack {
                                GiriEditorLabel("1シーズン")
                                Spacer()
                                Text("全\(last)回").font(.body.weight(.semibold))
                            }
                        }
                    }
                }
                Toggle("シーズンの合計成績を記録", isOn: settings.trackSeasonTotals)
                    .tint(AppSectionAccent.artist)
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    private var specialSection: some View {
        Section {
            DisclosureGroup(timing == .irregular ? "回の日程" : "特別週（プレーオフ・入れ替え戦など）", isExpanded: $specialExpanded) {
                ForEach(settings.wrappedValue.specialPeriods) { period in
                    Button { editingSpecial = period } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(period.title.isEmpty ? period.kind.title : period.title).foregroundStyle(.primary)
                            Text(GiriDateText.dateTime(period.round.submissionStart) + " 〜 " + GiriDateText.dateTime(period.round.votingEnd))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain)
                    .swipeActions { Button("削除", role: .destructive) { var value = settings.wrappedValue; value.specialPeriods.removeAll { $0.id == period.id }; settings.wrappedValue = value } }
                }
                Button(timing == .irregular ? "回を追加" : "特別週を追加", systemImage: "plus.circle") { addPeriod() }
                    .buttonStyle(.borderless)
                Text(timing == .irregular ? "回ごとに投稿・投票の日時を保存します。" : "通常の回と別の日程（プレーオフ・入れ替え戦・エキシビション・短い最終回）を1件ずつ追加します。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    private func addPeriod() {
        var period = SiteSpecialPeriod()
        if timing == .irregular {
            period = siteIrregularPeriod(site, deadline: addCalendarDays(fiveMinuteSelection(Date()), site.submissionDays))
        } else {
            period.kind = .exhibition
            period.title = "特別週"
            period.seasonName = settings.wrappedValue.seasonName
            period.round.name = period.title
            period.round.promptNumber = currentCycle
        }
        editingSpecial = period
    }

    private func initialize() {
        guard !initialized else { return }
        initialized = true
        if site.cycleSettings == nil {
            var value = SiteCycleSettings()
            value.pattern = .overlapping
            value.anchorStart = fiveMinuteSelection(Date())
            value.intervalDays = site.submissionDays
            site.cycleSettings = value
            if isNew { site.recurrence = .weekly }
        }
        if let cap = settings.wrappedValue.regularCycleCount, cap < settings.wrappedValue.anchorCycleNumber {
            var corrected = settings.wrappedValue
            corrected.regularCycleCount = nil
            settings.wrappedValue = corrected
        }
        let value = settings.wrappedValue
        timing = SiteNextPromptTiming.current(site)
        intervalDays = value.intervalDays
        seasons = value.seasonID != nil || value.seasonNumber != nil || value.trackSeasonTotals || !value.seasonName.isEmpty
        currentCycle = value.anchorCycleNumber
        specialExpanded = timing == .irregular || !value.specialPeriods.isEmpty
        // 今の回から、締切と状態を読み直す（開くだけでは保存内容を変えない）。
        let now = Date()
        let allDescriptors = siteCycleDescriptors(site, around: now)
        let activeStarts = allDescriptors.filter { !$0.cycleKey.hasPrefix("special:") && $0.isActive(now) }.compactMap(\.start)
        waitingCutoff = min(activeStarts.min() ?? now, now)
        let descriptors = allDescriptors
            .filter { site.recurrence == .irregular || ($0.ruleRevisionID == value.ruleRevisionID && !$0.cycleKey.hasPrefix("special:")) }
            .sorted { ($0.round.submissionStart ?? .distantPast) > ($1.round.submissionStart ?? .distantPast) }
        if value.waitingForNext {
            phase = .waiting; nextStart = nil
        } else if let active = descriptors.first(where: { $0.round.isSubmissionOpen(Date()) }), let end = active.round.submissionEnd {
            phase = .posting; deadline = end; currentCycle = active.cycleNumber ?? value.anchorCycleNumber
        } else if let active = descriptors.first(where: { $0.round.isVotingOpen(Date()) }), let end = active.round.votingEnd {
            phase = .voting; deadline = end; currentCycle = active.cycleNumber ?? value.anchorCycleNumber
        } else if let start = value.notBefore, start > now, site.recurrence != .irregular {
            // 次のお題の開始だけ分かっている間。
            phase = .waiting; nextStart = start
        } else {
            var round = EventRound(); round.submissionStart = value.anchorStart
            round = completeRoundSchedule(round, submissionDays: site.submissionDays, votingDays: site.votingDays)
            phase = .posting
            deadline = round.submissionEnd ?? deadline
        }
        if site.hasAffiliations && value.leagues.isEmpty && !site.affiliation.isEmpty {
            var changed = value; changed.leagues = [site.affiliation]; settings.wrappedValue = changed
        }
        if isNew {
            timing = .withVoting
            phase = .posting
            deadline = addCalendarDays(fiveMinuteSelection(Date()), site.submissionDays)
            updateSchedule()
        }
    }

    private func changePhase(_ value: SiteSetupPhase) {
        // 次のお題待ちにする時は、記録した回の続きを次の番号の候補にする。
        if value == .waiting && phase != .waiting { currentCycle = siteSuggestedResumeCycleNumber(site, events: store.events) }
        phase = value
        updateSchedule()
    }

    /// 今の状態・締切・出方を、日程の計算に使う保存項目へ反映する。
    private func updateSchedule() {
        applySiteTiming(timing, to: &site, intervalDays: intervalDays)
        var value = settings.wrappedValue
        if phase == .waiting && editsCurrentDeadline {
            applyWaiting(to: &value)
            settings.wrappedValue = value
            return
        }
        let anchor = siteAnchorStart(posting: phase == .posting, deadline: deadline,
                                     submissionDays: site.submissionDays, votingDays: site.votingDays)
        if editsCurrentDeadline { value.waitingForNext = false }
        if let limit = value.notBefore, anchor < limit { value.notBefore = nil }
        if timing == .irregular {
            // 新しく作る時だけ、今の回を1件用意する。既存の回の日程は個別に編集する。
            if isNew || value.specialPeriods.isEmpty || value.specialPeriods.contains(where: { $0.id == initialPeriodID }) {
                var period = value.specialPeriods.first { $0.id == initialPeriodID } ?? SiteSpecialPeriod(id: initialPeriodID)
                period.kind = .regular
                period.title = period.title.isEmpty ? "第1回" : period.title
                var round = period.round
                round.name = period.title
                round.promptNumber = max(1, round.promptNumber)
                round.submissionStart = anchor
                round.submissionEnd = addCalendarDays(anchor, site.submissionDays)
                round.votingStart = round.submissionEnd
                round.votingEnd = addCalendarDays(anchor, site.submissionDays + site.votingDays)
                period.round = round
                period.seasonName = value.seasonName
                value.specialPeriods.removeAll { $0.id == initialPeriodID }
                value.specialPeriods.append(period)
            }
        } else {
            value.anchorStart = anchor
            value.anchorCycleNumber = currentCycle
            if let last = value.regularCycleCount, last < currentCycle { value.regularCycleCount = nil }
        }
        settings.wrappedValue = value
        site.startHour = Calendar.current.component(.hour, from: anchor)
        site.startMinute = Calendar.current.component(.minute, from: anchor)
        site.weekday = Calendar.current.component(.weekday, from: anchor)
    }

    /// 投稿中でも投票中でもない（シーズンの合間など）。次のお題の開始が分かれば、そこから自動で進める。
    /// 分からない間は通常の回を作らず、前の決まりの回は今の回より前で止める。
    private func applyWaiting(to value: inout SiteCycleSettings) {
        if timing == .irregular {
            value.specialPeriods.removeAll { $0.id == initialPeriodID }
            value.waitingForNext = true
            return
        }
        if let nextStart {
            value.anchorStart = nextStart
            value.notBefore = nextStart
            value.waitingForNext = false
            site.startHour = Calendar.current.component(.hour, from: nextStart)
            site.startMinute = Calendar.current.component(.minute, from: nextStart)
            site.weekday = Calendar.current.component(.weekday, from: nextStart)
        } else {
            if !value.waitingForNext { value.anchorStart = waitingCutoff }
            value.waitingForNext = true
            value.notBefore = nil
        }
        value.anchorCycleNumber = currentCycle
        if let last = value.regularCycleCount, last < currentCycle { value.regularCycleCount = nil }
    }

    private func changeSeason(_ enabled: Bool) {
        seasons = enabled
        var value = settings.wrappedValue
        let oldRuleKey = giriSeasonRuleKey(value.seasonID)
        defer {
            // 0.23：シーズンの有無を切り替えても、選んだルールは今の期間のものとして引き継ぐ。
            let newRuleKey = giriSeasonRuleKey(site.cycleSettings?.seasonID)
            if oldRuleKey != newRuleKey, let ruleID = site.seasonRuleIDs.removeValue(forKey: oldRuleKey) {
                site.seasonRuleIDs[newRuleKey] = ruleID
            }
        }
        if enabled {
            if value.seasonID == nil { value.seasonID = UUID().uuidString }
            if value.seasonNumber == nil { value.seasonNumber = 1 }
            if value.seasonName.isEmpty { value.seasonName = "第\(value.seasonNumber ?? 1)シーズン" }
        } else {
            value.seasonID = nil
            value.seasonNumber = nil
            value.seasonName = ""
            value.seasonStart = nil
            value.seasonEndsAt = nil
            value.regularCycleCount = nil
            value.seasonLengthDays = nil
            value.trackSeasonTotals = false
            value.leagueChangesPerSeason = false
        }
        settings.wrappedValue = value
    }
    private func leagueName(_ index: Int) -> Binding<String> {
        Binding(get: { settings.wrappedValue.leagues.indices.contains(index) ? settings.wrappedValue.leagues[index] : "" }, set: { name in var value = settings.wrappedValue; if value.leagues.indices.contains(index) { value.leagues[index] = name; settings.wrappedValue = value } })
    }
    private func moveLeague(_ index: Int, by offset: Int) {
        var value = settings.wrappedValue
        guard value.leagues.indices.contains(index + offset) else { return }
        value.leagues.swapAt(index, index + offset); settings.wrappedValue = value
    }
}

private struct GiriSiteSpecialPeriodEditor: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (SiteSpecialPeriod) -> Void
    @State private var draft: SiteSpecialPeriod
    @State private var original: SiteSpecialPeriod
    @State private var discard = false
    init(period: SiteSpecialPeriod, onSave: @escaping (SiteSpecialPeriod) -> Void) {
        self.onSave = onSave
        _draft = State(initialValue: period); _original = State(initialValue: period)
    }
    private var changed: Bool { draft != original }
    var body: some View {
        Form {
            Section {
                AppCardSectionTitle(title: "個別の日程", systemImage: "calendar", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                TextField("名前", text: $draft.title)
                Picker("種類", selection: $draft.kind) { ForEach(SitePeriodKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu).tint(.primary)
                TextField("シーズン名", text: $draft.seasonName)
                if draft.kind == .regular { Stepper("第\(draft.round.promptNumber)回", value: $draft.round.promptNumber, in: 1...999) }
                GiriSchedulePeriodRow(title: "投稿", start: $draft.round.submissionStart, end: $draft.round.submissionEnd)
                GiriSchedulePeriodRow(title: "投票", start: $draft.round.votingStart, end: $draft.round.votingEnd)
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
        }
        .appEditorFormStyle().navigationTitle("個別の日程").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { if changed { discard = true } else { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) { Button("保存") { draft.round.name = draft.title.isEmpty ? draft.kind.title : draft.title; onSave(draft); dismiss() }.disabled(!validDates) }
        }
        .interactiveDismissDisabled(changed)
        .giriDiscardChangesAlert(isPresented: $discard) { dismiss() }
    }
    private var validDates: Bool {
        let r = draft.round
        guard r.submissionStart != nil || r.votingStart != nil else { return false }
        if let a = r.submissionStart, let b = r.submissionEnd, b < a { return false }
        if let a = r.votingStart, let b = r.votingEnd, b < a { return false }
        return true
    }
}
