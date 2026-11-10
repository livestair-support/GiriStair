import SwiftUI
import UIKit

// LiveStair-native filters and cards, with four independent GiriStair formats.
struct GiriListView: View {
    @EnvironmentObject private var store: GiriStore
    @EnvironmentObject private var navigation: GiriNavigation
    @State private var search = ""
    @State private var selectedFormat: EventFormat = .live
    @State private var didInitializeFormat = false
    @State private var attended = false
    @State private var year = "all"
    @State private var meeting = "all"
    @State private var status = "all"
    @State private var venue = "all"
    @State private var selectedPlayers: Set<String> = []
    @State private var showsPlayerDropdown = false
    @State private var playerSearch = ""
    @State private var site = "all"
    @State private var stage = "all"
    /// 主催者（共催を含む）で絞り込む。0.27：シリーズの代わりに常に出す。プレイヤー・団体詳細の「主催した会」からも開く。
    @State private var hostFilter = "all"
    /// 通常サイトの詳細・編集・結果入力（このタブの中で遷移する）。
    @State private var siteRoute: GiriSiteRoute?
    @State private var ascending: Bool?
    @State private var isCollapsed = false
    @State private var destinationID: String?
    @State private var deletingEvent: GiriEvent?
    @State private var timelineStart = Date()

