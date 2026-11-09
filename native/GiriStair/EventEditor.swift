import SwiftUI
import PhotosUI

/// The same native Form / menu Picker / section modifiers as EventBasicEditor.
struct GiriEventEditor: View {
    @EnvironmentObject private var store: GiriStore
    @EnvironmentObject private var navigation: GiriNavigation
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
    /// 画面の読み取り結果（文字と位置）。参加者の欄を分けるのに使う。
    @State private var importLines: [GiriOCRLine]?
    @State private var showImport = false
    @State private var photo: PhotosPickerItem?
    @State private var recognizing = false
    @State private var showDiscard = false
    @State private var showLeave = false
    @State private var saving = false
    @State private var site = OnlineSite()
    @State private var lastOrganizer = ""
    @State private var lastEventDay: Date?
    /// 主催・共催・MC・審査員に自分が入っているか（変わった時だけ「自分の立場」の初期値を変える）。
    @State private var lastSelfStaff = false
    /// トーナメント表（生大喜利・個人戦）の読み取り結果の確認。
    @State private var bracketDraft: GiriBracketDraft?
    /// イベントページ（ツイプラなど）の読み取り：基本情報と参加者を確認してから反映する。
    @State private var eventPagePhoto: PhotosPickerItem?
    @State private var readingEventPage = false
    @State private var eventPageDraft: GiriEventPageDraft?
    /// 応募の日程は、入れる時だけ欄を出す。
    @State private var showsEntry = false
    /// 参加者を外す時に、リザーバー1を繰り上げるかを聞く。
    @State private var removingParticipant: Int?
    /// 0.19：募集期間の開始・締切を選ぶシート。
    @State private var entryEndpoint: GiriEntryEndpoint?

    init(event: GiriEvent? = nil, onSaved: (() -> Void)? = nil) {
        self.event = event
        self.onSaved = onSaved
    }

    private var isSite: Bool {
        event == nil && draft.eventFormat == .onlineLong && draft.meetingType == .casual
    }
    private var isTeamTournament: Bool { draft.meetingType == .tournament && draft.tournamentFormat != .individual }
    private var isLive: Bool { draft.eventFormat == .live }
    private var isTournament: Bool { draft.meetingType == .tournament }
    /// 生大喜利の個人戦トーナメント：参加者の並びをトーナメント表の順に使う。
    private var isKnockoutBracket: Bool { isLive && isTournament && draft.knockout && !isTeamTournament }
    private var selfIsStaff: Bool { draft.staffNames.contains { store.preferences.isSelf($0) } }
    /// チーム戦は参加者ではなく「自分のチーム・他のチーム」として入力する。
    /// 即席チームの時だけ、先に参加者を入れて後からチームへ振り分ける。
    private var showsParticipantSection: Bool {
        if isTeamTournament { return draft.impromptuTeams }
        if isKnockoutBracket { return true }
        return !(draft.meetingType == .tournament && (draft.eventFormat == .onlineLong || draft.eventFormat == .onlineShort))
    }
    /// 参加者が2人以上の時だけ並び替えを付ける（1人の時は「≡」を出さない）。
    private var participantMoveAction: ((IndexSet, Int) -> Void)? {
        guard canReorderParticipants else { return nil }
        return { source, destination in participants.move(fromOffsets: source, toOffset: destination) }
    }
    private var canReorderReserves: Bool { showsReserves && draft.hasReserves && draft.reserves.count > 1 }
    private var canReorderParticipants: Bool {
        showsParticipantSection && participants.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count > 1
    }
    /// まだどのチームにも入っていない参加者（即席チーム）。
    private var unassignedNames: [String] {
        let assigned = Set(draft.teams.flatMap(\.members).map(giriEditorNameKey))
        return participants.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !assigned.contains(giriEditorNameKey($0)) }
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
    /// 参加状況。生大喜利の「観覧」は参加状況で選び、自分の立場を観覧にする（ほかの立場は入力から決める）。
    private var participationChoice: Binding<String> {
        Binding(get: {
            if draft.status == .canceled { return "canceled" }
            if draft.isInterested { return "interested" }
            return isLive && draft.selfRole == .spectator ? "spectating" : "participating"
        }, set: { choice in
            draft.isInterested = choice == "interested"
            draft.isParticipating = choice == "participating" || choice == "spectating"
            draft.status = choice == "canceled" ? .canceled : .planned
            let spectating = choice == "spectating"
            if spectating != (draft.selfRole == .spectator) {
                draft.selfRole = spectating ? .spectator : .player
                placeSelf(force: true)
            }
        })
    }
    private var promoteTitle: String {
        guard let index = removingParticipant, participants.indices.contains(index) else { return "リザーバーを繰り上げますか？" }
        return "「\(participants[index])」を外して、リザーバーを繰り上げますか？"
    }

