import SwiftUI
import PhotosUI
import UIKit
import ImageIO

private enum ThoughtAnswerScope: String, CaseIterable, Identifiable {
    case long, other
    var id: String { rawValue }
    var title: String { self == .long ? "長考" : "その他" }
}

// Card lists use the source LiveListEventCard directly in a full-width scroll
// container. Grouped List row backgrounds/insets must not wrap these cards.
@MainActor
struct GiriThinkingView: View {
    @EnvironmentObject private var store: GiriStore
    @EnvironmentObject private var navigation: GiriNavigation
    @State private var promptMode = false
    @State private var answerScope: ThoughtAnswerScope = .long
    @State private var ownerFilter = "all"
    @State private var search = ""
    @State private var path: [GiriThoughtDestination] = []
    @State private var usedFilter = "all"
    @State private var editing: ThoughtNote?
    @State private var creatingKind: NoteKind?
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
            .sheet(item: $creatingKind) { kind in
                NavigationStack {
                    GiriThoughtEditor(kind: kind,
                        preferredFormat: !promptMode && answerScope == .long && kind == .answers ? .onlineLong : .live,
                        answerCategory: !promptMode && answerScope == .long && kind == .answers ? "long" : "other")
                }
            }
            .navigationDestination(for: GiriThoughtDestination.self) { destination in
                switch destination {
                case .event(let id): GiriThoughtsForEvent(eventID: id)
                case .site(let id): GiriThoughtsForSite(siteID: id)
                case .round(let eventID, let roundID): GiriRoundWorkspace(eventID: eventID, roundID: roundID)
                case .note(let id): GiriThoughtNotePage(noteID: id)
                }
            }
            .confirmationDialog("メモを削除しますか？", isPresented: Binding(
                get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }
            ), titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    guard let note = deleteCandidate else { return }
                    store.run { try store.deleteNote(note.id); playLiveStairDeleteFeedback() }
                    deleteCandidate = nil
                }
            } message: { Text(deleteCandidate.map(thoughtTitle) ?? "") }
        }
        .onAppear(perform: consumeDestination)
        .onChange(of: navigation.thoughtDestination) { _, _ in consumeDestination() }
    }

    private func consumeDestination() {
        guard let destination = navigation.thoughtDestination else { return }
        promptMode = false
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
                    Button { creatingKind = promptMode ? .prompts : .answers } label: { headerIcon("plus") }
                        .accessibilityLabel(promptMode ? "お題を作る" : "回答メモを作る")
                        .contextMenu {
                            Button("自由メモを作る", systemImage: "square.and.pencil") { creatingKind = .free }
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

    private func thoughtList(now: Date) -> some View {
        let postings = activePostingGroups(now: now)
        let activeNoteIDs = Set(postings.flatMap { $0.notes.map(\.id) })
        let notes = historyNotes(excluding: !promptMode && answerScope == .long ? activeNoteIDs : [])
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                filters
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                if !promptMode && answerScope == .long {
                    thoughtSectionHeading("投稿中のお題", symbol: "clock", count: postings.reduce(0) { $0 + max(1, $1.notes.count) })
                    if postings.isEmpty {
                        emptyCard("現在投稿中のお題はありません", symbol: "text.bubble")
                    }
                    ForEach(postings) { posting in
                        postingGroup(posting, now: now)
                    }
                }
                thoughtSectionHeading(promptMode ? "保存したお題" : answerScope == .long ? "履歴" : "回答メモ・ツボ上げ",
                    symbol: promptMode ? "lightbulb" : "text.bubble", count: notes.count)
                if notes.isEmpty {
                    emptyCard(search.isEmpty ? (promptMode ? "お題がありません" : "回答の記録がありません") : "該当する記録がありません",
                        symbol: promptMode ? "lightbulb" : "text.bubble")
                }
                ForEach(notes) { note in
                    Button { path.append(.note(note.id)) } label: {
                        GiriThoughtCard(note: note, event: eventFor(note))
                    }
                    .buttonStyle(.plain).thoughtCardRow()
                    .contextMenu { noteMenu(note) }
                }
            }.padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(appBackgroundColor)
    }

    private var filters: some View {
        VStack(spacing: 12) {
            if !promptMode {
                Picker("回答の使い方", selection: $answerScope) {
                    ForEach(ThoughtAnswerScope.allCases) { scope in Text(scope.title).tag(scope) }
                }.pickerStyle(.segmented)
                if answerScope == .other {
                    Picker("回答者", selection: $ownerFilter) {
                        Text("すべて").tag("all")
                        Text("自分").tag("mine")
                        Text("他人").tag("others")
                    }.pickerStyle(.segmented)
                }
            } else {
                HStack {
                    Text("使用状況").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Picker("使用状況", selection: $usedFilter) {
                        Text("すべて").tag("all")
                        Text("未使用").tag("unused")
                        Text("使用済み").tag("used")
                    }.labelsHidden().pickerStyle(.menu).tint(.primary)
                }
            }
            AppSearchField(text: $search, placeholder: promptMode ? "お題・メモを検索" : "お題・回答・回答者・会を検索")
        }
    }

    private func eventFor(_ note: ThoughtNote) -> GiriEvent? { store.events.first { $0.id == note.eventId } }

    private func belongsToLong(_ note: ThoughtNote) -> Bool {
        guard note.kind == .answers, !note.isOthersAnswer else { return false }
        if let category = note.answerCategory { return category == "long" }
        return eventFor(note)?.eventFormat == .onlineLong
    }

    private func historyNotes(excluding activeIDs: Set<String>) -> [ThoughtNote] {
        store.notes.filter { note in
            if promptMode {
                guard note.kind == .prompts && (usedFilter == "all" || note.used == (usedFilter == "used")) else { return false }
            } else {
                guard note.kind != .prompts && (belongsToLong(note) == (answerScope == .long)) else { return false }
                if answerScope == .long && activeIDs.contains(note.id) { return false }
                if answerScope == .other {
                    if ownerFilter == "mine" && note.isOthersAnswer { return false }
                    if ownerFilter == "others" && !note.isOthersAnswer { return false }
                }
            }
            return thoughtSearchMatches(note, event: eventFor(note), query: search)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func activePostingGroups(now: Date) -> [ThoughtPostingGroup] {
        store.events.filter { $0.eventFormat == .onlineLong && $0.isActualParticipant }.flatMap { event in
            event.effectiveRounds.filter { $0.isSubmissionOpen(now) }.map { round in
                ThoughtPostingGroup(event: event, round: round,
                    notes: store.notes.filter { note in
                        belongsToLong(note) && thoughtMatches(note, eventID: event.id, roundID: round.id)
                    }.sorted { $0.updatedAt > $1.updatedAt })
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
                        Label("お題・回答を追加", systemImage: "plus.circle").font(.subheadline).foregroundStyle(accentActionColor)
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
        } else {
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
            .navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
    }
}

@MainActor
struct GiriThoughtsForEvent: View {
    @EnvironmentObject private var store: GiriStore
    let eventID: String
    @State private var creating = false
    @State private var search = ""
    private var event: GiriEvent? { store.events.first { $0.id == eventID } }
    private var rounds: [EventRound] {
        (event?.effectiveRounds ?? []).sorted {
            ($0.submissionStart ?? $0.votingEnd ?? .distantPast) > ($1.submissionStart ?? $1.votingEnd ?? .distantPast)
        }
    }
    private var independentNotes: [ThoughtNote] {
        store.notes.filter { note in
            guard note.eventId == eventID, note.kind != .prompts else { return false }
            return (note.roundId == nil || !rounds.contains { $0.id == note.roundId }) && thoughtSearchMatches(note, event: event, query: search)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
    private var matchingRounds: [EventRound] {
        rounds.filter { round in
            search.isEmpty || round.name.localizedStandardContains(search) || store.notes.contains {
                thoughtMatches($0, eventID: eventID, roundID: round.id) && thoughtSearchMatches($0, event: event, query: search)
            }
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let event {
                    VStack(alignment: .leading, spacing: 8) {
                        AppCardSectionTitle(title: event.title, systemImage: thoughtFormatSymbol(event.eventFormat), accentColor: AppSectionAccent.artist)
                        Text(event.eventFormat.title).font(.subheadline).foregroundStyle(.secondary)
                        if !event.affiliation.isEmpty { LabeledContent("所属", value: event.affiliation) }
                        if !event.cycleResult.isEmpty { LabeledContent("結果", value: event.cycleResult) }
                        if let rank = event.cyclePlacement { LabeledContent("順位", value: "\(rank)位") }
                    }.padding(14).appTintedCard(accentColor: AppSectionAccent.artist).thoughtCardRow()
                    AppSearchField(text: $search, placeholder: "段階・お題・回答を検索")
                        .padding(.horizontal, 18).padding(.vertical, 8)
                    ForEach(matchingRounds) { round in
                        NavigationLink(value: GiriThoughtDestination.round(eventID: eventID, roundID: round.id)) {
                            GiriThoughtRoundCard(event: event, round: round)
                        }.buttonStyle(.plain).thoughtCardRow()
                    }
                    ForEach(independentNotes) { note in
                        NavigationLink(value: GiriThoughtDestination.note(note.id)) { GiriThoughtCard(note: note, event: event) }
                            .buttonStyle(.plain).thoughtCardRow()
                    }
                    Button { creating = true } label: { Label("お題・回答を追加", systemImage: "plus.circle").frame(maxWidth: .infinity, alignment: .leading) }
                        .buttonStyle(.plain).foregroundStyle(accentActionColor)
                        .padding(14).appTintedCard(accentColor: AppSectionAccent.memo).thoughtCardRow()
                } else {
                    CenteredEmptyMessage(systemImage: "text.bubble", title: "この会は削除されています")
                }
            }.padding(.bottom, 24)
        }.background(appBackgroundColor).scrollDismissesKeyboard(.interactively)
            .navigationTitle("お題/回答").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .sheet(isPresented: $creating) {
                NavigationStack { GiriThoughtEditor(kind: .answers, eventID: eventID) }
            }
    }
}

private struct GiriThoughtEventCard: View {
    @EnvironmentObject private var store: GiriStore
    let event: GiriEvent
    var body: some View {
        GiriListCard(accentColor: AppSectionAccent.artist) {
            VStack(alignment: .leading, spacing: 6) {
                Text(GiriDateText.day(thoughtEventDate(event))).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                HStack {
                    Text(event.title).font(.headline).foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text(thoughtPhase(event: event, round: thoughtNewestRound(event))).font(.caption.weight(.semibold)).foregroundStyle(AppSectionAccent.artist)
                }
                let cycleLabels = [event.siteSeason, event.siteCycleNumber.map { "第\($0)回" } ?? "", event.affiliation].filter { !$0.isEmpty }
                if !cycleLabels.isEmpty { Text(cycleLabels.joined(separator: "・")).font(.subheadline).foregroundStyle(.secondary) }
                if !event.cycleResult.isEmpty { Text(event.cycleResult).font(.subheadline).foregroundStyle(.secondary) }
                if let rank = event.cyclePlacement { Text("\(rank)位").font(.subheadline.weight(.semibold)).foregroundStyle(AppSectionAccent.ticket) }
                let count = store.notes.filter { $0.eventId == event.id && $0.kind != .prompts }.count
                Text("\(count)題").font(.caption).foregroundStyle(.secondary)
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
            .navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
    }
}

/// The period and its prompt cards are kept in the Thinking tab.
@MainActor
struct GiriRoundWorkspaceSections: View {
    @EnvironmentObject private var store: GiriStore
    let eventID: String
    let roundID: String
    @State private var editing: ThoughtNote?
    @State private var creating = false
    @State private var deleteCandidate: ThoughtNote?
    private var event: GiriEvent? { store.events.first { $0.id == eventID } }
    private var round: EventRound? { event?.effectiveRounds.first { $0.id == roundID } }
    private var notes: [ThoughtNote] {
        store.notes.filter { $0.kind == .answers && thoughtMatches($0, eventID: eventID, roundID: roundID) }
            .sorted { $0.updatedAt > $1.updatedAt }
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
                    }.buttonStyle(.borderless)
                }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
            }
            if round != nil {
                Section {
                    Button { creating = true } label: { Label("お題と回答を追加", systemImage: "plus.circle") }
                }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
            }
        }
        .sheet(item: $editing) { note in NavigationStack { GiriThoughtEditor(note: note) } }
        .sheet(isPresented: $creating) {
            NavigationStack { GiriThoughtEditor(kind: .answers, eventID: eventID, roundID: roundID) }
        }
        .confirmationDialog("お題と回答を削除しますか？", isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }), titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                guard let note = deleteCandidate else { return }
                store.run { try store.deleteNote(note.id); playLiveStairDeleteFeedback() }
                deleteCandidate = nil
            }
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
                Text(thoughtPhase(event: event, round: round))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(AppSectionAccent.artist)
                GiriThoughtPeriodRow(title: "投稿", start: round.submissionStart, end: round.submissionEnd, enabled: round.submissionEnabled, accent: AppSectionAccent.artist)
                GiriThoughtPeriodRow(title: "投票", start: round.votingStart, end: round.votingEnd, enabled: round.votingRequired, accent: AppSectionAccent.memo)
                if event.meetingType == .tournament {
                    NavigationLink { GiriResultEntry(eventID: eventID, initialRoundID: roundID) } label: { Label("この回の結果", systemImage: "trophy") }
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
    let noteID: String
    @State private var editing = false
    private var note: ThoughtNote? { store.notes.first { $0.id == noteID } }
    private var event: GiriEvent? { store.events.first { $0.id == note?.eventId } }
    var body: some View {
        Form {
            if let note {
                if let event, let round = event.effectiveRounds.first(where: { $0.id == note.roundId }) {
                    Section {
                        AppCardSectionTitle(title: event.title, systemImage: thoughtFormatSymbol(event.eventFormat), accentColor: AppSectionAccent.artist)
                            .listRowSeparator(.hidden)
                        Text(thoughtRoundLabel(event: event, round: round)).font(.subheadline.weight(.semibold))
                        Text(thoughtPhase(event: event, round: round)).font(.subheadline.weight(.semibold))
                        GiriThoughtPeriodRow(title: "投稿", start: round.submissionStart, end: round.submissionEnd, enabled: round.submissionEnabled, accent: AppSectionAccent.artist)
                        GiriThoughtPeriodRow(title: "投票", start: round.votingStart, end: round.votingEnd, enabled: round.votingRequired, accent: AppSectionAccent.memo)
                    }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
                }
                Section { GiriThoughtNoteRows(note: note, event: event, onEdit: { editing = true }) }
                    .appSectionCardStyle(accentColor: AppSectionAccent.memo)
            } else {
                CenteredEmptyMessage(systemImage: "text.bubble", title: "このメモは削除されています")
            }
        }
        .appEditorFormStyle().navigationTitle("お題/回答").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { if note != nil { Button("編集") { editing = true } } }
            ToolbarItem(placement: .topBarTrailing) {
                if let note {
                    Menu { GiriThoughtShareActions(note: note, event: event) } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("お題・回答を共有")
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let note { NavigationStack { GiriThoughtEditor(note: note) } }
        }
    }
}

private struct GiriThoughtCard: View {
    let note: ThoughtNote
    let event: GiriEvent?
    var body: some View {
        GiriListCard(accentColor: AppSectionAccent.memo) {
            HStack(alignment: .top, spacing: 12) {
                if let data = Data(base64Encoded: note.imageDataBase64), let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(thoughtTitle(note)).font(.headline).foregroundStyle(.primary).lineLimit(3)
                    if note.kind == .prompts {
                        Text(note.used ? "使用済み" : "未使用").font(.subheadline).foregroundStyle(.secondary)
                        if let event { Text(event.title).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    } else {
                        if let event {
                            Text(event.title).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            if event.eventFormat == .onlineLong && !note.isOthersAnswer {
                                Text(thoughtPhase(event: event, round: thoughtRound(note, event: event)))
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(AppSectionAccent.artist)
                                if let round = thoughtRound(note, event: event) {
                                    let deadline = round.isSubmissionOpen(Date()) ? round.submissionEnd : round.votingEnd
                                    if let deadline {
                                        Text("締切 " + GiriDateText.dateTime(deadline)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        if note.kind == .answers {
                            if let answer = note.effectiveAnswerRecords.first(where: \.isSubmitted) ?? note.effectiveAnswerRecords.first,
                               answer.text != thoughtTitle(note) {
                                Text(answer.text).font(.subheadline).foregroundStyle(.primary).lineLimit(3)
                            }
                            Text(note.isOthersAnswer ? (note.answerer.isEmpty ? "他人の回答" : note.answerer + "の回答") : "自分の回答")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        let summary = thoughtResultSummary(note, event: event)
                        if !summary.isEmpty { Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.trailing, 18)
        }
    }
}

private struct GiriThoughtShareActions: View {
    let note: ThoughtNote
    let event: GiriEvent?
    var record: AnswerRecord? = nil
    var body: some View {
        if let url = thoughtTweetURL(note, event: event, record: record) {
            Link(destination: url) { Label("Xで投稿を作成", systemImage: "square.and.pencil") }
        }
        ShareLink(item: thoughtShareText(note, event: event, record: record)) {
            Label("共有", systemImage: "square.and.arrow.up")
        }
    }
}

@MainActor
private struct GiriThoughtNoteRows: View {
    @EnvironmentObject private var store: GiriStore
    let note: ThoughtNote
    let event: GiriEvent?
    let onEdit: () -> Void
    var body: some View {
        Text(thoughtTitle(note)).font(.headline).textSelection(.enabled)
        if !note.imageDataBase64.isEmpty { GiriThoughtImage(base64: note.imageDataBase64) }
        if note.isOthersAnswer {
            Text("回答者　" + (note.answerer.isEmpty ? "未設定" : note.answerer)).font(.subheadline).foregroundStyle(.secondary)
        }
        if note.kind == .answers {
            let records = note.effectiveAnswerRecords
            if records.isEmpty {
                Button("回答案を追加", action: onEdit)
            }
            ForEach(records) { record in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        if !note.isOthersAnswer { Button { toggleSubmitted(record.id) } label: {
                            Image(systemName: record.isSubmitted ? "checkmark.square.fill" : "square")
                                .foregroundStyle(record.isSubmitted ? accentActionColor : Color.secondary)
                        }.buttonStyle(.borderless)
                            .accessibilityLabel(record.isSubmitted ? "提出した回答の選択を外す" : "提出した回答にする")
                        }
                        Text(record.text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        if record.isSubmitted && !note.isOthersAnswer { Text("提出").font(.caption.weight(.semibold)).foregroundStyle(accentActionColor) }
                        Menu { GiriThoughtShareActions(note: note, event: event, record: record) } label: {
                            Image(systemName: "ellipsis").frame(minWidth: 28, minHeight: 28)
                        }.accessibilityLabel("この回答を共有")
                    }
                    let result = thoughtAnswerResult(record)
                    if !result.isEmpty { Text(result).font(.caption.weight(.medium)).foregroundStyle(AppSectionAccent.ticket) }
                }.padding(.vertical, 2)
            }
        } else if !note.body.isEmpty {
            Text(note.body).textSelection(.enabled)
        }
    }
    private func toggleSubmitted(_ id: String) {
        var updated = note
        var answers = updated.effectiveAnswerRecords
        guard let index = answers.firstIndex(where: { $0.id == id }) else { return }
        answers[index].isSubmitted.toggle()
        updated.answerRecords = answers
        updated.usesAnswerRecords = true
        updated.answers = answers.map(\.text)
        updated.updatedAt = Date()
        store.run { try store.saveNote(updated) }
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

/// Separate answer/prompt pages share image handling and safe draft persistence;
/// the creation mode is fixed by the page instead of a generic "kind" menu.
@MainActor
struct GiriThoughtEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    @State private var initial: ThoughtNote
    @State private var draft: ThoughtNote
    @State private var primaryText: String
    @State private var bodyText: String
    @State private var answers: [AnswerRecord]
    @State private var initialAnswers: [AnswerRecord]
    @State private var selectedFormat: EventFormat
    @State private var relationInitialized = false
    @State private var showingAllEvents = false
    @State private var eventSearch = ""
    @State private var readingImage = false
    @State private var error: String?
    @State private var discard = false
    @State private var answerCategory: String
    private let requestedAnswerCategory: String?

    init(note: ThoughtNote? = nil, kind: NoteKind = .answers, eventID: String? = nil, roundID: String? = nil,
         preferredFormat: EventFormat? = nil, answerCategory: String? = nil) {
        var value = note ?? ThoughtNote()
        if note == nil {
            value.kind = kind
            value.eventId = eventID
            value.roundId = roundID
        }
        _initial = State(initialValue: value)
        _draft = State(initialValue: value)
        _primaryText = State(initialValue: thoughtEditorPrimaryText(value))
        _bodyText = State(initialValue: value.body)
        _answers = State(initialValue: value.effectiveAnswerRecords)
        _initialAnswers = State(initialValue: value.effectiveAnswerRecords)
        _selectedFormat = State(initialValue: preferredFormat ?? (value.answerCategory == "long" ? .onlineLong : .live))
        requestedAnswerCategory = answerCategory
        _answerCategory = State(initialValue: value.answerCategory ?? answerCategory ?? "other")
    }

    var body: some View {
        Form {
            periodSection
            Section {
                AppCardSectionTitle(title: "関連する会", systemImage: "link", accentColor: AppSectionAccent.memo)
                    .listRowSeparator(.hidden)
                Picker("形式", selection: $selectedFormat) {
                    ForEach(EventFormat.allCases) { format in Text(format.title).tag(format) }
                }.pickerStyle(.menu).tint(.primary)
                eventPicker
                if event?.eventFormat.hasOnlineRounds == true { roundPicker }
                if draft.kind == .prompts { Toggle("使用済み", isOn: $draft.used).tint(AppSectionAccent.memo) }
            }.appSectionCardStyle(accentColor: AppSectionAccent.memo)

            Section {
                AppCardSectionTitle(title: draft.kind == .free ? "タイトル" : "お題", systemImage: draft.kind == .free ? "square.and.pencil" : "lightbulb", accentColor: AppSectionAccent.memo)
                    .listRowSeparator(.hidden)
                TextField(draft.kind == .free ? "タイトル（任意）" : answerCategory == "other" && draft.kind == .answers ? "お題（任意）" : "お題を入力", text: $primaryText, axis: .vertical)
                    .lineLimit(1...10)
                GiriThoughtImagePicker(base64: $draft.imageDataBase64, reading: $readingImage, error: $error)
            }.appSectionCardStyle(accentColor: AppSectionAccent.memo)

            if draft.kind == .answers {
                answerSections
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
        .navigationTitle(draft.kind == .prompts ? "お題を作る" : draft.kind == .answers ? "回答を考える" : "メモ")
        .navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
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
        .confirmationDialog("変更を保存せずに戻りますか？", isPresented: $discard, titleVisibility: .visible) {
            Button("保存せずに戻る", role: .destructive) { dismiss() }
        }
        .onAppear {
            if !relationInitialized {
                if let event {
                    selectedFormat = event.eventFormat
                    if initial.answerCategory == nil && requestedAnswerCategory == nil {
                        answerCategory = event.eventFormat == .onlineLong && !draft.isOthersAnswer ? "long" : "other"
                    }
                }
                relationInitialized = true
            }
        }
        .onChange(of: selectedFormat) { _, value in
            if relationInitialized && value != .onlineLong && answerCategory == "long" { answerCategory = "other" }
            if relationInitialized, let event, event.eventFormat != value {
                draft.eventId = nil; draft.roundId = nil
            }
        }
        .sheet(isPresented: $showingAllEvents) { allEventsPicker }
    }

    @ViewBuilder private var periodSection: some View {
        if let event, let round = thoughtRound(draft, event: event) {
            Section {
                AppCardSectionTitle(title: event.title, systemImage: thoughtFormatSymbol(event.eventFormat), accentColor: AppSectionAccent.artist)
                    .listRowSeparator(.hidden)
                Text(thoughtRoundLabel(event: event, round: round)).font(.subheadline.weight(.semibold))
                Text(thoughtPhase(event: event, round: round)).font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppSectionAccent.artist)
                GiriThoughtPeriodRow(title: "投稿", start: round.submissionStart, end: round.submissionEnd, enabled: round.submissionEnabled, accent: AppSectionAccent.artist)
                GiriThoughtPeriodRow(title: "投票", start: round.votingStart, end: round.votingEnd, enabled: round.votingRequired, accent: AppSectionAccent.memo)
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
        }
    }

    @ViewBuilder private var answerSections: some View {
        Section {
            AppCardSectionTitle(title: "回答者", systemImage: "person", accentColor: AppSectionAccent.memo)
                .listRowSeparator(.hidden)
            Picker("回答者", selection: $draft.isOthersAnswer) {
                Text("自分の回答").tag(false)
                Text("他人の回答").tag(true)
            }.pickerStyle(.segmented)
            if draft.isOthersAnswer {
                GiriPlayerSuggestionField(title: "回答者", text: $draft.answerer, showsLabel: true, textAlignment: .trailing)
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
        Section {
            AppCardSectionTitle(title: "回答案", systemImage: "text.bubble", accentColor: AppSectionAccent.memo)
                .listRowSeparator(.hidden)
            ForEach(answers) { record in
                if let index = answers.firstIndex(where: { $0.id == record.id }) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            TextField("回答案", text: answerBinding(record.id).text, axis: .vertical)
                                .lineLimit(1...8)
                            Button(role: .destructive) { answers.removeAll { $0.id == record.id } } label: {
                                Image(systemName: "minus.circle").frame(minWidth: 28, minHeight: 32)
                            }.buttonStyle(.borderless)
                        }
                        if !draft.isOthersAnswer {
                            Toggle("提出した回答", isOn: answerBinding(answers[index].id).isSubmitted)
                                .tint(accentActionColor)
                        }
                    }.padding(.vertical, 4)
                }
            }
            Button("回答案を追加", systemImage: "plus.circle") { answers.append(AnswerRecord()) }
            Button("貼り付けた文章から追加", systemImage: "doc.on.clipboard") {
                guard let text = UIPasteboard.general.string else { return }
                answers.append(contentsOf: thoughtLines(text).map { AnswerRecord(text: $0) })
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.memo)

        if !draft.isOthersAnswer && answers.contains(where: \.isSubmitted) {
            Section {
                AppCardSectionTitle(title: "提出した回答の結果", systemImage: "trophy", accentColor: AppSectionAccent.ticket)
                    .listRowSeparator(.hidden)
                GiriAnswerResultFields(records: $answers)
            }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
        }
        if !bodyText.isEmpty && !initial.usesAnswerRecords {
            Section {
                AppCardSectionTitle(title: "元の本文", systemImage: "doc.text", accentColor: AppSectionAccent.memo)
                    .listRowSeparator(.hidden)
                Text(bodyText).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
            }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
        }
    }

    private var event: GiriEvent? { store.events.first { $0.id == draft.eventId } }

    private var primaryEvents: [GiriEvent] {
        let now = Date()
        return store.events.filter { event in
            guard event.eventFormat == selectedFormat, event.isActualParticipant else { return false }
            return selectedFormat == .live || event.participationState(now: now) == .ongoing
        }.sorted { thoughtEventComesFirst($0, $1, now: now) }
    }

    private var allEvents: [GiriEvent] {
        store.events.filter { $0.eventFormat == selectedFormat && (eventSearch.isEmpty || [$0.title, $0.organizer, $0.venue].joined(separator: " ").localizedStandardContains(eventSearch)) }
            .sorted { thoughtEventComesFirst($0, $1, now: Date()) }
    }

    private var eventPicker: some View {
        Group {
            Picker("関連する会", selection: Binding(
                get: { draft.eventId }, set: { draft.eventId = $0; draft.roundId = nil }
            )) {
                Text("関連づけなし").tag(nil as String?)
                ForEach(primaryEvents) { event in Text(thoughtEventPickerTitle(event)).tag(Optional(event.id)) }
                if let selected = event, !primaryEvents.contains(where: { $0.id == selected.id }) {
                    Text(thoughtEventPickerTitle(selected)).tag(Optional(selected.id))
                }
                if let id = draft.eventId, event == nil { Text("削除された会").tag(Optional(id)) }
            }.pickerStyle(.menu).tint(.primary)
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
                        showingAllEvents = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title).foregroundStyle(.primary)
                            Text(thoughtEventPickerTitle(event)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .appIndexListStyle().searchable(text: $eventSearch, prompt: "会・主催者・会場")
            .navigationTitle("その他の会").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { showingAllEvents = false } } }
        }
    }

    private var roundPicker: some View {
        Picker("日程", selection: $draft.roundId) {
            Text("関連づけなし").tag(nil as String?)
            if let event {
                ForEach(event.effectiveRounds.sorted { ($0.submissionStart ?? .distantPast) > ($1.submissionStart ?? .distantPast) }) { round in
                    Text(thoughtRoundLabel(event: event, round: round)).tag(Optional(round.id))
                }
            }
            if let id = draft.roundId, !(event?.effectiveRounds.contains(where: { $0.id == id }) ?? false) {
                Text("削除された日程").tag(Optional(id))
            }
        }.pickerStyle(.menu).tint(.primary)
    }

    private func answerBinding(_ id: String) -> Binding<AnswerRecord> {
        Binding(get: { answers.first { $0.id == id } ?? AnswerRecord(id: id) }, set: { value in
            if let index = answers.firstIndex(where: { $0.id == id }) { answers[index] = value }
        })
    }

    private var isDirty: Bool {
        draft != initial || primaryText != thoughtEditorPrimaryText(initial) || bodyText != initial.body || answers != initialAnswers
    }

    private func save() {
        let primary = primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAnswer = draft.kind == .answers && answers.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if draft.kind == .answers && (answerCategory == "other" || draft.isOthersAnswer) {
            guard hasAnswer || !primary.isEmpty || !draft.imageDataBase64.isEmpty else {
                error = "お題か回答を入力してください。"; return
            }
        } else if (draft.kind != .free && primary.isEmpty && draft.imageDataBase64.isEmpty) || (primary.isEmpty && body.isEmpty && draft.imageDataBase64.isEmpty) {
            error = draft.kind == .free ? "タイトルか本文を入力してください。" : "お題か画像を入力してください。"
            return
        }
        if draft.kind == .answers && draft.isOthersAnswer && draft.answerer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = "他人の回答を記録する場合は回答者を入力してください。"
            return
        }
        var saved = draft
        let fallbackTitle = hasAnswer ? answers.first(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.text ?? "回答" : body.components(separatedBy: .newlines).first ?? "メモ"
        saved.title = String((!primary.isEmpty ? primary : !draft.imageDataBase64.isEmpty ? "画像のお題" : fallbackTitle).prefix(120))
        saved.prompt = draft.kind == .free ? "" : primary
        saved.body = bodyText
        if draft.kind == .answers {
            saved.answerCategory = draft.isOthersAnswer ? "other" : answerCategory
            if answers.contains(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ($0.placement != nil || $0.points != nil || $0.voterCount != nil) }) {
                error = "結果を記録した回答の本文を入力してください。"
                return
            }
            saved.answerRecords = answers.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { record in
                var copy = record; copy.text = record.text.trimmingCharacters(in: .whitespacesAndNewlines); return copy
            }
            saved.usesAnswerRecords = true
            saved.answers = saved.answerRecords.map(\.text)
        }
        saved.used = draft.kind == .prompts && draft.used
        saved.updatedAt = Date()
        do { try store.saveNote(saved); playLiveStairSaveFeedback(); dismiss() }
        catch { self.error = "保存できませんでした。内容を残したまま再試行できます。\n\(error.localizedDescription)" }
    }
}

/// Result entry and Thinking use the same submitted-answer fields. Unsubmitted
/// drafts stay in the binding and are never discarded by this view.
struct GiriAnswerResultFields: View {
    @Binding var records: [AnswerRecord]
    var body: some View {
        if !records.contains(where: \.isSubmitted) {
            Text("提出した回答をお題/回答で選択してください。").font(.subheadline).foregroundStyle(.secondary)
        }
        ForEach(records.filter(\.isSubmitted)) { record in
            VStack(alignment: .leading, spacing: 6) {
                Text(record.text).font(.subheadline.weight(.semibold)).lineLimit(4)
                GiriIntegerField(title: "この回答の順位（任意）", value: recordBinding(record.id).placement, suffix: "位")
                GiriIntegerField(title: "投票人数（任意）", value: recordBinding(record.id).voterCount, suffix: "人")
                HStack {
                    TextField("得点（任意）", value: recordBinding(record.id).points, format: .number).keyboardType(.decimalPad)
                    Text("点").foregroundStyle(.secondary)
                }
                Stepper("1人あたりの満点 \(record.maxPointsPerVoter)点", value: recordBinding(record.id).maxPointsPerVoter, in: 1...1000)
                if let rate = record.voteRate {
                    LabeledContent("得票率", value: rate.formatted(.number.precision(.fractionLength(2))) + "%")
                }
                TextField("回答のメモ", text: recordBinding(record.id).memo, axis: .vertical).lineLimit(1...5)
            }.padding(.vertical, 4)
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
                    Label(reading ? "読み込み中" : "画像のお題", systemImage: "photo")
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

private struct GiriThoughtImage: View {
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
        parts = [round.name, "\(round.promptNumber)回目"]
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
    if let rate = result.voteRate { parts.append("得票率" + rate.formatted(.number.precision(.fractionLength(2))) + "%") }
    return parts.joined(separator: " · ")
}

private func thoughtAnswerResult(_ record: AnswerRecord) -> String {
    var parts: [String] = []
    if let placement = record.placement { parts.append("\(placement)位") }
    if let rate = record.voteRate { parts.append("得票率" + rate.formatted(.number.precision(.fractionLength(2))) + "%") }
    if let points = record.points { parts.append(points.formatted(.number.precision(.fractionLength(0...2))) + "点") }
    return parts.joined(separator: " · ")
}

private func thoughtResultSummary(_ note: ThoughtNote, event: GiriEvent?) -> String {
    if note.kind == .prompts { return note.used ? "使用済み" : "未使用" }
    guard note.kind == .answers else { return String(note.body.prefix(100)) }
    let records = note.effectiveAnswerRecords
    let submitted = records.filter(\.isSubmitted)
    var parts = note.isOthersAnswer || note.answerCategory == "other" ? ["回答\(records.count)件"] : ["回答\(records.count)案", "提出\(submitted.count)件"]
    for record in submitted.prefix(2) {
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
    let fields = [note.title, note.prompt, note.body, note.answerer, event?.title ?? "", event?.affiliation ?? "", event?.block ?? ""] + note.effectiveAnswerRecords.map(\.text)
    return fields.joined(separator: " ").localizedStandardContains(trimmed)
}

/// Explicit taps open a compose screen; the app never sends a post itself.
private func thoughtTweetURL(_ note: ThoughtNote, event: GiriEvent?, record: AnswerRecord? = nil) -> URL? {
    var components = URLComponents(string: "https://twitter.com/intent/tweet")
    components?.queryItems = [URLQueryItem(name: "text", value: thoughtShareText(note, event: event, record: record))]
    return components?.url
}

private func thoughtShareText(_ note: ThoughtNote, event: GiriEvent?, record: AnswerRecord? = nil) -> String {
    var parts: [String] = []
    if let event { parts.append(event.title) }
    if note.kind == .answers {
        if !note.prompt.isEmpty { parts.append("お題：" + note.prompt) }
        let records: [AnswerRecord]
        if let record { records = [record] }
        else {
            let submitted = note.effectiveAnswerRecords.filter(\.isSubmitted)
            records = submitted.isEmpty ? note.effectiveAnswerRecords : submitted
        }
        parts.append(contentsOf: records.map(\.text).filter { !$0.isEmpty })
        if note.isOthersAnswer && !note.answerer.isEmpty { parts.append("回答：" + note.answerer) }
    } else {
        parts.append(thoughtTitle(note))
        if !note.body.isEmpty { parts.append(note.body) }
    }
    return parts.joined(separator: "\n\n")
}
