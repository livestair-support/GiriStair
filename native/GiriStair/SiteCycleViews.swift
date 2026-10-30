import SwiftUI

/// Site status has one card boundary and one disclosure. Posting and voting
/// can refer to different cycles, so neither is reduced to an ambiguous week.
struct GiriSiteStatusCard: View {
    @EnvironmentObject private var navigation: GiriNavigation
    let site: OnlineSite
    @State private var showingSite = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { showingSite = true } label: {
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
            GiriSitePeriodActions(site: site)
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
struct GiriSitePeriodActions: View {
    @EnvironmentObject private var store: GiriStore
    @EnvironmentObject private var navigation: GiriNavigation
    let site: OnlineSite
    @State private var showingSetup = false
    @State private var resultEvent: GiriEvent?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            periodRows(now: context.date)
        }
        .sheet(isPresented: $showingSetup) { NavigationStack { GiriSiteEditor(site: site) } }
        .sheet(item: $resultEvent) { event in NavigationStack { GiriCycleResultEditor(eventID: event.id) } }
    }

    private func cycles(now: Date) -> [SiteVisibleCycle] {
        let events = store.events.filter { $0.onlineSiteId == site.id }
        let descriptors = site.cycleSettings == nil ? [] : siteCycleDescriptors(site, around: now)
        var values = descriptors.map { descriptor -> SiteVisibleCycle in
            let event = events.first { $0.cycleKey == descriptor.cycleKey }
            let round = event?.isActualParticipant == true ? event?.effectiveRounds.first ?? descriptor.round : descriptor.round
            let title = [descriptor.seasonName, descriptor.title].filter { !$0.isEmpty }.joined(separator: "・")
            return SiteVisibleCycle(descriptor: descriptor, event: event, round: round, title: title)
        }
        for event in events where event.isActualParticipant {
            for round in event.effectiveRounds where !values.contains(where: { $0.event?.id == event.id && $0.round.id == round.id }) {
                let title = [event.siteSeason, event.siteCycleNumber.map { "第\($0)回" } ?? "", event.sitePeriodKind == .regular ? "" : event.sitePeriodKind.title]
                    .filter { !$0.isEmpty }.joined(separator: "・")
                values.append(SiteVisibleCycle(descriptor: nil, event: event, round: round, title: title.isEmpty ? event.title : title))
            }
        }
        return values.sorted { ($0.round.submissionStart ?? $0.round.votingStart ?? .distantPast) > ($1.round.submissionStart ?? $1.round.votingStart ?? .distantPast) }
    }

