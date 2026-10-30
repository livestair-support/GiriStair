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
        event == nil && draft.eventFormat == .onlineLong && draft.meetingType == .casual
    }
    private var showsParticipantSection: Bool {
        !(draft.meetingType == .tournament && (draft.eventFormat == .onlineLong || draft.eventFormat == .onlineShort))
    }
    private var orderedTeamIndices: [Int] {
        draft.teams.indices.sorted { first, second in
            let firstIsMine = draft.teams[first].id == draft.myTeamId
            let secondIsMine = draft.teams[second].id == draft.myTeamId
            if firstIsMine != secondIsMine { return firstIsMine }
            return first < second
        }
    }
    private var fixedTeamSize: Int? { draft.tournamentFormat == .pair ? 2 : draft.teamSize }
    private var participationChoice: Binding<String> {
        Binding(get: {
            draft.status == .canceled ? "canceled" : draft.isInterested ? "interested" : "participating"
        }, set: { choice in
            draft.isInterested = choice == "interested"
            draft.isParticipating = choice == "participating"
            draft.status = choice == "canceled" ? .canceled : .planned
        })
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
                if showsParticipantSection { participantSection }
                if draft.meetingType == .tournament { teamSections }
                if draft.eventFormat.hasOnlineRounds { scheduleSections }
                Section {
                    GiriEventCardSectionTitle(title: "メモ", systemImage: "text.alignleft", accentColor: AppSectionAccent.memo)
                        .listRowSeparator(.hidden)
                    TextField("メモ", text: $draft.memo, axis: .vertical).lineLimit(3...10)
                }.appEventEditorCardStyle(accentColor: AppSectionAccent.memo)
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
        .onChange(of: draft.eventFormat) { _, format in
            if format == .onlineLong && draft.rounds.isEmpty && !isSite { addRound(sameStage: false) }
        }
        .onChange(of: draft.meetingType) { _, type in
            if type == .tournament && draft.eventFormat == .onlineLong && draft.rounds.isEmpty { addRound(sameStage: false) }
            if type == .tournament && draft.tournamentFormat != .individual { ensureOwnTeam() }
        }
        .onChange(of: draft.tournamentFormat) { old, format in
            if format != .individual {
                if old == .individual && draft.teamSize == nil && draft.teams.isEmpty { draft.teamSize = 2 }
                ensureOwnTeam()
            }
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
            GiriEventCardSectionTitle(title: "基本情報", systemImage: "slider.horizontal.3", accentColor: AppSectionAccent.live)
                .listRowSeparator(.hidden)
            Picker(selection: $draft.eventFormat) {
                ForEach(EventFormat.allCases) { Text($0.title).tag($0) }
            } label: { GiriEditorLabel("形式") }.pickerStyle(.menu).tint(.primary)
            Picker(selection: $draft.meetingType) {
                Text("通常").tag(MeetingType.casual)
                Text("大会").tag(MeetingType.tournament)
            } label: { GiriEditorLabel("会の種類") }.pickerStyle(.menu).tint(.primary)
            if !isSite {
                Picker(selection: participationChoice) {
                    Text("参加").tag("participating")
                    Text("興味あり").tag("interested")
                    Text("キャンセル").tag("canceled")
                } label: { GiriEditorLabel("参加状況") }.pickerStyle(.menu).tint(.primary)
            }
            TextField(isSite ? "サイト名 *" : "会・大会名 *", text: $draft.title, axis: .vertical)
                .lineLimit(1...5)
            if !isSite {
                GiriEditorPlayerField(title: "主催者", text: $draft.organizer, preferHosts: true)
                if draft.eventFormat.hasLiveTiming {
                    OptionalDateRow(title: "日付", selection: $draft.eventDate, components: .date)
                    GiriEventTimeRow(startsAt: clockBinding(start: true), endsAt: clockBinding(start: false))
                    if draft.eventFormat != .onlineShort {
                        GiriVenueSuggestionField(text: $draft.venue)
                    }
                }
                if draft.eventFormat.hasOnlineRounds {
                    TextField("サイトURL", text: $draft.siteUrl).keyboardType(.URL).textInputAutocapitalization(.never)
                    if draft.onlineSiteId.flatMap({ store.onlineSiteById($0) })?.hasAffiliations == true || !draft.affiliation.isEmpty {
                        TextField("所属・部", text: $draft.affiliation)
                    }
                    TextField("ブロック", text: $draft.block)
                }
            } else {
                TextField("サイトURL", text: $site.url).keyboardType(.URL).textInputAutocapitalization(.never)
            }
        }.appEventEditorCardStyle(accentColor: AppSectionAccent.live)
    }

    private var siteSection: some View {
        Section {
            GiriEventCardSectionTitle(title: "投稿・投票", systemImage: "globe", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
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
            Toggle("所属・部がある", isOn: $site.hasAffiliations).tint(AppSectionAccent.artist)
            if site.hasAffiliations { TextField("現在の所属・部", text: $site.affiliation) }
            TextField("ブロック", text: $site.block)
            TextField("メモ", text: $site.memo, axis: .vertical).lineLimit(2...6)
        }.appEventEditorCardStyle(accentColor: AppSectionAccent.artist)
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
            HStack(spacing: 6) {
                GiriEventCardSectionTitle(title: "参加者", systemImage: "person.2", accentColor: AppSectionAccent.artist)
                Text("\(participants.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count)人")
                    .font(.caption).foregroundStyle(.secondary).fixedSize()
                Button { importText = ""; showImport = true } label: {
                    importIcon("doc.on.clipboard")
                }
                .buttonStyle(.borderless).accessibilityLabel("文字貼り付け")
                PhotosPicker(selection: $photo, matching: .images) {
                    if recognizing { ProgressView().frame(width: 32, height: 32) }
                    else { importIcon("text.viewfinder") }
                }
                .buttonStyle(.borderless).disabled(recognizing).accessibilityLabel("OCR読み取り")
            }.listRowSeparator(.hidden)
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
        }.appEventEditorCardStyle(accentColor: AppSectionAccent.artist)
    }

    private func importIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(accentActionColor)
            .frame(width: 28, height: 28)
            .background(accentActionColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
    }

    @ViewBuilder private var teamSections: some View {
        Section {
            GiriEventCardSectionTitle(title: "大会の形式", systemImage: "person.2", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
            Picker("参加形式", selection: $draft.tournamentFormat) {
                Text("個人戦").tag(TournamentFormat.individual)
                Text("チーム戦").tag(TournamentFormat.team)
                if draft.tournamentFormat == .pair { Text("タッグ戦").tag(TournamentFormat.pair) }
            }.pickerStyle(.menu).tint(.primary)
            if draft.tournamentFormat != .individual {
                Picker("チーム人数", selection: Binding(get: { fixedTeamSize ?? 0 }, set: changeTeamSize)) {
                    Text("制限なし").tag(0)
                    ForEach(2...6, id: \.self) { Text("\($0)人").tag($0) }
                    if let size = draft.teamSize, size > 6 { Text("\(size)人").tag(size) }
                }.pickerStyle(.menu).tint(.primary)
            }
        }.appEventEditorCardStyle(accentColor: AppSectionAccent.artist)
        if draft.tournamentFormat != .individual {
            ForEach(orderedTeamIndices, id: \.self) { index in
                Section {
                    HStack {
                        GiriEventCardSectionTitle(title: draft.teams[index].id == draft.myTeamId ? "自分のチーム" : "チーム\(index + 1)", systemImage: "person.3", accentColor: AppSectionAccent.artist)
                        if draft.teams[index].id != draft.myTeamId {
                            Button(role: .destructive) { draft.teams.remove(at: index) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                        }
                    }.listRowSeparator(.hidden)
                    TextField(draft.teams[index].id == draft.myTeamId ? "自分のチーム名" : "チーム名", text: $draft.teams[index].name)
                    ForEach(draft.teams[index].members.indices, id: \.self) { memberIndex in
                        HStack {
                            GiriEditorPlayerField(title: "メンバー\(memberIndex + 1)", text: teamMemberBinding(team: index, member: memberIndex), compact: true)
                            if fixedTeamSize == nil {
                                Button(role: .destructive) {
                                    draft.teams[index].members.remove(at: memberIndex)
                                    if draft.teams[index].members.isEmpty { draft.teams[index].members = [""] }
                                } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                            }
                        }
                    }
                    if fixedTeamSize == nil {
                        Button { draft.teams[index].members.append("") } label: { Label("メンバーを追加", systemImage: "plus.circle") }.tint(accentActionColor)
                    }
                }.appEventEditorCardStyle(accentColor: AppSectionAccent.artist)
            }
            Section {
                Button { appendOtherTeam() } label: { Label("他のチームを追加", systemImage: "plus.circle") }
            }.appEventEditorCardStyle(accentColor: AppSectionAccent.artist)
        }
    }

    private func changeTeamSize(_ value: Int) {
        let limit: Int? = value == 0 ? nil : value
        if let limit, draft.teams.contains(where: { $0.members.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count > limit }) {
            store.errorMessage = "入力済みのメンバーが新しい人数を超えています。先にメンバーを確認してください。"
            return
        }
        if draft.tournamentFormat == .pair && value != 2 { draft.tournamentFormat = .team }
        draft.teamSize = limit
        normalizeTeamSlots()
    }
    private func ensureOwnTeam() {
        guard draft.tournamentFormat != .individual else { return }
        if let mine = draft.teams.first(where: { $0.id == draft.myTeamId || $0.isMine }) {
            draft.myTeamId = mine.id
        } else {
            var mine = GiriTeam()
            mine.isMine = true
            let me = store.preferences.selfName.trimmingCharacters(in: .whitespacesAndNewlines)
            mine.members = me.isEmpty ? [""] : [me]
            draft.myTeamId = mine.id
            draft.teams.insert(mine, at: 0)
        }
        for index in draft.teams.indices { draft.teams[index].isMine = draft.teams[index].id == draft.myTeamId }
        normalizeTeamSlots()
    }
    private func normalizeTeamSlots() {
        for index in draft.teams.indices {
            let names = draft.teams[index].members.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if let count = fixedTeamSize {
                // Never remove a saved person to fit a reduced team size.
                draft.teams[index].members = names + Array(repeating: "", count: max(0, count - names.count))
            } else if draft.teams[index].members.isEmpty { draft.teams[index].members = [""] }
        }
    }
    private func appendOtherTeam() {
        var team = GiriTeam()
        team.members = Array(repeating: "", count: fixedTeamSize ?? 1)
        draft.teams.append(team)
    }
    private func teamMemberBinding(team: Int, member: Int) -> Binding<String> {
        Binding(get: {
            guard draft.teams.indices.contains(team), draft.teams[team].members.indices.contains(member) else { return "" }
            return draft.teams[team].members[member]
        }, set: { value in
            guard draft.teams.indices.contains(team), draft.teams[team].members.indices.contains(member) else { return }
            draft.teams[team].members[member] = value
        })
    }

    @ViewBuilder private var scheduleSections: some View {
        ForEach(draft.rounds.indices, id: \.self) { index in
            Section {
                HStack {
                    GiriEventCardSectionTitle(title: draft.rounds[index].name, systemImage: "calendar", accentColor: AppSectionAccent.artist)
                    Text("\(draft.rounds[index].promptNumber)回目").font(.subheadline).foregroundStyle(.secondary).fixedSize()
                    Menu {
                        if index > 0 { Button("上へ移動", systemImage: "arrow.up") { draft.rounds.swapAt(index, index - 1) } }
                        if index + 1 < draft.rounds.count { Button("下へ移動", systemImage: "arrow.down") { draft.rounds.swapAt(index, index + 1) } }
                        Button("削除", systemImage: "trash", role: .destructive) { draft.rounds.remove(at: index) }
                    } label: { Image(systemName: "ellipsis.circle") }.tint(accentActionColor)
                }.listRowSeparator(.hidden)
                GiriRoundFields(round: $draft.rounds[index], automatic: Binding(get: { automaticFields[draft.rounds[index].id] ?? [] }, set: { automaticFields[draft.rounds[index].id] = $0 }), tournament: draft.meetingType == .tournament)
            }.appEventEditorCardStyle(accentColor: AppSectionAccent.artist)
        }
        Section {
            Button { addRound(sameStage: false) } label: { Label(draft.meetingType == .tournament ? "次の段階を追加" : "日程を追加", systemImage: "plus.circle") }
            if draft.meetingType == .tournament && !draft.rounds.isEmpty {
                Button { addRound(sameStage: true) } label: { Label("同じ段階の次回を追加", systemImage: "plus.square.on.square") }
            }
        }.appEventEditorCardStyle(accentColor: AppSectionAccent.artist)
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
        if draft.tournamentFormat != .individual { ensureOwnTeam() }
        initial = draft
        selfWasAdded = false
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
        guard showsParticipantSection else { return }
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
        let round = nextEventRound(rounds: draft.rounds, preferences: store.preferences,
            sameStage: sameStage, tournament: draft.meetingType == .tournament,
            referenceDate: draft.eventDate ?? Date())
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
                site.format = draft.eventFormat
                try store.saveOnlineSite(site)
            } else {
                var candidate = draft
                candidate.title = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let venueMatch = store.venueDirectory.first { playerSearchKey($0.name) == playerSearchKey(candidate.venue) }
                candidate.venueId = venueMatch.flatMap { $0.id.hasPrefix("history:") ? nil : $0.id }
                var seen = Set<String>()
                if showsParticipantSection {
                    candidate.participants = participants.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert(giriEditorNameKey($0)).inserted }
                }
                for i in candidate.teams.indices { candidate.teams[i].members = candidate.teams[i].members.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
                if let size = candidate.teamSize, candidate.teams.contains(where: { $0.members.count > size }) {
                    store.errorMessage = "チーム人数を超えているチームがあります。人数設定かメンバーを確認してください。"; return
                }
                try giriEditorValidate(candidate)
                try store.saveEvent(candidate)
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

/// Compatibility wrapper used by roster/result editors; all name inputs use
/// the same LiveStair-derived suggestion card rather than horizontal chips.
struct GiriEditorPlayerField: View {
    let title: String
    @Binding var text: String
    var preferHosts = false
    var compact = false
    var body: some View {
        GiriPlayerSuggestionField(title: title, text: $text, organizer: preferHosts,
            showsLabel: preferHosts, textAlignment: preferHosts ? .trailing : .leading)
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
