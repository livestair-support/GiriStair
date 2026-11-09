import SwiftUI
import PhotosUI
import UIKit
import ImageIO

/// 「＋」から開く新しいお題・回答の初期値。
struct GiriThoughtCreation: Identifiable {
    let id = UUID()
    var kind: NoteKind = .answers
    var eventID: String? = nil
    var roundID: String? = nil
    var resultStageID: String? = nil
    var format: EventFormat? = nil
}

// 回答モードは一覧・戦績と同じ形式タブ。長考は投稿中のお題で回答案を作り、
// それ以外の形式は会ごとにお題・自分の回答・ツボ（他の人の回答）をまとめる。
// Card lists use the source LiveListEventCard directly in a full-width scroll
// container. Grouped List row backgrounds/insets must not wrap these cards.
@MainActor
struct GiriThinkingView: View {
    @EnvironmentObject private var store: GiriStore
    @EnvironmentObject private var navigation: GiriNavigation
    @State private var promptMode = false
    @State private var selectedFormat: EventFormat = .onlineLong
    @State private var didInitializeFormat = false
    @State private var search = ""
    @State private var path: [GiriThoughtDestination] = []
    @State private var usedFilter = "all"
    @State private var editing: ThoughtNote?
    @State private var creating: GiriThoughtCreation?
    @State private var deleteCandidate: ThoughtNote?

    var body: some View {
        NavigationStack(path: $path) {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                thoughtList(now: timeline.date)
            }
            .safeAreaInset(edge: .top, spacing: 0) { pageHeader }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editing) { note in
                NavigationStack { GiriThoughtEditor(note: note) }
            }
            .sheet(item: $creating) { request in
                NavigationStack {
                    GiriThoughtEditor(kind: request.kind, eventID: request.eventID, roundID: request.roundID,
                                      resultStageID: request.resultStageID, preferredFormat: request.format)
                }
            }
            .navigationDestination(for: GiriThoughtDestination.self) { destination in
                switch destination {
                case .event(let id): GiriThoughtsForEvent(eventID: id)
                case .site(let id): GiriThoughtsForSite(siteID: id)
                case .round(let eventID, let roundID): GiriRoundWorkspace(eventID: eventID, roundID: roundID)
                case .note(let id): GiriThoughtNotePage(noteID: id)
                case .answerer(let name): GiriThoughtsForPerson(name: name, role: .answerer)
                case .author(let name): GiriThoughtsForPerson(name: name, role: .author)
                }
            }
            .giriDeleteAlert(deleteCandidate.map(thoughtDeleteTitle) ?? "削除しますか？",
                             isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
                             message: deleteCandidate.map { "「\(thoughtTitle($0))」を削除します。" } ?? "") {
                guard let note = deleteCandidate else { return }
                store.run { try store.deleteNote(note.id); playLiveStairDeleteFeedback() }
                deleteCandidate = nil
            }
        }
        .onAppear {
            if !didInitializeFormat {
                selectedFormat = store.preferences.visibleFormatOrder.first ?? .live
                didInitializeFormat = true
            }
            consumeDestination()
        }
        .onChange(of: navigation.thoughtDestination) { _, _ in consumeDestination() }
        .onChange(of: store.preferences.visibleFormatOrder) { previous, next in
            if selectedFormat == previous.first || !next.contains(selectedFormat) { selectedFormat = next.first ?? .live }
        }
    }

    private func consumeDestination() {
        guard let destination = navigation.thoughtDestination else { return }
        promptMode = false
        let eventID: String?
        switch destination {
        case .event(let id): eventID = id
        case .round(let id, _): eventID = id
        default: eventID = nil
        }
        if let format = eventID.flatMap({ id in store.events.first { $0.id == id }?.eventFormat }),
           store.preferences.isFormatVisible(format) {
            selectedFormat = format
        }
        path = [destination]
        navigation.thoughtDestination = nil
    }

    private var pageHeader: some View {
        AppPageHeader(title: "お題/回答", systemImage: promptMode ? "lightbulb" : "text.bubble", accentColor: AppSectionAccent.memo)
            .overlay(alignment: .trailing) {
                HStack(spacing: 10) {
                    Button { promptMode.toggle() } label: {
                        headerIcon(promptMode ? "text.bubble" : "lightbulb")
                    }
                    .accessibilityLabel(promptMode ? "回答モードに切り替える" : "お題モードに切り替える")
                    Button { creating = newCreation() } label: { headerIcon("plus") }
                        .accessibilityLabel(promptMode ? "お題を作る" : "お題・回答を記録する")
                        .contextMenu {
                            Button("自由メモを作る", systemImage: "square.and.pencil") { creating = GiriThoughtCreation(kind: .free) }
                        }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 18)
            }
    }

    private func headerIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: appFontSize(19), weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .background(appCardColor).clipShape(Circle())
            .overlay { Circle().stroke(Color.primary.opacity(0.10), lineWidth: 1) }
    }

    /// すぐメモ：選んでいる形式で、当日・開催中の会があれば最初から紐付ける（後から変更可）。
    private func newCreation() -> GiriThoughtCreation {
        if promptMode { return GiriThoughtCreation(kind: .prompts) }
        return GiriThoughtCreation(kind: .answers, eventID: suggestedEventID(selectedFormat), format: selectedFormat)
    }

    private func suggestedEventID(_ format: EventFormat) -> String? {
        guard format != .onlineLong else { return nil }
        let now = Date()
        return store.events.filter { $0.eventFormat == format && $0.isActualParticipant }.first { event in
            if event.participationState(now: now) == .ongoing { return true }
            guard let day = event.eventDate ?? event.startsAt else { return false }
            return Calendar.current.isDate(day, inSameDayAs: now)
        }?.id
    }

    private func thoughtList(now: Date) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                filters
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                if promptMode {
                    promptContent
                } else if selectedFormat == .onlineLong {
                    longContent(now: now)
                } else {
                    formatContent
                }
            }.padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(appBackgroundColor)
    }

    private var filters: some View {
        VStack(spacing: 12) {
            if promptMode {
                HStack {
                    Text("使用状況").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Picker("使用状況", selection: $usedFilter) {
                        Text("すべて").tag("all")
                        Text("未使用").tag("unused")
                        Text("使用済み").tag("used")
                    }.labelsHidden().pickerStyle(.menu).tint(.primary)
                }
            } else {
                GiriFormatPicker(selection: $selectedFormat, formats: store.preferences.visibleFormatOrder, identifier: "thought-format-tabs")
            }
            AppSearchField(text: $search, placeholder: promptMode ? "お題・メモを検索" : "お題・回答・回答者・作題者・会を検索")
        }
    }

    private func eventFor(_ note: ThoughtNote) -> GiriEvent? { store.events.first { $0.id == note.eventId } }

    private func formatNotes(_ format: EventFormat) -> [ThoughtNote] {
        // 参加していないお題は下に分ける。
        giriParticipationOrdered(store.notes.filter { $0.kind == .answers && $0.effectiveFormat(event: eventFor($0)) == format }
            .sorted { $0.updatedAt > $1.updatedAt })
    }

    @ViewBuilder private var promptContent: some View {
        let prompts = store.notes.filter {
            $0.kind == .prompts && (usedFilter == "all" || $0.used == (usedFilter == "used")) && thoughtSearchMatches($0, event: eventFor($0), query: search)
        }.sorted { $0.updatedAt > $1.updatedAt }
        thoughtSectionHeading("保存したお題", symbol: "lightbulb", count: prompts.count)
        if prompts.isEmpty {
            emptyCard(search.isEmpty ? "お題がありません" : "該当する記録がありません", symbol: "lightbulb")
        }
        ForEach(prompts) { note in noteRow(note) }
        let free = store.notes.filter { $0.kind == .free && thoughtSearchMatches($0, event: eventFor($0), query: search) }
            .sorted { $0.updatedAt > $1.updatedAt }
        if !free.isEmpty {
            thoughtSectionHeading("自由メモ", symbol: "square.and.pencil", count: free.count)
            ForEach(free) { note in noteRow(note) }
        }
    }

    @ViewBuilder private func longContent(now: Date) -> some View {
        let postings = activePostingGroups(now: now)
        let activeIDs = Set(postings.flatMap { $0.notes.map(\.id) })
        let history = formatNotes(.onlineLong).filter { !activeIDs.contains($0.id) && thoughtSearchMatches($0, event: eventFor($0), query: search) }
        thoughtSectionHeading("投稿中のお題", symbol: "clock", count: postings.reduce(0) { $0 + max(1, $1.notes.count) })
        if postings.isEmpty {
            emptyCard("現在投稿中のお題はありません", symbol: "text.bubble")
        }
        ForEach(postings) { posting in
            postingGroup(posting, now: now)
        }
        thoughtSectionHeading("履歴", symbol: "text.bubble", count: history.count)
        if history.isEmpty {
            emptyCard(search.isEmpty ? "回答の記録がありません" : "該当する記録がありません", symbol: "text.bubble")
        }
        ForEach(history) { note in noteRow(note) }
    }

    /// 生・短考・スプシ系：会ごとにお題をまとめ、会に紐付けていない記録は下に出す。
    @ViewBuilder private var formatContent: some View {
        if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let events = eventsWithNotes(selectedFormat)
            thoughtSectionHeading("会ごとのお題", symbol: "calendar", count: events.count)
            if events.isEmpty {
                emptyCard("お題の記録がありません", symbol: "text.bubble")
            }
            ForEach(events) { event in
                NavigationLink(value: GiriThoughtDestination.event(event.id)) { GiriThoughtEventCard(event: event) }
                    .buttonStyle(.plain).thoughtCardRow()
            }
            let loose = formatNotes(selectedFormat).filter { eventFor($0) == nil }
            if !loose.isEmpty {
                thoughtSectionHeading("会に紐付けていないお題", symbol: "tray", count: loose.count)
                ForEach(loose) { note in noteRow(note) }
            }
        } else {
            let matches = formatNotes(selectedFormat).filter { thoughtSearchMatches($0, event: eventFor($0), query: search) }
            thoughtSectionHeading("検索結果", symbol: "magnifyingglass", count: matches.count)
            if matches.isEmpty {
                emptyCard("該当する記録がありません", symbol: "text.bubble")
            }
            ForEach(matches) { note in noteRow(note) }
        }
    }

    private func eventsWithNotes(_ format: EventFormat) -> [GiriEvent] {
        let ids = Set(store.notes.filter { $0.kind == .answers }.compactMap(\.eventId))
        return store.events.filter { ids.contains($0.id) && $0.eventFormat == format }
            .sorted { thoughtEventDate($0) > thoughtEventDate($1) }
    }

    private func noteRow(_ note: ThoughtNote) -> some View {
        Button { path.append(.note(note.id)) } label: {
            GiriThoughtCard(note: note, event: eventFor(note))
        }
        .buttonStyle(.plain).thoughtCardRow()
        .contextMenu { noteMenu(note) }
    }

    private func activePostingGroups(now: Date) -> [ThoughtPostingGroup] {
        store.events.filter { $0.eventFormat == .onlineLong && $0.isActualParticipant }.flatMap { event in
            event.effectiveRounds.filter { $0.isSubmissionOpen(now) }.map { round in
                ThoughtPostingGroup(event: event, round: round,
                    notes: giriParticipationOrdered(store.notes.filter { note in
                        note.kind == .answers && thoughtMatches(note, eventID: event.id, roundID: round.id)
                    }.sorted { $0.updatedAt > $1.updatedAt }))
            }
        }.sorted { ($0.round.submissionEnd ?? .distantFuture) < ($1.round.submissionEnd ?? .distantFuture) }
    }

    @ViewBuilder private func postingGroup(_ posting: ThoughtPostingGroup, now: Date) -> some View {
        if posting.notes.isEmpty {
            Button { path.append(.round(eventID: posting.event.id, roundID: posting.round.id)) } label: {
                GiriListCard(accentColor: AppSectionAccent.artist) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(posting.event.title).font(.headline).foregroundStyle(.primary)
                        Text(thoughtRoundLabel(event: posting.event, round: posting.round)).font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            Text("投稿中").font(.subheadline.weight(.semibold)).foregroundStyle(AppSectionAccent.artist)
                            if let end = posting.round.submissionEnd {
                                Text("締切 \(GiriDateText.dateTime(end))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Label("お題・回答案を追加", systemImage: "plus.circle").font(.subheadline).foregroundStyle(accentActionColor)
                    }.padding(.trailing, 18)
                }
            }.buttonStyle(.plain).thoughtCardRow()
        } else {
            ForEach(posting.notes) { note in
                Button { path.append(.note(note.id)) } label: { GiriThoughtCard(note: note, event: posting.event) }
                    .buttonStyle(.plain).thoughtCardRow()
                    .contextMenu { noteMenu(note) }
            }
        }
    }

    @ViewBuilder private func noteMenu(_ note: ThoughtNote) -> some View {
        Button("編集", systemImage: "pencil") { editing = note }
        if note.kind == .prompts {
            Button(note.used ? "未使用に戻す" : "使用済みにする", systemImage: note.used ? "arrow.uturn.backward" : "checkmark.circle") {
                var changed = note; changed.used.toggle(); changed.updatedAt = Date()
                store.run { try store.saveNote(changed) }
            }
        } else if note.kind == .answers {
            GiriThoughtShareActions(note: note, event: eventFor(note))
        }
        Button("削除", systemImage: "trash", role: .destructive) { deleteCandidate = note }
    }

    private func emptyCard(_ title: String, symbol: String) -> some View {
        CenteredEmptyMessage(systemImage: symbol, title: title)
            .frame(maxWidth: .infinity, minHeight: 108)
            .appTintedCard(accentColor: AppSectionAccent.memo)
            .thoughtCardRow()
    }
}

