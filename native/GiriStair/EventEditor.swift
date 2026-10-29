import SwiftUI
import PhotosUI

/// The same native Form / menu Picker / section modifiers as EventBasicEditor.
struct GiriEventEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    let event: GiriEvent?
    let onSaved: (() -> Void)?
    @State private var draft = GiriEvent()
    @State private var initial = GiriEvent()
    @State private var loaded = false
    @State private var participants: [String] = [""]
    @State private var automaticFields: [String: Set<String>] = [:]
    @State private var selfWasAdded = false
    @State private var importText = ""
    @State private var showImport = false
    @State private var photo: PhotosPickerItem?
    @State private var recognizing = false
    @State private var showDiscard = false
    @State private var showLeave = false
    @State private var saving = false
    @State private var site = OnlineSite()
    @State private var lastOrganizer = ""
    @State private var lastEventDay: Date?

    init(event: GiriEvent? = nil, onSaved: (() -> Void)? = nil) {
        self.event = event
        self.onSaved = onSaved
    }

    private var isSite: Bool {
        event == nil && draft.kind == .online && draft.meetingType == .casual
    }
    private var isValid: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var isDirty: Bool {
        draft != initial || participants.filter { !$0.isEmpty } != initial.participants
    }

    var body: some View {
        Form {
            basicSection
            if isSite { siteSection }
            if !isSite {
                participantSection
                if draft.meetingType == .tournament { teamSections }
                if draft.kind == .online { scheduleSections }
                Section {
                    AppCardSectionTitle(title: "振り返り", systemImage: "text.alignleft", accentColor: AppSectionAccent.memo)
                        .listRowSeparator(.hidden)
                    TextField("メモ", text: $draft.memo, axis: .vertical).lineLimit(3...10)
                }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
            }
        }
        .appEditorFormStyle()
        .environment(\.defaultMinListRowHeight, 48)
        .navigationTitle(event == nil ? "" : "編集")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(event != nil && isDirty)
        .toolbar(event == nil ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            if event != nil {
                ToolbarItem(placement: .topBarLeading) {
                    if isDirty {
                        Button { showLeave = true } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("戻る")
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(!isValid || saving) }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if event == nil {
                AppPageHeader(title: "登録", systemImage: "plus", accentColor: AppSectionAccent.live)
                    .overlay(alignment: .trailing) { saveHeaderButton.padding(.trailing, 16) }
            }
        }
        .interactiveDismissDisabled(isDirty)
        .onAppear { if !loaded { load() } }
        .onChange(of: draft.organizer) { _, next in
            if next != lastOrganizer { lastOrganizer = next; syncSelf() }
        }
        .onChange(of: draft.eventDate) { _, next in
            if next != lastEventDay { let previous = lastEventDay; lastEventDay = next; moveDay(from: previous, to: next) }
        }
        .onChange(of: draft.kind) { _, kind in
            if kind == .online && draft.rounds.isEmpty && !isSite { addRound(sameStage: false) }
        }
        .onChange(of: draft.meetingType) { _, type in
            if type == .tournament && draft.kind == .online && draft.rounds.isEmpty { addRound(sameStage: false) }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            recognizing = true
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw GiriParticipantReadError.unreadable }
                    importText = try await GiriParticipantOCR.recognize(data)
                    showImport = true
                } catch { store.errorMessage = error.localizedDescription }
                recognizing = false
                photo = nil
            }
        }
        .sheet(isPresented: $showImport) {
            NavigationStack {
                GiriParticipantImport(source: importText) { names in
                    let existing = Set(participants.map(giriEditorNameKey))
                    let added = names.filter { !existing.contains(giriEditorNameKey($0)) }
                    participants.removeAll { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    participants.append(contentsOf: added)
                    participants.append("")
                }
            }
        }
        .alert("入力を空にしますか？", isPresented: $showDiscard) {
            Button("キャンセル", role: .cancel) {}
            Button("空にする", role: .destructive) { loaded = false; load() }
        } message: { Text("保存済みの記録は変更されません。") }
        .alert("変更を保存せず戻りますか？", isPresented: $showLeave) {
            Button("編集を続ける", role: .cancel) {}
            Button("変更を破棄", role: .destructive) { dismiss() }
        }
    }

    private var saveHeaderButton: some View {
        Button("保存", action: save)
            .font(.headline.bold())
            .foregroundStyle(isValid ? accentActionColor : Color.secondary)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(Capsule().fill(appCardColor))
            .overlay(Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 1))
            .disabled(!isValid || saving)
            .opacity(isValid && !saving ? 1 : 0.55)
    }

    private var basicSection: some View {
        Section {
            AppCardSectionTitle(title: "基本情報", systemImage: "slider.horizontal.3", accentColor: AppSectionAccent.live)
                .listRowSeparator(.hidden)
            Picker(selection: $draft.kind) {
                ForEach([EventKind.live, .online], id: \.self) { Text($0.title).tag($0) }
            } label: { GiriEditorLabel("形式") }.pickerStyle(.menu).tint(.primary)
            Picker(selection: $draft.meetingType) {
                Text("通常").tag(MeetingType.casual)
                Text("大会").tag(MeetingType.tournament)
            } label: { GiriEditorLabel("会の種類") }.pickerStyle(.menu).tint(.primary)
            if !isSite {
                Picker(selection: $draft.status) {
                    ForEach([EventStatus.planned, .attended, .canceled], id: \.self) { Text($0.title).tag($0) }
                } label: { GiriEditorLabel("参加状況") }.pickerStyle(.menu).tint(.primary)
            }
            TextField(isSite ? "サイト名 *" : "会・大会名 *", text: $draft.title)
            if !isSite {
                GiriEditorPlayerField(title: "主催者", text: $draft.organizer, preferHosts: true)
                if draft.kind == .live {
                    OptionalDateRow(title: "日付", selection: $draft.eventDate, components: .date)
                    HStack(spacing: 12) {
                        OptionalDateRow(title: "開始", selection: clockBinding(start: true), components: .hourAndMinute)
                        OptionalDateRow(title: "終了", selection: clockBinding(start: false), components: .hourAndMinute)
                        Button { draft.startsAt = nil; draft.endsAt = nil } label: {
                            VStack(spacing: 2) { Image(systemName: "arrow.counterclockwise"); Text("未定").font(.caption2) }
                        }.buttonStyle(.borderless).tint(accentActionColor)
                    }
                    TextField("会場名", text: $draft.venue)
                    if !draft.venue.isEmpty {
                        let matches = store.venues.filter { $0.name.localizedCaseInsensitiveContains(draft.venue) }
                        ForEach(Array(matches.prefix(5))) { venue in
                            Button {
                                draft.venue = venue.name
                                draft.venueId = venue.id
                            } label: {
                                HStack { Text(venue.name); Spacer(); Text(venue.prefecture).foregroundStyle(.secondary).font(.subheadline) }
                            }.buttonStyle(.borderless)
                        }
                    }
                } else {
                    TextField("サイトURL", text: $draft.siteUrl).keyboardType(.URL).textInputAutocapitalization(.never)
                    TextField("所属・部", text: $draft.affiliation)
                    TextField("ブロック・担当お題", text: $draft.block)
                }
            } else {
                TextField("サイトURL", text: $site.url).keyboardType(.URL).textInputAutocapitalization(.never)
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.live)
    }

    private var siteSection: some View {
        Section {
            AppCardSectionTitle(title: "投稿・投票", systemImage: "globe", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
            Picker("開催間隔", selection: $site.recurrence) {
                Text("不定期").tag(SiteRecurrence.irregular)
                Text("毎週").tag(SiteRecurrence.weekly)
            }.pickerStyle(.menu).tint(.primary)
            if site.recurrence == .weekly {
                Picker("投稿開始曜日", selection: $site.weekday) {
                    ForEach(1...7, id: \.self) { Text(["月", "火", "水", "木", "金", "土", "日"][$0 - 1] + "曜日").tag($0) }
                }.pickerStyle(.menu).tint(.primary)
            }
            OptionalDateRow(title: "開始時刻", selection: siteClock, components: .hourAndMinute)
            Stepper("投稿期間　\(site.submissionDays)日", value: $site.submissionDays, in: 1...365)
            Stepper("投票期間　\(site.votingDays)日", value: $site.votingDays, in: 1...365)
            TextField("所属・部", text: $site.affiliation)
            TextField("ブロック・担当お題", text: $site.block)
            TextField("メモ", text: $site.memo, axis: .vertical).lineLimit(2...6)
        }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    private var siteClock: Binding<Date?> {
        Binding(get: {
            Calendar.current.date(bySettingHour: site.startHour, minute: site.startMinute, second: 0, of: Date())
        }, set: { date in
            guard let date else { return }
            site.startHour = Calendar.current.component(.hour, from: date)
            site.startMinute = Calendar.current.component(.minute, from: date)
        })
    }

    private var participantSection: some View {
        Section {
            AppCardSectionTitle(title: "参加者", systemImage: "person.2", accentColor: AppSectionAccent.artist)
                .overlay(alignment: .trailing) {
                    Text("\(participants.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count)人")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.listRowSeparator(.hidden)
            HStack(spacing: 12) {
                Button { importText = ""; showImport = true } label: { Label("文字貼り付け", systemImage: "doc.on.clipboard") }
                Spacer(minLength: 0)
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("OCR読み取り", systemImage: "text.viewfinder")
                }.disabled(recognizing)
            }.font(.subheadline.weight(.medium)).buttonStyle(.bordered).tint(accentActionColor)
            if recognizing { ProgressView("読み取り中") }
            ForEach(participants.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    GiriEditorPlayerField(title: "参加者名", text: participantBinding(index), compact: true)
                    Button(role: .destructive) {
                        participants.remove(at: index)
                        if participants.isEmpty { participants = [""] }
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).accessibilityLabel("参加者を削除")
                }.listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 12))
                    .environment(\.defaultMinListRowHeight, 36)
            }
            Button { participants.append("") } label: { Label("参加者を追加", systemImage: "plus.circle") }.tint(accentActionColor)
        }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    @ViewBuilder private var teamSections: some View {
        Section {
            AppCardSectionTitle(title: "大会の形式", systemImage: "person.2", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
            Picker("参加形式", selection: $draft.tournamentFormat) {
                Text("個人戦").tag(TournamentFormat.individual)
                Text("チーム戦").tag(TournamentFormat.team)
                if draft.tournamentFormat == .pair { Text("タッグ戦").tag(TournamentFormat.pair) }
            }.pickerStyle(.menu).tint(.primary)
            if draft.tournamentFormat != .individual {
                Picker("チーム人数", selection: Binding(get: { draft.teamSize ?? 0 }, set: { draft.teamSize = $0 == 0 ? nil : $0 })) {
                    Text("制限なし").tag(0)
                    ForEach(2...6, id: \.self) { Text("\($0)人").tag($0) }
                    if let size = draft.teamSize, size > 6 { Text("\(size)人").tag(size) }
                }.pickerStyle(.menu).tint(.primary)
                Picker("自分のチーム", selection: Binding(get: { draft.myTeamId ?? "" }, set: { value in
                    draft.myTeamId = value.isEmpty ? nil : value
                    for i in draft.teams.indices { draft.teams[i].isMine = draft.teams[i].id == value }
                })) {
                    Text("未設定").tag("")
                    ForEach(draft.teams) { Text($0.name.isEmpty ? "名前未入力" : $0.name).tag($0.id) }
                }.pickerStyle(.menu).tint(.primary)
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
        if draft.tournamentFormat != .individual {
            ForEach(draft.teams.indices, id: \.self) { index in
                Section {
                    HStack {
                        AppCardSectionTitle(title: draft.teams[index].id == draft.myTeamId ? "自分のチーム" : "チーム\(index + 1)", systemImage: "person.3", accentColor: AppSectionAccent.artist)
                        Button(role: .destructive) {
                            if draft.myTeamId == draft.teams[index].id { draft.myTeamId = nil }
                            draft.teams.remove(at: index)
                        } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }.listRowSeparator(.hidden)
                    TextField("チーム名", text: $draft.teams[index].name)
                    ForEach(draft.teams[index].members.indices, id: \.self) { memberIndex in
                        HStack {
                            GiriEditorPlayerField(title: "メンバー名", text: $draft.teams[index].members[memberIndex], compact: true)
                            Button(role: .destructive) { draft.teams[index].members.remove(at: memberIndex) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                        }
                    }
                    Button { draft.teams[index].members.append("") } label: { Label("メンバーを追加", systemImage: "plus.circle") }.tint(accentActionColor)
                }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            }
            Section {
                Button {
                    var team = GiriTeam()
                    team.isMine = draft.teams.isEmpty
                    if team.isMine { draft.myTeamId = team.id }
                    team.members = store.preferences.selfName.isEmpty || !team.isMine ? [""] : [store.preferences.selfName]
                    draft.teams.append(team)
                } label: { Label("チームを追加", systemImage: "plus.circle") }
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
        }
    }

    @ViewBuilder private var scheduleSections: some View {
        ForEach(draft.rounds.indices, id: \.self) { index in
            Section {
                HStack {
                    AppCardSectionTitle(title: draft.rounds[index].name, systemImage: "calendar", accentColor: AppSectionAccent.artist)
                    Menu {
                        if index > 0 { Button("上へ移動", systemImage: "arrow.up") { draft.rounds.swapAt(index, index - 1) } }
                        if index + 1 < draft.rounds.count { Button("下へ移動", systemImage: "arrow.down") { draft.rounds.swapAt(index, index + 1) } }
                        Button("削除", systemImage: "trash", role: .destructive) { draft.rounds.remove(at: index) }
                    } label: { Image(systemName: "ellipsis.circle") }.tint(accentActionColor)
                }.listRowSeparator(.hidden)
                GiriRoundFields(round: $draft.rounds[index], automatic: Binding(get: { automaticFields[draft.rounds[index].id] ?? [] }, set: { automaticFields[draft.rounds[index].id] = $0 }), tournament: draft.meetingType == .tournament)
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
        }
        Section {
            Button { addRound(sameStage: false) } label: { Label(draft.meetingType == .tournament ? "次の段階を追加" : "日程を追加", systemImage: "plus.circle") }
            if draft.meetingType == .tournament && !draft.rounds.isEmpty {
                Button { addRound(sameStage: true) } label: { Label("同じ段階のお題を追加", systemImage: "plus.square.on.square") }
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    private func load() {
        draft = event ?? GiriEvent()
        if event == nil { draft.eventDate = Calendar.current.startOfDay(for: Date()) }
        if draft.rounds.isEmpty { draft.rounds = draft.effectiveRounds }
        participants = draft.participants.isEmpty ? [""] : draft.participants + [""]
        if draft.teams.isEmpty, let old = draft.tournamentResult, old.format != .individual,
           !old.members.isEmpty || !old.teamName.isEmpty {
            var team = GiriTeam(); team.name = old.teamName; team.members = old.members; team.isMine = true
            draft.teams = [team]; draft.myTeamId = team.id; draft.tournamentFormat = old.format
        }
        initial = draft
        lastOrganizer = draft.organizer
        lastEventDay = draft.eventDate
        site = OnlineSite()
        site.submissionDays = store.preferences.submissionDays
        site.votingDays = store.preferences.votingDays
        site.startHour = store.preferences.submissionStartHour
        site.startMinute = store.preferences.submissionStartMinute
        automaticFields = [:]
        loaded = true
    }

    private func syncSelf() {
        let me = store.preferences.selfName.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = draft.organizer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !me.isEmpty, !host.isEmpty else { return }
        if giriEditorNameKey(me) == giriEditorNameKey(host) {
            if selfWasAdded { participants.removeAll { giriEditorNameKey($0) == giriEditorNameKey(me) }; selfWasAdded = false }
        } else if !participants.contains(where: { giriEditorNameKey($0) == giriEditorNameKey(me) }) {
            if let index = participants.firstIndex(where: { $0.isEmpty }) { participants[index] = me }
            else { participants.append(me) }
            selfWasAdded = true
        }
        if participants.isEmpty { participants = [""] }
    }

    private func participantBinding(_ index: Int) -> Binding<String> {
        Binding(get: { participants.indices.contains(index) ? participants[index] : "" }, set: { value in
            if participants.indices.contains(index) { participants[index] = value }
        })
    }

    private func clockBinding(start: Bool) -> Binding<Date?> {
        Binding(get: { start ? draft.startsAt : draft.endsAt }, set: { value in
            guard let value else { if start { draft.startsAt = nil } else { draft.endsAt = nil }; return }
            let clock = Calendar.current.dateComponents([.hour, .minute], from: value)
            let day = draft.eventDate ?? value
            var result = Calendar.current.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: day) ?? value
            if !start, let begin = draft.startsAt, result < begin { result = Calendar.current.date(byAdding: .day, value: 1, to: result) ?? result }
            if start { draft.startsAt = result } else { draft.endsAt = result }
            if draft.eventDate == nil { draft.eventDate = Calendar.current.startOfDay(for: result) }
        })
    }

    private func moveDay(from old: Date?, to new: Date?) {
        guard let new else { draft.startsAt = nil; draft.endsAt = nil; return }
        func moved(_ value: Date?) -> Date? {
            guard let value else { return nil }
            let calendar = Calendar.current
            let offset = old.map { calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: calendar.startOfDay(for: value)).day ?? 0 } ?? 0
            let day = calendar.date(byAdding: .day, value: offset, to: new) ?? new
            let clock = calendar.dateComponents([.hour, .minute], from: value)
            return calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: day)
        }
        draft.startsAt = moved(draft.startsAt)
        draft.endsAt = moved(draft.endsAt)
    }

    private func addRound(sameStage: Bool) {
        let preferences = store.preferences
        var round = EventRound()
        let previous = draft.rounds.last
        round.name = draft.meetingType == .tournament ? (sameStage ? previous?.name ?? "予選1回戦" : giriEditorNextStage(previous?.name ?? "")) : "投稿・投票"
        round.stageId = sameStage ? previous?.effectiveStageId ?? round.id : round.id
        round.promptNumber = sameStage ? (previous?.promptNumber ?? 0) + 1 : 1
        round.block = previous?.block ?? draft.block
        let reference = draft.eventDate ?? Date()
        let defaultDay = Calendar.current.date(byAdding: .day, value: preferences.submissionStartDayOffset, to: reference) ?? reference
        round.submissionStart = previous?.votingEnd ?? previous?.submissionEnd ?? Calendar.current.date(bySettingHour: preferences.submissionStartHour, minute: preferences.submissionStartMinute, second: 0, of: defaultDay)
        if let start = round.submissionStart {
            round.submissionEnd = Calendar.current.date(byAdding: .day, value: preferences.submissionDays, to: start)
            round.votingStart = round.submissionEnd
            if let voting = round.votingStart { round.votingEnd = Calendar.current.date(byAdding: .day, value: preferences.votingDays, to: voting) }
        }
        automaticFields[round.id] = ["submissionEnd", "votingStart", "votingEnd"]
        draft.rounds.append(round)
    }

    private func save() {
        guard isValid, !saving else { return }
        saving = true
        defer { saving = false }
        do {
            if isSite {
                site.name = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                try store.saveOnlineSite(site)
            } else {
                draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let venueMatch = store.venueDirectory.first { playerSearchKey($0.name) == playerSearchKey(draft.venue) }
                draft.venueId = venueMatch.flatMap { $0.id.hasPrefix("history:") ? nil : $0.id }
                var seen = Set<String>()
                draft.participants = participants.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert(giriEditorNameKey($0)).inserted }
                for i in draft.teams.indices { draft.teams[i].members = draft.teams[i].members.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
                if let size = draft.teamSize, draft.teams.contains(where: { $0.members.count > size }) {
                    store.errorMessage = "チーム人数を超えているチームがあります。人数設定かメンバーを確認してください。"; return
                }
                try giriEditorValidate(draft)
                try store.saveEvent(draft)
            }
            playLiveStairSaveFeedback()
            if event != nil { dismiss() } else { loaded = false; load(); onSaved?() }
        } catch { store.errorMessage = error.localizedDescription }
    }
}

struct GiriEditorLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View { Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary) }
}

struct GiriEditorPlayerField: View {
    @EnvironmentObject private var store: GiriStore
    let title: String
    @Binding var text: String
    var preferHosts = false
    var compact = false
    @FocusState private var focused: Bool

    private var suggestions: [String] {
        guard focused else { return [] }
        return Array(store.suggestPlayers(text, organizer: preferHosts).prefix(8)).map(\.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            TextField(title, text: $text).focused($focused).autocorrectionDisabled().textInputAutocapitalization(.never)
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(suggestions, id: \.self) { name in
                            Button { text = name; focused = false } label: { Text(name).font(.subheadline).lineLimit(1) }
                                .buttonStyle(.bordered).tint(AppSectionAccent.artist)
                        }
                    }
                }
            }
        }
    }
}

func giriEditorNameKey(_ value: String) -> String {
    playerSearchKey(value)
}

func giriEditorNextStage(_ name: String) -> String {
    if let range = name.range(of: #"[0-9]+(?=回戦$)"#, options: .regularExpression), let number = Int(name[range]) { return name.replacingCharacters(in: range, with: String(number + 1)) }
    if name.contains("準々決勝") { return "準決勝" }
    if name.contains("準決勝") { return "決勝" }
    if name.contains("決勝") { return "追加日程" }
    if name.contains("予選") { return "本戦1回戦" }
    return "予選1回戦"
}

enum GiriEditorValidationError: LocalizedError {
    case schedule(String)
    var errorDescription: String? { switch self { case .schedule(let message): return message } }
}

func giriEditorValidate(_ event: GiriEvent) throws {
    if let start = event.startsAt, let end = event.endsAt, end < start { throw GiriEditorValidationError.schedule("終了を開始より後にしてください。") }
    for round in event.effectiveRounds {
        if let start = round.submissionStart, let end = round.submissionEnd, end < start { throw GiriEditorValidationError.schedule("\(round.name)の投稿締切を投稿開始より後にしてください。") }
        if let start = round.votingStart, let end = round.votingEnd, end < start { throw GiriEditorValidationError.schedule("\(round.name)の投票締切を投票開始より後にしてください。") }
    }
}