    /// 会の種類（企画は通常の会として保存し、企画の印を付ける）。
    private var meetingChoice: Binding<String> {
        Binding(get: { draft.isKumiteEvent ? "kumite" : draft.isProjectEvent ? "project" : draft.meetingType.rawValue }, set: { value in
            draft.isProject = value == "project"
            draft.isKumite = value == "kumite"
            draft.meetingType = value == "tournament" ? .tournament : .casual
        })
    }
    /// 入力した内容から決まる自分の立場（保存する時もこれを使う）。
    private var currentSelfRole: GiriSelfRole {
        var value = draft
        value.participants = participants
        return value.derivedSelfRole(isSelf: store.preferences.isSelf)
    }
    private var hasReservesBinding: Binding<Bool> {
        Binding(get: { draft.hasReserves }, set: { enabled in
            draft.hasReserves = enabled
            if enabled && draft.reserves.isEmpty { draft.reserves = [""] }
            placeSelf(force: false)
        })
    }
    /// 生大喜利の大会だけ：参加者の一番下でリザーバーのあり・なしと名前を入れる。
    /// 0.19：リザーバーは生大喜利のどの会でも入れられる。
    private var showsReserves: Bool { isLive }
    /// リザーバーはオンにした下に、繰り上がる順の番号を付けて並べる（並び替えられる）。
    @ViewBuilder private var reserveRows: some View {
        Toggle(isOn: hasReservesBinding) { GiriEditorLabel("リザーバー") }
            .tint(AppSectionAccent.artist)
        if draft.hasReserves {
            ForEach(draft.reserves.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    Button(role: .destructive) {
                        guard draft.reserves.indices.contains(index) else { return }
                        draft.reserves.remove(at: index)
                        placeSelf(force: false)
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).accessibilityLabel("リザーバーを削除")
                    Text("\(index + 1)").font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(AppSectionAccent.artist).frame(width: 22, alignment: .center)
                    GiriEditorPlayerField(title: "リザーバー", text: reserveBinding(index), compact: true)
                }.listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 12))
                    .environment(\.defaultMinListRowHeight, 36)
            }
            .onMove(perform: reserveMoveAction)
            Button { draft.reserves.append("") } label: { Label("リザーバーを追加", systemImage: "plus.circle") }
                .tint(accentActionColor)
        }
    }

    private func reserveBinding(_ index: Int) -> Binding<String> {
        Binding(get: { draft.reserves.indices.contains(index) ? draft.reserves[index] : "" }, set: { value in
            guard draft.reserves.indices.contains(index) else { return }
            draft.reserves[index] = value
            placeSelf(force: false)
        })
    }

    private var reserveMoveAction: ((IndexSet, Int) -> Void)? {
        guard draft.reserves.count > 1 else { return nil }
        return { source, destination in draft.reserves.move(fromOffsets: source, toOffset: destination) }
    }

    /// リザーバー1（名前のある最初の人）。
    private var firstReserveName: String? {
        draft.reserveNames.first
    }

    /// 参加者を外す。リザーバーがいる時は、リザーバー1を繰り上げるかを聞く。
    private func requestRemoveParticipant(_ index: Int) {
        guard participants.indices.contains(index) else { return }
        let name = participants[index].trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty && showsReserves && firstReserveName != nil {
            removingParticipant = index
        } else {
            removeParticipant(index, promote: false)
        }
    }

    private func removeParticipant(_ index: Int, promote: Bool) {
        guard participants.indices.contains(index) else { return }
        participants.remove(at: index)
        if promote, let reserveIndex = draft.reserves.firstIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            // リザーバー1を参加者の一番下へ。残りのリザーバーは番号を1つずつ繰り上げる。
            let promoted = draft.reserves.remove(at: reserveIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            participants.removeAll { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            participants.append(promoted)
            if draft.reserves.isEmpty { draft.reserves = [""] }
        }
        if participants.isEmpty { participants = [""] }
        placeSelf(force: false)
    }
    private var isValid: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var isDirty: Bool {
        draft != initial || participants.filter { !$0.isEmpty } != initial.participants
    }

    // 型チェックが長くならないように、本体・見た目・変更の処理・シートと確認を分ける。
    var body: some View {
        withSheets(withPhotoHandler(withChangeHandlers(editorChrome)))
    }

    /// LiveStair EventBasicEditor と同じく、参加者（リザーバー）が2人以上の時は「≡」を長押しして並び替える。
    private var editModeValue: EditMode {
        canReorderParticipants || canReorderReserves ? .active : .inactive
    }

    private var editorForm: some View {
        Form {
            if isLive { eventReadSection }
            basicSection
            if isSite { siteSection }
            if !isSite {
                // 0.19：組手は主役の枠と対戦相手の枠を分ける（対戦相手は参加者の欄）。
                if draft.isKumiteEvent { kumiteMainSection }
                if showsParticipantSection { participantSection }
                if draft.meetingType == .tournament { teamSections }
                if showsReserves && !showsParticipantSection { reserveSection }
                // 応募の日程は参加者の下。入れる時だけ欄を出す。
                entrySection
                if draft.eventFormat.hasOnlineRounds { scheduleSections }
                Section {
                    GiriEventCardSectionTitle(title: "メモ", systemImage: "text.alignleft", accentColor: AppSectionAccent.memo)
                        .listRowSeparator(.hidden)
                    TextField("メモ", text: $draft.memo, axis: .vertical).lineLimit(3...10)
                }.appEventEditorCardStyle(accentColor: AppSectionAccent.memo)
            }
        }
    }

    private var editorChrome: some View {
        editorForm
        .appEditorFormStyle()
        .environment(\.defaultMinListRowHeight, 48)
        // LiveStair EventBasicEditor と同じく、参加者が2人以上の時は「≡」を長押しして並び替える。
        .environment(\.editMode, .constant(editModeValue))
        .navigationTitle(event == nil ? "" : "編集")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(event != nil && isDirty)
        .toolbar(event == nil ? .hidden : .visible, for: .navigationBar)
        .toolbarBackground(appHeaderColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
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
    }

    private func withChangeHandlers<Content: View>(_ content: Content) -> some View {
        content
        .onAppear { if !loaded { load() } }
        // 編集中に別のタブから別の記録を開いても、この入力を黙って閉じない。
        .onChange(of: isDirty) { _, dirty in if let event { navigation.markEditor(event.id, unsaved: dirty) } }
        .onChange(of: draft.organizer) { _, next in
            if next != lastOrganizer { lastOrganizer = next; syncSelf() }
        }
        // 共催・MC・審査員・主催の種類が変わった時も、自分がプレイヤーかどうかを合わせる。
        .onChange(of: draft.staffNames) { _, _ in syncSelf() }
        .onChange(of: draft.eventDate) { _, next in
            if next != lastEventDay { let previous = lastEventDay; lastEventDay = next; moveDay(from: previous, to: next) }
        }
        .onChange(of: draft.eventFormat) { _, format in
            if format == .onlineLong && draft.rounds.isEmpty && !isSite { addRound(sameStage: false) }
            // 立場・対戦形式は生大喜利だけ。ほかの形式ではプレイヤーとして扱う。
            if format != .live { draft.selfRole = .player; draft.knockout = false }
        }
        .onChange(of: draft.meetingType) { _, type in
            if type == .tournament && draft.eventFormat == .onlineLong && draft.rounds.isEmpty { addRound(sameStage: false) }
            if type == .tournament && draft.tournamentFormat != .individual { ensureOwnTeam() }
        }
        .onChange(of: draft.tournamentFormat) { old, format in
            if format != .individual {
                if old == .individual && draft.teamSize == nil && draft.teams.isEmpty { draft.teamSize = 2 }
                ensureOwnTeam()
                // 個人戦で入れた参加者は消さず、即席チームとして後から振り分けられるようにする。
                if old == .individual && participants.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.preferences.isSelf($0) }) {
                    draft.impromptuTeams = true
                }
            }
        }
    }

    /// 参加者の画面・トーナメント表の画像を読み取る。
    private func withPhotoHandler<Content: View>(_ content: Content) -> some View {
        content
        .onChange(of: photo) { _, item in
            guard let item else { return }
            recognizing = true
            let bracket = isKnockoutBracket
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw GiriParticipantReadError.unreadable }
                    if bracket {
                        // トーナメント表は文字の位置から上の山→下の山の順に並べ、確認してから使う。
                        let lines = try await GiriParticipantOCR.recognizeLines(data)
                        bracketDraft = GiriBracketDraft(names: giriBracketOrder(lines))
                    } else {
                        // 参加者一覧の画面は、文字の位置から「参加者」の欄を分けて確認に進む。
                        importLines = try await GiriParticipantOCR.recognizeLines(data)
                        importText = ""
                        showImport = true
                    }
                } catch { store.errorMessage = error.localizedDescription }
                recognizing = false
                photo = nil
            }
        }
    }

    private func withSheets<Content: View>(_ content: Content) -> some View {
        withPromoteAlert(content)
        .sheet(isPresented: $showImport) {
            NavigationStack {
                GiriParticipantImport(source: importText, lines: importLines, existing: participants) { names in
                    let existing = Set(participants.map(giriEditorNameKey))
                    let added = names.filter { !existing.contains(giriEditorNameKey($0)) }
                    participants.removeAll { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    participants.append(contentsOf: added)
                    if participants.isEmpty { participants = [""] }
                }
            }
        }
        .sheet(item: $bracketDraft) { draft in
            NavigationStack {
                GiriBracketEditor(names: draft.names) { names in participants = names.isEmpty ? [""] : names }
            }
        }
        .alert("入力内容を空にしますか？", isPresented: $showDiscard) {
            Button("キャンセル", role: .cancel) {}
            Button("空にする", role: .destructive) { loaded = false; load() }
        } message: { Text("現在入力している内容を空にします。保存済みの記録には影響しません。") }
        // LiveStair と同じく、登録タブを続けて2回押すと入力内容を空にする確認を出す。
        .onChange(of: navigation.registrationClearToken) { _, _ in
            if event == nil && isDirty { showDiscard = true }
        }
        .giriDiscardChangesAlert(isPresented: $showLeave) {
            if let event { navigation.markEditor(event.id, unsaved: false) }
            dismiss()
        }
    }

    /// 参加者を外す時に、リザーバー1を繰り上げるかを聞く。
    private func withPromoteAlert<Content: View>(_ content: Content) -> some View {
        content
        .alert(promoteTitle, isPresented: Binding(get: { removingParticipant != nil }, set: { if !$0 { removingParticipant = nil } })) {
            Button("繰り上げる") {
                if let index = removingParticipant { removeParticipant(index, promote: true) }
                removingParticipant = nil
            }
            Button("繰り上げない") {
                if let index = removingParticipant { removeParticipant(index, promote: false) }
                removingParticipant = nil
            }
            Button("キャンセル", role: .cancel) { removingParticipant = nil }
        } message: { Text("リザーバー1の「\(firstReserveName ?? "")」を参加者の一番下に入れ、ほかのリザーバーの番号を1つずつ上げます。") }
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

    /// LiveStair EventBasicEditor ocrReadRow：イベントページの画像から基本情報・参加者を読み取る。
    private var eventReadSection: some View {
        Section {
            PhotosPicker(selection: $eventPagePhoto, matching: .images) {
                HStack(spacing: 12) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: appFontSize(17), weight: .semibold))
                        .foregroundStyle(AppSectionAccent.scan)
                        .frame(width: 30, height: 30)
                        .background(AppSectionAccent.scan.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("画像からOCR読み取り").font(.body.weight(.semibold)).foregroundStyle(.primary)
                        Text("イベントページから基本情報・参加者を入力").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if readingEventPage { ProgressView().controlSize(.small) }
                    else { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(readingEventPage)
            .onChange(of: eventPagePhoto) { _, item in
                if let item { readEventPage(item) }
            }
            .sheet(item: $eventPageDraft) { page in
                NavigationStack {
                    GiriEventPageReview(draft: page, onApply: applyEventPage)
                }
            }
        }.appEventEditorCardStyle(accentColor: AppSectionAccent.scan)
    }

    private func readEventPage(_ item: PhotosPickerItem) {
        readingEventPage = true
        let known = giriParticipantKnownNames(store)
        let venues = store.venueDirectory.map(\.name)
        var organizers = store.playerDirectory.map(\.name)
        organizers.append(contentsOf: store.groupDirectory.map(\.name))
        let current = participants
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw GiriParticipantReadError.unreadable }
                let lines = try await GiriParticipantOCR.recognizeLines(data)
                var page = giriEventPageDraft(lines: lines, known: known, venues: venues, organizers: organizers)
                page.participants = giriMarkingAlreadyAdded(giriResolvingAliases(page.participants, store: store),
                                                            existing: giriResolvedNames(current, store: store))
                guard page.hasBasicInfo || !page.participants.isEmpty else { throw GiriParticipantReadError.noText }
                eventPageDraft = page
            } catch { store.errorMessage = error.localizedDescription }
            readingEventPage = false
            eventPagePhoto = nil
        }
    }

    /// 読み取った内容を入力に反映する。置き換えない時は空欄だけに入れ、参加者は重ならない人だけ足す。
    private func applyEventPage(_ page: GiriEventPageDraft, replace: Bool) {
        let calendar = Calendar.current
        // 新しく登録する時の日付（今日のまま触っていない）は、読み取った日付で上書きする。
        let untouchedDate = draft.eventDate == nil || (event == nil && draft.eventDate == initial.eventDate)
        if let date = page.date, replace || untouchedDate {
            let previous = draft.eventDate
            let newDay = calendar.startOfDay(for: date)
            lastEventDay = newDay
            draft.eventDate = newDay
            moveDay(from: previous, to: newDay)
        }
        var value = draft
        value.title = Self.merged(value.title, page.title, replace: replace)
        value.venue = Self.merged(value.venue, page.venue, replace: replace)
        value.venueRoom = Self.merged(value.venueRoom, page.venueRoom, replace: replace)
        value.organizer = Self.merged(value.organizer, page.organizer, replace: replace)
        if let fee = page.fee, replace || value.entryFee == nil { value.entryFee = fee }
        let day = value.eventDate ?? calendar.startOfDay(for: Date())
        value.opensAt = Self.merged(value.opensAt, page.opens, on: day, replace: replace)
        value.startsAt = Self.merged(value.startsAt, page.start, on: day, replace: replace)
        value.endsAt = Self.merged(value.endsAt, page.end, on: day, replace: replace)
        if let start = value.startsAt, let end = value.endsAt, end < start {
            value.endsAt = calendar.date(byAdding: .day, value: 1, to: end)
        }
        if value.eventDate == nil && (value.startsAt != nil || value.opensAt != nil) {
            lastEventDay = day
            value.eventDate = day
        }
        draft = value
        let existing = Set(participants.map(giriEditorNameKey))
        let added = giriSelectedParticipantNames(page.participants).filter { !existing.contains(giriEditorNameKey($0)) }
        // 読み取った後は空の行を作らない（「参加者を追加」で増やす）。
        if !added.isEmpty {
            participants.removeAll { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            participants.append(contentsOf: added)
        }
    }

    private static func merged(_ current: String, _ read: String, replace: Bool) -> String {
        let text = read.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return current }
        return replace || current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : current
    }

    private static func merged(_ current: Date?, _ clock: GiriClock?, on day: Date, replace: Bool) -> Date? {
        guard let clock, replace || current == nil, let value = giriClockDate(clock, on: day) else { return current }
        return value
    }

    private var basicSection: some View {
        Section {
            GiriEventCardSectionTitle(title: "基本情報", systemImage: "slider.horizontal.3", accentColor: AppSectionAccent.live)
                .listRowSeparator(.hidden)
            HStack(spacing: 4) {
                GiriEditorLabel("形式")
                AppInfoButton(title: "形式について",
                              message: "使わない形式は、設定→デフォルト設定の「使用する形式・並び順」でチェックを外すと、ここと一覧・戦績のタブに出なくなります。登録済みの記録は消えません。",
                              tintColor: AppSectionAccent.live)
                Spacer(minLength: 8)
                Picker("形式", selection: $draft.eventFormat) {
                    ForEach(store.preferences.formatChoices(including: event?.eventFormat)) { Text($0.title).tag($0) }
                }.labelsHidden().pickerStyle(.menu).tint(.primary)
            }
            Picker(selection: meetingChoice) {
                Text("通常").tag("casual")
                Text("大会").tag("tournament")
                // 生大喜利・スプシ系は、通常・大会とは別に「企画」も選べる。
                if draft.eventFormat.allowsProject { Text("企画").tag("project") }
                // 0.19：組手（主役に対してたくさんのメンバーが対戦する企画）。
                if draft.eventFormat.allowsProject { Text("組手").tag("kumite") }
            } label: { GiriEditorLabel("会の種類") }.pickerStyle(.menu).tint(.primary)
            // 大会は生・ネットを問わず、ここで個人戦／チーム戦と人数を選ぶ（結果入力もこれに合わせる）。
            if draft.meetingType == .tournament {
                Picker(selection: $draft.tournamentFormat) {
                    Text("個人戦").tag(TournamentFormat.individual)
                    Text("チーム戦").tag(TournamentFormat.team)
                    if draft.tournamentFormat == .pair { Text("タッグ戦").tag(TournamentFormat.pair) }
                } label: { GiriEditorLabel("参加形式") }.pickerStyle(.menu).tint(.primary)
                if draft.tournamentFormat != .individual {
                    Picker(selection: Binding(get: { fixedTeamSize ?? 0 }, set: changeTeamSize)) {
                        Text("制限なし").tag(0)
                        ForEach(2...6, id: \.self) { Text("\($0)人").tag($0) }
                        if let size = draft.teamSize, size > 6 { Text("\(size)人").tag(size) }
                    } label: { GiriEditorLabel("チーム人数") }.pickerStyle(.menu).tint(.primary)
                    Toggle(isOn: $draft.impromptuTeams) {
                        HStack(spacing: 4) {
                            GiriEditorLabel("即席チーム")
                            AppInfoButton(title: "即席チームについて",
                                          message: "当日にチームを分ける大会で使います。先に参加者を入れ、後から各チームへ振り分けます。",
                                          tintColor: AppSectionAccent.live)
                        }
                    }.tint(AppSectionAccent.live)
                }
                if isLive {
                    Picker(selection: $draft.knockout) {
                        Text("横並び・その他").tag(false)
                        Text("トーナメント（1対1）").tag(true)
                    } label: { GiriEditorLabel("対戦形式") }.pickerStyle(.menu).tint(.primary)
                }
            }
            if !isSite {
                Picker(selection: participationChoice) {
                    Text("参加").tag("participating")
                    if isLive { Text("観覧").tag("spectating") }
                    Text("興味あり").tag("interested")
                    Text("キャンセル").tag("canceled")
                } label: { GiriEditorLabel("参加状況") }.pickerStyle(.menu).tint(.primary)
            }
            TextField(isSite ? "サイト名 *" : "会・大会名 *", text: $draft.title, axis: .vertical)
                .lineLimit(1...5)
            if !isSite {
                // 主催団体一覧に登録した団体は、名前を入れると団体の主催として保存する。
                GiriEditorPlayerField(title: "主催者", text: $draft.organizer, preferHosts: true)
                if isLive { staffRows }
                GiriHashtagField(text: $draft.hashtag)
                if draft.eventFormat.hasLiveTiming {
                    OptionalDateRow(title: "日付", selection: $draft.eventDate, components: .date)
                    GiriEventTimeRow(startsAt: clockBinding(start: true), endsAt: clockBinding(start: false),
                                     opensAt: isLive ? openClockBinding : nil)
                    if draft.eventFormat != .onlineShort {
                        GiriVenueSuggestionField(text: $draft.venue)
                        // 施設の会議室などは、会場名と分けて部屋を入れる（会場一覧は施設でまとまる）。
                        HStack(spacing: 12) {
                            GiriEditorLabel("部屋")
                            TextField("会議室名・部屋番号（任意）", text: $draft.venueRoom).multilineTextAlignment(.trailing)
                        }
                    }
                    // 参加費は生大喜利だけ（スプシ系・ネットは参加費なし）。
                    if draft.eventFormat == .live || draft.entryFee != nil {
                        GiriEntryFeeField(value: $draft.entryFee)
                    }
                }
                // イベントページ・サイトのURL（どの形式でも入れられる）。
                TextField(draft.eventFormat.hasOnlineRounds ? "サイトURL" : "イベントページのURL", text: $draft.siteUrl)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                if draft.eventFormat.hasOnlineRounds {
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
        Group {
            GiriSiteCycleSettingsForm(site: $site, isNew: true)
            Section { TextField("メモ", text: $site.memo, axis: .vertical).lineLimit(2...6) }
                .appEventEditorCardStyle(accentColor: AppSectionAccent.memo)
        }
    }

    private var participantSection: some View {
        Section {
            HStack(spacing: 6) {
                GiriEventCardSectionTitle(title: isTeamTournament ? "参加者（チーム分け前）" : isKnockoutBracket ? "トーナメント表（上から順）" : draft.isKumiteEvent ? "対戦相手" : "参加者",
                                          systemImage: isKnockoutBracket ? "list.number" : "person.2", accentColor: AppSectionAccent.artist)
                Text(isTeamTournament ? "未振り分け\(unassignedNames.count)人" : "\(participants.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count)人")
                    .font(.caption).foregroundStyle(.secondary).fixedSize()
                Button { importText = ""; importLines = nil; showImport = true } label: {
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
                    // 並び替えの「≡」と押し間違えないように、外すボタンは左に置く。
                    Button(role: .destructive) { requestRemoveParticipant(index) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).accessibilityLabel("参加者を削除")
                    if isKnockoutBracket {
                        Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22, alignment: .trailing)
                    }
                    GiriEditorPlayerField(title: "参加者名", text: participantBinding(index), compact: true)
                    if isTeamTournament { assignMenu(index) }
                }.listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 12))
                    .environment(\.defaultMinListRowHeight, 36)
            }
            .onMove(perform: participantMoveAction)
            Button { participants.append("") } label: { Label("参加者を追加", systemImage: "plus.circle") }.tint(accentActionColor)
            if isKnockoutBracket {
                Button { bracketDraft = GiriBracketDraft(names: participants.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }) } label: {
                    Label("並びと自分の山を確認", systemImage: "arrow.triangle.branch")
                }.tint(accentActionColor)
            }
            if showsReserves { reserveRows }
        }.appEventEditorCardStyle(accentColor: AppSectionAccent.artist)
    }

    /// 0.19：組手の主役（タッグなどは複数）。
    private var kumiteMainSection: some View {
        Section {
            GiriEventCardSectionTitle(title: "主役", systemImage: "star", accentColor: AppSectionAccent.favorite)
                .listRowSeparator(.hidden)
            GiriNamesField(title: "", names: $draft.kumiteMains, priorityNames: participants.filter { !$0.isEmpty })
        }.appEventEditorCardStyle(accentColor: AppSectionAccent.favorite)
    }

    /// 0.19：募集期間。見出しは最初から出し、「日程を追加」で開始（今日から）を入れる。
    /// 締切はチェックを入れた時だけ。日時は LiveStair のチケット予定管理と同じボタンとシートで選ぶ。
    private var entrySection: some View {
        Section {
            HStack(spacing: 8) {
                GiriEventCardSectionTitle(title: "募集期間", systemImage: "calendar.badge.clock", accentColor: AppSectionAccent.ticket)
                if showsEntry {
                    Spacer(minLength: 8)
                    Button(role: .destructive) {
                        draft.entryStart = nil
                        draft.entryEnd = nil
                        showsEntry = false
                    } label: { Image(systemName: "xmark.circle").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("募集期間を外す")
                }
            }
            .listRowSeparator(.hidden)
            if showsEntry {
                HStack(spacing: 8) {
                    GiriEndpointButton(title: "開始", date: draft.entryStart) { entryEndpoint = .start }
                    if draft.entryEnd != nil {
                        Text("〜").foregroundStyle(.secondary)
                        GiriEndpointButton(title: "締切", date: draft.entryEnd) { entryEndpoint = .end }
                    }
                }
                Toggle(isOn: Binding(get: { draft.entryEnd != nil }, set: { on in
                    draft.entryEnd = on ? addCalendarDays(draft.entryStart ?? Date(), 7) : nil
                })) { GiriEditorLabel("締切を入れる") }
                .tint(AppSectionAccent.ticket)
                if let start = draft.entryStart, let end = draft.entryEnd, end < start {
                    Text("締切を開始以降の日時にしてください。").font(.caption).foregroundStyle(.red)
                }
                Text(entryNotificationCaption).font(.caption).foregroundStyle(.secondary)
            } else {
                Button {
                    if draft.entryStart == nil { draft.entryStart = giriFiveMinuteRounded(Date()) }
                    showsEntry = true
                } label: { Label("日程を追加", systemImage: "plus.circle") }
                .tint(accentActionColor)
            }
        }
        .appEventEditorCardStyle(accentColor: AppSectionAccent.ticket)
        .sheet(item: $entryEndpoint) { endpoint in
            GiriDateTimePickerSheet(title: endpoint == .start ? "募集開始" : "募集締切",
                                    date: (endpoint == .start ? draft.entryStart : draft.entryEnd) ?? giriFiveMinuteRounded(Date())) { date in
                if endpoint == .start { draft.entryStart = date } else { draft.entryEnd = date }
            }
        }
    }

    private var entryNotificationCaption: String {
        let preferences = store.preferences
        guard preferences.notificationsEnabled else { return "設定で通知をオンにすると、募集開始を知らせます。" }
        var parts: [String] = []
        let lead = preferences.entryLeadMinutes ?? preferences.reminderMinutes
        if preferences.entryNotifyBefore && lead > 0 { parts.append("開始の" + giriLeadText(lead) + "前") }
        if preferences.entryNotifyAtStart || (preferences.entryNotifyBefore && lead == 0) { parts.append("開始時") }
        return parts.isEmpty ? "募集期間の通知はオフです（設定の通知で変えられます）。" : "募集の" + parts.joined(separator: "と") + "に通知します（設定の通知で変えられます）。"
    }

    /// チーム戦（参加者の欄がない時）のリザーバー。
    private var reserveSection: some View {
        Section {
            GiriEventCardSectionTitle(title: "リザーバー", systemImage: "person.badge.clock", accentColor: AppSectionAccent.artist)
                .listRowSeparator(.hidden)
            reserveRows
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

    /// 参加形式とチーム人数は基本情報で選ぶ。チーム戦の時だけ、自分のチームと他のチームを入れる。
    @ViewBuilder private var teamSections: some View {
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
                            GiriEditorPlayerField(title: "メンバー\(memberIndex + 1)", text: teamMemberBinding(team: index, member: memberIndex), compact: true,
                                                  priorityNames: draft.impromptuTeams ? unassignedNames : [])
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

    /// 生大喜利の共催・MC・審査員（MC・審査員は大会だけ）。
    @ViewBuilder private var staffRows: some View {
        ForEach(draft.coOrganizers.indices, id: \.self) { index in staffNameRow("共催", \.coOrganizers, index) }
        if isTournament {
            ForEach(draft.mcs.indices, id: \.self) { index in staffNameRow("MC", \.mcs, index) }
            ForEach(draft.judges.indices, id: \.self) { index in staffNameRow("審査員", \.judges, index) }
        }
        Menu {
            Button("共催を追加") { draft.coOrganizers.append("") }
            if isTournament {
                Button("MCを追加") { draft.mcs.append("") }
                Button("審査員を追加") { draft.judges.append("") }
            }
        } label: { Label(isTournament ? "共催・MC・審査員を追加" : "共催を追加", systemImage: "plus.circle") }
        .tint(accentActionColor)
    }

    private func staffNameRow(_ title: String, _ path: WritableKeyPath<GiriEvent, [String]>, _ index: Int) -> some View {
        HStack(spacing: 8) {
            GiriEditorPlayerField(title: title, text: Binding(get: {
                draft[keyPath: path].indices.contains(index) ? draft[keyPath: path][index] : ""
            }, set: { value in
                if draft[keyPath: path].indices.contains(index) { draft[keyPath: path][index] = value }
            }), preferHosts: true)
            Button(role: .destructive) {
                if draft[keyPath: path].indices.contains(index) { draft[keyPath: path].remove(at: index) }
            } label: { Image(systemName: "minus.circle") }
            .buttonStyle(.borderless).accessibilityLabel("\(title)を削除")
        }
    }

    private func teamTitle(_ index: Int) -> String {
        guard draft.teams.indices.contains(index) else { return "チーム" }
        let name = draft.teams[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return draft.teams[index].id == draft.myTeamId ? "自分のチーム" : "チーム\(index + 1)"
    }
    private func teamIndex(of name: String) -> Int? {
        let key = giriEditorNameKey(name)
        guard !key.isEmpty else { return nil }
        return draft.teams.firstIndex { $0.members.contains { giriEditorNameKey($0) == key } }
    }
    /// 即席チーム：参加者をチームへ振り分ける（1人は1チームだけ）。
    private func assignMenu(_ index: Int) -> some View {
        let name = participants.indices.contains(index) ? participants[index] : ""
        let current = teamIndex(of: name)
        return Menu {
            ForEach(orderedTeamIndices, id: \.self) { team in
                Button { assign(name, toTeam: team) } label: {
                    if current == team { Label(teamTitle(team), systemImage: "checkmark") } else { Text(teamTitle(team)) }
                }
            }
            Button {
                appendOtherTeam()
                assign(name, toTeam: draft.teams.count - 1)
            } label: { Label("新しいチームに入れる", systemImage: "plus") }
        } label: {
            Text(current.map(teamTitle) ?? "チームへ")
                .font(.caption.weight(.semibold)).lineLimit(1)
                .foregroundStyle(current == nil ? accentActionColor : Color.secondary)
        }
        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel("チームに振り分ける")
    }
    private func assign(_ name: String, toTeam index: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = giriEditorNameKey(trimmed)
        guard !key.isEmpty, draft.teams.indices.contains(index) else { return }
        if draft.teams[index].members.contains(where: { giriEditorNameKey($0) == key }) { return }
        let hasEmptySlot = draft.teams[index].members.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let hasRoom = hasEmptySlot || (fixedTeamSize.map { draft.teams[index].members.count < $0 } ?? true)
        guard hasRoom else {
            store.errorMessage = "「\(teamTitle(index))」は人数がいっぱいです。チーム人数かメンバーを確認してください。"
            return
        }
        // ほかのチームに入っていれば外す。
        for team in draft.teams.indices where team != index {
            if let member = draft.teams[team].members.firstIndex(where: { giriEditorNameKey($0) == key }) { draft.teams[team].members[member] = "" }
        }
        if let empty = draft.teams[index].members.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            draft.teams[index].members[empty] = trimmed
        } else {
            draft.teams[index].members.append(trimmed)
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
        // プレイヤーとして出ない時（主催・観覧など）は「自分のチーム」を作らない。
        guard draft.tournamentFormat != .individual, currentSelfRole == .player else { return }
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
                    if let number = giriRoundNumberText(draft.rounds[index], in: draft.rounds) {
                        Text(number).font(.subheadline).foregroundStyle(.secondary).fixedSize()
                    }
                    Menu {
                        if index > 0 { Button("上へ移動", systemImage: "arrow.up") { draft.rounds.swapAt(index, index - 1) } }
                        if index + 1 < draft.rounds.count { Button("下へ移動", systemImage: "arrow.down") { draft.rounds.swapAt(index, index + 1) } }
                        Button("削除", systemImage: "trash", role: .destructive) { draft.rounds.remove(at: index) }
                    } label: { Image(systemName: "ellipsis.circle") }.tint(accentActionColor)
                }.listRowSeparator(.hidden)
                GiriRoundFields(round: $draft.rounds[index], automatic: Binding(get: { automaticFields[draft.rounds[index].id] ?? [] }, set: { automaticFields[draft.rounds[index].id] = $0 }), tournament: draft.meetingType == .tournament,
                                siblingCount: draft.rounds.filter { $0.effectiveStageId == draft.rounds[index].effectiveStageId }.count)
            }.appEventEditorCardStyle(accentColor: AppSectionAccent.artist)
        }
        Section {
            // 大会は、1回目に「全N回」を入れた段階なら次の回、それ以外は次の段階を追加する。
            let parallel = draft.meetingType == .tournament && giriNextRoundIsParallel(draft.rounds)
            Button { addRound(sameStage: parallel) } label: {
                Label(draft.meetingType != .tournament ? "日程を追加" : parallel ? "同じ段階の次の回を追加" : "次の段階を追加", systemImage: "plus.circle")
            }
        }.appEventEditorCardStyle(accentColor: AppSectionAccent.artist)
    }

    private func load() {
        draft = event ?? GiriEvent()
        if event == nil {
            draft.eventDate = Calendar.current.startOfDay(for: Date())
            // 使わない形式を新規登録の初期値にしない（並び順の先頭を使う）。
            if !store.preferences.isFormatVisible(draft.eventFormat), let first = store.preferences.visibleFormatOrder.first {
                draft.eventFormat = first
            }
        }
        if draft.rounds.isEmpty { draft.rounds = draft.effectiveRounds }
        participants = draft.participants.isEmpty ? [""] : draft.participants
        showsEntry = draft.entryStart != nil || draft.entryEnd != nil
        if draft.teams.isEmpty, let old = draft.tournamentResult, old.format != .individual,
           !old.members.isEmpty || !old.teamName.isEmpty {
            var team = GiriTeam(); team.name = old.teamName; team.members = old.members; team.isMine = true
            draft.teams = [team]; draft.myTeamId = team.id; draft.tournamentFormat = old.format
        }
        // 0.10〜0.11 で「自分の立場」をリザーバーにした記録は、リザーバーの欄に自分を入れて開く（立場は入力から決める）。
        if event != nil && isLive && draft.selfRole == .reserve && !draft.reserveNames.contains(where: { store.preferences.isSelf($0) }) {
            let me = store.preferences.selfName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !me.isEmpty { draft.hasReserves = true; draft.reserves.insert(me, at: 0) }
        }
        lastSelfStaff = selfIsStaff
        if draft.tournamentFormat != .individual { ensureOwnTeam() }
        // チーム戦でチームに入っていない参加者がいる旧データは、即席チームとして参加者の欄を出す（消さない）。
        if draft.meetingType == .tournament && draft.tournamentFormat != .individual && !draft.unassignedParticipants.isEmpty {
            draft.impromptuTeams = true
        }
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

    /// 生大喜利：主催・共催・MC・審査員に自分を入れたら、自動で入れた参加者の自分を外す
    /// （出る時は参加者に自分を入れる）。自分の立場は入力から決める。ほかの形式は従来どおり。
    private func syncSelf() {
        guard isLive else { legacySyncSelf(); return }
        let staff = selfIsStaff
        if staff != lastSelfStaff {
            lastSelfStaff = staff
            if staff { removeAutoAddedSelf() }
        }
        placeSelf(force: false)
    }

    /// 自動で入れた自分（参加者・自分だけのチーム）を外す。
    private func removeAutoAddedSelf() {
        if selfWasAdded {
            participants.removeAll { store.preferences.isSelf($0) }
            if participants.isEmpty { participants = [""] }
            selfWasAdded = false
        }
        if isTeamTournament, let index = draft.teams.firstIndex(where: { $0.id == draft.myTeamId }),
           draft.teams[index].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           draft.teams[index].members.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).allSatisfy({ store.preferences.isSelf($0) }) {
            removeSelfFromTeams()
        }
    }

    private func removeSelfFromTeams() {
        for team in draft.teams.indices {
            for member in draft.teams[team].members.indices where store.preferences.isSelf(draft.teams[team].members[member]) {
                draft.teams[team].members[member] = ""
            }
            if draft.teams[team].isMine { draft.teams[team].isMine = false }
        }
        if draft.myTeamId != nil { draft.myTeamId = nil }
    }

    /// 入力から決まる立場に合わせて、参加者・自分のチームに自分を入れる／外す。
    private func placeSelf(force: Bool) {
        guard isLive else { return }
        let me = store.preferences.selfName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !me.isEmpty else { return }
        switch currentSelfRole {
        case .player:
            if isTeamTournament {
                ensureOwnTeam()
                if let index = draft.teams.firstIndex(where: { $0.id == draft.myTeamId }),
                   !draft.teams[index].members.contains(where: { store.preferences.isSelf($0) }) {
                    if let empty = draft.teams[index].members.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                        draft.teams[index].members[empty] = me
                    } else { draft.teams[index].members.insert(me, at: 0) }
                }
            } else if showsParticipantSection, force || !draft.organizer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !participants.contains(where: { store.preferences.isSelf($0) }) {
                if let index = participants.firstIndex(where: { $0.isEmpty }) { participants[index] = me }
                else { participants.append(me) }
                selfWasAdded = true
            }
        case .spectator, .reserve:
            if participants.contains(where: { store.preferences.isSelf($0) }) {
                participants.removeAll { store.preferences.isSelf($0) }
                if participants.isEmpty { participants = [""] }
            }
            selfWasAdded = false
            removeSelfFromTeams()
        case .staff:
            break
        }
    }

    private func legacySyncSelf() {
        guard showsParticipantSection else { return }
        let me = store.preferences.selfName.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = draft.organizer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !me.isEmpty, !host.isEmpty else { return }
        // 別名義で主催・参加している場合も自分として扱う。
        if store.preferences.isSelf(host) {
            if selfWasAdded { participants.removeAll { giriEditorNameKey($0) == giriEditorNameKey(me) }; selfWasAdded = false }
        } else if !participants.contains(where: { store.preferences.isSelf($0) }) {
            if let index = participants.firstIndex(where: { $0.isEmpty }) { participants[index] = me }
            else { participants.append(me) }
            selfWasAdded = true
        }
        if participants.isEmpty { participants = [""] }
    }

    private func cleanedNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(giriEditorNameKey($0)).inserted }
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

    /// 開場（生大喜利）。日付は会の日付に合わせる。
    private var openClockBinding: Binding<Date?> {
        Binding(get: { draft.opensAt }, set: { value in
            guard let value else { draft.opensAt = nil; return }
            let clock = Calendar.current.dateComponents([.hour, .minute], from: value)
            let day = draft.eventDate ?? value
            draft.opensAt = Calendar.current.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: day) ?? value
            if draft.eventDate == nil { draft.eventDate = Calendar.current.startOfDay(for: value) }
        })
    }

    private func moveDay(from old: Date?, to new: Date?) {
        guard let new else { draft.startsAt = nil; draft.endsAt = nil; draft.opensAt = nil; return }
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
        draft.opensAt = moved(draft.opensAt)
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
                if var settings = site.cycleSettings {
                    settings.leagues = settings.leagues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    site.cycleSettings = settings
                }
                try store.saveOnlineSite(site)
            } else {
                var candidate = draft
                candidate.title = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
                candidate.organizer = candidate.organizer.trimmingCharacters(in: .whitespacesAndNewlines)
                // 主催が団体かどうかは、主催団体一覧に登録した団体かどうかで決める。
                candidate.organizerIsGroup = store.groupByName(candidate.organizer) != nil
                candidate.coOrganizers = cleanedNames(candidate.coOrganizers)
                candidate.mcs = cleanedNames(candidate.mcs)
                candidate.judges = cleanedNames(candidate.judges)
                candidate.reserves = candidate.hasReserves ? cleanedNames(candidate.reserves) : []
                // 企画は生大喜利・スプシ系の通常の会だけ。
                if !candidate.eventFormat.allowsProject || candidate.meetingType != .casual { candidate.isProject = false; candidate.isKumite = false }
                candidate.kumiteMains = candidate.isKumite ? cleanedNames(candidate.kumiteMains) : candidate.kumiteMains
                candidate.siteUrl = candidate.siteUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                candidate.judging = candidate.judging.trimmingCharacters(in: .whitespacesAndNewlines)
                candidate.venueRoom = candidate.venueRoom.trimmingCharacters(in: .whitespacesAndNewlines)
                candidate.series = candidate.series.trimmingCharacters(in: .whitespacesAndNewlines)
                let venueMatch = store.venueDirectory.first { playerSearchKey($0.name) == playerSearchKey(candidate.venue) }
                candidate.venueId = venueMatch.flatMap { $0.id.hasPrefix("history:") ? nil : $0.id }
                var seen = Set<String>()
                if showsParticipantSection {
                    candidate.participants = participants.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert(giriEditorNameKey($0)).inserted }
                }
                for i in candidate.teams.indices { candidate.teams[i].members = candidate.teams[i].members.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
                // 自分の立場は選ばず、参加状況（観覧）・リザーバー・参加者・主催などの入力から決める。
                candidate.selfRole = candidate.derivedSelfRole(isSelf: store.preferences.isSelf)
                if let size = candidate.teamSize, candidate.teams.contains(where: { $0.members.count > size }) {
                    store.errorMessage = "チーム人数を超えているチームがあります。人数設定かメンバーを確認してください。"; return
                }
                if let original = event, original.onlineSiteId != nil, candidate.effectiveRounds != original.effectiveRounds {
                    candidate.siteScheduleCustomized = true
                }
                try giriEditorValidate(candidate)
                try store.saveEvent(candidate)
            }
            playLiveStairSaveFeedback()
            if let event { navigation.markEditor(event.id, unsaved: false); dismiss() } else { loaded = false; load(); onSaved?() }
        } catch { store.errorMessage = error.localizedDescription }
    }
}