    @ViewBuilder private func periodRows(now: Date) -> some View {
        let values = cycles(now: now)
        let posting = values.filter { $0.round.isSubmissionOpen(now) }
        let voting = values.filter { $0.round.isVotingOpen(now) }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(posting) { cycle in phaseRow(cycle, posting: true) }
            ForEach(voting) { cycle in phaseRow(cycle, posting: false) }
            if posting.isEmpty && voting.isEmpty {
                if site.cycleSettings == nil {
                    Text("開催のしくみを設定してください").font(.subheadline).foregroundStyle(.secondary)
                    Button("投稿・投票の日程を設定", systemImage: "calendar.badge.clock") { showingSetup = true }
                        .font(.subheadline.weight(.semibold)).buttonStyle(.borderless).tint(accentActionColor)
                } else {
                    Text("現在は投稿・投票の期間外です").font(.subheadline).foregroundStyle(.secondary)
                    if let next = values.filter({ ($0.round.submissionStart ?? .distantPast) > now }).min(by: { ($0.round.submissionStart ?? .distantFuture) < ($1.round.submissionStart ?? .distantFuture) }), let date = next.round.submissionStart {
                        Text("次の投稿　" + GiriDateText.dateTime(date)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let pending = pendingResult(now: now) {
                Divider().overlay(appSeparatorColor)
                Button { resultEvent = pending } label: {
                    HStack {
                        Image(systemName: "square.and.pencil")
                        Text("終了した回の結果を記録")
                        Spacer(minLength: 8)
                        if let number = pending.siteCycleNumber { Text("第\(number)回").foregroundStyle(.secondary) }
                    }.font(.subheadline)
                }.buttonStyle(.plain).tint(accentActionColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pendingResult(now: Date) -> GiriEvent? {
        store.events.filter { $0.onlineSiteId == site.id && $0.isActualParticipant && $0.hasEnded(now: now) && !$0.hasCycleResult }
            .max { ($0.participationEndDate ?? .distantPast) < ($1.participationEndDate ?? .distantPast) }
    }

    private func phaseRow(_ cycle: SiteVisibleCycle, posting: Bool) -> some View {
        Button { open(cycle, join: posting) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(posting ? "投稿中" : "投票中", systemImage: posting ? "square.and.pencil" : "checkmark.bubble")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(posting ? accentActionColor : AppSectionAccent.artist)
                    Spacer(minLength: 8)
                    if !cycle.title.isEmpty { Text(cycle.title).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    let end = posting ? cycle.round.submissionEnd : cycle.round.votingEnd
                    Text("締切 " + GiriDateText.dateTime(end)).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(posting ? (cycle.event?.isActualParticipant == true ? "回答を考える" : "参加して回答") : "お題・回答を開く")
                        .font(.caption.weight(.semibold)).foregroundStyle(accentActionColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func open(_ cycle: SiteVisibleCycle, join: Bool) {
        store.run {
            let event: GiriEvent
            if let descriptor = cycle.descriptor {
                event = try store.createSiteCycle(site.id, descriptor: descriptor, join: join || cycle.event?.isActualParticipant == true)
            } else if var existing = cycle.event {
                if join && !existing.isActualParticipant {
                    existing.isParticipating = true; existing.isInterested = false; existing.status = .planned
                    try store.saveEvent(existing)
                }
                event = existing
            } else { return }
            guard let round = event.effectiveRounds.first(where: { $0.id == cycle.round.id }) ?? event.effectiveRounds.first else { return }
            navigation.openThoughts(eventID: event.id, roundID: round.id)
        }
    }
}

private enum SiteSetupPhase: String, CaseIterable, Identifiable {
    case posting, voting
    var id: String { rawValue }
    var title: String { self == .posting ? "投稿中" : "投票中" }
}

/// One setup form serves registration and Settings. Most sites only need the
/// current phase, its start, and the repeat pattern. Season rules stay optional.
struct GiriSiteCycleSettingsForm: View {
    @Binding var site: OnlineSite
    var isNew = false
    @State private var initialized = false
    @State private var phase: SiteSetupPhase = .posting
    @State private var phaseStart = fiveMinuteSelection(Date())
    @State private var currentCycle = 1
    @State private var seasons = false
    @State private var seasonExpanded = false
    @State private var specialExpanded = false
    @State private var editingSpecial: SiteSpecialPeriod?

    private var settings: Binding<SiteCycleSettings> {
        Binding(get: { site.cycleSettings ?? SiteCycleSettings() }, set: { site.cycleSettings = $0 })
    }

    var body: some View {
        Group {
            scheduleSection
            leagueSection
            seasonSection
            specialSection
        }
        .onAppear(perform: initialize)
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

    private var scheduleSection: some View {
        Section {
            AppCardSectionTitle(title: "投稿・投票のしくみ", systemImage: "arrow.triangle.2.circlepath", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
            Picker("開催", selection: Binding(get: { site.recurrence }, set: { value in
                site.recurrence = value
                if value == .irregular { specialExpanded = true }
            })) {
                Text("定期開催").tag(SiteRecurrence.weekly)
                Text("個別の日程").tag(SiteRecurrence.irregular)
            }.pickerStyle(.menu).tint(.primary)
            if site.recurrence == .weekly {
            Picker("繰り返し", selection: Binding(get: { settings.wrappedValue.pattern }, set: changePattern)) {
                Text(SiteCyclePattern.alternating.title).tag(SiteCyclePattern.alternating)
                Text(SiteCyclePattern.overlapping.title).tag(SiteCyclePattern.overlapping)
            }.pickerStyle(.menu).tint(.primary)
            Picker("現在の状態", selection: Binding(get: { phase }, set: { phase = $0; updateAnchor() })) {
                ForEach(SiteSetupPhase.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.menu).tint(.primary)
            OptionalDateRow(title: phase == .posting ? "この投稿の開始" : "この投票の開始", selection: Binding(get: { phaseStart }, set: { if let date = $0 { phaseStart = date; updateAnchor() } }))
            Stepper("投稿期間　\(site.submissionDays)日", value: Binding(get: { site.submissionDays }, set: { site.submissionDays = $0; updateDefaultInterval(); updateAnchor() }), in: 1...365)
            Stepper("投票期間　\(site.votingDays)日", value: Binding(get: { site.votingDays }, set: { site.votingDays = $0; updateDefaultInterval() }), in: 1...365)
            if settings.wrappedValue.pattern == .overlapping {
                Stepper("新しいお題の間隔　\(settings.wrappedValue.intervalDays)日", value: settings.intervalDays, in: 1...365)
            }
            Text(settings.wrappedValue.pattern == .alternating ? "投稿締切から投票開始、投票締切から次の投稿開始になります。" : "投票期間と次のお題の投稿期間を別々に表示します。")
                .font(.caption).foregroundStyle(.secondary)
            } else {
                Button("日程を追加", systemImage: "plus.circle") { addIndependentPeriod() }
                    .buttonStyle(.borderless)
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    private var leagueSection: some View {
        Section {
            AppCardSectionTitle(title: "リーグ・所属", systemImage: "list.number", accentColor: AppSectionAccent.memo).listRowSeparator(.hidden)
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
                Button("リーグを追加", systemImage: "plus.circle") { var value = settings.wrappedValue; value.leagues.append(""); settings.wrappedValue = value }.buttonStyle(.borderless)
                Picker("現在のリーグ", selection: $site.affiliation) {
                    Text("未設定").tag("")
                    ForEach(Array(settings.wrappedValue.leagues.enumerated()), id: \.offset) { _, name in
                        if !name.isEmpty { Text(name).tag(name) }
                    }
                    if !site.affiliation.isEmpty && !settings.wrappedValue.leagues.contains(site.affiliation) { Text(site.affiliation).tag(site.affiliation) }
                }.pickerStyle(.menu).tint(.primary)
                Text("上から下へ、リーグの強さの順に並べます。昇格・降格は結果入力時に選びます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextField("ブロック（任意）", text: $site.block)
        }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
    }

    private var seasonSection: some View {
        Section {
            DisclosureGroup("シーズンを管理", isExpanded: $seasonExpanded) {
                Toggle("シーズンがある", isOn: Binding(get: { seasons }, set: changeSeason))
                    .tint(AppSectionAccent.artist)
                if seasons {
                    TextField("シーズン名（例：第12シーズン）", text: settings.seasonName)
                    Stepper("登録するお題は第\(currentCycle)回", value: Binding(get: { currentCycle }, set: { currentCycle = $0; updateAnchor() }), in: 1...999)
                    OptionalDateRow(title: "シーズン開始", selection: settings.seasonStart)
                    Stepper("通常のお題　\(settings.wrappedValue.regularCycleCount ?? 9)回", value: optionalInteger(\.regularCycleCount, fallback: 9), in: 1...999)
                    Stepper("1シーズン　\(settings.wrappedValue.seasonLengthDays ?? 70)日", value: optionalInteger(\.seasonLengthDays, fallback: 70), in: 1...730)
                    if site.hasAffiliations { Toggle("昇降格はシーズン終了後", isOn: settings.leagueChangesPerSeason).tint(AppSectionAccent.artist) }
                    if !isNew {
                        Button("次のシーズンを設定", systemImage: "arrow.right.circle") { startNextSeason() }
                            .buttonStyle(.borderless)
                        Text("次のシーズンの特別週は、日程を確認して追加してください。過去の参加記録は残ります。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("通常回の後は、下の特別週に日程を追加します。入れ替え戦への出場と昇降格は別に記録できます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    private var specialSection: some View {
        Section {
            DisclosureGroup("特別週・個別の日程", isExpanded: $specialExpanded) {
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
                Button("特別週を追加", systemImage: "plus.circle") {
                    var period = SiteSpecialPeriod()
                    period.kind = .exhibition
                    period.seasonName = settings.wrappedValue.seasonName
                    period.round.name = "特別週"
                    period.round.promptNumber = currentCycle
                    editingSpecial = period
                }.buttonStyle(.borderless)
                Text("エキシビション・プレーオフ・入れ替え戦や、短い最終回の日程を個別に保存します。1つの期間につき1件ずつ追加できます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    private func addIndependentPeriod() {
        var period = SiteSpecialPeriod()
        period.kind = site.recurrence == .irregular ? .regular : .exhibition
        period.title = site.recurrence == .irregular ? "個別の日程" : "特別週"
        period.seasonName = settings.wrappedValue.seasonName
        period.round.name = period.title
        editingSpecial = period
    }

    private func initialize() {
        guard !initialized else { return }
        initialized = true
        let hadSettings = site.cycleSettings != nil
        if !hadSettings {
            var value = SiteCycleSettings()
            value.pattern = .alternating
            value.anchorStart = fiveMinuteSelection(Date())
            value.intervalDays = site.submissionDays + site.votingDays
            site.cycleSettings = value
            if isNew { site.recurrence = .weekly }
            else if site.recurrence == .irregular { specialExpanded = true }
        }
        let value = settings.wrappedValue
        seasons = value.seasonStart != nil || value.regularCycleCount != nil || !value.seasonName.isEmpty
        seasonExpanded = seasons
        currentCycle = value.anchorCycleNumber
        phaseStart = value.anchorStart
        let descriptors = siteCycleDescriptors(site)
        if let active = descriptors.first(where: { $0.round.isSubmissionOpen(Date()) }) {
            phase = .posting; phaseStart = active.round.submissionStart ?? value.anchorStart; currentCycle = active.cycleNumber ?? value.anchorCycleNumber
        } else if let active = descriptors.first(where: { $0.round.isVotingOpen(Date()) }) {
            phase = .voting; phaseStart = active.round.votingStart ?? value.anchorStart; currentCycle = active.cycleNumber ?? value.anchorCycleNumber
        }
        if site.hasAffiliations && value.leagues.isEmpty && !site.affiliation.isEmpty {
            var changed = value; changed.leagues = [site.affiliation]; settings.wrappedValue = changed
        }
    }

    private func updateAnchor() {
        var value = settings.wrappedValue
        value.anchorStart = phase == .posting ? phaseStart : addCalendarDays(phaseStart, -site.submissionDays)
        value.anchorCycleNumber = currentCycle
        if seasons {
            value.seasonStart = addCalendarDays(value.anchorStart, -(currentCycle - 1) * value.intervalDays)
        }
        settings.wrappedValue = value
        site.startHour = Calendar.current.component(.hour, from: value.anchorStart)
        site.startMinute = Calendar.current.component(.minute, from: value.anchorStart)
    }
    private func changePattern(_ pattern: SiteCyclePattern) {
        var value = settings.wrappedValue; value.pattern = pattern
        value.intervalDays = pattern == .alternating ? site.submissionDays + site.votingDays : site.submissionDays
        settings.wrappedValue = value
        updateAnchor()
    }
    private func updateDefaultInterval() {
        var value = settings.wrappedValue
        value.intervalDays = value.pattern == .alternating ? site.submissionDays + site.votingDays : site.submissionDays
        settings.wrappedValue = value
    }
    private func changeSeason(_ enabled: Bool) {
        seasons = enabled
        var value = settings.wrappedValue
        if enabled {
            if value.seasonName.isEmpty { value.seasonName = "シーズン1" }
            value.seasonStart = addCalendarDays(value.anchorStart, -(currentCycle - 1) * value.intervalDays)
            value.regularCycleCount = value.regularCycleCount ?? 9
            value.seasonLengthDays = value.seasonLengthDays ?? 70
        } else {
            value.seasonName = ""; value.seasonStart = nil; value.regularCycleCount = nil; value.seasonLengthDays = nil
            value.leagueChangesPerSeason = false
        }
        settings.wrappedValue = value
    }
    private func startNextSeason() {
        var value = settings.wrappedValue
        let next = value.seasonStart.map { addCalendarDays($0, value.seasonLengthDays ?? 70) } ?? Date()
        if site.hasAffiliations { site.affiliation = siteLeague(site, at: next) }
        value.anchorStart = next; value.anchorCycleNumber = 1; value.seasonStart = next
        value.seasonName = "次のシーズン"
        // Joined historical events retain their snapshots. New-season special
        // dates receive fresh IDs when the user adds them.
        value.specialPeriods = []
        settings.wrappedValue = value
        phase = .posting; phaseStart = next; currentCycle = 1
    }
    private func optionalInteger(_ keyPath: WritableKeyPath<SiteCycleSettings, Int?>, fallback: Int) -> Binding<Int> {
        Binding(get: { settings.wrappedValue[keyPath: keyPath] ?? fallback }, set: { var value = settings.wrappedValue; value[keyPath: keyPath] = $0; settings.wrappedValue = value })
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
        .confirmationDialog("入力を保存せず戻りますか？", isPresented: $discard, titleVisibility: .visible) { Button("保存せず戻る", role: .destructive) { dismiss() } }
    }
    private var validDates: Bool {
        let r = draft.round
        guard r.submissionStart != nil || r.votingStart != nil else { return false }
        if let a = r.submissionStart, let b = r.submissionEnd, b < a { return false }
        if let a = r.votingStart, let b = r.votingEnd, b < a { return false }
        return true
    }
}