    private var accent: Color { GiriEventPresentation.accent(selectedFormat) }
    private var isCalendar: Bool { store.preferences.listCurrentMode }
    private var searchableEvents: [GiriEvent] {
        store.events.filter {
            $0.eventFormat == selectedFormat && ($0.onlineSiteId == nil || $0.isActualParticipant || $0.isInterested)
        }
    }
    private var years: [String] {
        Array(Set(searchableEvents.compactMap {
            GiriEventPresentation.date($0).map { String(Calendar(identifier: .gregorian).component(.year, from: $0)) }
        })).sorted(by: >)
    }
    private var venueNames: [String] { Array(Set(searchableEvents.map(\.venue).filter { !$0.isEmpty })).sorted() }
    private var playerNames: [String] {
        // 別名義をまとめて表示する人は、本名義だけを出す。
        let merged = store.mergedAliasOwners
        var names: [String] = []
        var seen = Set<String>()
        for name in searchableEvents.flatMap({ $0.participants + $0.teams.flatMap(\.members) }) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let shown = merged[playerSearchKey(trimmed)] ?? trimmed
            if seen.insert(playerSearchKey(shown)).inserted { names.append(shown) }
        }
        return names.sorted { first, second in
            let firstPlayer = store.players.first { playerSearchKey($0.name) == playerSearchKey(first) }
            let secondPlayer = store.players.first { playerSearchKey($0.name) == playerSearchKey(second) }
            let firstReading = firstPlayer.flatMap { $0.furigana.isEmpty ? nil : $0.furigana } ?? first
            let secondReading = secondPlayer.flatMap { $0.furigana.isEmpty ? nil : $0.furigana } ?? second
            return firstReading.localizedStandardCompare(secondReading) == .orderedAscending
        }
    }
    private var stageNames: [String] { Array(Set(searchableEvents.flatMap { $0.effectiveRounds.map(\.name) })).sorted() }
    /// 折りたたんだ時に出す、初期状態と違う条件。
    private var collapsedConditions: [String] {
        var values: [String] = []
        if year != "all" { values.append(year) }
        if meeting != "all" { values.append(meeting == "casual" ? "通常" : meeting == "project" ? "企画" : "大会") }
        if venue != "all" { values.append(venue) }
        if !selectedPlayers.isEmpty { values.append(selectedPlayers.sorted().joined(separator: " / ")) }
        if stage != "all" { values.append(stage) }
        if hostFilter != "all" { values.append("主催者：" + hostFilter) }
        if !search.isEmpty { values.append("検索「\(search)」") }
        return values
    }
    /// 会の種類（生大喜利・スプシ系は企画も選べる）。
    private var meetingOptions: [(String, String)] {
        var options = [("all", "すべて"), ("casual", "通常"), ("tournament", "大会")]
        if selectedFormat.allowsProject || meeting == "project" { options.append(("project", "企画")) }
        if selectedFormat.allowsProject || meeting == "kumite" { options.append(("kumite", "組手")) }
        return options
    }
    /// 主催者・共催（団体を含む）の名前。
    private var hostNames: [String] {
        var names: [String] = []
        var seen = Set<String>()
        for event in searchableEvents {
            for name in [event.organizer] + event.coOrganizers {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && seen.insert(playerSearchKey(trimmed)).inserted { names.append(trimmed) }
            }
        }
        if hostFilter != "all" && seen.insert(playerSearchKey(hostFilter)).inserted { names.append(hostFilter) }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private func isHosted(_ event: GiriEvent, keys: Set<String>) -> Bool {
        keys.contains(playerSearchKey(event.organizer)) || event.coOrganizers.contains { keys.contains(playerSearchKey($0)) }
    }
    private var filteredEvents: [GiriEvent] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        // 別名義をまとめて表示する人は、別名義で入った会も同じ人として探す。
        let playerKeySets = selectedPlayers.map { store.nameKeys(for: $0) }
        let hostKeys = hostFilter == "all" ? Set<String>() : store.nameKeys(for: hostFilter)
        return searchableEvents.filter { event in
            if meeting != "all" && event.meetingFilterKey != meeting { return false }
            switch status {
            case "interested": if !event.isInterested { return false }
            case "canceled": if event.status != .canceled { return false }
            default:
                guard event.isActualParticipant else { return false }
                let phase = event.participationState(now: now)
                if attended ? phase != .completed : (phase != .upcoming && phase != .ongoing) { return false }
            }
            if year != "all" {
                guard let date = GiriEventPresentation.date(event),
                      String(Calendar(identifier: .gregorian).component(.year, from: date)) == year else { return false }
            }
            // 会場・参加者の条件は、その行を表示する形式（生・短考・スプシ系）でだけ使う。
            // 形式を切り替えても条件は残し、長考では適用しない。
            if hasParticipantFilter && venue != "all" && event.venue != venue { return false }
            // LiveStair selectedArtists is an AND filter, retaining all selected people.
            if hasParticipantFilter && !playerKeySets.isEmpty && !playerKeySets.allSatisfy({ keys in
                (event.participants + event.teams.flatMap(\.members)).contains { keys.contains(playerSearchKey($0)) }
            }) { return false }
            if hasParticipantFilter && !hostKeys.isEmpty && !isHosted(event, keys: hostKeys) { return false }
            if site != "all" && event.onlineSiteId != site { return false }
            if stage != "all" && !event.effectiveRounds.contains(where: { $0.name == stage }) { return false }
            let venueRecord = store.venues.first { $0.id == event.venueId || $0.name == event.venue }
            let siteRecord = store.onlineSites.first { $0.id == event.onlineSiteId }
            guard !query.isEmpty else { return true }
            // 会場は部屋あり・なしのどちらでも、シリーズ名でも探せる。
            var fields: [String] = [event.title, event.organizer, event.venue, event.venueRoom, event.venue + event.venueRoom,
                                    event.memo, event.affiliation, event.block, venueRecord?.prefecture ?? "", siteRecord?.name ?? ""]
            fields.append(event.seriesTitle)
            fields += event.coOrganizers
            fields += event.reserves
            fields += event.participants
            fields += event.teams.flatMap { [$0.name] + $0.members }
            let text = fields.joined(separator: " ")
            let compactQuery = query.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
            return text.localizedStandardContains(query) || (event.venue + event.venueRoom).replacingOccurrences(of: " ", with: "").localizedStandardContains(compactQuery)
        }.sorted { a, b in
            let ad = GiriEventPresentation.date(a), bd = GiriEventPresentation.date(b)
            if ad == nil && bd == nil { return a.createdAt > b.createdAt }
            guard let ad else { return false }; guard let bd else { return true }
            if ad == bd { return a.title.localizedStandardCompare(b.title) == .orderedAscending }
            return (ascending ?? !attended) ? ad < bd : ad > bd
        }
    }
    private var visibleSites: [OnlineSite] { monitoredSites.filter { !$0.isPaused } }
    /// しばらく休んでいるサイト。カードは出さず、一覧の下に件数と戻り道だけを出す。
    private var pausedSites: [OnlineSite] { monitoredSites.filter(\.isPaused) }
    private var monitoredSites: [OnlineSite] {
        guard selectedFormat == .onlineLong, !attended, meeting != "tournament", status == "all", year == "all", stage == "all" else { return [] }
        return store.onlineSites.filter { record in
            record.format == selectedFormat && (site == "all" || site == record.id) &&
            (search.isEmpty || [record.name, record.affiliation, record.block, record.memo].joined(separator: " ").localizedStandardContains(search))
        }
    }
    // A monitored site's current periods already appear in its status card.
    // Keep those same cycles out of the adjacent list rather than duplicating
    // the site and its current posting/voting as unrelated cards.
    private var eventCards: [GiriEvent] {
        let displayedSiteIDs = Set(visibleSites.map(\.id))
        return filteredEvents.filter { event in
            guard let siteID = event.onlineSiteId else { return true }
            return !displayedSiteIDs.contains(siteID)
        }
    }
    private var visibleEntryCount: Int { visibleSites.count + eventCards.count }
    private var hasParticipantFilter: Bool { selectedFormat.hasLiveTiming }

    var body: some View {
        TimelineView(.periodic(from: timelineStart, by: 60)) { context in
            VStack(spacing: 0) {
                if isCalendar {
                    ScrollView { GiriCalendarView(events: store.events) }
                } else {
                    filterHeader
                    eventList(now: context.date)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(appBackgroundColor)
        .safeAreaInset(edge: .top, spacing: 0) { pageHeader }
        .overlay(alignment: .topTrailing) {
            if showsPlayerDropdown {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { closePlayerDropdown() }
                    .zIndex(998)
                playerDropdownPanel
                    .padding(.top, 112).padding(.trailing, 18)
                    .zIndex(999)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if !didInitializeFormat {
                selectedFormat = store.preferences.visibleFormatOrder.first ?? .live
                didInitializeFormat = true
            }
            consumeListRequest()
            consumeDetailRequest()
        }
        .onChange(of: navigation.listRequest) { _, _ in consumeListRequest() }
        .onChange(of: navigation.detailRequest) { _, _ in consumeDetailRequest() }
        .onChange(of: store.preferences.visibleFormatOrder) { previous, next in
            if selectedFormat == previous.first || !next.contains(selectedFormat) {
                selectedFormat = next.first ?? .live
            }
        }
        .onChange(of: selectedFormat) { _, _ in
            // 会場・参加者・主催者は詳細のショートカットから開いた条件を形式の切替後も残す。
            year = "all"; meeting = "all"; status = "all"; site = "all"; stage = "all"
            closePlayerDropdown()
        }
        .onChange(of: isCalendar) { _, _ in closePlayerDropdown() }
        .onChange(of: isCollapsed) { _, collapsed in if collapsed { closePlayerDropdown() } }
        .navigationDestination(isPresented: Binding(get: { destinationID != nil }, set: { if !$0 { destinationID = nil } })) {
            if let id = destinationID { GiriEventDetail(eventID: id) }
        }
        .navigationDestination(item: $siteRoute) { GiriSiteRouteView(route: $0) }
        .giriDeleteAlert("記録を削除しますか？", isPresented: Binding(get: { deletingEvent != nil }, set: { if !$0 { deletingEvent = nil } }),
                         message: "「\(deletingEvent?.title ?? "")」を削除します。設定の「最近削除した会」に30日間残ります。") {
            guard let event = deletingEvent else { return }
            store.run { try store.deleteEvent(event.id, keepsInTrash: true); playLiveStairDeleteFeedback() }
            deletingEvent = nil
        }
    }
    private func eventList(now: Date) -> some View {
        // Keep one native List/data source mounted when a format has no rows.
        // Changing the segmented control must update its rows rather than
        // replace the collection view while UIKit is handling that selection.
        List {
            ForEach(visibleSites) { record in
                GiriSiteStatusCard(site: record, now: now, onRoute: { siteRoute = $0 })
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: record.id == visibleSites.first?.id ? 2 : 6, leading: 18, bottom: 6, trailing: 18))
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
            if !pausedSites.isEmpty {
                NavigationLink { GiriSitesView() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pause.circle").foregroundStyle(.secondary)
                        Text("休止中のサイト \(pausedSites.count)件").font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text("再開").font(.subheadline.weight(.semibold)).foregroundStyle(accentActionColor)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .appTintedCard(accentColor: AppSectionAccent.memo)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 6, trailing: 18))
                .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
            ForEach(eventCards) { event in
                Button { destinationID = event.id } label: { GiriEventCard(event: event) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { destinationID = event.id } label: { Label("詳細", systemImage: "info.circle") }
                        Button(role: .destructive) { deletingEvent = event } label: { Label("削除", systemImage: "trash") }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { deletingEvent = event } label: { Label("削除", systemImage: "trash") }
                    }
                    .listRowInsets(EdgeInsets(top: visibleSites.isEmpty && event.id == eventCards.first?.id ? 2 : 6, leading: 18, bottom: 6, trailing: 18))
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .contentMargins(.bottom, 104, for: .scrollContent).scrollIndicators(.hidden)
        .overlay {
            if eventCards.isEmpty && visibleSites.isEmpty && pausedSites.isEmpty {
                CenteredEmptyMessage(systemImage: "calendar.badge.exclamationmark", title: searchableEvents.isEmpty ? "記録がありません" : "該当する記録がありません")
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(appBackgroundColor)
    }
    private var pageHeader: some View {
        AppPageHeader(title: "一覧", systemImage: "list.bullet.rectangle", accentColor: accent)
            .overlay(alignment: .trailing) {
                HStack(spacing: 10) {
                    Button {
                        var preferences = store.preferences; preferences.listCurrentMode.toggle()
                        store.run { try store.savePreferences(preferences) }
                    } label: { headerIcon(isCalendar ? "list.bullet" : "calendar") }
                    .buttonStyle(.plain).accessibilityLabel(isCalendar ? "一覧表示に切り替える" : "カレンダー表示に切り替える")
                    if !isCalendar {
                        AppMenu {
                            Button { ascending = true } label: { Label("日付の早い順", systemImage: (ascending ?? !attended) ? "checkmark" : "") }
                            Button { ascending = false } label: { Label("日付の遅い順", systemImage: !(ascending ?? !attended) ? "checkmark" : "") }
                        } label: { headerIcon("arrow.up.arrow.down") }
                        .buttonStyle(.plain).accessibilityLabel("並び順")
                    }
                }.padding(.trailing, 18)
            }
    }
    private func headerIcon(_ image: String) -> some View {
        Image(systemName: image).font(.system(size: appFontSize(19), weight: .semibold)).foregroundStyle(.primary)
            .frame(width: 44, height: 44).background(appCardColor).clipShape(Circle())
            .overlay { Circle().stroke(Color.primary.opacity(0.10), lineWidth: 1) }
    }
    private var filterHeader: some View {
        VStack(spacing: 5) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal.decrease").font(.system(size: appFontSize(16), weight: .semibold)).foregroundStyle(accent).frame(width: 22)
                Text("表示・絞り込み").font(.system(size: appFontSize(18), weight: .bold, design: .rounded))
                Spacer()
                Text("\(visibleEntryCount)件").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                AppHeaderCollapseButton(isCollapsed: $isCollapsed, tintColor: accent)
            }
            GiriFormatPicker(selection: $selectedFormat, formats: store.preferences.visibleFormatOrder)
            if !isCollapsed {
                AppSearchField(text: $search, placeholder: selectedFormat.hasLiveTiming ? "会・大会名・会場・主催者・参加者・メモ" : "大会・サイト・段階・ブロック・メモ")
                    .padding(.bottom, 2)
            }
            Picker("表示", selection: Binding(get: { attended }, set: { attended = $0; status = "all" })) {
                Text("参加中・参加予定").tag(false)
                Text("参加済").tag(true)
            }.pickerStyle(.segmented).tint(accent)
            if !isCollapsed {
                separator
                HStack(spacing: 0) {
                    GiriListFilterMenu(title: "年", selection: $year, options: [("all", "全期間")] + years.map { ($0, $0) }, valueWidth: 64)
                    Divider().overlay(appSeparatorColor).frame(height: 30).padding(.horizontal, 9)
                    GiriListFilterMenu(title: "会の種類", selection: $meeting, options: meetingOptions, valueWidth: 64)
                }
                if hasParticipantFilter {
                    separator
                    participantFilter
                    separator
                    GiriListFilterMenu(title: "会場", selection: $venue, options: [("all", "全会場")] + (venueNames + (venue != "all" && !venueNames.contains(venue) ? [venue] : [])).map { ($0, $0) })
                }
                if hasParticipantFilter && (!hostNames.isEmpty || hostFilter != "all") {
                    separator
                    GiriListFilterMenu(title: "主催者", selection: $hostFilter, options: [("all", "全主催者")] + hostNames.map { ($0, $0) })
                }
                if selectedFormat == .onlineLong {
                    separator
                    GiriListFilterMenu(title: "サイト", selection: $site, options: [("all", "全サイト")] + store.onlineSites.filter { $0.format == selectedFormat }.map { ($0.id, $0.name) })
                }
                if selectedFormat.hasOnlineRounds && meeting != "casual" {
                    separator
                    GiriListFilterMenu(title: "段階", selection: $stage, options: [("all", "すべて")] + stageNames.map { ($0, $0) })
                }
                separator
                GiriListFilterMenu(title: "参加状況", selection: $status, options: [("all", "参加記録"), ("interested", "興味あり"), ("canceled", "キャンセル")])
            } else {
                let conditions = collapsedConditions
                if !conditions.isEmpty { AppHeaderConditionSummary(conditions: conditions) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .appTintedCard(accentColor: accent, cornerRadius: 20, railVerticalInset: 14, lightTintOpacity: 0.065)
        .padding(.horizontal, 18).padding(.bottom, 12)
    }
    private var participantFilter: some View {
        Button {
            if showsPlayerDropdown { closePlayerDropdown() }
            else { showsPlayerDropdown = true }
        } label: {
            LiveListFullWidthFilterLabel(title: "参加者", value: selectedPlayers.isEmpty ? "全参加者" : selectedPlayers.sorted().joined(separator: " / "), symbolName: showsPlayerDropdown ? "chevron.up" : "chevron.down", tintColor: accent)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }
    // ContentView.swift liveListArtistDropdownPanel / liveListArtistDropdownRow.
    // Individual selections keep this panel open so many people can be chosen.
    private var playerDropdownPanel: some View {
        let query = playerSearchKey(playerSearch)
        let names = playerNames.filter { name in
            guard !query.isEmpty else { return true }
            let reading = store.playerByName(name)?.furigana ?? ""
            return playerSearchKey(name).contains(query) || playerSearchKey(reading).contains(query)
        }
        return VStack(alignment: .leading, spacing: 8) {
            TextField("参加者を検索", text: $playerSearch)
                .font(.caption).textFieldStyle(.roundedBorder)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
            Button {
                selectedPlayers.removeAll()
                closePlayerDropdown()
            } label: {
                playerDropdownLabel("全参加者", isSelected: selectedPlayers.isEmpty, minimumHeight: 44)
            }.buttonStyle(.plain)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !names.isEmpty {
                        Text("参加者").font(.caption).foregroundStyle(.secondary)
                            .padding(.top, 4).padding(.bottom, 6)
                    }
                    ForEach(names, id: \.self) { name in
                        Button {
                            if selectedPlayers.contains(name) { selectedPlayers.remove(name) }
                            else { selectedPlayers.insert(name) }
                        } label: {
                            playerDropdownLabel(name, isSelected: selectedPlayers.contains(name))
                        }.buttonStyle(.plain)
                    }
                    if names.isEmpty {
                        Text("該当なし").font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 24)
                    }
                }
            }.frame(height: 300)
        }
        .padding(10).frame(width: 280)
        .background(appCardColor)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(accent.opacity(0.32), lineWidth: 1) }
        .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: 3)
    }
    private func playerDropdownLabel(_ title: String, isSelected: Bool, minimumHeight: CGFloat = 40) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark" : "")
                .font(.caption).foregroundStyle(.primary).frame(width: 18)
            Text(title).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    /// 戦績タブの結果入力などから、この一覧タブで詳細を開く。編集中の内容は消さない。
    private func consumeDetailRequest() {
        guard let request = navigation.detailRequest else { return }
        navigation.detailRequest = nil
        guard destinationID != request.eventID else { return }
        if let editing = navigation.unsavedEditorEventID, editing != request.eventID {
            store.errorMessage = "編集中の内容があります。保存するか破棄してから、もう一度開いてください。"
            return
        }
        closePlayerDropdown()
        destinationID = request.eventID
    }
    /// プレイヤー・会場詳細のショートカット。並び順の左から、該当する記録がある形式を開く。
    private func consumeListRequest() {
        guard let request = navigation.listRequest else { return }
        navigation.listRequest = nil
        destinationID = nil
        closePlayerDropdown()
        let people = request.players.filter { !playerSearchKey($0).isEmpty }.map { store.nameKeys(for: $0) }
        let venueKey = request.venue.map(playerSearchKey) ?? ""
        let hostKeys = request.organizer.map { store.nameKeys(for: $0) } ?? []
        func matches(_ event: GiriEvent) -> Bool {
            guard event.isActualParticipant, event.eventFormat.hasLiveTiming else { return false }
            let names = (event.participants + event.teams.flatMap(\.members)).map(playerSearchKey)
            if !people.allSatisfy({ keys in names.contains { keys.contains($0) } }) { return false }
            if !venueKey.isEmpty && playerSearchKey(event.venue) != venueKey { return false }
            if !hostKeys.isEmpty && !isHosted(event, keys: hostKeys) { return false }
            return true
        }
        let candidates = store.preferences.visibleFormatOrder.filter(\.hasLiveTiming)
        let format = candidates.first { format in store.events.contains { $0.eventFormat == format && matches($0) } }
            ?? candidates.first ?? store.preferences.visibleFormatOrder.first ?? .live
        let now = Date()
        let hasCompleted = store.events.contains { $0.eventFormat == format && matches($0) && $0.participationState(now: now) == .completed }
        if store.preferences.listCurrentMode {
            var preferences = store.preferences
            preferences.listCurrentMode = false
            store.run { try store.savePreferences(preferences) }
        }
        selectedFormat = format
        search = ""; year = "all"; meeting = "all"; status = "all"; site = "all"; stage = "all"; ascending = nil
        attended = hasCompleted
        selectedPlayers = Set(request.players.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        hostFilter = request.organizer.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? "all"
        venue = request.venue.flatMap { $0.isEmpty ? nil : $0 } ?? "all"
        // 一覧の会場名と表記が違う場合は、記録に保存された名前で絞り込む。
        if let saved = store.events.first(where: { matches($0) && !$0.venue.isEmpty })?.venue, !venueKey.isEmpty { venue = saved }
    }
    private func closePlayerDropdown() {
        showsPlayerDropdown = false
        playerSearch = ""
    }
    private var separator: some View { Divider().overlay(appSeparatorColor) }
}

struct GiriFormatPicker: View {
    @Binding var selection: EventFormat
    var formats: [EventFormat] = EventFormat.allCases
    /// 一覧・戦績は "format-tabs"（UIテストで使う）。お題/回答は別のIDにする。
    var identifier = "format-tabs"
    var body: some View {
        Picker("形式", selection: $selection) {
            ForEach(formats) { format in
                Text(format.shortTitle).tag(format).accessibilityLabel(format.title)
            }
        }.pickerStyle(.segmented).accessibilityIdentifier(identifier)
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

/// Keep the source label's typography and measured placement, but let SwiftUI
/// draw the text. Changing a live UILabel's font from layoutSubviews and then
/// invalidating its intrinsic size during representable updates can re-enter
/// the layout graph while a format removes/replaces the filter rows.
private struct LiveListFilterValueText: View {
    let text: String
    let pointSize: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: pointSize, weight: .medium))
            .minimumScaleFactor(LiveListFilterTextMeasurement.minimumScale)
            .multilineTextAlignment(.trailing)
            .lineLimit(nil)
            .frame(maxWidth: .infinity, alignment: .trailing)
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
                        Text(selectedLabel).font(.system(size: appFontSize(17), weight: .semibold)).foregroundStyle(.primary)
                            .lineLimit(1).allowsTightening(true)
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
    var resultActionTitle: String? = nil
    private var accent: Color { GiriEventPresentation.cardAccent(event) }
    private var date: Date? { GiriEventPresentation.date(event) }
    private var venueRecord: GiriVenue? {
        store.venues.first { $0.id == event.venueId || $0.name == event.venue }
    }
    private var venueText: String {
        let room = event.venueRoom.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = event.venue.isEmpty ? "会場未設定" : (room.isEmpty ? event.venue : event.venue + " " + room)
        guard let prefecture = venueRecord?.prefecture, !prefecture.isEmpty else { return name }
        return "\(name)（\(prefecture)）"
    }
    var body: some View {
        GiriListCard(accentColor: accent, contentOpacity: event.status == .canceled ? 0.55 : 1) {
            VStack(alignment: .leading, spacing: 7) {
                topArea
                if event.eventFormat.hasLiveTiming { liveDetails }
                if event.eventFormat.hasOnlineRounds && !event.effectiveRounds.isEmpty { onlineDetails }
                if showsResult {
                    Divider().overlay(appSeparatorColor)
                    Text(resultActionTitle ?? GiriEventPresentation.resultSummary(event))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(resultActionTitle == nil && event.hasRecordedResult ? Color.primary : accentActionColor)
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
                if event.eventFormat.hasLiveTiming {
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
                // 形式（生大喜利・長考など）は一覧の形式タブで分かるので出さず、会の種類を上に詰める。
                GiriListBadge(text: event.meetingTitle, color: GiriBadgeColors.meeting(event), fitsColumn: true)
                    .frame(width: 70, alignment: .leading).offset(x: 2)
            }
            HStack(alignment: .top, spacing: 6) {
                Text(event.title.isEmpty ? "会・大会名未設定" : event.title)
                    .font(.system(size: appFontSize(16), weight: .bold, design: .rounded))
                    .foregroundStyle(.primary).multilineTextAlignment(.leading).lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                let badges = statusBadges
                if !badges.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                            GiriListBadge(text: badge.text, color: badge.color)
                        }
                    }
                    .frame(width: 70, alignment: .leading)
                }
            }
        }
    }
    /// LiveStair の一覧カードの右の札：立場・参加状況を、状態ごとの色で出す。
    /// 札は1つにまとめて、カードを縦に伸ばさない。
    private var statusBadges: [(text: String, color: Color)] {
        let state = event.participationState()
        // 生大喜利で、プレイヤーとして出ない立場（主催・観覧・リザーバー）。参加予定・参加済は立場の札だけにする。
        if event.eventFormat == .live && event.selfRole != .player && [.upcoming, .ongoing, .completed].contains(state) {
            return [(event.selfRole.shortTitle(tournament: event.meetingType == .tournament), GiriBadgeColors.role(event.selfRole))]
        }
        return state == .completed ? [] : [(state.title, GiriBadgeColors.state(state))]
    }
    private func dateLabel(compact: Bool) -> some View {
        Text(GiriEventPresentation.day(date, compact: compact))
            .font(.system(size: appFontSize(14), weight: .bold, design: .rounded))
            .foregroundStyle(date.map { GiriCalendarRules.dayColor($0, ordinary: .secondary) } ?? .secondary)
            .lineLimit(1).allowsTightening(true)
    }
    /// 主催（共催があれば「・」で続ける）。
    private var organizerLine: String {
        var names: [String] = []
        if !event.organizer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { names.append(event.organizer) }
        names += event.coOrganizers.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return names.joined(separator: "・")
    }
    private var liveDetails: some View {
        VStack(alignment: .leading, spacing: 7) {
            // タイトルと会場の間に「主催：〇〇」。
            if !organizerLine.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: "person.crop.circle").font(.caption2.weight(.semibold))
                        .foregroundStyle(accent).frame(width: 15)
                    // 会場と同じ大きさで出す。
                    Text("主催：" + organizerLine).font(.system(size: appFontSize(15), weight: .medium))
                        .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
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
            // チーム戦はチームのメンバーも出す（参加者ではなくチームとして入力するため）。
            if !event.everyone.isEmpty {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "person.2").font(.caption2.weight(.semibold))
                        .foregroundStyle(accent).frame(width: 15).padding(.top, 2)
                    Text(event.everyone.joined(separator: " / ")).font(.caption)
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

/// LiveStair の札の色（CommonUI LiveAttendanceStatus.badgeColor・チケットの状態・ライブの種類と同じ値）。
enum GiriBadgeColors {
    /// 参加予定・参加中（LiveStair の参加）
    static let going = Color(red: 0.32, green: 0.62, blue: 0.46)
    /// 興味あり（LiveStair の迷い中）
    static let considering = Color(red: 0.84, green: 0.62, blue: 0.10)
    /// キャンセル（LiveStair の中止）
    static let canceled = Color(red: 0.82, green: 0.30, blue: 0.30)
    /// リザーバー（LiveStair の延期）
    static let reserve = Color(red: 0.88, green: 0.55, blue: 0.18)
    /// 観覧（LiveStair の落選）
    static let spectator = Color(red: 0.52, green: 0.45, blue: 0.70)
    /// 主催・運営（LiveStair の取り置き）
    static let staff = Color(red: 0.76, green: 0.55, blue: 0.28)

    static func state(_ state: ParticipationState) -> Color {
        switch state {
        case .upcoming, .ongoing, .completed: return going
        case .interested: return considering
        case .canceled: return canceled
        case .unjoined: return Color.gray
        }
    }
    static func role(_ role: GiriSelfRole) -> Color {
        switch role {
        case .player: return going
        case .staff: return staff
        case .spectator: return spectator
        case .reserve: return reserve
        }
    }
    /// 会の種類（LiveStair のライブの種類と同じく、種類ごとの色）。
    static func meeting(_ type: MeetingType) -> Color {
        type == .tournament ? AppSectionAccent.ticket : AppSectionAccent.artist
    }
    static func meeting(_ event: GiriEvent) -> Color {
        event.isKumiteEvent ? AppSectionAccent.favorite : event.isProjectEvent ? AppSectionAccent.venue : meeting(event.meetingType)
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
    static func kindTitle(_ kind: EventKind) -> String { kind == .live ? "生大喜利" : "ネット大喜利（長考）" }
    static func formatBadgeTitle(_ format: EventFormat) -> String {
        switch format { case .live: "生大喜利"; case .onlineLong: "長考"; case .onlineShort: "短考"; case .hybrid: "スプシ系" }
    }
    static func symbol(_ format: EventFormat) -> String {
        switch format { case .live: "person.2.fill"; case .onlineLong: "globe"; case .onlineShort: "bolt.fill"; case .hybrid: "arrow.triangle.merge" }
    }
    static func accent(_ format: EventFormat) -> Color {
        switch format { case .live: AppSectionAccent.live; case .onlineLong: AppSectionAccent.artist; case .onlineShort: AppSectionAccent.scan; case .hybrid: AppSectionAccent.venue }
    }
    static func statusTitle(_ status: EventStatus) -> String {
        switch status { case .planned: "参加予定"; case .attended: "参加済"; case .canceled: "キャンセル" }
    }
    static func accent(_ event: GiriEvent) -> Color { accent(event.eventFormat) }
    // The meeting type controls the card rail/background. Format colors remain
    // unchanged for the format tabs and the calendar's four-category legend.
    static func cardAccent(_ event: GiriEvent) -> Color {
        // 大会・企画は、通常の会と色を分ける（企画は札と同じ色）。
        let base = event.meetingType == .tournament ? AppSectionAccent.ticket
            : event.isKumiteEvent ? AppSectionAccent.favorite
            : event.isProjectEvent ? AppSectionAccent.venue : accent(event.eventFormat)
        // 観覧の会は、参加する会と見分けられるように少し色を変える。
        if event.eventFormat == .live && event.selfRole == .spectator { return base.mix(with: GiriBadgeColors.spectator, by: 0.55) }
        return base
    }
    static func date(_ event: GiriEvent, now: Date = Date()) -> Date? {
        if !event.eventFormat.hasOnlineRounds || event.effectiveRounds.isEmpty { return event.eventDate ?? event.startsAt }
        var dates = event.effectiveRounds.flatMap { round -> [Date] in
            var dates: [Date] = []
            if round.submissionEnabled, let date = round.submissionEnd { dates.append(date) }
            if round.votingRequired, let date = round.votingEnd { dates.append(date) }
            return dates
        }
        if event.eventFormat.hasLiveTiming, let date = event.eventDate ?? event.startsAt { dates.append(date) }
        dates.sort()
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
        if event.meetingType == .tournament {
            if let number = giriRoundNumberText(round, in: event.effectiveRounds) { parts.append(number) }
        } else if round.promptNumber > 1 { parts.append("\(round.promptNumber)回目") }
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
        // 例：予選1位通過・本戦1回戦敗退／決勝 優勝
        let progress = event.resultProgressSummary
        if !progress.isEmpty { return progress }
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