/// LiveStair EventBasicEditor.priceInputRow の「¥」と数字だけの入力を、
/// 左に項目名を置く登録画面の行にしたもの。空欄は未入力（nil）、0円は無料として保存する。
struct GiriEntryFeeField: View {
    @Binding var value: Int?
    @State private var text = ""
    var body: some View {
        HStack(spacing: 8) {
            GiriEditorLabel("参加費")
            Spacer(minLength: 8)
            Text("¥").foregroundStyle(.secondary)
            TextField("未入力", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140)
                .accessibilityLabel("参加費（円）")
        }
        .onAppear { text = value.map(String.init) ?? "" }
        .onChange(of: text) { _, newValue in
            let digits = String(newValue.filter { $0.isASCII && $0.isWholeNumber }.prefix(7))
            if digits != newValue { text = digits; return }
            let number = digits.isEmpty ? nil : Int(digits)
            if number != value { value = number }
        }
        .onChange(of: value) { _, newValue in
            let current = newValue.map(String.init) ?? ""
            if current != text { text = current }
        }
    }
}

/// 会が指定するツボ上げ・感想用のハッシュタグ。「#」は表示だけで、保存時に外す。
struct GiriHashtagField: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 4) {
            GiriEditorLabel("ハッシュタグ")
            AppInfoButton(title: "ハッシュタグについて",
                          message: "会がツボ上げや感想に指定するタグです。お題/回答から投稿を作るときに末尾へ付けます。",
                          tintColor: AppSectionAccent.live)
            Spacer(minLength: 8)
            Text("#").foregroundStyle(.secondary)
            TextField("未入力", text: $text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("ハッシュタグ")
        }
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
    /// 先に出す名前（即席チームのまだ振り分けていない参加者など）。
    var priorityNames: [String] = []
    var body: some View {
        GiriPlayerSuggestionField(title: title, text: $text, organizer: preferHosts,
            showsLabel: preferHosts, textAlignment: preferHosts ? .trailing : .leading,
            priorityNames: priorityNames)
    }
}