private struct ThoughtPostingGroup: Identifiable {
    let event: GiriEvent
    let round: EventRound
    let notes: [ThoughtNote]
    var id: String { event.id + ":" + round.id }
}

private func thoughtSectionHeading(_ title: String, symbol: String, count: Int) -> some View {
    HStack(spacing: 10) {
        AppCardSectionTitle(title: title, systemImage: symbol, accentColor: AppSectionAccent.memo)
        Spacer(minLength: 8)
        Text("\(count)件").font(.caption).foregroundStyle(.secondary)
    }.padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 8)
}

private extension View {
    func thoughtCardRow() -> some View {
        self.padding(.horizontal, 18).padding(.vertical, 6)
    }
}

/// Latest cycles first. Affiliation and result are each cycle's snapshot.
@MainActor
struct GiriThoughtsForSite: View {
    @EnvironmentObject private var store: GiriStore
    let siteID: String
    @State private var search = ""
    private var site: OnlineSite? { store.onlineSites.first { $0.id == siteID } }
    private var cycles: [GiriEvent] {
        store.events.filter { event in
            guard event.onlineSiteId == siteID &&
                (event.isActualParticipant || store.notes.contains(where: { $0.eventId == event.id })) else { return false }
            let text = [event.title, event.affiliation, event.cycleResult, event.block].joined(separator: " ")
            return search.isEmpty || text.localizedStandardContains(search) || store.notes.contains {
                $0.eventId == event.id && thoughtSearchMatches($0, event: event, query: search)
            }
        }.sorted { thoughtEventDate($0) > thoughtEventDate($1) }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                AppSearchField(text: $search, placeholder: "所属・結果・お題・回答を検索")
                    .padding(.horizontal, 18).padding(.vertical, 8)
                if cycles.isEmpty {
                    CenteredEmptyMessage(systemImage: "globe", title: "回答の記録がありません")
                        .frame(maxWidth: .infinity, minHeight: 108)
                }
                ForEach(cycles) { event in
                    NavigationLink(value: GiriThoughtDestination.event(event.id)) { GiriThoughtEventCard(event: event) }
                        .buttonStyle(.plain).thoughtCardRow()
                }
            }.padding(.bottom, 24)
        }.background(appBackgroundColor).scrollDismissesKeyboard(.interactively)
            .navigationTitle(site?.name ?? "サイトの回答")
            .navigationBarTitleDisplayMode(.inline).giriNavigationBarStyle()
    }
}

private struct ThoughtStageGroup: Identifiable {
    let id: String
    let title: String
    let notes: [ThoughtNote]
}

/// 会のお題一覧。ネットは回（投稿期間）ごと、生・スプシ系などは大会の段階ごとにお題を並べる。
@MainActor
struct GiriThoughtsForEvent: View {
    @EnvironmentObject private var store: GiriStore
    let eventID: String
    @State private var creating: GiriThoughtCreation?
    @State private var bulkAdding = false
    @State private var search = ""
    private var event: GiriEvent? { store.events.first { $0.id == eventID } }
    private var notes: [ThoughtNote] {
        store.notes.filter { $0.eventId == eventID && $0.kind != .prompts && thoughtSearchMatches($0, event: event, query: search) }
            .sorted { $0.createdAt < $1.createdAt }
    }
    private var rounds: [EventRound] {
        (event?.effectiveRounds ?? []).sorted {
            ($0.submissionStart ?? $0.votingEnd ?? .distantPast) > ($1.submissionStart ?? $1.votingEnd ?? .distantPast)
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let event {
                    header(event).thoughtCardRow()
                    AppSearchField(text: $search, placeholder: "お題・回答・回答者・作題者を検索")
                        .padding(.horizontal, 18).padding(.vertical, 8)
                    if event.eventFormat.hasOnlineRounds && !rounds.isEmpty {
                        onlineContent(event)
                    } else {
                        let groups = stageGroups(event)
                        if groups.isEmpty {
                            CenteredEmptyMessage(systemImage: "text.bubble", title: search.isEmpty ? "お題の記録がありません" : "該当する記録がありません")
                                .frame(maxWidth: .infinity, minHeight: 108)
                                .appTintedCard(accentColor: AppSectionAccent.memo)
                                .thoughtCardRow()
                        }
                        ForEach(groups) { group in
                            thoughtSectionHeading(group.title, symbol: "flag", count: group.notes.count)
                            ForEach(Array(group.notes.enumerated()), id: \.element.id) { index, note in
                                NavigationLink(value: GiriThoughtDestination.note(note.id)) {
                                    GiriThoughtCard(note: note, event: event, number: index + 1)
                                }.buttonStyle(.plain).thoughtCardRow()
                            }
                        }
                    }
                    Button { creating = GiriThoughtCreation(kind: .answers, eventID: eventID, format: event.eventFormat) } label: {
                        Label("お題を追加", systemImage: "plus.circle").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain).foregroundStyle(accentActionColor)
                    .padding(14).appTintedCard(accentColor: AppSectionAccent.memo).thoughtCardRow()
                    Button { bulkAdding = true } label: {
                        Label("会のお題をまとめて入れる", systemImage: "list.bullet.rectangle").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain).foregroundStyle(accentActionColor)
                    .padding(14).appTintedCard(accentColor: AppSectionAccent.memo).thoughtCardRow()
                } else {
                    CenteredEmptyMessage(systemImage: "text.bubble", title: "この会は削除されています")
                }
            }.padding(.bottom, 24)
        }
        .background(appBackgroundColor).scrollDismissesKeyboard(.interactively)
        .navigationTitle("お題/回答").navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
        .sheet(item: $creating) { request in
            NavigationStack {
                GiriThoughtEditor(kind: request.kind, eventID: request.eventID, roundID: request.roundID,
                                  resultStageID: request.resultStageID, preferredFormat: request.format)
            }
        }
        .sheet(isPresented: $bulkAdding) { NavigationStack { GiriBulkPromptEditor(eventID: eventID) } }
    }

    private func header(_ event: GiriEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AppCardSectionTitle(title: event.title, systemImage: thoughtFormatSymbol(event.eventFormat), accentColor: GiriEventPresentation.accent(event))
            HStack(spacing: 8) {
                Text(event.eventFormat.title)
                if let date = GiriEventPresentation.date(event) { Text(GiriDateText.day(date, compact: true)) }
            }.font(.subheadline).foregroundStyle(.secondary)
            if !event.hashtag.isEmpty {
                Text("#" + event.hashtag).font(.subheadline.weight(.semibold)).foregroundStyle(accentActionColor).textSelection(.enabled)
            }
            if event.meetingType == .tournament {
                let summary = event.resultProgressSummary
                if !summary.isEmpty { Text(summary).font(.subheadline.weight(.semibold)).foregroundStyle(AppSectionAccent.ticket) }
            }
            if !event.affiliation.isEmpty { LabeledContent("所属", value: event.affiliation) }
            if !event.cycleResult.isEmpty { LabeledContent("結果", value: event.cycleResult) }
            if let rank = event.cyclePlacement { LabeledContent("順位", value: "\(rank)位") }
        }
        .padding(14).appTintedCard(accentColor: GiriEventPresentation.accent(event))
    }

    @ViewBuilder private func onlineContent(_ event: GiriEvent) -> some View {
        let matching = rounds.filter { round in
            search.isEmpty || round.name.localizedStandardContains(search) || notes.contains { thoughtMatches($0, eventID: eventID, roundID: round.id) }
        }
        ForEach(matching) { round in
            NavigationLink(value: GiriThoughtDestination.round(eventID: eventID, roundID: round.id)) {
                GiriThoughtRoundCard(event: event, round: round)
            }.buttonStyle(.plain).thoughtCardRow()
        }
        let loose = notes.filter { note in note.roundId == nil || !rounds.contains { $0.id == note.roundId } }
        ForEach(loose) { note in
            NavigationLink(value: GiriThoughtDestination.note(note.id)) { GiriThoughtCard(note: note, event: event) }
                .buttonStyle(.plain).thoughtCardRow()
        }
    }

    private func stageGroups(_ event: GiriEvent) -> [ThoughtStageGroup] {
        // 参加していないお題（参加していないブロックのお題など）は、いちばん下にまとめる。
        let all = notes.filter(\.isParticipatingPrompt)
        let notJoined = notes.filter { !$0.isParticipatingPrompt }
        let stages = event.stageResults
        var groups: [ThoughtStageGroup] = stages.compactMap { stage in
            let items = all.filter { $0.resultStageId == stage.id }
            return items.isEmpty ? nil : ThoughtStageGroup(id: stage.id, title: stage.name.isEmpty ? "段階" : stage.name, notes: items)
        }
        let known = Set(stages.map(\.id))
        let rest = all.filter { note in note.resultStageId.map { !known.contains($0) } ?? true }
        if !rest.isEmpty {
            groups.append(ThoughtStageGroup(id: "none", title: stages.isEmpty ? "お題" : "段階を選んでいないお題", notes: rest))
        }
        if !notJoined.isEmpty {
            groups.append(ThoughtStageGroup(id: "not-joined", title: "参加していないお題", notes: notJoined))
        }
        return groups
    }
}

enum GiriThoughtPersonRole { case answerer, author }

/// プレイヤー詳細から開く「好きな回答」（その人のツボ）と「作ったお題」。
@MainActor
struct GiriThoughtsForPerson: View {
    @EnvironmentObject private var store: GiriStore
    let name: String
    let role: GiriThoughtPersonRole
    @State private var search = ""
    private var key: String { playerSearchKey(name) }
    private var notes: [ThoughtNote] {
        store.notes.filter { note in
            let matches = role == .author ? playerSearchKey(note.promptAuthor) == key
                : note.otherAnswerRecords.contains { playerSearchKey($0.answerer) == key }
            return matches && thoughtSearchMatches(note, event: store.events.first { $0.id == note.eventId }, query: search)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                AppSearchField(text: $search, placeholder: "お題・回答・会を検索")
                    .padding(.horizontal, 18).padding(.vertical, 8)
                let values = notes
                if values.isEmpty {
                    CenteredEmptyMessage(systemImage: role == .author ? "lightbulb" : "text.bubble",
                                         title: search.isEmpty ? (role == .author ? "作ったお題の記録がありません" : "好きな回答の記録がありません") : "該当する記録がありません")
                        .frame(maxWidth: .infinity, minHeight: 108)
                        .appTintedCard(accentColor: AppSectionAccent.memo)
                        .thoughtCardRow()
                }
                ForEach(values) { note in
                    NavigationLink(value: GiriThoughtDestination.note(note.id)) {
                        if role == .author {
                            GiriThoughtCard(note: note, event: store.events.first { $0.id == note.eventId })
                        } else {
                            answerCard(note)
                        }
                    }.buttonStyle(.plain).thoughtCardRow()
                }
            }.padding(.bottom, 24)
        }
        .background(appBackgroundColor).scrollDismissesKeyboard(.interactively)
        .navigationTitle(role == .author ? "\(name)の作ったお題" : "\(name)の回答")
        .navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
    }

    private func answerCard(_ note: ThoughtNote) -> some View {
        let records = note.otherAnswerRecords.filter { playerSearchKey($0.answerer) == key }
        let event = store.events.first { $0.id == note.eventId }
        return GiriListCard(accentColor: AppSectionAccent.favorite) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(records) { record in
                    Text("「\(record.text)」").font(.headline).foregroundStyle(.primary).lineLimit(4)
                }
                Text(thoughtTitle(note)).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                if let event { Text(event.title).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 18)
        }
    }
}

private struct GiriThoughtEventCard: View {
    @EnvironmentObject private var store: GiriStore
    let event: GiriEvent
    var body: some View {
        let notes = store.notes.filter { $0.eventId == event.id && $0.kind == .answers }
        let own = notes.reduce(0) { $0 + $1.ownAnswerRecords.count }
        let tsubo = notes.reduce(0) { $0 + $1.otherAnswerRecords.count }
        GiriListCard(accentColor: GiriEventPresentation.cardAccent(event)) {
            VStack(alignment: .leading, spacing: 6) {
                Text(GiriDateText.day(thoughtEventDate(event))).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                HStack {
                    Text(event.title).font(.headline).foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if event.eventFormat.hasOnlineRounds {
                        Text(thoughtPhase(event: event, round: thoughtNewestRound(event))).font(.caption.weight(.semibold)).foregroundStyle(AppSectionAccent.artist)
                    }
                }
                let cycleLabels = [event.siteSeason, event.siteCycleNumber.map { "第\($0)回" } ?? "", event.affiliation].filter { !$0.isEmpty }
                if !cycleLabels.isEmpty { Text(cycleLabels.joined(separator: "・")).font(.subheadline).foregroundStyle(.secondary) }
                if event.meetingType == .tournament {
                    let summary = event.resultProgressSummary
                    if !summary.isEmpty { Text(summary).font(.subheadline.weight(.semibold)).foregroundStyle(AppSectionAccent.ticket) }
                }
                if !event.cycleResult.isEmpty { Text(event.cycleResult).font(.subheadline).foregroundStyle(.secondary) }
                if let rank = event.cyclePlacement { Text("\(rank)位").font(.subheadline.weight(.semibold)).foregroundStyle(AppSectionAccent.ticket) }
                if !event.hashtag.isEmpty { Text("#" + event.hashtag).font(.caption).foregroundStyle(.secondary) }
                Text("お題\(notes.count)題・自分の回答\(own)件・ツボ\(tsubo)件").font(.caption).foregroundStyle(.secondary)
            }.padding(.trailing, 18)
        }
    }
}

