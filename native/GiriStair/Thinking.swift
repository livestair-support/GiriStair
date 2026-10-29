import SwiftUI
import PhotosUI
import UIKit
import ImageIO

// The native thought workspace keeps the schedule and drafts in the same Form.
// Stable event/round IDs continue to address the Flutter document's existing notes.
@MainActor
struct GiriThinkingView: View {
    @EnvironmentObject private var store: GiriStore
    @State private var mode = 0
    @State private var noteFilter = "all"
    @State private var usedFilter = "all"
    @State private var editing: ThoughtNote?
    @State private var creatingKind: NoteKind?
    @State private var deleteCandidate: ThoughtNote?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            thoughtList(now: timeline.date)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack(alignment: .trailing) {
                AppPageHeader(title: "思考", systemImage: "lightbulb", accentColor: AppSectionAccent.memo)
                Button { creatingKind = .free } label: {
                    Label("メモ", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(accentActionColor)
                .padding(.trailing, 18)
            }
            .background(appHeaderColor)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editing) { note in
            NavigationStack { GiriThoughtEditor(note: note) }
        }
        .sheet(item: $creatingKind) { kind in
            NavigationStack { GiriThoughtEditor(kind: kind) }
        }
        .confirmationDialog("メモを削除しますか？", isPresented: Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        ), titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                guard let note = deleteCandidate else { return }
                store.run {
                    try store.deleteNote(note.id)
                    playLiveStairDeleteFeedback()
                }
                deleteCandidate = nil
            }
        } message: {
            Text(deleteCandidate.map(thoughtTitle) ?? "")
        }
    }

    private func thoughtList(now: Date) -> some View {
        let active = activeRounds(now: now)
        let notes = filteredNotes(active: active)
        return List {
            Section {
                Picker("思考", selection: $mode) {
                    Text("回答作成").tag(0)
                    Text("お題作成").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowSeparator(.hidden)
            }
            Section {
                AppCardSectionTitle(
                    title: mode == 0 ? "回答を考える" : "お題作成",
                    systemImage: mode == 0 ? "square.and.pencil" : "lightbulb",
                    accentColor: AppSectionAccent.memo
                )
                .listRowSeparator(.hidden)
                Button {
                    creatingKind = mode == 0 ? .answers : .prompts
                } label: {
                    Label(mode == 0 ? "回答メモを追加" : "お題を作る", systemImage: "plus.circle")
                }
                .tint(accentActionColor)
            }
            .appSectionCardStyle(accentColor: AppSectionAccent.memo)

            if mode == 0 {
                if active.isEmpty {
                    Section {
                        CenteredEmptyMessage(systemImage: "globe", title: "投稿期間中のネット大喜利はありません")
                            .padding(.vertical, 16)
                    }
                    .appSectionCardStyle(accentColor: AppSectionAccent.artist)
                }
                ForEach(active) { item in
                    GiriRoundWorkspaceSections(eventID: item.event.id, roundID: item.round.id)
                }
            }

            Section {
                AppCardSectionTitle(
                    title: mode == 0 ? "回答・メモ" : "保存したお題",
                    systemImage: mode == 0 ? "square.and.pencil" : "lightbulb",
                    accentColor: AppSectionAccent.memo
                )
                .listRowSeparator(.hidden)
                if mode == 0 {
                    Picker("種類", selection: $noteFilter) {
                        Text("すべて").tag("all")
                        Text("回答").tag(NoteKind.answers.rawValue)
                        Text("自由").tag(NoteKind.free.rawValue)
                    }
                    .pickerStyle(.menu)
                    .tint(.primary)
                } else {
                    Picker("使用状況", selection: $usedFilter) {
                        Text("すべて").tag("all")
                        Text("未使用").tag("unused")
                        Text("使用済み").tag("used")
                    }
                    .pickerStyle(.menu)
                    .tint(.primary)
                }
            }
            .appSectionCardStyle(accentColor: AppSectionAccent.memo)

            if notes.isEmpty {
                Section {
                    CenteredEmptyMessage(systemImage: mode == 0 ? "square.and.pencil" : "lightbulb", title: mode == 0 ? "回答・メモがありません" : "お題がありません")
                        .padding(.vertical, 16)
                }
                .appSectionCardStyle(accentColor: AppSectionAccent.memo)
            }
            ForEach(notes) { note in
                Section {
                    HStack(spacing: 12) {
                        Button { editing = note } label: {
                            GiriThoughtSummary(note: note, detail: noteContext(note))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Menu {
                            Button("編集", systemImage: "pencil") { editing = note }
                            if note.kind == .prompts {
                                Button(note.used ? "未使用に戻す" : "使用済みにする", systemImage: note.used ? "arrow.uturn.backward" : "checkmark.circle") {
                                    var updated = note
                                    updated.used.toggle()
                                    updated.updatedAt = Date()
                                    store.run { try store.saveNote(updated) }
                                }
                            }
                            Button("削除", systemImage: "trash", role: .destructive) { deleteCandidate = note }
                        } label: {
                            Image(systemName: "ellipsis").frame(minWidth: 30, minHeight: 44)
                        }
                        .tint(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                .appSectionCardStyle(accentColor: AppSectionAccent.memo)
            }
        }
        .appIndexListStyle()
        .scrollDismissesKeyboard(.interactively)
    }

    private func activeRounds(now: Date) -> [ThoughtActiveRound] {
        store.events.filter { $0.kind == .online && $0.isParticipating && $0.status != .canceled }
            .flatMap { event in
                event.effectiveRounds.filter { $0.isSubmissionOpen(now) }
                    .map { ThoughtActiveRound(event: event, round: $0) }
            }
            .sorted { ($0.round.submissionEnd ?? .distantFuture) < ($1.round.submissionEnd ?? .distantFuture) }
    }

    private func filteredNotes(active: [ThoughtActiveRound]) -> [ThoughtNote] {
        store.notes.filter { note in
            if mode == 1 {
                return note.kind == .prompts && (usedFilter == "all" || note.used == (usedFilter == "used"))
            }
            let inWorkspace = note.kind == .answers && active.contains { thoughtMatches(note, eventID: $0.event.id, roundID: $0.round.id) }
            return note.kind != .prompts && !inWorkspace && (noteFilter == "all" || note.kind.rawValue == noteFilter)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func noteContext(_ note: ThoughtNote) -> String {
        var parts = [note.kind == .prompts ? (note.used ? "使用済み" : "未使用") : note.kind == .answers ? "回答 \(thoughtAnswers(note).count)案" : "メモ"]
        if let event = store.events.first(where: { $0.id == note.eventId }) {
            parts.append(store.onlineSites.first(where: { $0.id == event.onlineSiteId })?.name ?? event.title)
            if let round = event.effectiveRounds.first(where: { $0.id == (note.roundId ?? "legacy") }) {
                parts.append(thoughtRoundLabel(event: event, round: round))
            } else if note.roundId != nil {
                parts.append("削除された日程")
            }
        } else if note.eventId != nil {
            parts.append("削除された会")
        }
        return parts.joined(separator: " · ")
    }
}

private struct ThoughtActiveRound: Identifiable {
    let event: GiriEvent
    let round: EventRound
    var id: String { event.id + ":" + round.id }
}

@MainActor
struct GiriRoundWorkspace: View {
    let eventID: String
    let roundID: String

    var body: some View {
        Form {
            GiriRoundWorkspaceSections(eventID: eventID, roundID: roundID)
        }
        .appEditorFormStyle()
        .navigationTitle("投稿・投票")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .tint(accentActionColor)
    }
}

/// Embeds the very same periods and editable drafts in an event detail Form.
@MainActor
struct GiriRoundWorkspaceSections: View {
    @EnvironmentObject private var store: GiriStore
    let eventID: String
    let roundID: String
    @State private var editingNoteID: String?
    @State private var creating = false
    @State private var draftGeneration = UUID()
    @State private var deleteCandidate: ThoughtNote?

    private var event: GiriEvent? { store.events.first { $0.id == eventID } }
    private var round: EventRound? { event?.effectiveRounds.first { $0.id == roundID } }
    private var notes: [ThoughtNote] {
        store.notes.filter { $0.kind == .answers && thoughtMatches($0, eventID: eventID, roundID: roundID) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        Group {
            periodSection
            ForEach(notes) { note in
                Section {
                    if editingNoteID == note.id {
                        GiriInlineThoughtEditor(note: note, eventID: eventID, roundID: roundID, onSaved: {
                            editingNoteID = nil
                        }, onCancel: {
                            editingNoteID = nil
                        })
                    } else {
                        draftRows(note)
                    }
                }
                .appSectionCardStyle(accentColor: AppSectionAccent.memo)
            }
            if round != nil {
                if creating || notes.isEmpty {
                    Section {
                        AppCardSectionTitle(title: "お題と回答案を追加", systemImage: "square.and.pencil", accentColor: AppSectionAccent.memo)
                            .listRowSeparator(.hidden)
                        GiriInlineThoughtEditor(note: nil, eventID: eventID, roundID: roundID, onSaved: {
                            creating = false
                            draftGeneration = UUID()
                        }, onCancel: notes.isEmpty ? nil : {
                            creating = false
                        })
                        .id(draftGeneration)
                    }
                    .appSectionCardStyle(accentColor: AppSectionAccent.memo)
                } else {
                    Section {
                        Button {
                            creating = true
                            editingNoteID = nil
                        } label: {
                            Label("お題を追加", systemImage: "plus.circle")
                        }
                        .tint(accentActionColor)
                    }
                    .appSectionCardStyle(accentColor: AppSectionAccent.memo)
                }
            }
        }
        .confirmationDialog("お題と回答を削除しますか？", isPresented: Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        ), titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                guard let note = deleteCandidate else { return }
                store.run {
                    try store.deleteNote(note.id)
                    playLiveStairDeleteFeedback()
                }
                deleteCandidate = nil
            }
        } message: {
            Text(deleteCandidate.map(thoughtTitle) ?? "")
        }
    }

    private var periodSection: some View {
        Section {
            AppCardSectionTitle(
                title: store.onlineSites.first(where: { $0.id == event?.onlineSiteId })?.name ?? event?.title ?? "削除された会",
                systemImage: "globe",
                accentColor: AppSectionAccent.artist
            )
            .listRowSeparator(.hidden)
            if let event, let round {
                HStack(alignment: .firstTextBaseline) {
                    Text(thoughtRoundLabel(event: event, round: round))
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 8)
                    NavigationLink {
                        GiriRoundEditor(eventID: eventID, round: round)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("日程を編集")
                }
                let urlText = store.onlineSites.first(where: { $0.id == event.onlineSiteId })?.url ?? event.siteUrl
                if let url = URL(string: urlText), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                    Link(url.host ?? urlText, destination: url).font(.footnote)
                }
                GiriThoughtPeriodRow(title: "投稿", start: round.submissionStart, end: round.submissionEnd, enabled: round.submissionEnabled, accent: AppSectionAccent.artist)
                GiriThoughtPeriodRow(title: "投票", start: round.votingStart, end: round.votingEnd, enabled: round.votingRequired, accent: AppSectionAccent.memo)
                if event.meetingType == .tournament {
                    NavigationLink {
                        GiriResultEntry(eventID: eventID, initialRoundID: roundID)
                    } label: {
                        Label("このお題・ステージの結果", systemImage: "trophy")
                    }
                }
            } else {
                Text("日程は削除されています。保存したお題と回答は残っています。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    @ViewBuilder
    private func draftRows(_ note: ThoughtNote) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(thoughtTitle(note)).font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button("編集", systemImage: "pencil") {
                    editingNoteID = note.id
                    creating = false
                }
                Button("削除", systemImage: "trash", role: .destructive) { deleteCandidate = note }
            } label: {
                Image(systemName: "ellipsis").frame(minWidth: 30, minHeight: 32)
            }
            .tint(.secondary)
        }
        if !note.imageDataBase64.isEmpty {
            GiriThoughtImage(base64: note.imageDataBase64)
        }
        if thoughtAnswers(note).isEmpty {
            Button("回答案を追加") { editingNoteID = note.id }
                .tint(accentActionColor)
        } else {
            ForEach(Array(thoughtAnswers(note).enumerated()), id: \.offset) { index, answer in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 16, alignment: .trailing)
                    Text(answer).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 2)
                .onTapGesture { editingNoteID = note.id }
            }
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
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent.opacity(enabled ? 1 : 0.3))
                .frame(width: 3)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                if !enabled {
                    Text(title == "投稿" ? "投稿対象外" : "投票なし").foregroundStyle(.secondary)
                }
                Text(start.map(thoughtDateTime) ?? "開始未定")
                Text("〜 " + (end.map(thoughtDateTime) ?? "締切未定"))
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            if enabled, let start, let end, start <= Date(), Date() < end {
                Text("期間中")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.12), in: Capsule())
                    .fixedSize()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private struct GiriInlineThoughtEditor: View {
    @EnvironmentObject private var store: GiriStore
    @State private var original: ThoughtNote
    private let onSaved: () -> Void
    private let onCancel: (() -> Void)?
    @State private var prompt: String
    @State private var answersText: String
    @State private var image: String
    @State private var error: String?
    @State private var readingImage = false
    @State private var confirmsCancel = false

    init(note: ThoughtNote?, eventID: String, roundID: String, onSaved: @escaping () -> Void, onCancel: (() -> Void)?) {
        var value = note ?? ThoughtNote()
        if note == nil {
            value.kind = .answers
            value.eventId = eventID
            value.roundId = roundID
        }
        _original = State(initialValue: value)
        let prompt = value.prompt.isEmpty ? value.title : value.prompt
        let answers = value.answers.isEmpty ? value.body : value.answers.joined(separator: "\n")
        _prompt = State(initialValue: prompt)
        _answersText = State(initialValue: answers)
        _image = State(initialValue: value.imageDataBase64)
        self.onSaved = onSaved
        self.onCancel = onCancel
    }

    var body: some View {
        Group {
            TextField("お題を入力", text: $prompt, axis: .vertical)
                .lineLimit(1...8)
            GiriThoughtImagePicker(base64: $image, reading: $readingImage, error: $error)
            TextField("回答案を1行ずつ入力", text: $answersText, axis: .vertical)
                .lineLimit(4...20)
            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            HStack {
                if let onCancel {
                    Button("キャンセル") {
                        if isDirty { confirmsCancel = true } else { onCancel() }
                    }
                }
                Spacer()
                Button("保存", action: save)
                    .font(.headline)
                    .disabled(readingImage)
            }
            .tint(accentActionColor)
        }
        .confirmationDialog("変更を保存せずに閉じますか？", isPresented: $confirmsCancel, titleVisibility: .visible) {
            Button("保存せずに閉じる", role: .destructive) { onCancel?() }
        }
    }

    private var isDirty: Bool {
        prompt != (original.prompt.isEmpty ? original.title : original.prompt) ||
        answersText != (original.answers.isEmpty ? original.body : original.answers.joined(separator: "\n")) ||
        image != original.imageDataBase64
    }

    private func save() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !image.isEmpty else {
            error = "お題か画像を入力してください。"
            return
        }
        var note = original
        note.prompt = trimmed
        note.title = trimmed.isEmpty ? "画像のお題" : String(trimmed.prefix(120))
        note.body = answersText.trimmingCharacters(in: .whitespacesAndNewlines)
        note.answers = thoughtLines(answersText)
        note.imageDataBase64 = image
        note.updatedAt = Date()
        do {
            try store.saveNote(note)
            playLiveStairSaveFeedback()
            onSaved()
        } catch {
            self.error = "保存できませんでした。内容を残したまま再試行できます。\n\(error.localizedDescription)"
        }
    }
}

/// Independent notes use a native navigation sheet. Cancel and interactive
/// dismissal never discard an edited draft without an explicit decision.
@MainActor
struct GiriThoughtEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    @State private var initial: ThoughtNote
    @State private var draft: ThoughtNote
    @State private var primaryText: String
    @State private var bodyText: String
    @State private var readingImage = false
    @State private var error: String?
    @State private var discard = false

    init(note: ThoughtNote? = nil, kind: NoteKind = .free, eventID: String? = nil, roundID: String? = nil) {
        var value = note ?? ThoughtNote()
        if note == nil {
            value.kind = kind
            value.eventId = eventID
            value.roundId = roundID
        }
        _initial = State(initialValue: value)
        _draft = State(initialValue: value)
        _primaryText = State(initialValue: value.prompt.isEmpty ? value.title : value.prompt)
        _bodyText = State(initialValue: value.kind == .answers && !value.answers.isEmpty ? value.answers.joined(separator: "\n") : value.body)
    }

    var body: some View {
        Form {
            if let event, let round = event.effectiveRounds.first(where: { $0.id == (draft.roundId ?? "legacy") }) {
                Section {
                    AppCardSectionTitle(title: store.onlineSites.first(where: { $0.id == event.onlineSiteId })?.name ?? event.title, systemImage: "globe", accentColor: AppSectionAccent.artist)
                        .listRowSeparator(.hidden)
                    Text(thoughtRoundLabel(event: event, round: round)).font(.subheadline.weight(.medium))
                    GiriThoughtPeriodRow(title: "投稿", start: round.submissionStart, end: round.submissionEnd, enabled: round.submissionEnabled, accent: AppSectionAccent.artist)
                    GiriThoughtPeriodRow(title: "投票", start: round.votingStart, end: round.votingEnd, enabled: round.votingRequired, accent: AppSectionAccent.memo)
                }
                .appSectionCardStyle(accentColor: AppSectionAccent.artist)
            }
            Section {
                AppCardSectionTitle(title: "基本情報", systemImage: "link", accentColor: AppSectionAccent.memo)
                    .listRowSeparator(.hidden)
                Picker("種類", selection: $draft.kind) {
                    ForEach(NoteKind.allCases) { kind in Text(kind.title).tag(kind) }
                }
                .pickerStyle(.menu)
                .tint(.primary)
                eventPicker
                if event?.kind == .online { roundPicker }
                if draft.kind == .prompts {
                    Toggle("使用済み", isOn: $draft.used).tint(AppSectionAccent.memo)
                }
            }
            .appSectionCardStyle(accentColor: AppSectionAccent.memo)

            Section {
                AppCardSectionTitle(title: draft.kind == .free ? "タイトル" : "お題", systemImage: draft.kind == .free ? "square.and.pencil" : "lightbulb", accentColor: AppSectionAccent.memo)
                    .listRowSeparator(.hidden)
                TextField(draft.kind == .free ? "タイトル（任意）" : "お題を入力", text: $primaryText, axis: .vertical)
                    .lineLimit(1...10)
                GiriThoughtImagePicker(base64: $draft.imageDataBase64, reading: $readingImage, error: $error)
            }
            .appSectionCardStyle(accentColor: AppSectionAccent.memo)
            Section {
                AppCardSectionTitle(title: draft.kind == .answers ? "回答案" : "メモ", systemImage: "square.and.pencil", accentColor: AppSectionAccent.memo)
                    .listRowSeparator(.hidden)
                TextField(draft.kind == .answers ? "回答案を1行ずつ入力" : "メモを入力", text: $bodyText, axis: .vertical)
                    .lineLimit(6...30)
            }
            .appSectionCardStyle(accentColor: AppSectionAccent.memo)
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
        .appEditorFormStyle()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(draft.kind == .prompts ? "お題" : draft.kind == .answers ? "回答メモ" : "メモ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") {
                    if isDirty { discard = true } else { dismiss() }
                }
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
    }

    private var event: GiriEvent? { store.events.first { $0.id == draft.eventId } }

    private var eventPicker: some View {
        Picker("関連する会", selection: Binding(
            get: { draft.eventId },
            set: { draft.eventId = $0; draft.roundId = nil }
        )) {
            Text("関連づけなし").tag(nil as String?)
            ForEach(store.events) { event in Text(event.title).tag(Optional(event.id)) }
            if let id = draft.eventId, !store.events.contains(where: { $0.id == id }) {
                Text("削除された会").tag(Optional(id))
            }
        }
        .pickerStyle(.menu)
        .tint(.primary)
    }

    private var roundPicker: some View {
        Picker("日程", selection: $draft.roundId) {
            Text("関連づけなし").tag(nil as String?)
            if let event {
                ForEach(event.effectiveRounds) { round in
                    Text(thoughtRoundLabel(event: event, round: round)).tag(Optional(round.id))
                }
            }
            if let id = draft.roundId, !(event?.effectiveRounds.contains(where: { $0.id == id }) ?? false) {
                Text("削除された日程").tag(Optional(id))
            }
        }
        .pickerStyle(.menu)
        .tint(.primary)
    }

    private var isDirty: Bool {
        draft != initial || primaryText != (initial.prompt.isEmpty ? initial.title : initial.prompt) || bodyText != (initial.kind == .answers && !initial.answers.isEmpty ? initial.answers.joined(separator: "\n") : initial.body)
    }

    private func save() {
        let primary = primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if (draft.kind != .free && primary.isEmpty && draft.imageDataBase64.isEmpty) || (primary.isEmpty && body.isEmpty && draft.imageDataBase64.isEmpty) {
            error = draft.kind == .free ? "タイトルか本文を入力してください。" : "お題か画像を入力してください。"
            return
        }
        var saved = draft
        saved.title = String((!primary.isEmpty ? primary : !draft.imageDataBase64.isEmpty ? "画像のお題" : body.components(separatedBy: .newlines).first ?? "メモ").prefix(120))
        saved.prompt = draft.kind == .free ? "" : primary
        saved.body = body
        saved.answers = draft.kind == .answers ? thoughtLines(body) : []
        saved.used = draft.kind == .prompts && draft.used
        saved.updatedAt = Date()
        do {
            try store.saveNote(saved)
            playLiveStairSaveFeedback()
            dismiss()
        } catch {
            self.error = "保存できませんでした。内容を残したまま再試行できます。\n\(error.localizedDescription)"
        }
    }
}

private struct GiriThoughtSummary: View {
    let note: ThoughtNote
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            if let data = Data(base64Encoded: note.imageDataBase64), let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: note.kind == .prompts ? (note.used ? "checkmark.circle" : "lightbulb") : "square.and.pencil")
                    .foregroundStyle(AppSectionAccent.memo)
                    .frame(width: 28, height: 28)
                    .background(AppSectionAccent.memo.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(thoughtTitle(note)).foregroundStyle(.primary).lineLimit(3)
                Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
            }
        }
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

private func thoughtAnswers(_ note: ThoughtNote) -> [String] {
    note.answers.isEmpty ? thoughtLines(note.body) : note.answers
}

private func thoughtLines(_ value: String) -> [String] {
    value.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func thoughtRoundLabel(event: GiriEvent, round: EventRound) -> String {
    var parts = [event.meetingType == .tournament ? round.name : "投稿・投票"]
    if event.meetingType == .tournament || round.promptNumber > 1 { parts.append("お題\(round.promptNumber)") }
    if !event.affiliation.isEmpty { parts.append(event.affiliation) }
    let block = round.block.isEmpty ? event.block : round.block
    if !block.isEmpty { parts.append(block) }
    return parts.joined(separator: " · ")
}

private func thoughtDateTime(_ date: Date) -> String {
    date.formatted(.dateTime.year().month(.defaultDigits).day().weekday(.abbreviated).hour(.twoDigits(amPM: .omitted)).minute().locale(Locale(identifier: "ja_JP")))
}