func giriEditorNameKey(_ value: String) -> String {
    playerSearchKey(value)
}

enum GiriEditorValidationError: LocalizedError {
    case schedule(String)
    var errorDescription: String? { switch self { case .schedule(let message): return message } }
}

func giriEditorValidate(_ event: GiriEvent) throws {
    if let start = event.startsAt, let end = event.endsAt, end < start { throw GiriEditorValidationError.schedule("終了を開始より後にしてください。") }
    if let opens = event.opensAt, let start = event.startsAt, start < opens { throw GiriEditorValidationError.schedule("開場を開始より前にしてください。") }
    if let start = event.entryStart, let end = event.entryEnd, end < start { throw GiriEditorValidationError.schedule("応募締切を応募開始より後にしてください。") }
    for round in event.effectiveRounds {
        if let start = round.submissionStart, let end = round.submissionEnd, end < start { throw GiriEditorValidationError.schedule("\(round.name)の投稿締切を投稿開始より後にしてください。") }
        if let start = round.votingStart, let end = round.votingEnd, end < start { throw GiriEditorValidationError.schedule("\(round.name)の投票締切を投票開始より後にしてください。") }
    }
}

/// 0.19：募集期間の開始・締切。
enum GiriEntryEndpoint: String, Identifiable { case start, end; var id: String { rawValue } }