private struct GiriThoughtRoundCard: View {
    @EnvironmentObject private var store: GiriStore
    let event: GiriEvent
    let round: EventRound
    var body: some View {
        GiriListCard(accentColor: AppSectionAccent.artist) {
            VStack(alignment: .leading, spacing: 6) {
                Text(thoughtRoundLabel(event: event, round: round)).font(.headline).foregroundStyle(.primary)
                Text(thoughtPhase(event: event, round: round)).font(.subheadline.weight(.semibold)).foregroundStyle(AppSectionAccent.artist)
                if let end = round.votingEnd ?? round.submissionEnd {
                    Text("締切 \(GiriDateText.dateTime(end))").font(.caption).foregroundStyle(.secondary)
                }
                let notes = store.notes.filter { $0.kind == .answers && thoughtMatches($0, eventID: event.id, roundID: round.id) }
                Text("\(notes.count)題").font(.caption).foregroundStyle(.secondary)
                if let result = event.tournamentResult?.stages.last(where: { $0.roundId == round.id || ($0.roundId == nil && $0.stageId == round.effectiveStageId) }) {
                    Text(thoughtStageSummary(result)).font(.caption.weight(.medium)).foregroundStyle(AppSectionAccent.ticket)
                }
            }.padding(.trailing, 18)
        }
    }
}

@MainActor
struct GiriRoundWorkspace: View {
    @EnvironmentObject private var store: GiriStore
    let eventID: String
    let roundID: String
    var body: some View {
        Form { GiriRoundWorkspaceSections(eventID: eventID, roundID: roundID) }
            .appEditorFormStyle().navigationTitle("お題/回答")
            .navigationBarTitleDisplayMode(.inline).giriNavigationBarStyle()
    }
}

/// The period and its prompt cards are kept in the Thinking tab.
@MainActor
struct GiriRoundWorkspaceSections: View {
    @EnvironmentObject private var store: GiriStore
    @EnvironmentObject private var navigation: GiriNavigation
    let eventID: String
    let roundID: String
    @State private var editing: ThoughtNote?
    @State private var creating = false
    @State private var bulkAdding = false
    @State private var deleteCandidate: ThoughtNote?
    private var event: GiriEvent? { store.events.first { $0.id == eventID } }
    private var round: EventRound? { event?.effectiveRounds.first { $0.id == roundID } }
    private var notes: [ThoughtNote] {
        // 回答を足しても並びが動かないように、作った順（新しいお題が上）にする。
        giriParticipationOrdered(store.notes.filter { $0.kind == .answers && thoughtMatches($0, eventID: eventID, roundID: roundID) }
            .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt })
    }
    var body: some View {
        Group {
            periodSection
            ForEach(notes) { note in
                Section {
                    GiriThoughtNoteRows(note: note, event: event, onEdit: { editing = note })
                    HStack {
                        Button("編集", systemImage: "pencil") { editing = note }
                        Spacer()
                        Button("削除", systemImage: "trash", role: .destructive) { deleteCandidate = note }
                    }.buttonStyle(.borderless).tint(accentActionColor)
                }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
            }
            if round != nil {
                Section {
                    Button { creating = true } label: { Label("お題を追加", systemImage: "plus.circle") }
                        .tint(accentActionColor)
                    Button { bulkAdding = true } label: { Label("お題をまとめて入れる", systemImage: "list.bullet.rectangle") }
                        .tint(accentActionColor)
                }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
            }
        }
        .sheet(item: $editing) { note in NavigationStack { GiriThoughtEditor(note: note) } }
        .sheet(isPresented: $creating) {
            NavigationStack { GiriThoughtEditor(kind: .answers, eventID: eventID, roundID: roundID, preferredFormat: event?.eventFormat) }
        }
        .sheet(isPresented: $bulkAdding) { NavigationStack { GiriBulkPromptEditor(eventID: eventID, roundID: roundID) } }
        .giriDeleteAlert("お題と回答を削除しますか？",
                         isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
                         message: deleteCandidate.map { "「\(thoughtTitle($0))」を削除します。" } ?? "") {
            guard let note = deleteCandidate else { return }
            store.run { try store.deleteNote(note.id); playLiveStairDeleteFeedback() }
            deleteCandidate = nil
        }
    }
    private var periodSection: some View {
        Section {
            AppCardSectionTitle(title: event?.title ?? "削除された会", systemImage: "globe", accentColor: AppSectionAccent.artist)
                .listRowSeparator(.hidden)
            if let event, let round {
                HStack(alignment: .firstTextBaseline) {
                    Text(thoughtRoundLabel(event: event, round: round)).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    NavigationLink { GiriRoundEditor(eventID: eventID, round: round) } label: { Image(systemName: "pencil") }
                        .accessibilityLabel("日程を編集")
                }
                GiriThoughtScheduleDisclosure(event: event, round: round)
                if event.meetingType == .tournament {
                    Button { navigation.openResultEntry(eventID, roundID: roundID) } label: { Label("この回の結果", systemImage: "trophy") }
                        .tint(accentActionColor)
                }
            } else {
                Text("日程は削除されています。保存したお題と回答は残っています。").font(.subheadline).foregroundStyle(.secondary)
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }
}

@MainActor
private struct GiriThoughtNotePage: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    let noteID: String
    @State private var editing = false
    @State private var deleting = false
    /// 0.17：回答の欄のタブ（自分の回答・他人の回答）。
    @State private var mode: GiriAnswerMode = .own
    /// 0.18：お題を上に固定して、見ながら回答を考える。
    @State private var pinned = false
    private var note: ThoughtNote? { store.notes.first { $0.id == noteID } }
    private var event: GiriEvent? { store.events.first { $0.id == note?.eventId } }
    var body: some View {
        ScrollViewReader { proxy in
            pageForm.environment(\.giriRevealPosting, { giriRevealPostingForm(proxy) })
        }
        .navigationTitle(note?.kind == .prompts ? "お題" : note?.kind == .free ? "メモ" : "お題/回答")
    }

    private var pageForm: some View {
        Form {
            if let note {
                // 固定している時は、締切などの会の情報は出さない。
                if !pinned { contextSection(note) }
                if note.kind == .answers {
                    GiriNoteSections(note: note, event: event, mode: $mode, pinned: $pinned)
                } else {
                    Section { GiriThoughtNoteRows(note: note, event: event, onEdit: { editing = true }) }
                        .appSectionCardStyle(accentColor: AppSectionAccent.memo)
                }
            } else {
                CenteredEmptyMessage(systemImage: "text.bubble", title: "このメモは削除されています")
            }
        }
        .appEditorFormStyle()
        .safeAreaInset(edge: .top, spacing: 0) {
            if pinned, let note { GiriPinnedPrompt(note: note) { withAnimation { pinned = false } } }
        }
        .navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
        .toolbar {
            if let note {
                // LiveDetailView と同じ並び：共有 → 削除 → 編集
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if note.kind == .answers {
                        Menu { GiriThoughtShareActions(note: note, event: event) } label: {
                            Image(systemName: "square.and.arrow.up").foregroundStyle(accentActionColor)
                        }
                        .accessibilityLabel("お題・回答を共有")
                    }
                    Button(role: .destructive) { deleting = true } label: {
                        Image(systemName: "trash").foregroundStyle(accentActionColor)
                    }
                    .accessibilityLabel("削除")
                    Button("編集") { editing = true }
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let note { NavigationStack { GiriThoughtEditor(note: note) } }
        }
        .giriDeleteAlert(note.map(thoughtDeleteTitle) ?? "削除しますか？", isPresented: $deleting,
                         message: "「\(note.map(thoughtTitle) ?? "")」を削除します。") {
            store.run {
                try store.deleteNote(noteID)
                playLiveStairDeleteFeedback()
                dismiss()
            }
        }
    }

    /// 大会は「この大会の」、ネット大喜利の通常のサイトは「このサイトの」、それ以外は「この会の」お題一覧。
    @ViewBuilder private func listLink(_ event: GiriEvent) -> some View {
        if event.meetingType == .tournament {
            NavigationLink(value: GiriThoughtDestination.event(event.id)) { listLabel("この大会のお題一覧") }
        } else if let siteID = event.onlineSiteId, event.eventFormat.hasOnlineRounds {
            NavigationLink(value: GiriThoughtDestination.site(siteID)) { listLabel("このサイトのお題一覧") }
        } else {
            NavigationLink(value: GiriThoughtDestination.event(event.id)) { listLabel("この会のお題一覧") }
        }
    }

    private func listLabel(_ title: String) -> some View {
        Label { Text(title).foregroundStyle(.primary) } icon: { Image(systemName: "list.bullet").foregroundStyle(accentActionColor) }
    }

    @ViewBuilder private func contextSection(_ note: ThoughtNote) -> some View {
        if let event {
            Section {
                AppCardSectionTitle(title: event.title, systemImage: thoughtFormatSymbol(event.eventFormat), accentColor: AppSectionAccent.artist)
                    .listRowSeparator(.hidden)
                if let round = event.effectiveRounds.first(where: { $0.id == (note.roundId ?? "legacy") }), event.eventFormat.hasOnlineRounds {
                    Text(thoughtRoundLabel(event: event, round: round)).font(.subheadline.weight(.semibold))
                    GiriThoughtScheduleDisclosure(event: event, round: round)
                } else if let stage = event.stageResults.first(where: { $0.id == note.resultStageId }) {
                    Text(stage.name).font(.subheadline.weight(.semibold))
                    let detail = [stage.group, stage.lineup, stage.judging].filter { !$0.isEmpty }
                    if !detail.isEmpty { Text(detail.joined(separator: "・")).font(.caption).foregroundStyle(.secondary) }
                } else if let date = GiriEventPresentation.date(event) {
                    Text(GiriDateText.day(date)).font(.subheadline).foregroundStyle(.secondary)
                }
                listLink(event)
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
        }
    }
}

private struct GiriThoughtCard: View {
    let note: ThoughtNote
    let event: GiriEvent?
    var number: Int? = nil
    var body: some View {
        GiriListCard(accentColor: AppSectionAccent.memo) {
            HStack(alignment: .top, spacing: 12) {
                if let image = thoughtUIImage(note) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 6) {
                    if let number { Text("お題\(number)").font(.caption.weight(.semibold)).foregroundStyle(AppSectionAccent.memo) }
                    if note.kind == .answers && !note.isParticipatingPrompt {
                        Text("参加していないお題").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    }
                    Text(thoughtTitle(note)).font(.headline).foregroundStyle(.primary).lineLimit(3)
                    if note.kind == .prompts {
                        Text(note.used ? "使用済み" : "未使用").font(.subheadline).foregroundStyle(.secondary)
                        if let event { Text(event.title).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    } else if note.kind == .free {
                        if !note.body.isEmpty { Text(note.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
                    } else {
                        answerSummary
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.trailing, 18)
        }
    }

    @ViewBuilder private var answerSummary: some View {
        if let event, number == nil {
            Text(event.title + thoughtPlaceLabel(note, event: event)).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            if event.eventFormat == .onlineLong, let round = thoughtRound(note, event: event) {
                Text(thoughtPhase(event: event, round: round))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(AppSectionAccent.artist)
                let deadline = round.isSubmissionOpen(Date()) ? round.submissionEnd : round.votingEnd
                if let deadline {
                    Text("締切 " + GiriDateText.dateTime(deadline)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        if !note.promptAuthor.isEmpty {
            Text("作題　" + thoughtAuthorText(note)).font(.caption).foregroundStyle(.secondary)
        }
        let own = note.ownAnswerRecords
        if let featured = own.first(where: \.isSubmitted) ?? own.first, featured.text != thoughtTitle(note) {
            if note.effectivePromptStyle == .fill {
                GiriFilledPromptText(prompt: note.prompt, answer: featured.text).font(.subheadline).lineLimit(3)
            } else {
                Text(featured.text).font(.subheadline).foregroundStyle(.primary).lineLimit(3)
            }
        }
        let others = note.otherAnswerRecords
        if let first = others.first {
            Text("\(first.answerer)「\(first.text)」").font(.subheadline).foregroundStyle(.primary).lineLimit(2)
        }
        Text("自分の回答\(own.count)件・ツボ\(others.count)件").font(.caption).foregroundStyle(.secondary)
        let summary = thoughtResultSummary(note, event: event)
        if !summary.isEmpty { Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
    }
}

/// 押した時だけXの投稿画面・共有シートを開く（自動投稿はしない）。
/// お題の画像がある時は、画像と文を一緒に共有できる。
private struct GiriThoughtShareActions: View {
    let note: ThoughtNote
    let event: GiriEvent?
    var record: AnswerRecord? = nil
    var body: some View {
        let text = thoughtShareText(note, event: event, record: record)
        let imageText = thoughtShareText(note, event: event, record: record, includePrompt: false)
        if let url = thoughtTweetURL(note, event: event, record: record) {
            Link(destination: url) { Label("Xで投稿を作成", systemImage: "square.and.pencil") }
        }
        if let image = thoughtUIImage(note) {
            let picture = Image(uiImage: image)
            ShareLink(item: picture, message: Text(imageText), preview: SharePreview("お題の画像", image: picture)) {
                Label("お題の画像と共有", systemImage: "photo")
            }
        }
        ShareLink(item: text) {
            Label("文字で共有", systemImage: "square.and.arrow.up")
        }
    }
}

@MainActor
private struct GiriThoughtNoteRows: View {
    @EnvironmentObject private var store: GiriStore
    let note: ThoughtNote
    let event: GiriEvent?
    let onEdit: () -> Void
    /// 0.17：一覧（overview）・お題の欄・回答の欄（自分／他人のタブ）。
    var part: GiriNoteRowsPart = .overview
    /// 回答の欄のタブ（自分の回答・他人の回答）。
    var mode: Binding<GiriAnswerMode>? = nil
    /// 0.14：移動せずに足す回答（案）。
    @State private var newAnswer = ""
    @State private var newOtherAnswerer = ""
    @State private var newOtherAnswer = ""
    @FocusState private var addingAnswer: Bool
    /// 0.15：回答案の並び（追加順・印の順）。端末に残す。
    @AppStorage("giriAnswerOrder") private var answerOrder = GiriAnswerOrder.added.rawValue
    @Environment(\.giriRevealPosting) private var revealPosting
    @State private var editingAnswerID: String?
    @State private var editingAnswerText = ""
    private var isLong: Bool { note.effectiveFormat(event: event) == .onlineLong }
    private var order: GiriAnswerOrder { GiriAnswerOrder(rawValue: answerOrder) ?? .added }
    var body: some View {
        if part != .answers { promptRows }
        if note.kind == .answers {
            let own = note.ownAnswerRecords
            let others = note.otherAnswerRecords
            switch part {
            case .prompt:
                // 0.18：「このお題に参加」はお題の登録・編集で決める（この画面には出さない）。
                EmptyView()
            case .answers:
                Picker("回答", selection: modeBinding) {
                    ForEach(GiriAnswerMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                if modeBinding.wrappedValue == .own {
                    postingForm
                    ownList(own)
                } else {
                    othersPostingForm
                    othersList(others)
                }
                if !note.memo.isEmpty {
                    Text(note.memo).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                }
            case .overview:
                if !note.isParticipatingPrompt {
                    Label("参加していないお題", systemImage: "eye.slash").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                ownList(own)
                othersList(others)
                if !note.memo.isEmpty {
                    Text(note.memo).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if !note.usesAnswerRecords && !note.body.isEmpty && !note.answers.isEmpty {
                    Text(note.body).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        } else if !note.body.isEmpty {
            Text(note.body).textSelection(.enabled)
        }
    }

    @ViewBuilder private var promptRows: some View {
        Text(thoughtTitle(note)).font(.headline).textSelection(.enabled)
            // 一覧（overview）からの長押しの「編集」もここで開く。
            .sheet(isPresented: editingAnswerShown) { answerEditSheet }
        if !note.imageDataBase64.isEmpty {
            // 0.22：お題の画面では、固定してもしなくても同じ大きさで出す（一覧などはこれまでどおり）。
            if part == .prompt { GiriThoughtImage(base64: note.imageDataBase64).frame(maxHeight: giriPromptImageHeight) }
            else { GiriThoughtImage(base64: note.imageDataBase64) }
        }
        if !note.promptAuthor.isEmpty {
            HStack {
                Text("作題").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(thoughtAuthorText(note)).font(.subheadline.weight(.semibold))
            }
        }
    }

    private var modeBinding: Binding<GiriAnswerMode> { mode ?? .constant(.own) }

    /// 自分の回答の一覧（並びの切り替え・印・出す回答）。
    @ViewBuilder private func ownList(_ own: [AnswerRecord]) -> some View {
        if !own.isEmpty {
            HStack(spacing: 8) {
                Text(isLong ? "回答案（出す回答に印）" : "自分の回答").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if own.count > 1 {
                    // 並びはアイコンのプルダウンで選ぶ。
                    Menu {
                        Picker("並び", selection: $answerOrder) {
                            ForEach(GiriAnswerOrder.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(accentActionColor)
                            .frame(width: 32, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("回答の並び（\(order.title)）")
                }
            }
        }
        ForEach(giriSortedAnswers(own, order: order)) { record in ownRow(record) }
    }

    @ViewBuilder private func othersList(_ others: [AnswerRecord]) -> some View {
        if !others.isEmpty {
            Text("他人の回答（ツボ）").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        ForEach(others) { record in otherRow(record) }
    }

    /// このお題に参加したか。参加していないお題（参加していないブロックのお題を考えるなど）は一覧で下に分ける。
    private var participationToggle: some View {
        Toggle(isOn: Binding(get: { note.isParticipatingPrompt }, set: { value in
            var updated = note
            updated.participates = value
            updated.updatedAt = Date()
            store.run { try store.saveNote(updated) }
        })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("このお題に参加").font(.subheadline.weight(.semibold))
                Text("外すと、参加していないお題として一覧の下に出します。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .tint(AppSectionAccent.memo)
    }

    /// 他人の回答の投稿：回答者と回答を入れて「投稿」。
    private var othersPostingForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(editingOtherID == nil ? "他人の回答を投稿" : "他人の回答を編集").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            GiriPlayerSuggestionField(title: "回答者", text: $newOtherAnswerer)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.secondarySystemBackground)))
            TextField("回答を入力してください", text: $newOtherAnswer, axis: .vertical)
                .lineLimit(2...6)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.secondarySystemBackground)))
            postingButtons(editing: editingOtherID != nil, disabled: newOtherAnswerer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                           || newOtherAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           post: postOtherAnswer)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: editingAnswerShown) { answerEditSheet }
    }

    private func postOtherAnswer() {
        if let id = editingOtherID {
            let updated = giriNoteEditingAnswer(note, id: id, text: newOtherAnswer, answerer: newOtherAnswerer)
            store.run {
                try store.saveNote(updated)
                playLiveStairSaveFeedback()
                cancelEditing()
            }
            return
        }
        guard let updated = giriNoteAddingOtherAnswer(note, answerer: newOtherAnswerer, text: newOtherAnswer) else { return }
        store.run {
            try store.saveNote(updated)
            newOtherAnswer = ""
            newOtherAnswerer = ""
        }
    }

    private func ownRow(_ record: AnswerRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button { toggleSubmitted(record.id) } label: {
                    Image(systemName: record.isSubmitted ? "checkmark.square.fill" : "square")
                        .foregroundStyle(record.isSubmitted ? accentActionColor : Color.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(record.isSubmitted ? "提出した回答の印を外す" : "提出した回答にする")
                if !record.mark.isEmpty {
                    Text(record.mark).font(.subheadline.weight(.bold)).foregroundStyle(AppSectionAccent.ticket)
                }
                Group {
                    if note.effectivePromptStyle == .fill { GiriFilledPromptText(prompt: note.prompt, answer: record.text) }
                    else { Text(giriCharacterWrapped(record.text)) }
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                if record.isSubmitted {
                    Text(isLong ? "採用" : "出した").font(.caption.weight(.semibold)).foregroundStyle(accentActionColor)
                }
            }
            let result = thoughtAnswerResult(record)
            if !result.isEmpty { Text(result).font(.caption.weight(.medium)).foregroundStyle(AppSectionAccent.ticket) }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        // コピー・編集・印・削除・共有は長押しのメニューから。
        .contextMenu {
            copyButton(record)
            Button("編集", systemImage: "pencil") { beginEditing(record) }
            Menu("印を付ける", systemImage: "circle.circle") {
                ForEach(["◎", "〇", "△", "×"], id: \.self) { mark in
                    Button(mark) { saveAnswer(id: record.id, mark: mark) }
                }
                Menu("点数") {
                    ForEach(1...10, id: \.self) { point in Button("\(point)点") { saveAnswer(id: record.id, mark: String(point)) } }
                }
                if !record.mark.isEmpty { Button("印を外す", role: .destructive) { saveAnswer(id: record.id, mark: "") } }
            }
            GiriThoughtShareActions(note: note, event: event, record: record)
            Button("削除", systemImage: "trash", role: .destructive) { saveAnswer(id: record.id, delete: true) }
        }
    }

    /// 一覧（overview）には入力欄がないので、そこからの編集だけ別の画面で開く。
    private var editingAnswerShown: Binding<Bool> {
        Binding(get: { part == .overview && editingAnswerID != nil }, set: { if !$0 { editingAnswerID = nil } })
    }

    /// 0.20：回答をそのままコピーする（大喜利サイトに貼り付けられる）。
    private func copyButton(_ record: AnswerRecord) -> some View {
        Button("コピー", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = record.text
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    /// 0.20：回答の編集は、別の画面ではなく投稿の入力欄に戻して直す。
    private func beginEditing(_ record: AnswerRecord) {
        editingAnswerText = record.text
        editingAnswerID = record.id
        guard part != .overview else { return }
        if record.isOwn {
            if let mode { mode.wrappedValue = .own }
            newAnswer = record.text
            addingAnswer = true
        } else {
            if let mode { mode.wrappedValue = .others }
            newOtherAnswerer = record.answerer
            newOtherAnswer = record.text
        }
    }

    private func cancelEditing() {
        editingAnswerID = nil
        newAnswer = ""
        newOtherAnswer = ""
        newOtherAnswerer = ""
        addingAnswer = false
    }

    /// 編集中の回答（自分の回答・他人の回答の入力欄で別々に扱う）。
    private var editingOwnID: String? {
        guard part != .overview, let id = editingAnswerID, note.ownAnswerRecords.contains(where: { $0.id == id }) else { return nil }
        return id
    }
    private var editingOtherID: String? {
        guard part != .overview, let id = editingAnswerID, note.otherAnswerRecords.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    /// 入力欄の下のボタン：編集中は「キャンセル」と「更新」、それ以外は「投稿」。
    private func postingButtons(editing: Bool, disabled: Bool, post: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Spacer()
            if editing {
                Button("キャンセル", action: cancelEditing)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .tint(accentActionColor)
            }
            Button(editing ? "更新" : "投稿", action: post)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(accentActionColor)
                .disabled(disabled)
        }
    }

    private var answerEditSheet: some View {
        NavigationStack {
            GiriAnswerTextEditor(text: $editingAnswerText) {
                if let id = editingAnswerID { saveAnswer(id: id, text: editingAnswerText) }
                editingAnswerID = nil
            } onCancel: { editingAnswerID = nil }
        }
    }

    /// 長考の投稿フォーム：回答案を1つずつ書いて「投稿」で足す（改行は回答の中の改行）。
    private var postingForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(editingOwnID == nil ? "回答案を投稿" : "回答案を編集").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField("回答案を入力してください", text: $newAnswer, axis: .vertical)
                .lineLimit(2...6)
                .focused($addingAnswer)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.secondarySystemBackground)))
            postingButtons(editing: editingOwnID != nil, disabled: newAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, post: postAnswer)
        }
        .padding(.vertical, 4)
        // 0.21：入力を始めたら、見出し（回答案を投稿）と「投稿」が両方見える位置までずらす。
        .id(giriPostingFormID)
        .onChange(of: addingAnswer) { _, focused in
            if focused { revealPosting?() }
        }
        .sheet(isPresented: editingAnswerShown) { answerEditSheet }
    }

    private func postAnswer() {
        if let id = editingOwnID {
            let updated = giriNoteEditingAnswer(note, id: id, text: newAnswer)
            store.run {
                try store.saveNote(updated)
                playLiveStairSaveFeedback()
                cancelEditing()
            }
            return
        }
        guard let updated = giriNoteAddingAnswer(note, text: newAnswer) else { return }
        store.run {
            try store.saveNote(updated)
            newAnswer = ""
            addingAnswer = true
        }
    }

    private func saveAnswer(id: String, text: String? = nil, mark: String? = nil, delete: Bool = false) {
        let updated = giriNoteEditingAnswer(note, id: id, text: text, mark: mark, delete: delete)
        store.run {
            try store.saveNote(updated)
            if delete { playLiveStairDeleteFeedback() }
        }
    }

    private func otherRow(_ record: AnswerRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(record.answerer).font(.caption.weight(.semibold)).foregroundStyle(AppSectionAccent.favorite)
            Text(giriCharacterWrapped(record.text)).font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            copyButton(record)
            Button("編集", systemImage: "pencil") { beginEditing(record) }
            GiriThoughtShareActions(note: note, event: event, record: record)
            Button("削除", systemImage: "trash", role: .destructive) { saveAnswer(id: record.id, delete: true) }
        }
    }

    /// お題と別に、この画面のまま回答を足す。改行で続けて入れられる（行の先頭の印も読む）。
    private var quickAddRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "plus.circle.fill").font(.subheadline).foregroundStyle(accentActionColor)
            TextField(isLong ? "回答案を追加" : "回答を追加", text: $newAnswer)
                .font(.subheadline)
                .focused($addingAnswer)
                .submitLabel(.next)
                .onSubmit(addAnswer)
            if !newAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("追加", action: addAnswer)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .tint(accentActionColor)
            }
        }
        .padding(.vertical, 2)
        .sheet(isPresented: editingAnswerShown) { answerEditSheet }
    }

    private func addAnswer() {
        guard let updated = giriNoteAddingAnswers(note, text: newAnswer) else { return }
        store.run {
            try store.saveNote(updated)
            newAnswer = ""
            // 続けて入れられるように、入力欄にとどまる。
            addingAnswer = true
        }
    }

    private func toggleSubmitted(_ id: String) {
        var updated = note
        var answers = updated.effectiveAnswerRecords
        guard let index = answers.firstIndex(where: { $0.id == id }), answers[index].isOwn else { return }
        answers[index].isSubmitted.toggle()
        updated.answerRecords = answers
        updated.usesAnswerRecords = true
        updated.isOthersAnswer = false
        updated.answerer = ""
        updated.answers = answers.map(\.text)
        updated.updatedAt = Date()
        store.run { try store.saveNote(updated) }
    }
}

/// 0.14：投稿・投票の日程は畳める。畳んだ時は今の状態と次の締切だけを出す。
/// 開いたか畳んだかは端末に残す（次に開いた時も同じ）。
private struct GiriThoughtScheduleDisclosure: View {
    let event: GiriEvent
    let round: EventRound
    @AppStorage("giriThoughtScheduleExpanded") private var expanded = false
    var body: some View {
        // 0.18：状態と締切を1行に。開閉の「>」は一覧へのリンクと同じ色にする。
        Button { withAnimation { expanded.toggle() } } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(thoughtPhase(event: event, round: round))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(AppSectionAccent.artist)
                if let deadline = giriThoughtCurrentDeadline(round) {
                    Text("締切 " + thoughtDateTime(deadline)).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if expanded {
            GiriThoughtPeriodRow(title: "投稿", start: round.submissionStart, end: round.submissionEnd, enabled: round.submissionEnabled, accent: AppSectionAccent.artist)
            GiriThoughtPeriodRow(title: "投票", start: round.votingStart, end: round.votingEnd, enabled: round.votingRequired, accent: AppSectionAccent.memo)
        }
    }
}

private struct GiriThoughtPeriodRow: View {
    let title: String
    let start: Date?
    let end: Date?
    let enabled: Bool
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            scheduleLine(title + "開始", date: start, missing: "開始未定")
            scheduleLine(title + "締切", date: end, missing: "締切未定")
        }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
    }
    private func scheduleLine(_ title: String, date: Date?, missing: String) -> some View {
        let isPast = date.map { $0 < Date() } ?? false
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "clock").font(.subheadline).foregroundStyle(isPast || !enabled ? Color.secondary : accent).frame(width: 20)
            Text(title).foregroundStyle(isPast || !enabled ? Color.secondary : Color.primary).lineLimit(2)
            Spacer(minLength: 8)
            Text(date.map(thoughtDateTime) ?? missing).font(.subheadline).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }.opacity(isPast ? 0.6 : 1)
    }
}

/// お題・自分の回答・ツボ（他の人の回答）を1つの画面で記録する。長考は回答案を並べて
/// 採用した回答に印を付け、それ以外は出した回答に印を付ける。画像のお題は文字を読み取れる。
@MainActor
struct GiriThoughtEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    @State private var initial: ThoughtNote
    @State private var draft: ThoughtNote
    @State private var primaryText: String
    @State private var bodyText: String
    @State private var memoText: String
    @State private var ownAnswers: [AnswerRecord]
    @State private var otherAnswers: [AnswerRecord]
    @State private var initialOwn: [AnswerRecord]
    @State private var initialOthers: [AnswerRecord]
    /// 回答案をメモのように1行に1つで書く（印は先頭に △・〇 など）。
    @State private var answerMemo: String
    @State private var selectedFormat: EventFormat
    @State private var relationInitialized = false
    @State private var showingAllEvents = false
    @State private var eventSearch = ""
    @State private var readingImage = false
    @State private var recognizing = false
    @State private var ocrLines: [String] = []
    @State private var showingOCR = false
    @State private var error: String?
    @State private var discard = false

    /// 0.15：新しく作る時だけ true。登録済みのお題の編集には回答の欄を出さない（回答はお題の画面で足す・直す）。
    private let isNewNote: Bool

    init(note: ThoughtNote? = nil, kind: NoteKind = .answers, eventID: String? = nil, roundID: String? = nil,
         resultStageID: String? = nil, preferredFormat: EventFormat? = nil) {
        isNewNote = note == nil
        var value = note ?? ThoughtNote()
        if note == nil {
            value.kind = kind
            value.eventId = eventID
            value.roundId = roundID
            value.resultStageId = resultStageID
            value.format = preferredFormat
        }
        let records = value.effectiveAnswerRecords
        _initial = State(initialValue: value)
        _draft = State(initialValue: value)
        _primaryText = State(initialValue: thoughtEditorPrimaryText(value))
        _bodyText = State(initialValue: value.body)
        _memoText = State(initialValue: value.memo)
        _ownAnswers = State(initialValue: records.filter(\.isOwn))
        _otherAnswers = State(initialValue: records.filter { !$0.isOwn })
        _initialOwn = State(initialValue: records.filter(\.isOwn))
        _initialOthers = State(initialValue: records.filter { !$0.isOwn })
        _answerMemo = State(initialValue: giriAnswerMemo(records.filter(\.isOwn)))
        _selectedFormat = State(initialValue: preferredFormat ?? value.format ?? (value.answerCategory == "long" ? .onlineLong : .live))
    }

    private var event: GiriEvent? { store.events.first { $0.id == draft.eventId } }
    private var isLong: Bool { selectedFormat == .onlineLong }

    /// 0.16：新しいお題を保存したあと、どちらのモードで回答を入れるかを選ぶ。
    /// 0.17：「このお題に参加」はお題の側で決める（nil は触っていない）。
    @State private var participatesDraft: Bool?
    @State private var savedNoteID: String?
    @State private var modeChoice = false
    @State private var chosenMode: GiriAnswerMode?

    var body: some View {
        if let mode = chosenMode, let id = savedNoteID {
            GiriAnswerModePage(noteID: id, initialMode: mode)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() }.fontWeight(.bold) }
                }
        } else {
            editorBody
                .alert("回答を入れますか？", isPresented: $modeChoice) {
                    Button("自分の回答") { chosenMode = .own }
                    Button("他人の回答") { chosenMode = .others }
                    Button("あとで", role: .cancel) { dismiss() }
                } message: { Text("お題を保存しました。") }
        }
    }

    private var editorBody: some View {
        Form {
            periodSection
            relationSection
            promptSection
            if draft.kind == .answers {
                // 0.16：どの形式でも、登録はお題だけ。回答は保存のあとに「自分の回答」「他人の回答」の画面で入れる。
                if !isNewNote && ownAnswers.contains(where: \.isSubmitted) {
                    Section {
                        AppCardSectionTitle(title: isLong ? "採用した回答の結果" : "出した回答の結果", systemImage: "trophy", accentColor: AppSectionAccent.ticket)
                            .listRowSeparator(.hidden)
                        GiriAnswerResultFields(records: $ownAnswers)
                    }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
                }
                if !isNewNote {
                    Section {
                        AppCardSectionTitle(title: "メモ", systemImage: "note.text", accentColor: AppSectionAccent.memo)
                            .listRowSeparator(.hidden)
                        TextField("手応え・覚えておきたいことなど", text: $memoText, axis: .vertical).lineLimit(2...10)
                    }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
                }
                if !bodyText.isEmpty && !initial.usesAnswerRecords {
                    Section {
                        AppCardSectionTitle(title: "元の本文", systemImage: "doc.text", accentColor: AppSectionAccent.memo)
                            .listRowSeparator(.hidden)
                        Text(bodyText).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                    }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
                }
            } else {
                Section {
                    AppCardSectionTitle(title: "メモ", systemImage: "square.and.pencil", accentColor: AppSectionAccent.memo)
                        .listRowSeparator(.hidden)
                    TextField("メモを入力", text: $bodyText, axis: .vertical).lineLimit(6...30)
                }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
        .appEditorFormStyle().scrollDismissesKeyboard(.interactively)
        .environment(\.defaultMinListRowHeight, 48)
        .navigationTitle(draft.kind == .prompts ? "お題を作る" : draft.kind == .answers ? (isNewNote ? "お題を登録" : "お題を編集") : "メモ")
        .navigationBarTitleDisplayMode(.inline).giriNavigationBarStyle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { if isDirty { discard = true } else { dismiss() } }.disabled(readingImage)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save).fontWeight(.bold).disabled(readingImage)
            }
        }
        .tint(accentActionColor)
        .interactiveDismissDisabled(isDirty || readingImage)
        .giriDiscardChangesAlert(isPresented: $discard) { dismiss() }
        .onAppear {
            guard !relationInitialized else { return }
            if let event { selectedFormat = event.eventFormat }
            else if !store.preferences.isFormatVisible(selectedFormat), initial.format == nil,
                    let first = store.preferences.visibleFormatOrder.first { selectedFormat = first }
            relationInitialized = true
        }
        .onChange(of: selectedFormat) { _, value in
            if relationInitialized, let event, event.eventFormat != value {
                draft.eventId = nil; draft.roundId = nil; draft.resultStageId = nil
            }
        }
        .sheet(isPresented: $showingAllEvents) { allEventsPicker }
        .sheet(isPresented: $showingOCR) {
            NavigationStack {
                GiriThoughtOCRSheet(lines: ocrLines, onPrompt: { text in
                    primaryText = text
                }, onAuthor: { name in
                    let revised = name.contains("（改）") || name.contains("(改)")
                    draft.promptAuthor = name.replacingOccurrences(of: "（改）", with: "").replacingOccurrences(of: "(改)", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if revised { draft.promptRevised = true }
                })
            }
        }
    }

    @ViewBuilder private var periodSection: some View {
        if let event, event.eventFormat.hasOnlineRounds, let round = thoughtRound(draft, event: event) {
            Section {
                AppCardSectionTitle(title: event.title, systemImage: thoughtFormatSymbol(event.eventFormat), accentColor: AppSectionAccent.artist)
                    .listRowSeparator(.hidden)
                Text(thoughtRoundLabel(event: event, round: round)).font(.subheadline.weight(.semibold))
                Text(thoughtPhase(event: event, round: round)).font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppSectionAccent.artist)
                GiriThoughtPeriodRow(title: "投稿", start: round.submissionStart, end: round.submissionEnd, enabled: round.submissionEnabled, accent: AppSectionAccent.artist)
                GiriThoughtPeriodRow(title: "投票", start: round.votingStart, end: round.votingEnd, enabled: round.votingRequired, accent: AppSectionAccent.memo)
                // 戦績で入れたこの回の結果。
                if let stage = event.tournamentResult?.stages.last(where: { $0.roundId == round.id }) {
                    let summary = thoughtStageSummary(stage)
                    if !summary.isEmpty {
                        Text("この回の結果　" + summary).font(.subheadline.weight(.semibold)).foregroundStyle(AppSectionAccent.ticket)
                    }
                }
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
        }
    }

    private var relationSection: some View {
        Section {
            AppCardSectionTitle(title: "関連する会", systemImage: "link", accentColor: AppSectionAccent.memo,
                                infoTitle: "関連する会について",
                                infoMessage: "会は後からでも選べます。選ばずに保存したお題は、お題/回答の「会に紐付けていないお題」に入ります。")
                .listRowSeparator(.hidden)
            Picker(selection: $selectedFormat) {
                ForEach(store.preferences.formatChoices(including: selectedFormat)) { format in Text(format.title).tag(format) }
            } label: { GiriEditorLabel("形式") }
            .pickerStyle(.menu).tint(.primary)
            eventPicker
            if let event, event.eventFormat.hasOnlineRounds, !event.effectiveRounds.isEmpty { roundPicker }
            if let event, !event.stageResults.isEmpty, !(event.eventFormat.hasOnlineRounds && !event.effectiveRounds.isEmpty) { stagePicker(event) }
            if draft.kind == .prompts { Toggle("使用済み", isOn: $draft.used).tint(AppSectionAccent.memo) }
        }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
    }

    /// 長考の回答を考える時だけ、お題の種類（通常・画像・穴埋め）を選ぶ。
    /// 0.16：どの形式でもお題の種類（通常・画像・穴埋め）を選ぶ。
    private var choosesPromptStyle: Bool { draft.kind == .answers }
    private var promptStyle: GiriPromptStyle { choosesPromptStyle ? draft.effectivePromptStyle : (draft.imageDataBase64.isEmpty ? .plain : .image) }
    private var promptPlaceholder: String {
        if draft.kind == .free { return "タイトル（任意）" }
        guard choosesPromptStyle else { return draft.kind == .answers ? "お題（画像だけでも可）" : "お題を入力" }
        switch promptStyle {
        case .plain: return "お題"
        case .image: return "お題の文（任意）"
        case .fill: return "お題（〇〇の部分を回答で埋めます）"
        }
    }

    private var participationBinding: Binding<Bool> {
        Binding(get: { participatesDraft ?? (isNewNote ? giriDefaultPromptParticipation(event: event) : initial.isParticipatingPrompt) },
                set: { participatesDraft = $0 })
    }

    private var promptSection: some View {
        Section {
            AppCardSectionTitle(title: draft.kind == .free ? "タイトル" : "お題", systemImage: draft.kind == .free ? "square.and.pencil" : "lightbulb", accentColor: AppSectionAccent.memo)
                .listRowSeparator(.hidden)
            if choosesPromptStyle {
                Picker(selection: Binding(get: { promptStyle }, set: { draft.promptStyle = $0.rawValue })) {
                    ForEach(GiriPromptStyle.allCases) { Text($0.title).tag($0) }
                } label: { GiriEditorLabel("お題の種類") }
                .pickerStyle(.menu).tint(.primary)
            }
            TextField(promptPlaceholder, text: $primaryText, axis: .vertical)
                .lineLimit(1...10)
            if choosesPromptStyle && promptStyle == .fill {
                let blanks = giriPromptBlankCount(primaryText)
                Text(blanks == 0 ? "埋める所を〇〇・△△・××で書いてください" : blanks == 1 ? "回答は〇〇に入る言葉だけを書きます" : "回答は\(blanks)か所を「／」で区切って書きます")
                    .font(.caption).foregroundStyle(.secondary)
            }
            // 通常お題は画像を付けない。
            if !(choosesPromptStyle && promptStyle == .plain) {
                GiriThoughtImagePicker(base64: $draft.imageDataBase64, reading: $readingImage, error: $error)
            }
            if !draft.imageDataBase64.isEmpty && !(choosesPromptStyle && promptStyle == .plain) {
                Button {
                    recognizeImage()
                } label: {
                    Label(recognizing ? "読み取り中" : "画像の文字を読み取る", systemImage: "text.viewfinder")
                }
                .disabled(recognizing || readingImage)
            }
            if draft.kind == .answers {
                GiriPlayerSuggestionField(title: "作題者", text: $draft.promptAuthor, showsLabel: true, textAlignment: .trailing)
                if !draft.promptAuthor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Toggle("（改）", isOn: $draft.promptRevised).tint(AppSectionAccent.memo)
                }
                // 0.17：参加したかはお題の側で決める。
                Toggle(isOn: participationBinding) { GiriEditorLabel("このお題に参加") }
                    .tint(AppSectionAccent.memo)
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
    }

    /// 回答案はメモのように1行に1つ。最後に提出した回答を選び、△・〇などの印や点数は行の先頭に書く。
    private var ownSection: some View {
        Section {
            AppCardSectionTitle(title: isLong ? "回答案" : "自分の回答", systemImage: "text.bubble", accentColor: AppSectionAccent.memo,
                                infoTitle: isLong ? "回答案について" : "自分の回答について",
                                infoMessage: "1行に1つ書きます。行の先頭に △ や 〇、「3・」のような点数を付けると印になります。" + (isLong ? "最後に採用した回答を選びます。" : "最後に出した回答を選びます。"))
                .listRowSeparator(.hidden)
            ZStack(alignment: .topLeading) {
                if answerMemo.isEmpty {
                    Text("・回答案\n△・迷っている案").font(.body).foregroundStyle(.tertiary)
                        .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                }
                TextEditor(text: Binding(get: { answerMemo }, set: { text in
                    answerMemo = text
                    ownAnswers = giriReconcileAnswers(giriAnswerLines(text), previous: ownAnswers)
                }))
                .frame(minHeight: 150)
                .scrollContentBackground(.hidden)
            }
            if !ownAnswers.isEmpty {
                Menu {
                    ForEach(ownAnswers) { record in
                        Button { toggleSubmitted(record.id) } label: {
                            if record.isSubmitted { Label(answerDisplay(record), systemImage: "checkmark") }
                            else { Text(answerDisplay(record)) }
                        }
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        GiriEditorLabel(isLong ? "採用した回答" : "出した回答")
                        Spacer(minLength: 8)
                        Text(submittedSummary).font(.subheadline.weight(.semibold))
                            .foregroundStyle(ownAnswers.contains(where: \.isSubmitted) ? Color.primary : Color.secondary)
                            .multilineTextAlignment(.trailing).lineLimit(3)
                        Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
            }
            // 穴埋めは、お題に入れた形で確かめられる。
            if choosesPromptStyle && promptStyle == .fill && !ownAnswers.isEmpty {
                ForEach(ownAnswers) { record in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if !record.mark.isEmpty { Text(record.mark).font(.subheadline.weight(.bold)).foregroundStyle(AppSectionAccent.ticket) }
                        GiriFilledPromptText(prompt: primaryText, answer: record.text).font(.subheadline)
                    }
                }
            }
            Button("貼り付けた文章から追加", systemImage: "doc.on.clipboard") {
                guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
                answerMemo = answerMemo.isEmpty ? text : answerMemo + "\n" + text
                ownAnswers = giriReconcileAnswers(giriAnswerLines(answerMemo), previous: ownAnswers)
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
    }

    private func answerDisplay(_ record: AnswerRecord) -> String {
        let text = choosesPromptStyle && promptStyle == .fill ? giriFilledPromptText(prompt: primaryText, answer: record.text) : record.text
        return record.mark.isEmpty ? text : record.mark + " " + text
    }

    private var submittedSummary: String {
        let submitted = ownAnswers.filter(\.isSubmitted)
        guard !submitted.isEmpty else { return "選ぶ" }
        return submitted.map(\.text).joined(separator: "\n")
    }

    private func toggleSubmitted(_ id: String) {
        guard let index = ownAnswers.firstIndex(where: { $0.id == id }) else { return }
        ownAnswers[index].isSubmitted.toggle()
    }

    private var othersSection: some View {
        Section {
            AppCardSectionTitle(title: "ツボ（他の人の回答）", systemImage: "face.smiling", accentColor: AppSectionAccent.favorite,
                                infoTitle: "ツボについて",
                                infoMessage: "面白かった他の人の回答を回答者と一緒に残します。プレイヤー詳細の「好きな回答」にも出ます。")
                .listRowSeparator(.hidden)
            ForEach(otherAnswers) { record in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        GiriPlayerSuggestionField(title: "回答者", text: otherBinding(record.id).answerer, showsLabel: true, textAlignment: .trailing)
                        Button(role: .destructive) { otherAnswers.removeAll { $0.id == record.id } } label: {
                            Image(systemName: "minus.circle").frame(minWidth: 28, minHeight: 32)
                        }.buttonStyle(.borderless).accessibilityLabel("このツボを外す")
                    }
                    TextField("回答", text: otherBinding(record.id).text, axis: .vertical).lineLimit(1...8)
                }.padding(.vertical, 4)
            }
            Button("ツボを追加", systemImage: "plus.circle") { otherAnswers.append(AnswerRecord()) }
        }.appSectionCardStyle(accentColor: AppSectionAccent.favorite)
    }

    private var primaryEvents: [GiriEvent] {
        let now = Date()
        return store.events.filter { event in
            guard event.eventFormat == selectedFormat, event.isActualParticipant else { return false }
            return selectedFormat != .onlineLong || event.participationState(now: now) == .ongoing
        }.sorted { thoughtEventComesFirst($0, $1, now: now) }
    }

    private var allEvents: [GiriEvent] {
        store.events.filter { $0.eventFormat == selectedFormat && (eventSearch.isEmpty || [$0.title, $0.organizer, $0.venue, $0.hashtag].joined(separator: " ").localizedStandardContains(eventSearch)) }
            .sorted { thoughtEventComesFirst($0, $1, now: Date()) }
    }

    private var eventPicker: some View {
        Group {
            Picker(selection: Binding(
                get: { draft.eventId }, set: { draft.eventId = $0; draft.roundId = nil; draft.resultStageId = nil }
            )) {
                Text("関連づけなし").tag(nil as String?)
                ForEach(primaryEvents) { event in Text(thoughtEventPickerTitle(event)).tag(Optional(event.id)) }
                if let selected = event, !primaryEvents.contains(where: { $0.id == selected.id }) {
                    Text(thoughtEventPickerTitle(selected)).tag(Optional(selected.id))
                }
                if let id = draft.eventId, event == nil { Text("削除された会").tag(Optional(id)) }
            } label: { GiriEditorLabel("会") }
            .pickerStyle(.menu).tint(.primary)
            Button("その他の会から選ぶ", systemImage: "ellipsis.circle") { showingAllEvents = true }
        }
    }

    private var allEventsPicker: some View {
        NavigationStack {
            List {
                ForEach(allEvents) { event in
                    Button {
                        draft.eventId = event.id
                        draft.roundId = nil
                        draft.resultStageId = nil
                        showingAllEvents = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title).foregroundStyle(.primary)
                            Text(thoughtEventPickerTitle(event)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .appIndexListStyle().searchable(text: $eventSearch, prompt: "会・主催者・会場・ハッシュタグ")
            .navigationTitle("その他の会").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { showingAllEvents = false } } }
        }
    }

    private var roundPicker: some View {
        Picker(selection: $draft.roundId) {
            Text("関連づけなし").tag(nil as String?)
            if let event {
                ForEach(event.effectiveRounds.sorted { ($0.submissionStart ?? .distantPast) > ($1.submissionStart ?? .distantPast) }) { round in
                    Text(thoughtRoundLabel(event: event, round: round)).tag(Optional(round.id))
                }
            }
            if let id = draft.roundId, !(event?.effectiveRounds.contains(where: { $0.id == id }) ?? false) {
                Text("削除された日程").tag(Optional(id))
            }
        } label: { GiriEditorLabel("日程") }
        .pickerStyle(.menu).tint(.primary)
    }

    private func stagePicker(_ event: GiriEvent) -> some View {
        Picker(selection: $draft.resultStageId) {
            Text("選ばない").tag(nil as String?)
            ForEach(event.stageResults) { stage in Text(stage.name.isEmpty ? "段階" : stage.name).tag(Optional(stage.id)) }
            if let id = draft.resultStageId, !event.stageResults.contains(where: { $0.id == id }) {
                Text("削除された段階").tag(Optional(id))
            }
        } label: { GiriEditorLabel("段階") }
        .pickerStyle(.menu).tint(.primary)
    }

    private func ownBinding(_ id: String) -> Binding<AnswerRecord> {
        Binding(get: { ownAnswers.first { $0.id == id } ?? AnswerRecord(id: id) }, set: { value in
            if let index = ownAnswers.firstIndex(where: { $0.id == id }) { ownAnswers[index] = value }
        })
    }

    private func otherBinding(_ id: String) -> Binding<AnswerRecord> {
        Binding(get: { otherAnswers.first { $0.id == id } ?? AnswerRecord(id: id) }, set: { value in
            if let index = otherAnswers.firstIndex(where: { $0.id == id }) { otherAnswers[index] = value }
        })
    }

    private var isDirty: Bool {
        draft != initial || primaryText != thoughtEditorPrimaryText(initial) || bodyText != initial.body ||
            memoText != initial.memo || ownAnswers != initialOwn || otherAnswers != initialOthers
    }

    private func recognizeImage() {
        guard let data = Data(base64Encoded: draft.imageDataBase64) else { return }
        recognizing = true
        error = nil
        Task { @MainActor in
            defer { recognizing = false }
            do {
                let text = try await GiriParticipantOCR.recognize(data)
                ocrLines = thoughtLines(text)
                showingOCR = !ocrLines.isEmpty
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func save() {
        let primary = primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        func cleaned(_ records: [AnswerRecord]) -> [AnswerRecord] {
            records.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { record in
                var copy = record
                copy.text = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
                copy.answerer = record.answerer.trimmingCharacters(in: .whitespacesAndNewlines)
                return copy
            }
        }
        let own = cleaned(ownAnswers)
        let others = cleaned(otherAnswers)
        if draft.kind == .answers {
            guard !own.isEmpty || !others.isEmpty || !primary.isEmpty || !draft.imageDataBase64.isEmpty else {
                error = "お題か回答を入力してください。"; return
            }
            if others.contains(where: { $0.answerer.isEmpty }) {
                error = "ツボの回答者を入力してください。"; return
            }
            if ownAnswers.contains(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ($0.placement != nil || $0.points != nil || $0.voterCount != nil) }) {
                error = "結果を記録した回答の本文を入力してください。"; return
            }
        } else if (draft.kind != .free && primary.isEmpty && draft.imageDataBase64.isEmpty) || (primary.isEmpty && body.isEmpty && draft.imageDataBase64.isEmpty) {
            error = draft.kind == .free ? "タイトルか本文を入力してください。" : "お題か画像を入力してください。"
            return
        }
        var saved = draft
        // 長考で通常お題を選んだ時は画像を付けない。長考以外は種類を保存しない（以前の版と同じ）。
        if choosesPromptStyle {
            saved.promptStyle = promptStyle.rawValue
            if promptStyle == .plain { saved.imageDataBase64 = "" }
        }
        let firstAnswer = (own + others).first?.text
        let fallbackTitle = firstAnswer ?? (body.components(separatedBy: .newlines).first ?? "メモ")
        saved.title = String((!primary.isEmpty ? primary : !saved.imageDataBase64.isEmpty ? "画像のお題" : fallbackTitle).prefix(120))
        saved.prompt = draft.kind == .free ? "" : primary
        saved.promptAuthor = draft.promptAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
        if saved.promptAuthor.isEmpty { saved.promptRevised = false }
        if draft.kind == .answers {
            // 0.8以降は1つのお題に自分の回答とツボをまとめ、回答者は各回答に持たせる。
            saved.answerRecords = own + others
            saved.usesAnswerRecords = true
            saved.answers = saved.answerRecords.map(\.text)
            saved.isOthersAnswer = false
            saved.answerer = ""
            saved.answerCategory = isLong ? "long" : "other"
            saved.memo = memoText.trimmingCharacters(in: .whitespacesAndNewlines)
            saved.body = initial.body
        } else {
            saved.body = bodyText
        }
        saved.format = event?.eventFormat ?? selectedFormat
        saved.used = draft.kind == .prompts && draft.used
        // 0.16：新しいお題は、関連する会に参加していれば「このお題に参加」から始める。
        if draft.kind == .answers {
            if let participatesDraft { saved.participates = participatesDraft }
            else if isNewNote { saved.participates = giriDefaultPromptParticipation(event: event) }
        }
        saved.updatedAt = Date()
        do {
            try store.saveNote(saved)
            playLiveStairSaveFeedback()
            if isNewNote && draft.kind == .answers {
                savedNoteID = saved.id
                initial = saved
                draft = saved
                modeChoice = true
            } else {
                dismiss()
            }
        }
        catch { self.error = "保存できませんでした。内容を残したまま再試行できます。\n\(error.localizedDescription)" }
    }
}

/// 画像のお題から読み取った文字。行を選んでお題にし、作題者の名前は行ごとに入れる。
private struct GiriThoughtOCRSheet: View {
    @Environment(\.dismiss) private var dismiss
    let lines: [String]
    let onPrompt: (String) -> Void
    let onAuthor: (String) -> Void
    @State private var selected: Set<Int> = []
    var body: some View {
        List {
            Section {
                AppCardSectionTitle(title: "読み取った文字", systemImage: "text.viewfinder", accentColor: AppSectionAccent.scan,
                                    infoTitle: "読み取った文字について",
                                    infoMessage: "お題にする行を選んで「お題にする」を押します。作題者の名前がある行は右の「作題者」で入れられます。")
                    .listRowSeparator(.hidden)
                ForEach(lines.indices, id: \.self) { index in
                    HStack(spacing: 10) {
                        Button {
                            if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selected.contains(index) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(index) ? accentActionColor : Color.secondary)
                                Text(lines[index]).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                            }.contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        Button("作題者") {
                            onAuthor(giriAuthorFromOCR(lines[index]))
                            dismiss()
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                        .tint(accentActionColor)
                    }
                }
            }.appSectionCardStyle(accentColor: AppSectionAccent.scan)
        }
        .appIndexListStyle()
        .navigationTitle("文字の読み取り").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("お題にする") {
                    onPrompt(selected.sorted().map { lines[$0] }.joined())
                    dismiss()
                }
                .disabled(selected.isEmpty)
            }
        }
    }
}

/// 「作題：〇〇」「作 〇〇（改）」などから名前の部分を取り出す。
func giriAuthorFromOCR(_ line: String) -> String {
    var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
    for prefix in ["作題者", "作題", "出題者", "出題", "作"] where value.hasPrefix(prefix) {
        value = String(value.dropFirst(prefix.count))
        break
    }
    while let first = value.first, [":", "：", " ", "　", "・", "/", "／"].contains(first) { value.removeFirst() }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Result entry and Thinking use the same submitted-answer fields. Unsubmitted
/// drafts and other people's answers stay in the binding unchanged.
struct GiriAnswerResultFields: View {
    @EnvironmentObject private var store: GiriStore
    @Binding var records: [AnswerRecord]
    /// 0.15：結果のページのスクリーンショットから、出した回答の順位・得点・投票人数を読む。
    @State private var resultPhoto: PhotosPickerItem?
    @State private var readingResult = false
    var body: some View {
        let submitted = records.filter { $0.isOwn && $0.isSubmitted }
        if submitted.isEmpty {
            Text("提出した回答をお題/回答で選んでください。").font(.subheadline).foregroundStyle(.secondary)
        } else {
            PhotosPicker(selection: $resultPhoto, matching: .images, photoLibrary: .shared()) {
                Label(readingResult ? "読み取り中" : "結果のスクショから読み取る", systemImage: "text.viewfinder")
            }
            .disabled(readingResult)
            .tint(accentActionColor)
            .onChange(of: resultPhoto) { _, item in readResult(item) }
        }
        ForEach(submitted) { record in
            VStack(alignment: .leading, spacing: 6) {
                Text(record.text).font(.subheadline.weight(.semibold)).lineLimit(4)
                GiriIntegerField(title: "この回答の順位（任意）", value: recordBinding(record.id).placement, suffix: "位")
                HStack {
                    TextField("得点（任意）", value: recordBinding(record.id).points, format: .number).keyboardType(.decimalPad)
                    Text("点").foregroundStyle(.secondary)
                }
                GiriIntegerField(title: "投票人数（任意）", value: recordBinding(record.id).voterCount, suffix: "人")
                if let value = record.pointsPerVoter {
                    LabeledContent("1人あたり", value: giriScoreText(value))
                }
                TextField("回答のメモ", text: recordBinding(record.id).memo, axis: .vertical).lineLimit(1...5)
            }.padding(.vertical, 4)
        }
    }
    /// 回答の文が載っている行の近くの「◯位」「◯点」と、ページの投票人数を、まだ入れていない欄にだけ入れる。
    private func readResult(_ item: PhotosPickerItem?) {
        guard let item else { return }
        readingResult = true
        Task {
            defer { readingResult = false; resultPhoto = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw GiriParticipantReadError.unreadable }
                let lines = try await GiriParticipantOCR.recognizeLines(data)
                let voters = giriVoterCountReading(lines: lines)
                var found = 0
                for index in records.indices where records[index].isOwn && records[index].isSubmitted {
                    let reading = giriAnswerResultReading(lines: lines, answer: records[index].text)
                    if reading != nil { found += 1 }
                    if records[index].placement == nil, let value = reading?.placement { records[index].placement = value }
                    if records[index].points == nil, let value = reading?.points { records[index].points = value }
                    if records[index].voterCount == nil, let voters { records[index].voterCount = voters }
                }
                if found == 0 { store.errorMessage = "結果の画像から、出した回答が見つかりませんでした。回答の文が写っている画面を選んでください。" }
            } catch { store.errorMessage = error.localizedDescription }
        }
    }

    private func recordBinding(_ id: String) -> Binding<AnswerRecord> {
        Binding(get: { records.first { $0.id == id } ?? AnswerRecord(id: id) }, set: { value in
            if let index = records.firstIndex(where: { $0.id == id }) { records[index] = value }
        })
    }
}

private struct GiriThoughtImagePicker: View {
    @Binding var base64: String
    @Binding var reading: Bool
    @Binding var error: String?
    @State private var selection: PhotosPickerItem?

    var body: some View {
        Group {
            if !base64.isEmpty { GiriThoughtImage(base64: base64) }
            HStack {
                PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
                    Label(reading ? "読み込み中" : base64.isEmpty ? "画像を追加" : "画像を変更", systemImage: "photo")
                }
                .disabled(reading)
                Spacer()
                if !base64.isEmpty {
                    Button("解除") { base64 = "" }.disabled(reading)
                }
            }
            .tint(accentActionColor)
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            reading = true
            error = nil
            Task {
                defer { reading = false; selection = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw ThoughtImageError.unreadable
                    }
                    base64 = try thoughtCompressedImage(data).base64EncodedString()
                } catch is CancellationError {
                    // Cancellation retains the existing image.
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

struct GiriThoughtImage: View {
    let base64: String
    @State private var showingFullImage = false

    var body: some View {
        Group {
            if let data = Data(base64Encoded: base64), let image = UIImage(data: data) {
                Button { showingFullImage = true } label: {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("画像のお題を拡大")
                .sheet(isPresented: $showingFullImage) {
                    NavigationStack {
                        ThoughtZoomImage(image: image)
                            .ignoresSafeArea(edges: .bottom)
                            .navigationTitle("画像のお題")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("完了") { showingFullImage = false }
                                }
                            }
                    }
                }
            } else {
                Label("画像を表示できませんでした", systemImage: "photo.badge.exclamationmark")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ThoughtZoomImage: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.backgroundColor = .black
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.delegate = context.coordinator
        let picture = UIImageView(image: image)
        picture.contentMode = .scaleAspectFit
        picture.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.addSubview(picture)
        context.coordinator.imageView = picture
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        guard let picture = context.coordinator.imageView else { return }
        picture.image = image
        if scroll.zoomScale == 1 {
            picture.frame = scroll.bounds
            scroll.contentSize = scroll.bounds.size
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    }
}

private enum ThoughtImageError: LocalizedError {
    case unreadable, tooLarge
    var errorDescription: String? {
        switch self {
        case .unreadable: return "画像を読み込めませんでした。別の画像を選んでください。"
        case .tooLarge: return "画像が大きすぎます。小さい画像を選んでください。"
        }
    }
}

private func thoughtCompressedImage(_ data: Data) throws -> Data {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceThumbnailMaxPixelSize: 1280,
              kCGImageSourceCreateThumbnailWithTransform: true,
          ] as CFDictionary) else {
        throw ThoughtImageError.unreadable
    }
    let image = UIImage(cgImage: thumbnail)
    for quality in [0.75, 0.6, 0.45, 0.3] {
        if let encoded = image.jpegData(compressionQuality: quality), encoded.count <= 1_048_576 {
            return encoded
        }
    }
    throw ThoughtImageError.tooLarge
}

private func thoughtMatches(_ note: ThoughtNote, eventID: String, roundID: String) -> Bool {
    note.eventId == eventID && (note.roundId == roundID || (roundID == "legacy" && note.roundId == nil))
}

private func thoughtTitle(_ note: ThoughtNote) -> String {
    if !note.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return note.prompt }
    if !note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return note.title }
    return note.imageDataBase64.isEmpty ? "メモ" : "画像のお題"
}

private func thoughtLines(_ value: String) -> [String] {
    value.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func thoughtRoundLabel(event: GiriEvent, round: EventRound) -> String {
    var parts: [String]
    if event.meetingType == .tournament {
        parts = [round.name]
        if let number = giriRoundNumberText(round, in: event.effectiveRounds) { parts.append(number) }
    } else {
        parts = [event.siteSeason, event.siteCycleNumber.map { "第\($0)回" } ?? "投稿・投票"].filter { !$0.isEmpty }
        if event.sitePeriodKind != .regular { parts.append(event.sitePeriodKind.title) }
    }
    if !event.affiliation.isEmpty { parts.append(event.affiliation) }
    let block = round.block.isEmpty ? event.block : round.block
    if !block.isEmpty { parts.append(block) }
    return parts.joined(separator: " · ")
}

private func thoughtDateTime(_ date: Date) -> String { GiriDateText.dateTime(date) }

private func thoughtFormatSymbol(_ format: EventFormat) -> String {
    switch format {
    case .live: return "person.3"
    case .onlineLong: return "globe"
    case .onlineShort: return "bolt"
    case .hybrid: return "tablecells"
    }
}

private func thoughtRound(_ note: ThoughtNote, event: GiriEvent) -> EventRound? {
    let id = note.roundId ?? "legacy"
    return event.effectiveRounds.first { $0.id == id }
}

private func thoughtNewestRound(_ event: GiriEvent, now: Date = Date()) -> EventRound? {
    let rounds = event.effectiveRounds
    let active = rounds.filter { $0.isSubmissionOpen(now) || $0.isVotingOpen(now) }
        .sorted { ($0.votingEnd ?? $0.submissionEnd ?? .distantFuture) < ($1.votingEnd ?? $1.submissionEnd ?? .distantFuture) }
    return active.first ?? rounds.max { ($0.submissionStart ?? $0.votingEnd ?? .distantPast) < ($1.submissionStart ?? $1.votingEnd ?? .distantPast) }
}

private func thoughtEventDate(_ event: GiriEvent) -> Date {
    event.effectiveRounds.compactMap { $0.submissionStart ?? $0.votingStart ?? $0.votingEnd }.max() ??
    event.eventDate ?? event.startsAt ?? event.createdAt
}

private func thoughtPhase(event: GiriEvent, round: EventRound?, now: Date = Date()) -> String {
    if event.isInterested { return "興味あり" }
    if let round {
        var phases: [String] = []
        if round.isSubmissionOpen(now) { phases.append("投稿中") }
        if round.isVotingOpen(now) { phases.append("投票中") }
        if !phases.isEmpty { return phases.joined(separator: "・") }
        if let end = round.votingEnd ?? round.submissionEnd, end <= now { return "終了" }
        if let start = round.submissionStart ?? round.votingStart, now < start { return "開始前" }
    }
    return event.participationState(now: now).title
}

private func thoughtStageSummary(_ result: ResultStage) -> String {
    var parts: [String] = []
    if result.outcome != .unrecorded { parts.append(result.outcome.title) }
    if let rank = result.placement { parts.append("\(rank)位") }
    if let rank = result.individualPlacement { parts.append("個人\(rank)位") }
    if let rank = result.teamPlacement { parts.append("チーム\(rank)位") }
    if let value = result.pointsPerVoter { parts.append("1人あたり" + giriScoreText(value)) }
    return parts.joined(separator: " · ")
}
private func thoughtAnswerResult(_ record: AnswerRecord) -> String {
    var parts: [String] = []
    if let placement = record.placement { parts.append("\(placement)位") }
    if let points = record.points { parts.append(points.formatted(.number.precision(.fractionLength(0...2))) + "点") }
    if let value = record.pointsPerVoter { parts.append("1人あたり" + giriScoreText(value)) }
    return parts.joined(separator: " · ")
}
private func thoughtResultSummary(_ note: ThoughtNote, event: GiriEvent?) -> String {
    if note.kind == .prompts { return note.used ? "使用済み" : "未使用" }
    guard note.kind == .answers else { return String(note.body.prefix(100)) }
    var parts: [String] = []
    for record in note.submittedAnswers.prefix(2) {
        let result = thoughtAnswerResult(record)
        if !result.isEmpty { parts.append(result) }
    }
    if let event, let result = event.tournamentResult?.stages.last(where: {
        $0.roundId == note.roundId && $0.roundId != nil
    }) {
        let summary = thoughtStageSummary(result)
        if !summary.isEmpty { parts.append(summary) }
    }
    return parts.joined(separator: " · ")
}

private func thoughtDeleteTitle(_ note: ThoughtNote) -> String {
    switch note.kind {
    case .prompts: return "お題を削除しますか？"
    case .answers: return "お題と回答を削除しますか？"
    case .free: return "メモを削除しますか？"
    }
}

private func thoughtAuthorText(_ note: ThoughtNote) -> String {
    note.promptAuthor + (note.promptRevised ? "（改）" : "")
}

private func thoughtUIImage(_ note: ThoughtNote) -> UIImage? {
    guard !note.imageDataBase64.isEmpty, let data = Data(base64Encoded: note.imageDataBase64) else { return nil }
    return UIImage(data: data)
}

/// カードに出す、会の中での位置（ネットの回・大会の段階）。
private func thoughtPlaceLabel(_ note: ThoughtNote, event: GiriEvent) -> String {
    if event.eventFormat.hasOnlineRounds, let round = thoughtRound(note, event: event) {
        return "　" + thoughtRoundLabel(event: event, round: round)
    }
    if let stage = event.stageResults.first(where: { $0.id == note.resultStageId }), !stage.name.isEmpty {
        return "　" + stage.name
    }
    return ""
}
private func thoughtEventPickerTitle(_ event: GiriEvent) -> String {
    let date = GiriEventPresentation.date(event) ?? event.eventDate ?? event.startsAt
    let dateText = date.map { GiriDateText.day($0, compact: true) + " " } ?? ""
    return dateText + event.title
}

private func thoughtEventComesFirst(_ first: GiriEvent, _ second: GiriEvent, now: Date) -> Bool {
    let firstDate = GiriEventPresentation.date(first) ?? first.eventDate ?? first.startsAt ?? first.createdAt
    let secondDate = GiriEventPresentation.date(second) ?? second.eventDate ?? second.startsAt ?? second.createdAt
    let firstToday = Calendar.current.isDate(firstDate, inSameDayAs: now)
    let secondToday = Calendar.current.isDate(secondDate, inSameDayAs: now)
    if firstToday != secondToday { return firstToday }
    let firstDistance = abs(firstDate.timeIntervalSince(now))
    let secondDistance = abs(secondDate.timeIntervalSince(now))
    if firstDistance != secondDistance { return firstDistance < secondDistance }
    return first.title.localizedStandardCompare(second.title) == .orderedAscending
}


private func thoughtEditorPrimaryText(_ note: ThoughtNote) -> String {
    if note.kind == .answers && note.usesAnswerRecords { return note.prompt }
    return note.prompt.isEmpty ? note.title : note.prompt
}

private func thoughtSearchMatches(_ note: ThoughtNote, event: GiriEvent?, query: String) -> Bool {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }
    var fields = [note.title, note.prompt, note.body, note.memo, note.answerer, note.promptAuthor,
                  event?.title ?? "", event?.hashtag ?? "", event?.organizer ?? "", event?.affiliation ?? "", event?.block ?? ""]
    fields += note.effectiveAnswerRecords.flatMap { [$0.text, $0.answerer] }
    return fields.joined(separator: " ").localizedStandardContains(trimmed)
}
/// Explicit taps open a compose screen; the app never sends a post itself.
private func thoughtTweetURL(_ note: ThoughtNote, event: GiriEvent?, record: AnswerRecord? = nil) -> URL? {
    var components = URLComponents(string: "https://twitter.com/intent/tweet")
    components?.queryItems = [URLQueryItem(name: "text", value: thoughtShareText(note, event: event, record: record))]
    return components?.url
}

/// ツボ上げの形：「回答者「回答」」を並べ、会のハッシュタグを最後に付ける。
/// ハッシュタグがない会は会の名前を先頭に残す。画像と一緒に共有する時は、お題は画像で伝える。
private func thoughtShareText(_ note: ThoughtNote, event: GiriEvent?, record: AnswerRecord? = nil, includePrompt: Bool = true) -> String {
    var parts: [String] = []
    let hashtag = event?.hashtag ?? ""
    if let event, hashtag.isEmpty { parts.append(event.title) }
    if note.kind == .answers {
        if includePrompt && !note.prompt.isEmpty { parts.append("お題：" + note.prompt) }
        let records: [AnswerRecord]
        if let record { records = [record] }
        else {
            let others = note.otherAnswerRecords
            let submitted = note.submittedAnswers
            records = !others.isEmpty ? others : (submitted.isEmpty ? note.ownAnswerRecords : submitted)
        }
        // 穴埋めはお題に入れた文で共有する。
        let fill = note.effectivePromptStyle == .fill
        let lines = records.filter { !$0.text.isEmpty }.map { record -> String in
            let text = fill ? giriFilledPromptText(prompt: note.prompt, answer: record.text) : record.text
            return record.isOwn ? text : "\(record.answerer)「\(text)」"
        }
        parts.append(lines.joined(separator: "\n"))
    } else {
        parts.append(thoughtTitle(note))
        if !note.body.isEmpty { parts.append(note.body) }
    }
    if !hashtag.isEmpty { parts.append("#" + hashtag) }
    return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
}

/// 穴埋めのお題を回答で埋めた表示（お題の文は薄く、回答で埋めた所は太く）。
struct GiriFilledPromptText: View {
    let prompt: String
    let answer: String
    var body: some View { Text(attributed) }

    private var attributed: AttributedString {
        var value = AttributedString()
        for segment in giriFilledPromptSegments(prompt: prompt, answer: answer) {
            var part = AttributedString(segment.text)
            if segment.isFill {
                part.inlinePresentationIntent = .stronglyEmphasized
                part.foregroundColor = Color.primary
            } else {
                part.foregroundColor = Color.secondary
            }
            value += part
        }
        return value
    }
}

/// 0.15：回答案の文を直す（改行も入れられる）。
struct GiriAnswerTextEditor: View {
    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void
    var body: some View {
        Form {
            Section {
                AppCardSectionTitle(title: "回答", systemImage: "text.bubble", accentColor: AppSectionAccent.memo)
                    .listRowSeparator(.hidden)
                TextField("回答", text: $text, axis: .vertical).lineLimit(3...10)
            }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
        }
        .appEditorFormStyle()
        .navigationTitle("回答を編集").navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル", action: onCancel) }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: onSave).fontWeight(.bold)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .presentationDetents([.medium])
    }
}

/// 0.16：回答のモード（自分の回答・他人の回答）。
enum GiriAnswerMode: String, CaseIterable, Identifiable, Hashable {
    case own, others
    var id: String { rawValue }
    var title: String { self == .own ? "自分の回答" : "他人の回答" }
}

/// 0.16：お題を上に出し、自分の回答／他人の回答を切り替えて入れる画面。
@MainActor
struct GiriAnswerModePage: View {
    @EnvironmentObject private var store: GiriStore
    let noteID: String
    @State private var mode: GiriAnswerMode
    @State private var pinned = false
    init(noteID: String, initialMode: GiriAnswerMode) {
        self.noteID = noteID
        _mode = State(initialValue: initialMode)
    }
    private var note: ThoughtNote? { store.notes.first { $0.id == noteID } }
    private var event: GiriEvent? { store.events.first { $0.id == note?.eventId } }
    var body: some View {
        ScrollViewReader { proxy in
            pageForm.environment(\.giriRevealPosting, { giriRevealPostingForm(proxy) })
        }
    }

    private var pageForm: some View {
        Form {
            if let note {
                GiriNoteSections(note: note, event: event, mode: $mode, pinned: $pinned)
            } else {
                CenteredEmptyMessage(systemImage: "text.bubble", title: "このお題は削除されています")
            }
        }
        .appEditorFormStyle()
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            if pinned, let note { GiriPinnedPrompt(note: note) { withAnimation { pinned = false } } }
        }
        .navigationTitle("お題/回答").navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
    }
}

/// 0.16：会のお題をまとめて入れる（1行に1つ）。保存したあとで、それぞれのお題に回答を入れる。
@MainActor
struct GiriBulkPromptEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    let eventID: String
    var roundID: String? = nil
    @State private var text = ""
    @State private var stageID = ""
    @State private var participates = false
    @State private var initialized = false
    private var event: GiriEvent? { store.events.first { $0.id == eventID } }
    private var preview: [ThoughtNote] {
        giriBulkPromptNotes(text: text, eventID: eventID, roundID: roundID, resultStageID: stageID.isEmpty ? nil : stageID,
                            format: event?.eventFormat, participates: participates)
    }
    var body: some View {
        Form {
            Section {
                AppCardSectionTitle(title: event?.title ?? "会", systemImage: "calendar", accentColor: AppSectionAccent.artist,
                                    infoTitle: "まとめて入れる", infoMessage: "1行に1つずつお題を書きます。「〇〇」などがあるお題は穴埋めお題になります。")
                    .listRowSeparator(.hidden)
                if let stages = event?.stageResults, !stages.isEmpty, roundID == nil {
                    Picker(selection: $stageID) {
                        Text("選ばない").tag("")
                        ForEach(stages) { stage in Text(stage.name.isEmpty ? "段階" : stage.name).tag(stage.id) }
                    } label: { GiriEditorLabel("段階") }
                    .pickerStyle(.menu).tint(Color.primary)
                }
                Toggle(isOn: $participates) { GiriEditorLabel("このお題に参加") }
                    .tint(AppSectionAccent.memo)
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            Section {
                AppCardSectionTitle(title: "お題（1行に1つ）", systemImage: "lightbulb", accentColor: AppSectionAccent.memo)
                    .listRowSeparator(.hidden)
                TextField("お題を1行に1つずつ", text: $text, axis: .vertical).lineLimit(6...30)
                Button("貼り付けた文章から追加", systemImage: "doc.on.clipboard") {
                    guard let pasted = UIPasteboard.general.string, !pasted.isEmpty else { return }
                    text = text.isEmpty ? pasted : text + "\n" + pasted
                }
                .tint(accentActionColor)
                if !preview.isEmpty {
                    Text("\(preview.count)題を登録します").font(.caption).foregroundStyle(.secondary)
                }
            }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
        }
        .appEditorFormStyle()
        .navigationTitle("お題をまとめて入れる").navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save).fontWeight(.bold).disabled(preview.isEmpty)
            }
        }
        .interactiveDismissDisabled(!text.isEmpty)
        .onAppear {
            guard !initialized else { return }
            initialized = true
            participates = giriDefaultPromptParticipation(event: event)
        }
    }
    private func save() {
        let notes = preview
        store.run {
            try store.saveNotes(notes)
            playLiveStairSaveFeedback()
            dismiss()
        }
    }
}

/// 0.17：お題の画面の欄（一覧の中のお題・お題の欄・回答の欄）。
enum GiriNoteRowsPart { case overview, prompt, answers }

/// 0.17：お題の欄（お題・画像・作題者・このお題に参加）と、回答の欄（自分の回答／他人の回答のタブ）。
struct GiriNoteSections: View {
    let note: ThoughtNote
    let event: GiriEvent?
    @Binding var mode: GiriAnswerMode
    /// 0.18：お題を上に固定している時は、お題の欄を出さない（上に出ている）。
    @Binding var pinned: Bool
    var body: some View {
        if !pinned {
            Section {
                HStack {
                    AppCardSectionTitle(title: "お題", systemImage: "lightbulb", accentColor: AppSectionAccent.memo)
                    Spacer(minLength: 8)
                    Button { withAnimation { pinned = true } } label: {
                        Image(systemName: "pin").font(.body.weight(.semibold)).foregroundStyle(accentActionColor)
                            .frame(width: 36, height: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("お題を上に固定")
                }
                .listRowSeparator(.hidden)
                GiriThoughtNoteRows(note: note, event: event, onEdit: {}, part: .prompt)
            }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
        }
        Section {
            AppCardSectionTitle(title: "回答", systemImage: "text.bubble", accentColor: mode == .own ? AppSectionAccent.artist : AppSectionAccent.favorite)
                .listRowSeparator(.hidden)
            GiriThoughtNoteRows(note: note, event: event, onEdit: {}, part: .answers, mode: $mode)
        }.appSectionCardStyle(accentColor: mode == .own ? AppSectionAccent.artist : AppSectionAccent.favorite)
    }
}

/// 0.18：上に固定したお題（ヘッダーのように出す）。ピンを押すと固定を外す。
struct GiriPinnedPrompt: View {
    let note: ThoughtNote
    let onUnpin: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(thoughtTitle(note)).font(.headline).lineLimit(3)
                Spacer(minLength: 8)
                Button(action: onUnpin) {
                    Image(systemName: "pin.fill").font(.body.weight(.semibold)).foregroundStyle(accentActionColor)
                        .frame(width: 36, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("お題の固定を外す")
            }
            // 0.22：固定しない時と同じ大きさ（画像は押すと拡大）。
            if !note.imageDataBase64.isEmpty {
                GiriThoughtImage(base64: note.imageDataBase64).frame(maxHeight: giriPromptImageHeight)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appTintedCard(accentColor: AppSectionAccent.memo)
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(appBackgroundColor)
    }
}

// MARK: - 0.21 回答案の入力欄をキーボードの上に見せる

let giriPostingFormID = "giri-posting-form"

/// お題の画面の画像の高さ（固定した時も同じ）。
let giriPromptImageHeight: CGFloat = 130

private struct GiriRevealPostingKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// お題の画面で、回答案の入力欄（見出しから「投稿」まで）をキーボードの上に見せる。
    var giriRevealPosting: (() -> Void)? {
        get { self[GiriRevealPostingKey.self] }
        set { self[GiriRevealPostingKey.self] = newValue }
    }
}

/// キーボードが出てから、入力欄の行の下端（「投稿」）を見える位置へずらす。
@MainActor
func giriRevealPostingForm(_ proxy: ScrollViewProxy) {
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(350))
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(giriPostingFormID, anchor: .bottom) }
    }
}
