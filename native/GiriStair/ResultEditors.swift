import SwiftUI
import PhotosUI

/// Date dependencies match TicketScheduleViews: only untouched derived fields move.
struct GiriRoundFields: View {
    @EnvironmentObject private var store: GiriStore
    @Binding var round: EventRound
    @Binding var automatic: Set<String>
    var tournament = true
    /// 同じ段階の回の数（2以上なら並列のお題がある）。
    var siblingCount = 1
    var onRename: ((String) -> Void)? = nil

    var body: some View {
        if tournament {
            HStack {
                GiriEditorLabel("段階")
                Spacer()
                TextField("段階名", text: $round.name).multilineTextAlignment(.trailing)
                Menu {
                    ForEach(["予選1回戦", "予選2回戦", "予選3回戦", "本戦1回戦", "本戦2回戦", "敗者復活戦", "準々決勝", "準決勝", "決勝"], id: \.self) { name in
                        Button(name) { round.name = name }
                    }
                } label: { Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.medium)) }
                    .tint(.primary)
                // 並列のお題がない段階は「--」。並列の時だけ1回目を選び、1回目で全何回かを入れる。
                Menu {
                    Button("--") { round.promptNumber = 1; round.promptCount = nil }
                    ForEach(1...max(10, round.promptNumber + 1), id: \.self) { number in
                        Button("\(number)回目") {
                            round.promptNumber = number
                            round.promptCount = number == 1 ? max(2, round.promptCount ?? 2) : nil
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(numberLabel)
                        Image(systemName: "chevron.up.chevron.down").font(.caption)
                    }.font(.body.weight(.semibold)).fixedSize()
                }.tint(.primary)
            }.onChange(of: round.name) { _, name in onRename?(name) }
            if round.promptNumber == 1, let count = round.promptCount {
                Picker(selection: Binding(get: { count }, set: { round.promptCount = $0 })) {
                    ForEach(2...max(10, count), id: \.self) { Text("全\($0)回").tag($0) }
                } label: { GiriEditorLabel("この段階のお題") }
                .pickerStyle(.menu).tint(.primary)
            }
        }
        TextField("ブロック", text: $round.block)
        GiriSchedulePeriodRow(title: "投稿", start: dateBinding("submissionStart"), end: dateBinding("submissionEnd"))
        GiriSchedulePeriodRow(title: "投票", start: dateBinding("votingStart"), end: dateBinding("votingEnd"))
    }

    private var numberLabel: String {
        if round.promptNumber == 1 && round.promptCount == nil && siblingCount <= 1 { return "--" }
        return "\(round.promptNumber)回目"
    }

    private func inheritedDate(from: Date?, to: Date?, base: Date?, fallbackDays: Int) -> Date? {
        guard let base else { return nil }
        guard let from, let to else { return Calendar.current.date(byAdding: .day, value: fallbackDays, to: base) }
        let parts = Calendar.current.dateComponents([.day, .hour, .minute, .second, .nanosecond], from: from, to: to)
        return Calendar.current.date(byAdding: parts, to: base) ?? base.addingTimeInterval(to.timeIntervalSince(from))
    }

    private func dateBinding(_ field: String) -> Binding<Date?> {
        Binding(get: {
            switch field {
            case "submissionStart": return round.submissionStart
            case "submissionEnd": return round.submissionEnd
            case "votingStart": return round.votingStart
            default: return round.votingEnd
            }
        }, set: { value in
            let previous = round
            switch field {
            case "submissionStart":
                round.submissionStart = value
                if automatic.contains("submissionEnd") || round.submissionEnd == nil {
                    round.submissionEnd = inheritedDate(from: previous.submissionStart, to: previous.submissionEnd, base: value, fallbackDays: store.preferences.submissionDays)
                    automatic.insert("submissionEnd")
                }
                if automatic.contains("votingStart") || round.votingStart == nil {
                    round.votingStart = inheritedDate(from: previous.submissionEnd, to: previous.votingStart, base: round.submissionEnd, fallbackDays: 0)
                    automatic.insert("votingStart")
                }
                if automatic.contains("votingEnd") || round.votingEnd == nil {
                    round.votingEnd = inheritedDate(from: previous.votingStart, to: previous.votingEnd, base: round.votingStart, fallbackDays: store.preferences.votingDays)
                    automatic.insert("votingEnd")
                }
            case "submissionEnd":
                automatic.remove("submissionEnd")
                round.submissionEnd = value
                if automatic.contains("votingStart") {
                    round.votingStart = inheritedDate(from: previous.submissionEnd, to: previous.votingStart, base: value, fallbackDays: 0)
                    if automatic.contains("votingEnd") {
                        round.votingEnd = inheritedDate(from: previous.votingStart, to: previous.votingEnd, base: round.votingStart, fallbackDays: store.preferences.votingDays)
                    }
                }
            case "votingStart":
                automatic.remove("votingStart")
                round.votingStart = value
                if automatic.contains("votingEnd") {
                    round.votingEnd = inheritedDate(from: previous.votingStart, to: previous.votingEnd, base: value, fallbackDays: store.preferences.votingDays)
                }
            default:
                automatic.remove("votingEnd")
                round.votingEnd = value
            }
        })
    }

}

struct GiriRoundEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    let eventID: String
    let original: EventRound
    @State private var round: EventRound
    @State private var automatic: Set<String> = []
    @State private var leave = false

    init(eventID: String, round: EventRound) {
        self.eventID = eventID
        original = round
        _round = State(initialValue: round)
    }

    private var event: GiriEvent? { store.events.first { $0.id == eventID } }
    private var changed: Bool { round != original }
    var body: some View {
        Form {
            Section {
                AppCardSectionTitle(title: "投稿・投票", systemImage: "calendar", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                GiriRoundFields(round: $round, automatic: $automatic, tournament: event?.meetingType == .tournament)
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
        }
        .appEditorFormStyle()
        .navigationTitle("日程を編集")
        .navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
        .navigationBarBackButtonHidden(changed)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if changed { Button { leave = true } label: { Image(systemName: "chevron.left") }.accessibilityLabel("戻る") }
            }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
        }
        .interactiveDismissDisabled(changed)
        .giriDiscardChangesAlert(isPresented: $leave) { dismiss() }
    }

    private func save() {
        guard var event else { return }
        do {
            var rounds = event.effectiveRounds
            if let index = rounds.firstIndex(where: { $0.id == original.id }) { rounds[index] = round }
            else { rounds.append(round) }
            if round.name != original.name {
                for index in rounds.indices where rounds[index].effectiveStageId == round.effectiveStageId { rounds[index].name = round.name }
            }
            event.rounds = rounds
            if event.onlineSiteId != nil { event.siteScheduleCustomized = true }
            try giriEditorValidate(event)
            try store.saveEvent(event)
            playLiveStairSaveFeedback()
            dismiss()
        } catch { store.errorMessage = error.localizedDescription }
    }
}

struct GiriResultEntry: View {
    @EnvironmentObject private var store: GiriStore
    @EnvironmentObject private var navigation: GiriNavigation
    @Environment(\.dismiss) private var dismiss
    let eventID: String
    var initialRoundID: String? = nil
    var initialStageID: String? = nil
    @State private var result = TournamentResult()
    @State private var placement: Int?
    @State private var standings: [TournamentStanding] = []
    @State private var selectedID = ""
    @State private var existing = Set<String>()
    @State private var loaded = false
    @State private var votingOnlyQuestion = false
    @State private var leave = false
    @State private var originalResult = TournamentResult()
    @State private var originalPlacement: Int?
    @State private var originalStandings: [TournamentStanding] = []
    @State private var answerNotes: [ThoughtNote] = []
    @State private var originalAnswerNotes: [ThoughtNote] = []
    @State private var showFinalResult = false
    @State private var nextDraft: GiriRoundDraftAction?
    @State private var resultSaved = false
    @State private var editingStageID: String?
    /// 最終結果を段階の記録から自動で入れた時（ユーザーが選び直したら自動では変えない）。
    @State private var autoFinal = false
    /// 0.19：大会名（会の中に大会を足した時など、任意で名前を付ける）。
    @State private var tournamentTitle = ""
    @State private var originalTitle = ""
    /// 0.27：「大会が複数ある」をオフにする時の確認。
    @State private var mergingTournaments = false
    /// 0.15：イベントページの大会の説明から段階の骨組みを読む。
    @State private var skeletonPhoto: PhotosPickerItem?
    @State private var readingSkeleton = false
    /// 0.25：段階ごとの組み合わせ（ブロック・トーナメント）。保存するまでこの画面で持つ。
    @State private var boards: [GiriStageBoard] = []
    @State private var originalBoards: [GiriStageBoard] = []
    @State private var boardStageID: String?


    private var event: GiriEvent? { store.events.first { $0.id == eventID } }
    private var changed: Bool { result != originalResult || placement != originalPlacement || standings != originalStandings || answerNotes != originalAnswerNotes || tournamentTitle != originalTitle || boards != originalBoards }
    private var stageIndex: Int? { result.stages.firstIndex { $0.id == selectedID } }

    var body: some View {
        boardHandlers(Form {
            if let event {
                eventSection(event)
                if event.isSelfPlayer {
                    stageListSection(event)
                    finalSection(event)
                } else {
                    // 主催・観覧などで出ていない大会は、上位成績だけを残す（戦績には数えない）。
                    Section {
                        Text("この大会には「\(event.selfRole.shortTitle(tournament: true))」として参加しているため、自分の結果は記録しません。優勝・準優勝などは下に残せます。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
                }
                standingSections(event)
                // 0.27：「この会の中の大会」の欄の代わりに、いちばん下で大会が複数あるかを選ぶ。
                if event.eventFormat == .live { multipleTournamentsSection(event) }
            } else {
                Text("この会は削除されています。").foregroundStyle(.secondary)
            }
        })
        .appEditorFormStyle()
        .navigationTitle("結果を記録")
        .navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
        .navigationBarBackButtonHidden(changed)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if changed { Button { leave = true } label: { Image(systemName: "chevron.left") }.accessibilityLabel("戻る") }
            }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: requestSave).disabled(event == nil) }
        }
        .onAppear { if !loaded { load() } }
        .onChange(of: changed) { _, value in navigation.markResultEntry(eventID, unsaved: value) }
        .onChange(of: result.stages) { _, _ in applyAutomaticResults() }
        .interactiveDismissDisabled(changed)
        .navigationDestination(item: $editingStageID) { id in
            if let event {
                GiriStageEditor(event: event, stage: stageBinding(id), answerNotes: $answerNotes,
                                team: result.format != .individual,
                                namePriority: stageNamePriority(id, event: event),
                                onDelete: {
                                    existing.remove(id)
                                    result.stages.removeAll { $0.id == id }
                                    editingStageID = nil
                                })
            }
        }
        .alert("以後の投稿・投票", isPresented: $votingOnlyQuestion) {
            Button("そのまま") { save(votingOnly: false) }
            Button("投票だけにする") { save(votingOnly: true) }
            Button("キャンセル", role: .cancel) {}
        } message: { Text("以後の投稿を止め、必要な投票の日程と通知を残しますか？") }
        .giriDiscardChangesAlert(isPresented: $leave) {
            navigation.markResultEntry(eventID, unsaved: false)
            dismiss()
        }
        .sheet(item: $nextDraft, onDismiss: { if resultSaved { dismiss() } }) { action in
            NavigationStack { GiriNextRoundEditor(eventID: eventID, sameStage: action == .sameStage) }
        }
    }

    /// 0.25：組み合わせの編集画面と、組み合わせから自分の記録を入れる処理（本体の修飾子を短くするため分ける）。
    private func boardHandlers<Content: View>(_ content: Content) -> some View {
        content
            .navigationDestination(item: $boardStageID) { id in boardEditor(id) }
            .onChange(of: boards) { _, _ in applyBoardsToStages() }
    }

    @ViewBuilder private func boardEditor(_ stageID: String) -> some View {
        let wide = result.stages.filter { $0.roundId == nil }
        if let event, let index = wide.firstIndex(where: { $0.id == stageID }) {
            let stage = wide[index]
            let previousBoard = index > 0 ? boards.first(where: { $0.id == wide[index - 1].id }) : nil
            let previous = previousBoard.map(giriBoardWinners) ?? []
            let participants = event.participants.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let fromPrevious = index > 0 && !previous.isEmpty
            GiriStageBoardEditor(
                board: Binding(get: { boards.first { $0.id == stageID } ?? GiriStageBoard(id: stageID) }, set: { value in
                    if let position = boards.firstIndex(where: { $0.id == stageID }) { boards[position] = value } else { boards.append(value) }
                }),
                stage: stage,
                sourceNames: fromPrevious ? previous : participants,
                sourceTitle: fromPrevious ? "「\(wide[index - 1].name)」の勝ち上がり" : "参加者",
                knockout: event.knockout,
                nextStageName: index + 1 < wide.count ? wide[index + 1].name : giriEditorNextStage(stage.name, live: !event.eventFormat.hasOnlineRounds),
                onAdvance: { winners in advanceBoard(from: stageID, winners: winners, event: event) })
        }
    }

    /// 勝ち上がりを次の段階の組み合わせにする（次の段階がなければ足す）。
    private func advanceBoard(from stageID: String, winners: [String], event: GiriEvent) {
        let wide = result.stages.filter { $0.roundId == nil }
        guard let index = wide.firstIndex(where: { $0.id == stageID }) else { return }
        let next: ResultStage
        if index + 1 < wide.count {
            next = wide[index + 1]
        } else {
            var stage = ResultStage()
            stage.name = giriEditorNextStage(wide[index].name, live: !event.eventFormat.hasOnlineRounds)
            stage.judging = wide[index].judging
            stage.lineup = wide[index].lineup
            stage.promptCount = wide[index].promptCount
            if !event.eventFormat.hasOnlineRounds { stage.laps = giriNormalizedLaps(stage, lapCount: 1) }
            result.stages.append(stage)
            existing.insert(stage.id)
            next = stage
        }
        let board = GiriStageBoard(id: next.id, blocks: giriBoardBlocks(members: winners, size: giriBoardBlockSize(next, knockout: event.knockout)))
        if let position = boards.firstIndex(where: { $0.id == next.id }) { boards[position] = board } else { boards.append(board) }
    }

    /// 組み合わせに自分がいる段階は、組・相手・通過／敗退を組み合わせから入れる。
    private func applyBoardsToStages() {
        for board in boards {
            guard let index = result.stages.firstIndex(where: { $0.id == board.id }) else { continue }
            let applied = giriApplyingBoard(board, to: result.stages[index], isSelf: store.preferences.isSelf)
            if applied != result.stages[index] { result.stages[index] = applied }
        }
    }

    /// 組み合わせの行（段階の下）。
    private func boardRow(_ stage: ResultStage) -> some View {
        let board = boards.first { $0.id == stage.id }
        let blocks = board?.blocks.count ?? 0
        let winners = board.map(giriBoardWinners)?.count ?? 0
        return Button { boardStageID = stage.id } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2").foregroundStyle(accentActionColor).frame(width: 22)
                Text(blocks == 0 ? "組み合わせを作る" : "組み合わせ \(blocks)組・勝ち上がり\(winners)人").font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.leading, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 登録したトーナメント表（生大喜利・個人戦のトーナメントは参加者の並び）。
    private func bracket(_ event: GiriEvent) -> [String] {
        guard event.knockout, event.tournamentFormat == .individual else { return [] }
        return event.participants.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// 対戦相手の候補：トーナメント表があれば、その回戦で当たりうる隣の山を先に出す。
    private func stageNamePriority(_ stageID: String, event: GiriEvent) -> [String] {
        let others = otherPlayerNames(event)
        let wide = result.stages.filter { $0.roundId == nil }
        let names = bracket(event)
        guard !names.isEmpty, let index = wide.firstIndex(where: { $0.id == stageID }) else { return others }
        return giriBracketOpponents(names, round: index + 1, isSelf: store.preferences.isSelf) + others
    }

    /// トーナメント表から最初の回戦を作る（相手も入れる）。勝つと、次の回戦が表に沿って自動で足される。
    private func addBracketStages(_ event: GiriEvent) {
        let names = bracket(event)
        guard let first = giriBracketStageNames(names.count).first else { return }
        var stage = ResultStage()
        stage.name = first
        stage.lineup = "タイマン"
        stage.judging = event.judging
        stage.opponents = giriBracketOpponents(names, round: 1, isSelf: store.preferences.isSelf)
        stage.laps = giriNormalizedLaps(stage, lapCount: 1)
        result.stages.append(stage)
        existing.insert(stage.id)
    }

    /// 0.15：段階がまだない時だけ、大会の仕組みの画像から骨組みを作る。
    private func skeletonReadRow(_ event: GiriEvent) -> some View {
        PhotosPicker(selection: $skeletonPhoto, matching: .images, photoLibrary: .shared()) {
            VStack(alignment: .leading, spacing: 3) {
                Label(readingSkeleton ? "読み取り中" : "大会の仕組みを画像から読み取る", systemImage: "text.viewfinder")
                Text("イベントページの「予選：5人1組・お題3問」などから、段階の骨組みだけを作ります。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(readingSkeleton)
        .tint(accentActionColor)
        .onChange(of: skeletonPhoto) { _, item in readSkeleton(item, event: event) }
    }

    private func readSkeleton(_ item: PhotosPickerItem?, event: GiriEvent) {
        guard let item else { return }
        readingSkeleton = true
        Task {
            defer { readingSkeleton = false; skeletonPhoto = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw GiriParticipantReadError.unreadable }
                let stages = giriTournamentSkeleton(lines: try await GiriParticipantOCR.recognizeLines(data))
                guard !stages.isEmpty else {
                    store.errorMessage = "大会の段階（予選・決勝など）を読み取れませんでした。大会の仕組みが書いてある画面を選んでください。"
                    return
                }
                for var stage in stages {
                    if stage.judging.isEmpty { stage.judging = event.judging }
                    if stage.lineup.isEmpty && event.knockout { stage.lineup = "タイマン" }
                    if !event.eventFormat.hasOnlineRounds { stage.laps = giriNormalizedLaps(stage, lapCount: 1) }
                    result.stages.append(stage)
                    existing.insert(stage.id)
                }
                playLiveStairSaveFeedback()
            } catch { store.errorMessage = error.localizedDescription }
        }
    }

    /// 段階の記録から自動で入れる：トーナメント表で勝った時の次の回戦、決勝・敗退からの最終結果。
    private func applyAutomaticResults() {
        // 開いた直後（読み込んだだけ）では何も変えない。
        guard let event, event.isSelfPlayer, loaded, result.stages != originalResult.stages else { return }
        if event.eventFormat.hasOnlineRounds { syncSingleRoundStages() }
        let names = bracket(event)
        if names.count >= 2, var next = giriNextBracketStage(result.stages, bracket: names, isSelf: store.preferences.isSelf) {
            if !event.eventFormat.hasOnlineRounds { next.laps = giriNormalizedLaps(next, lapCount: 1) }
            result.stages.append(next)
            existing.insert(next.id)
        }
        let current = finalChoice.wrappedValue
        guard current == .unrecorded || autoFinal, let suggestion = giriSuggestedFinalChoice(result.stages), suggestion != current else { return }
        finalChoice.wrappedValue = suggestion
        autoFinal = true
    }

    /// 最終結果を手で選んだ時は、以後は自動で変えない。
    private var manualFinalChoice: Binding<GiriFinalResultChoice> {
        Binding(get: { finalChoice.wrappedValue }, set: { value in
            autoFinal = false
            finalChoice.wrappedValue = value
        })
    }

    /// 0.23：ルールの段階（名前・種類・形式・審査方法・お題数・通過枠）を入れる。
    private func applyRuleStages(_ rule: GiriRule) {
        let live = event.map { !$0.eventFormat.hasOnlineRounds } ?? true
        for var stage in giriRuleStageResults(rule) {
            if live { stage.laps = giriNormalizedLaps(stage, lapCount: 1) }
            result.stages.append(stage)
            existing.insert(stage.id)
        }
    }

    /// 前回の同じ大会（同じ主催・同じ名前）の段階構成を使う。
    private func applyTemplate(from source: GiriEvent) {
        for stage in giriStageTemplate(from: source) {
            result.stages.append(stage)
            existing.insert(stage.id)
        }
    }

    /// どの大会の結果かを示し、一覧タブの詳細へ移れるようにする（結果入力は戦績タブに残る）。
    private func eventSection(_ event: GiriEvent) -> some View {
        Section {
            AppCardSectionTitle(title: "大会", systemImage: "flag.checkered", accentColor: AppSectionAccent.live)
                .listRowSeparator(.hidden)
            Button { navigation.openEventDetail(eventID) } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        Text(eventSubtitle(event)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text("詳細").font(.subheadline.weight(.semibold)).foregroundStyle(accentActionColor)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(event.title)の詳細を開く")
        }.appSectionCardStyle(accentColor: AppSectionAccent.live)
    }

    /// 0.27：同じ会で大会を2つ以上やった時。オンにすると「大会名1」「大会名2」に分かれ、
    /// ほかの大会の結果へ移ったり、大会を足したりできる。オフにするとこの大会だけ残す。
    private func multipleTournamentsSection(_ event: GiriEvent) -> some View {
        let group = store.tournamentGroup(of: event.id)
        let parent = event.parentEventId.flatMap { id in store.events.first { $0.id == id } }
        let others = group.filter { $0.id != event.id }
        return Section {
            AppCardSectionTitle(title: "大会の数", systemImage: "trophy", accentColor: AppSectionAccent.ticket,
                                infoTitle: "大会が複数ある時", infoMessage: "同じ会で大会を2つ以上やった時にオンにします。大会1・大会2…に分かれ、それぞれの結果を残せます。")
                .listRowSeparator(.hidden)
            Toggle(isOn: Binding(get: { group.count > 1 }, set: { on in
                if on { splitTournament(event) } else { mergingTournaments = true }
            })) { GiriEditorLabel("大会が複数ある") }
                .tint(AppSectionAccent.ticket)
                .giriDeleteAlert("ほかの大会を削除しますか？", isPresented: $mergingTournaments,
                                 message: "「\(others.map(\.title).joined(separator: "」「"))」を削除して、この大会だけにします。設定の「最近削除した会」に30日間残ります。") {
                    mergeTournaments(event)
                }
            if group.count > 1 {
                if let parent, parent.meetingType != .tournament {
                    HStack { GiriEditorLabel("元の会"); Spacer(); Text(parent.title).font(.subheadline) }
                }
                ForEach(Array(group.enumerated()), id: \.element.id) { offset, other in
                    if other.id == event.id {
                        HStack(spacing: 12) {
                            GiriEditorLabel("大会\(offset + 1)")
                            TextField("大会名", text: $tournamentTitle).multilineTextAlignment(.trailing)
                        }
                    } else {
                        NavigationLink {
                            GiriResultEntry(eventID: other.id)
                        } label: {
                            HStack(spacing: 12) {
                                GiriEditorLabel("大会\(offset + 1)")
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(other.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(other.finalResultTitle ?? "結果未入力").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Button {
                    store.run {
                        try store.addTournament(inside: event.parentEventId ?? event.id)
                        playLiveStairSaveFeedback()
                    }
                } label: { Label("大会を追加", systemImage: "plus.circle") }
                .tint(accentActionColor)
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
    }

    private func splitTournament(_ event: GiriEvent) {
        store.run {
            // 名前を変えるのは、この画面の大会が元の大会の時だけ（「大会名1」にする）。
            if let renamed = try store.splitTournament(event.id) {
                if tournamentTitle == originalTitle { tournamentTitle = renamed }
                originalTitle = renamed
            }
            playLiveStairSaveFeedback()
        }
    }

    private func mergeTournaments(_ event: GiriEvent) {
        store.run {
            if let renamed = try store.mergeTournamentGroup(keeping: event.id) {
                if tournamentTitle == originalTitle { tournamentTitle = renamed }
                originalTitle = renamed
            }
            playLiveStairDeleteFeedback()
        }
    }

    private func eventSubtitle(_ event: GiriEvent) -> String {
        var values = [event.eventFormat.title, giriTournamentFormatText(event)]
        if let date = GiriEventPresentation.date(event) { values.append(GiriDateText.day(date)) }
        return values.joined(separator: "・")
    }

    /// この大会で入力済みの名前（自分以外）。上位成績・対戦相手の候補に先に出す。
    private func otherPlayerNames(_ event: GiriEvent) -> [String] {
        event.enteredPlayerNames.filter { !store.preferences.isSelf($0) }
    }

    /// 段階（予選・本戦…）を上から並べ、ネットの各回はその段階の下に出す。
    private func stageListSection(_ event: GiriEvent) -> some View {
        let wide = result.stages.filter { $0.roundId == nil }
        let rounds = result.stages.filter { $0.roundId != nil }
        return Section {
            AppCardSectionTitle(title: "段階の結果", systemImage: "list.number", accentColor: AppSectionAccent.ticket,
                                infoTitle: "段階の結果について",
                                infoMessage: "予選・本戦などの段階ごとに、形式・審査方法と通過／敗退・順位を残します。周ごとの点を入れると合計が出て、決勝の結果や敗退は最終結果にも自動で入ります。")
                .listRowSeparator(.hidden)
            if wide.isEmpty && rounds.isEmpty {
                Text("段階がまだありません").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(wide) { stage in
                // 0.17：お題が1つだけの段階（ネット）は、段階と回を1行にまとめて回の入力を開く。
                let single = singleRound(of: stage, in: rounds)
                Button { editingStageID = single?.id ?? stage.id } label: { stageRow(single.map { mergedRow(stage, round: $0) } ?? stage, nested: false) }
                    .buttonStyle(.plain)
                // 同じ段階を違うブロックで何周かした時は、周ごとの結果を同じ枠の中に並べる。
                if stage.laps.count > 1 {
                    ForEach(Array(stage.laps.enumerated()), id: \.element.id) { offset, lap in
                        Button { editingStageID = stage.id } label: { lapRow(lap, number: offset + 1) }
                            .buttonStyle(.plain)
                    }
                }
                if single == nil {
                    ForEach(rounds.filter { $0.stageId != nil && $0.stageId == stage.stageId }) { round in
                        Button { editingStageID = round.id } label: { stageRow(round, nested: true) }
                            .buttonStyle(.plain)
                    }
                }
                // 0.25：生大喜利・スプシ系の段階は、組み合わせ（ブロック・トーナメント）を作れる。
                if event.eventFormat != .onlineLong && event.eventFormat != .onlineShort { boardRow(stage) }
            }
            if boards.contains(where: { !$0.blocks.isEmpty }) {
                NavigationLink {
                    GiriBoardBracketView(event: previewEvent(event))
                } label: { Label("トーナメント表で見る", systemImage: "rectangle.split.3x1") }
                .tint(accentActionColor)
            }
            // 段階に結び付かない旧データの回
            ForEach(rounds.filter { round in round.stageId == nil || !wide.contains { $0.stageId == round.stageId } }) { round in
                Button { editingStageID = round.id } label: { stageRow(round, nested: true) }
                    .buttonStyle(.plain)
            }
            if wide.isEmpty && rounds.isEmpty { skeletonReadRow(event) }
            // 0.23：大会に選んだルールの段階を入れる。
            if wide.isEmpty && rounds.isEmpty, let rule = event.ruleID.flatMap({ store.rule($0) }), !rule.stages.isEmpty {
                Button { applyRuleStages(rule) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("ルールの段階を入れる", systemImage: "list.bullet.rectangle")
                        Text(rule.displayName + "：" + rule.stages.map { $0.name.isEmpty ? ($0.stageKind?.title ?? "段階") : $0.name }.joined(separator: "→"))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .tint(accentActionColor)
            }
            if wide.isEmpty && rounds.isEmpty, let source = giriStageTemplateSource(for: event, in: store.events) {
                Button { applyTemplate(from: source) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("前回の段階を使う", systemImage: "square.on.square")
                        Text(templateCaption(source)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(accentActionColor)
            }
            if bracket(event).count >= 2 {
                bracketRow(event, hasStages: !wide.isEmpty)
            }
            Button {
                var stage = ResultStage()
                // 予選の後は本戦、本戦の後は生大喜利なら決勝・ネット大喜利なら準々決勝（名前は変えられる）。
                stage.name = wide.isEmpty ? "予選" : giriEditorNextStage(wide.last?.name ?? "", live: !event.eventFormat.hasOnlineRounds)
                // 基本情報の審査方法・対戦形式を初期値にする（段階ごとに変えられる）。前の段階の形式・お題数を引き継ぐ。
                stage.judging = wide.last?.judging.isEmpty == false ? (wide.last?.judging ?? event.judging) : event.judging
                stage.lineup = wide.last?.lineup ?? (event.knockout ? "タイマン" : "")
                if event.knockout && stage.lineup.isEmpty { stage.lineup = "タイマン" }
                stage.promptCount = wide.last?.promptCount
                if !event.eventFormat.hasOnlineRounds { stage.laps = giriNormalizedLaps(stage, lapCount: 1) }
                result.stages.append(stage)
                existing.insert(stage.id)
                editingStageID = stage.id
            } label: { Label("段階を追加", systemImage: "plus.circle") }
            .tint(accentActionColor)
        }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
    }

    /// 保存前の組み合わせ・段階で表示する会。
    private func previewEvent(_ event: GiriEvent) -> GiriEvent {
        var value = event
        value.stageBoards = boards
        var preview = result
        preview.stages = result.stages
        value.tournamentResult = preview
        return value
    }

    /// 段階の回が1つだけの時、その回の記録。
    private func singleRound(of stage: ResultStage, in rounds: [ResultStage]) -> ResultStage? {
        guard let stageID = stage.stageId else { return nil }
        let matches = rounds.filter { $0.stageId == stageID }
        return matches.count == 1 ? matches.first : nil
    }

    /// 1行にまとめた時の表示：名前・形式は段階、結果は回（なければ段階）。
    private func mergedRow(_ stage: ResultStage, round: ResultStage) -> ResultStage {
        var value = round
        value.name = stage.name
        if round.outcome == .unrecorded { value.outcome = stage.outcome }
        if round.placement == nil { value.placement = stage.placement }
        value.lineup = stage.lineup
        value.judging = stage.judging
        value.group = stage.group
        return value
    }

    /// お題が1つだけの段階は、回の通過・敗退と順位を段階の記録にも入れる（最終結果・まとめは段階で数える）。
    private func syncSingleRoundStages() {
        let rounds = result.stages.filter { $0.roundId != nil }
        for index in result.stages.indices where result.stages[index].roundId == nil {
            guard let round = singleRound(of: result.stages[index], in: rounds) else { continue }
            if round.outcome != .unrecorded && result.stages[index].outcome != round.outcome { result.stages[index].outcome = round.outcome }
            if let placement = round.placement, result.stages[index].placement != placement { result.stages[index].placement = placement }
        }
    }

    private func templateCaption(_ source: GiriEvent) -> String {
        let names = source.stageResults.map(\.name).filter { !$0.isEmpty }.joined(separator: "→")
        return [source.title, names].filter { !$0.isEmpty }.joined(separator: "：")
    }

    /// トーナメント表（登録の参加者の並び）。段階がなければ回戦を作れる。
    @ViewBuilder private func bracketRow(_ event: GiriEvent, hasStages: Bool) -> some View {
        let names = bracket(event)
        if hasStages {
            HStack {
                Label("トーナメント表", systemImage: "list.number").foregroundStyle(.secondary)
                Spacer()
                Text(bracketCaption(names)).font(.subheadline).foregroundStyle(.secondary)
            }
        } else {
            Button { addBracketStages(event) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Label("トーナメント表から回戦を作る", systemImage: "list.number")
                    Text(bracketCaption(names) + "・" + giriBracketStageNames(names.count).joined(separator: "→"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(accentActionColor)
        }
    }

    private func bracketCaption(_ names: [String]) -> String {
        guard let position = names.firstIndex(where: store.preferences.isSelf) else { return "\(names.count)人" }
        return "\(names.count)人・自分は\(position + 1)番目"
    }

    private func stageRow(_ stage: ResultStage, nested: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(stage.name.isEmpty ? "段階名未設定" : stage.name)
                    .font(nested ? .subheadline.weight(.semibold) : .body.weight(.semibold))
                    .foregroundStyle(.primary)
                let format = [stage.laps.count > 1 ? "" : stage.group, stage.lineup, stage.judging,
                              stage.promptCount.map { "お題\($0)題" + (stage.votesPerPrompt ? "（お題ごとに投票）" : "") } ?? ""].filter { !$0.isEmpty }
                if !format.isEmpty {
                    Text(format.joined(separator: "・")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(.leading, nested ? 16 : 0)
            Spacer(minLength: 8)
            Text(stageResultLabel(stage))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(stage.hasRecord ? AppSectionAccent.ticket : Color.secondary)
                .multilineTextAlignment(.trailing)
            Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    /// 周ごとの小結果（ブロック・相手・点）。通過・敗退は段階の総合結果で決める。
    private func lapRow(_ lap: StageLap, number: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text([String(number) + "周目", lap.group].filter { !$0.isEmpty }.joined(separator: "・"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                if !lap.opponents.isEmpty {
                    Text(lap.opponents.joined(separator: "・")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.leading, 16)
            Spacer(minLength: 8)
            let parts = [giriLapTotal(lap).map { giriScoreText($0) + "点" }, giriLapPlacement(lap).map { "\($0)位" }].compactMap { $0 }
            Text(parts.isEmpty ? "未入力" : parts.joined(separator: "・"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(parts.isEmpty ? Color.secondary : AppSectionAccent.ticket)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }

    private func stageResultLabel(_ stage: ResultStage) -> String {
        let text = giriStageResultText(stage)
        let name = stage.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let trimmed = text.hasPrefix(name) ? String(text.dropFirst(name.count)).trimmingCharacters(in: .whitespaces) : text
            return trimmed.isEmpty ? text : trimmed
        }
        if let value = stage.pointsPerVoter { return "1人あたり " + giriScoreText(value) }
        return "未入力"
    }

    private func stageBinding(_ id: String) -> Binding<ResultStage> {
        Binding(get: { result.stages.first { $0.id == id } ?? ResultStage(id: id) }, set: { value in
            if let index = result.stages.firstIndex(where: { $0.id == id }) { result.stages[index] = value }
        })
    }

    private var finalChoice: Binding<GiriFinalResultChoice> {
        Binding(get: {
            GiriFinalResultChoice.current(outcome: result.outcome == .advanced ? .unrecorded : result.outcome, placement: placement, bestOf: result.bestOf, finalist: result.finalist)
        }, set: { choice in
            result.outcome = choice.outcome
            result.bestOf = choice.bestOf
            result.finalist = choice == .finalist
            if choice != .finalist { result.finalEntrants = nil }
            switch choice {
            case .third: placement = 3
            case .placed, .finalist: if placement == 3 { placement = nil }
            default: placement = nil
            }
        })
    }

    /// 戦績に数える大会全体の結果。敗退は最後に敗退した段階の名前から表示する。
    private func finalSection(_ event: GiriEvent) -> some View {
        Section {
            AppCardSectionTitle(title: "最終結果", systemImage: "trophy", accentColor: AppSectionAccent.ticket,
                                infoTitle: "最終結果について",
                                infoMessage: "優勝・準優勝・3位・ベスト4を分けて数えます。決勝で順位がはっきりしない時は「決勝進出」（順位は分かれば）。敗退は段階の名前から「予選敗退」のように表示します。")
                .listRowSeparator(.hidden)
            Picker(selection: manualFinalChoice) {
                ForEach(GiriFinalResultChoice.allCases) { Text($0.title).tag($0) }
            } label: { GiriEditorLabel(autoFinal ? "最終結果（段階から自動）" : "最終結果") }
            .pickerStyle(.menu).tint(.primary)
            // 段階の記録（準々決勝で敗退→ベスト8 など）から候補を出す。押した時だけ反映する。
            if let suggestion = giriSuggestedFinalChoice(result.stages),
               [.unrecorded, .eliminated].contains(finalChoice.wrappedValue), suggestion != finalChoice.wrappedValue {
                Button { manualFinalChoice.wrappedValue = suggestion } label: {
                    Label("段階の記録から「\(suggestion.title)」にする", systemImage: "wand.and.stars")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .tint(accentActionColor)
            }
            if finalChoice.wrappedValue == .finalist {
                GiriIntegerField(title: "決勝の人数（任意）", value: $result.finalEntrants, suffix: "人")
                GiriIntegerField(title: "決勝の順位（任意）", value: $placement, suffix: "位")
            }
            if finalChoice.wrappedValue == .eliminated {
                HStack {
                    GiriEditorLabel("表示")
                    Spacer()
                    Text(eliminationPreview).font(.body.weight(.semibold))
                }
            }
            if finalChoice.wrappedValue == .placed {
                GiriIntegerField(title: "順位（任意）", value: $placement, suffix: "位")
            }
            if result.format != .individual {
                TextField("自分のチーム名", text: $result.teamName)
                GiriNamesField(title: "チームメンバー", names: $result.members,
                               priorityNames: event.teams.first(where: { $0.id == event.myTeamId || $0.isMine })?.members ?? [])
            }
            TextField("結果のメモ", text: $result.memo, axis: .vertical).lineLimit(3...10)
        }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
    }

    private var eliminationPreview: String {
        var copy = event ?? GiriEvent()
        copy.tournamentResult = result
        return copy.eliminationTitle
    }

    /// 大会の上位成績。登録の参加形式に合わせ、個人戦はプレイヤー名、チーム戦はチーム名とメンバー。
    /// 名前は、この大会で入力済みの参加者・チームから先に選べる。
    @ViewBuilder private func standingSections(_ event: GiriEvent) -> some View {
        let isTeam = result.format != .individual
        ForEach(standings.indices, id: \.self) { index in
            Section {
                HStack {
                    AppCardSectionTitle(title: "大会の上位成績", systemImage: "medal", accentColor: AppSectionAccent.ticket)
                    Button(role: .destructive) { standings.remove(at: index) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }.listRowSeparator(.hidden)
                Stepper("\(standings[index].placement)位", value: $standings[index].placement, in: 1...9999)
                if isTeam || !standings[index].teamName.isEmpty {
                    GiriTeamNameField(text: standingTeamBinding(index, event: event),
                                      suggestions: teamNameSuggestions(event),
                                      showsSuggestionsWhenEmpty: !event.teams.isEmpty)
                }
                GiriNamesField(title: isTeam ? "メンバー" : "プレイヤー名", names: $standings[index].playerNames,
                               priorityNames: standingNamePriority(index, event: event))
                TextField("メモ", text: $standings[index].memo, axis: .vertical).lineLimit(1...5)
            }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
        }
        Section {
            Button {
                var standing = TournamentStanding()
                standing.placement = (standings.map(\.placement).max() ?? 0) + 1
                // 個人戦は名前の欄を1つ開いておく（チーム戦はチーム名を選ぶとメンバーが入る）。
                standing.playerNames = isTeam ? [] : [""]
                standings.append(standing)
            } label: { Label(isTeam ? "優勝・準優勝などのチームを追加" : "優勝・準優勝などを追加", systemImage: "plus.circle") }
        }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
    }

    /// この大会のチームを先に、ほかの大会で入れたチーム名を後に出す。
    private func teamNameSuggestions(_ event: GiriEvent) -> [String] {
        var seen = Set<String>()
        let own = event.teams.map(\.name)
        let others = store.events.filter { $0.id != event.id }.flatMap { $0.teams.map(\.name) + $0.standings.map(\.teamName) }
        return (own + others).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(playerSearchKey($0)).inserted }
    }

    /// 登録したチームを選んだら、空のメンバー欄にそのチームのメンバーを入れる（入力済みの名前は消さない）。
    private func standingTeamBinding(_ index: Int, event: GiriEvent) -> Binding<String> {
        Binding(get: { standings.indices.contains(index) ? standings[index].teamName : "" }, set: { value in
            guard standings.indices.contains(index) else { return }
            standings[index].teamName = value
            let key = playerSearchKey(value)
            guard !key.isEmpty,
                  standings[index].playerNames.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  let team = event.teams.first(where: { playerSearchKey($0.name) == key }) else { return }
            let members = team.members.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !members.isEmpty { standings[index].playerNames = members }
        })
    }

    /// 名前の候補：選んだチームのメンバー → この大会のほかの名前。ほかの順位に入れた名前は後回し。
    private func standingNamePriority(_ index: Int, event: GiriEvent) -> [String] {
        guard standings.indices.contains(index) else { return [] }
        let teamKey = playerSearchKey(standings[index].teamName)
        let teamMembers = teamKey.isEmpty ? [] : (event.teams.first { playerSearchKey($0.name) == teamKey }?.members ?? [])
        let usedElsewhere = Set(standings.enumerated().filter { $0.offset != index }.flatMap { $0.element.playerNames }.map(playerSearchKey))
        return teamMembers + event.enteredPlayerNames.filter { !usedElsewhere.contains(playerSearchKey($0)) }
    }

    private func load() {
        guard let event else { return }
        result = event.tournamentResult ?? TournamentResult()
        // 登録の参加形式に合わせる。チーム名・メンバーが入った旧データだけはチームの入力を残す。
        let legacyTeam = event.tournamentResult.map { $0.format != .individual && (!$0.members.isEmpty || !$0.teamName.isEmpty) } ?? false
        if event.tournamentFormat != .individual || !legacyTeam {
            result.format = event.tournamentFormat
        }
        if result.memo.isEmpty { result.memo = event.resultText }
        if result.members.isEmpty, let mine = event.teams.first(where: { $0.id == event.myTeamId || $0.isMine }) {
            result.members = mine.members
            result.teamName = mine.name
        }
        placement = event.placement
        standings = event.standings
        boards = event.stageBoards
        originalBoards = boards
        tournamentTitle = event.title
        originalTitle = event.title
        existing = Set(result.stages.map(\.id))
        var seen = Set<String>()
        for round in event.effectiveRounds {
            if seen.insert(round.effectiveStageId).inserted,
               !result.stages.contains(where: { $0.roundId == nil && $0.stageId == round.effectiveStageId }) {
                var stage = ResultStage()
                stage.name = round.name
                stage.stageId = round.effectiveStageId
                result.stages.append(stage)
            }
            if !result.stages.contains(where: { $0.roundId == round.id }) {
                var prompt = ResultStage()
                prompt.name = giriRoundNumberText(round, in: event.effectiveRounds).map { "\(round.name) \($0)" } ?? round.name
                prompt.roundId = round.id
                prompt.stageId = round.effectiveStageId
                result.stages.append(prompt)
            }
        }
        selectedID = result.stages.first(where: { $0.id == initialStageID })?.id ?? result.stages.first(where: { $0.roundId == initialRoundID && initialRoundID != nil })?.id ?? result.stages.first?.id ?? ""
        // 詳細の「この回の結果」などから開いた時は、その段階・回の入力をそのまま開く。
        if (initialRoundID != nil || initialStageID != nil) && !selectedID.isEmpty {
            let target = selectedID
            DispatchQueue.main.async { editingStageID = target }
        }
        answerNotes = store.notes.filter { $0.eventId == eventID && $0.kind == .answers && !$0.isOthersAnswer }.map { note in
            var copy = note
            copy.answerRecords = note.effectiveAnswerRecords
            copy.usesAnswerRecords = true
            return copy
        }
        originalAnswerNotes = answerNotes
        showFinalResult = !event.eventFormat.hasOnlineRounds || event.hasFinalResult
        // 0.14：生大喜利の段階は周ごとの記録で入れる（以前の版の1周分を1周目にする）。開いただけでは変更にしない。
        if !event.eventFormat.hasOnlineRounds {
            for index in result.stages.indices where result.stages[index].roundId == nil && result.stages[index].laps.isEmpty {
                result.stages[index].laps = giriNormalizedLaps(result.stages[index], lapCount: 1)
            }
        }
        autoFinal = false
        originalResult = result
        originalPlacement = placement
        originalStandings = standings
        loaded = true
    }

    private func requestSave() {
        guard let event else { return }
        let wasEliminated = event.tournamentResult?.outcome == .eliminated
        let oldStageIDs = Set((event.tournamentResult?.stages ?? []).filter { $0.outcome == .eliminated }.map(\.id))
        let newElimination = result.outcome == .eliminated && !wasEliminated || result.stages.contains { $0.outcome == .eliminated && !oldStageIDs.contains($0.id) }
        if event.eventFormat.hasOnlineRounds && newElimination && !event.effectiveRounds.isEmpty { votingOnlyQuestion = true }
        else { save(votingOnly: false) }
    }

    private func save(votingOnly: Bool) {
        guard var event else { return }
        do {
            if let placement, placement < 1 { throw GiriEditorValidationError.schedule("順位は1以上で入力してください。") }
            for stage in result.stages {
                if [stage.placement, stage.teamPlacement, stage.individualPlacement].compactMap({ $0 }).contains(where: { $0 < 1 }) || (stage.voterCount ?? 0) < 0 || (stage.points ?? 0) < 0 || !(stage.points ?? 0).isFinite || stage.maxPointsPerVoter < 1 {
                    throw GiriEditorValidationError.schedule("順位・得点・投票人数を確認してください。")
                }
            }
            var saved = result
            saved.stages = result.stages.filter { $0.hasRecord || existing.contains($0.id) }
            if result.outcome == .champion { event.placement = 1 }
            else if result.outcome == .runnerUp { event.placement = 2 }
            else if result.outcome == .eliminated || result.outcome == .advanced { event.placement = nil }
            else { event.placement = placement }
            event.tournamentResult = saved
            // 0.25：残す段階の組み合わせだけ保存する（組のない組み合わせは書かない）。
            let keptStages = Set(saved.stages.map(\.id))
            event.stageBoards = boards.filter { keptStages.contains($0.id) && !$0.blocks.isEmpty }
            event.resultText = result.memo
            let title = tournamentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { event.title = title }
            saved.members = cleanNames(saved.members)
            event.tournamentResult = saved
            event.standings = standings.map { standing in var copy = standing; copy.playerNames = cleanNames(copy.playerNames); return copy }
            if votingOnly {
                var rounds = event.effectiveRounds
                let eliminatedStages = Set(result.stages.filter { $0.roundId == nil && $0.outcome == .eliminated }.compactMap(\.stageId))
                let eliminatedRounds = Set(result.stages.filter { $0.outcome == .eliminated }.compactMap(\.roundId))
                let cutoff = rounds.lastIndex(where: { eliminatedStages.contains($0.effectiveStageId) || eliminatedRounds.contains($0.id) }) ?? -1
                for index in rounds.indices where index > cutoff {
                    if (rounds[index].submissionEnd ?? rounds[index].submissionStart ?? .distantFuture) > Date() { rounds[index].submissionEnabled = false }
                }
                event.rounds = rounds
            }
            syncRoundResultsToAnswers()
            let notes = mergedAnswerResults()
            try store.saveResult(event: event, notes: notes)
            navigation.markResultEntry(eventID, unsaved: false)
            playLiveStairSaveFeedback()
            resultSaved = true
            // 通過したら、そのまま次の段階（1回目に全N回を入れた段階は次の回）の入力を開く。保存するまで追加しない。
            if shouldOfferNextRound(event) { nextDraft = giriNextRoundIsParallel(event.effectiveRounds) ? .sameStage : .nextStage }
            else { dismiss() }
        } catch { store.errorMessage = error.localizedDescription }
    }

    /// この回の結果（順位・得点・投票人数）を、提出した回答が1つだけの時はその回答にも入れる（回答側が未入力の時だけ）。
    private func syncRoundResultsToAnswers() {
        for stage in result.stages where stage.roundId != nil && (stage.placement != nil || stage.points != nil || stage.voterCount != nil) {
            var submitted: [(note: Int, record: Int)] = []
            for noteIndex in answerNotes.indices where answerNotes[noteIndex].roundId == stage.roundId {
                for recordIndex in answerNotes[noteIndex].answerRecords.indices {
                    let record = answerNotes[noteIndex].answerRecords[recordIndex]
                    if record.isOwn && record.isSubmitted { submitted.append((noteIndex, recordIndex)) }
                }
            }
            guard submitted.count == 1, let target = submitted.first else { continue }
            var record = answerNotes[target.note].answerRecords[target.record]
            guard record.placement == nil && record.points == nil && record.voterCount == nil else { continue }
            record.placement = stage.placement
            record.points = stage.points
            record.voterCount = stage.voterCount
            record.maxPointsPerVoter = stage.maxPointsPerVoter
            answerNotes[target.note].answerRecords[target.record] = record
        }
    }

    private func mergedAnswerResults() -> [ThoughtNote] {
        answerNotes.compactMap { edited in
            guard edited != originalAnswerNotes.first(where: { $0.id == edited.id }),
                  var current = store.notes.first(where: { $0.id == edited.id }) else { return nil }
            var records = current.effectiveAnswerRecords
            for index in records.indices {
                guard let changed = edited.answerRecords.first(where: { $0.id == records[index].id }) else { continue }
                records[index].placement = changed.placement
                records[index].points = changed.points
                records[index].voterCount = changed.voterCount
                records[index].maxPointsPerVoter = changed.maxPointsPerVoter
                records[index].memo = changed.memo
            }
            current.answerRecords = records
            current.usesAnswerRecords = true
            current.updatedAt = Date()
            return current
        }
    }

    private func shouldOfferNextRound(_ event: GiriEvent) -> Bool {
        guard event.eventFormat.hasOnlineRounds, event.meetingType == .tournament else { return false }
        let advanced = result.stages.filter { stage in
            stage.outcome == .advanced && originalResult.stages.first(where: { $0.id == stage.id })?.outcome != .advanced
        }
        guard let stage = advanced.last else { return false }
        let rounds = event.effectiveRounds
        let index: Int?
        if let roundID = stage.roundId { index = rounds.firstIndex { $0.id == roundID } }
        else if let stageID = stage.stageId { index = rounds.lastIndex { $0.effectiveStageId == stageID } }
        else { index = rounds.indices.last }
        guard let index else { return rounds.isEmpty }
        return index == rounds.count - 1
    }

    private func cleanNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert(playerSearchKey($0)).inserted }
    }
}

/// 段階（予選・本戦…）またはネットの1回の結果。LiveStair の入力行の形
/// （左に小さな項目名、右に値）で、形式・審査方法・結果・ネットの集計を分ける。
struct GiriStageEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: GiriStore
    let event: GiriEvent
    @Binding var stage: ResultStage
    @Binding var answerNotes: [ThoughtNote]
    var team = false
    /// この大会で入力済みの名前（自分以外）。対戦相手の候補に先に出す。
    var namePriority: [String] = []
    let onDelete: () -> Void
    @State private var deleting = false

    private var isStageWide: Bool { stage.roundId == nil }
    /// 0.28：この段階のチームのメンバー（自分を除く。入力中の段階のメンバーを使う）。
    private var previewTeammates: [String] {
        var preview = event
        var result = preview.tournamentResult ?? TournamentResult()
        if let index = result.stages.firstIndex(where: { $0.id == stage.id }) { result.stages[index] = stage } else { result.stages.append(stage) }
        preview.tournamentResult = result
        return preview.teammates(isSelf: store.preferences.isSelf, stageID: stage.id)
    }
    /// 0.28：途中でメンバーが変わる大会の、この段階のメンバー（出た・休み）と追加。
    @State private var newMember = ""
    private var memberSection: some View {
        let base = event.teammates(isSelf: store.preferences.isSelf)
        var seen = Set<String>()
        let names = (base + stage.members).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !store.preferences.isSelf($0) && seen.insert(playerSearchKey($0)).inserted }
        return Section {
            AppCardSectionTitle(title: "この段階のメンバー", systemImage: "person.2.badge.gearshape", accentColor: AppSectionAccent.artist,
                                infoTitle: "メンバーの変更", infoMessage: "途中でメンバーが増えた・入れ替わった・休んだ時に、この段階に出たメンバーを入れます。お題/回答の原案やメンバーの回答も、この段階のメンバーから選びます。")
                .listRowSeparator(.hidden)
            ForEach(names, id: \.self) { name in
                Picker(selection: Binding(get: { stage.absentMembers.contains { playerSearchKey($0) == playerSearchKey(name) } ? "absent" : "in" }, set: { value in
                    stage.absentMembers.removeAll { playerSearchKey($0) == playerSearchKey(name) }
                    if value == "absent" { stage.absentMembers.append(name) }
                    if stage.members.isEmpty { stage.members = base }
                    if !stage.members.contains(where: { playerSearchKey($0) == playerSearchKey(name) }) { stage.members.append(name) }
                })) {
                    Text("出た").tag("in")
                    Text("休み（欠員）").tag("absent")
                } label: { GiriEditorLabel(name) }
                .pickerStyle(.menu).tint(.primary)
            }
            HStack(spacing: 8) {
                GiriPlayerSuggestionField(title: "増えたメンバー", text: $newMember, showsLabel: true, textAlignment: .trailing)
                Button {
                    let name = newMember.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    if stage.members.isEmpty { stage.members = base }
                    if !stage.members.contains(where: { playerSearchKey($0) == playerSearchKey(name) }) { stage.members.append(name) }
                    newMember = ""
                } label: { Image(systemName: "plus.circle") }
                .buttonStyle(.borderless).accessibilityLabel("メンバーを足す")
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }
    private var isOnline: Bool { event.eventFormat.hasOnlineRounds && !event.effectiveRounds.isEmpty }
    private var roundIDs: Set<String> {
        if let roundID = stage.roundId { return [roundID] }
        guard let stageID = stage.stageId else { return [] }
        return Set(event.effectiveRounds.filter { $0.effectiveStageId == stageID }.map(\.id))
    }
    private var noteIndices: [Int] {
        answerNotes.indices.filter { index in
            let note = answerNotes[index]
            guard note.eventId == event.id, note.kind == .answers else { return false }
            if isOnline { return roundIDs.contains(note.roundId ?? "legacy") }
            return note.resultStageId == stage.id
        }
    }

    static let stageNames = ["予選", "予選1回戦", "予選2回戦", "本戦", "本戦1回戦", "本戦2回戦", "敗者復活戦", "準々決勝", "準決勝", "3位決定戦", "決勝"]
    static let lineups = ["横並び3人", "横並び4人", "横並び5人", "横並び6人", "タイマン", "総当たり", "トーナメント"]
    /// 審査方法は段階ごとに選ぶ（0.14：印象審査は投票だけ、拍手審査は分ける）。
    static let judgings = giriJudgingChoices

    /// 0.14：生大喜利などの段階全体は、周ごとの結果と総合結果に分けた入力にする。
    private var usesLiveSections: Bool { isStageWide && !isOnline }

    var body: some View {
        Form {
            if usesLiveSections {
                GiriLiveStageSections(event: event, stage: $stage, team: team, namePriority: namePriority)
            } else {
                standardSections
            }

            if team && event.hasMemberChanges && isStageWide { memberSection }
            if isOnline && isStageWide { onlineTotalsSection }

            if !noteIndices.isEmpty {
                ForEach(noteIndices, id: \.self) { index in
                    Section {
                        AppCardSectionTitle(title: "提出した回答の結果", systemImage: "text.bubble", accentColor: AppSectionAccent.memo)
                            .listRowSeparator(.hidden)
                        Text(answerNotes[index].prompt.isEmpty ? answerNotes[index].title : answerNotes[index].prompt)
                            .font(.subheadline.weight(.semibold)).lineLimit(4)
                        // 0.17：画像のお題は画像も出す。
                        if !answerNotes[index].imageDataBase64.isEmpty { GiriThoughtImage(base64: answerNotes[index].imageDataBase64) }
                        GiriAnswerResultFields(records: $answerNotes[index].answerRecords, teammates: previewTeammates)
                    }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
                }
            }

            Section {
                Button(role: .destructive) { deleting = true } label: {
                    Label(isStageWide ? "この段階の記録を削除" : "この回の記録を削除", systemImage: "trash")
                }
            }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
        }
        .appEditorFormStyle()
        .environment(\.defaultMinListRowHeight, 48)
        .navigationTitle(stage.name.isEmpty ? "段階" : stage.name)
        .navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
        .giriDeleteAlert(isStageWide ? "段階の記録を削除しますか？" : "この回の記録を削除しますか？", isPresented: $deleting,
                         message: "「\(stage.name)」の結果を削除します。お題と回答は残ります。保存すると確定します。") {
            // 親の editingStageID を外すと、この画面は自動で閉じる（dismiss を重ねない）。
            onDelete()
        }
    }

    /// 段階の結果の選択肢（決勝は優勝・準優勝など、それ以外は通過・敗退）。以前の版で選んだ値も残す。
    private var outcomeChoices: [TournamentOutcome] {
        guard isStageWide else { return [.unrecorded, .advanced, .eliminated, .champion, .runnerUp, .placed, .other] }
        var values = giriStageOutcomeChoices(stage.effectiveKind)
        if !values.contains(stage.outcome) { values.append(stage.outcome) }
        return values
    }

    @ViewBuilder private var standardSections: some View {
            Section {
                AppCardSectionTitle(title: isStageWide ? "段階" : "この回", systemImage: "flag", accentColor: AppSectionAccent.artist)
                    .listRowSeparator(.hidden)
                presetRow("段階名", placeholder: "予選・決勝など", text: $stage.name, presets: Self.stageNames)
                if isStageWide {
                    HStack(spacing: 4) {
                        GiriEditorLabel("種類")
                        AppInfoButton(title: "段階の種類について",
                                      message: "戦績のまとめで、予選通過率・決勝進出率と「どこまで進んだか」を数えるのに使います。段階名から自動で選びます。",
                                      tintColor: AppSectionAccent.artist)
                        Spacer(minLength: 8)
                        Picker("種類", selection: Binding(get: { stage.effectiveKind }, set: { stage.kind = $0 })) {
                            ForEach(StageKind.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden().pickerStyle(.menu).tint(.primary)
                    }
                    textRow("組", placeholder: "Aブロックなど", text: $stage.group)
                    presetRow("形式", placeholder: "横並び5人など", text: $stage.lineup, presets: Self.lineups)
                    Picker(selection: $stage.judging) {
                        Text("未設定").tag("")
                        ForEach(Self.judgings, id: \.self) { Text($0).tag($0) }
                        // 以前の版で入れた「挙手（1人1票）」などは、そのまま残して選べるようにする。
                        if !stage.judging.isEmpty && !Self.judgings.contains(stage.judging) { Text(stage.judging).tag(stage.judging) }
                    } label: { GiriEditorLabel("審査方法") }
                    .pickerStyle(.menu).tint(.primary)
                    GiriNamesField(title: "同じ組の人・対戦相手（任意）", names: $stage.opponents, priorityNames: namePriority)
                }
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)

            Section {
                AppCardSectionTitle(title: "結果", systemImage: "trophy", accentColor: AppSectionAccent.ticket,
                                    infoTitle: "結果について",
                                    infoMessage: "通過・敗退と順位だけでも記録できます。通過枠は分かる時だけ入れてください。")
                    .listRowSeparator(.hidden)
                Picker(selection: $stage.outcome) {
                    ForEach(outcomeChoices, id: \.self) { Text($0.title).tag($0) }
                } label: { GiriEditorLabel(isStageWide ? "結果" : "この回の結果") }
                .pickerStyle(.menu).tint(.primary)
                numberRow("順位", value: $stage.placement, suffix: "位")
                if isStageWide && stage.effectiveKind != .final { numberRow("通過枠", value: $stage.advanceCount, suffix: "人") }
                if team {
                    numberRow("チーム順位", value: $stage.teamPlacement, suffix: "位")
                    numberRow("個人順位", value: $stage.individualPlacement, suffix: "位")
                }
                if !isStageWide || !isOnline {
                    scoreRows(points: $stage.points, voters: $stage.voterCount, perVoter: stage.pointsPerVoter)
                }
                TextField("メモ（対戦・手応えなど）", text: $stage.memo, axis: .vertical).lineLimit(2...8)
            }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
    }

    /// ネット大喜利：競い方と通過ラインから、合計と残りのお題で必要な点を出す。
    private var onlineTotalsSection: some View {
        let summary = giriStageScoreSummary(event: event, stage: stage, notes: answerNotes)
        return Section {
            AppCardSectionTitle(title: "ネットの集計", systemImage: "chart.bar.xaxis", accentColor: AppSectionAccent.artist,
                                infoTitle: "ネットの集計について",
                                infoMessage: "提出した回答の「得点÷投票人数」（1人あたりの点）を合計します。通過ラインを入れると、残りのお題で必要な点を計算します。")
                .listRowSeparator(.hidden)
            Picker(selection: Binding(get: { stage.scoring ?? .total }, set: { stage.scoring = $0 })) {
                ForEach(StageScoring.allCases) { Text($0.title).tag($0) }
            } label: { GiriEditorLabel("競い方") }
            .pickerStyle(.menu).tint(.primary)
            HStack {
                GiriEditorLabel("通過ライン")
                Spacer(minLength: 8)
                TextField("未入力", value: $stage.borderScore, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 120)
            }
            if let summary {
                valueRow("合計", giriScoreText(summary.total) + "（\(summary.scoredPrompts)題）")
                if summary.remainingPrompts > 0 { valueRow("残りのお題", "\(summary.remainingPrompts)題") }
                if let needed = summary.neededTotal {
                    if needed <= 0 {
                        valueRow("通過ラインまで", "到達")
                    } else if let perPrompt = summary.neededPerPrompt {
                        valueRow("通過ラインまで", "あと" + giriScoreText(needed) + "（1題あたり" + giriScoreText(perPrompt) + "）")
                    } else {
                        valueRow("通過ラインまで", "あと" + giriScoreText(needed))
                    }
                }
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    private func textRow(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            GiriEditorLabel(title)
            TextField(placeholder, text: text).multilineTextAlignment(.trailing)
        }
    }

    private func presetRow(_ title: String, placeholder: String, text: Binding<String>, presets: [String]) -> some View {
        HStack(spacing: 8) {
            GiriEditorLabel(title)
            TextField(placeholder, text: text).multilineTextAlignment(.trailing)
            Menu {
                ForEach(presets, id: \.self) { value in Button(value) { text.wrappedValue = value } }
            } label: {
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.medium))
            }
            .tint(.primary)
            .accessibilityLabel("\(title)の候補")
        }
    }

    private func numberRow(_ title: String, value: Binding<Int?>, suffix: String) -> some View {
        HStack(spacing: 8) {
            GiriEditorLabel(title)
            Spacer(minLength: 8)
            TextField("未入力", value: value, format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 100)
            Text(suffix).foregroundStyle(.secondary)
        }
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack {
            GiriEditorLabel(title)
            Spacer(minLength: 8)
            Text(value).font(.body.weight(.semibold)).multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder private func scoreRows(points: Binding<Double?>, voters: Binding<Int?>, perVoter: Double?) -> some View {
        HStack(spacing: 8) {
            GiriEditorLabel("得点")
            Spacer(minLength: 8)
            TextField("未入力", value: points, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 100)
            Text("点").foregroundStyle(.secondary)
        }
        numberRow("投票人数", value: voters, suffix: "人")
        if let perVoter { valueRow("1人あたり", giriScoreText(perVoter)) }
    }
}

struct GiriIntegerField: View {
    let title: String
    @Binding var value: Int?
    var suffix = ""
    var body: some View {
        HStack {
            TextField(title, value: $value, format: .number).keyboardType(.numberPad)
            if !suffix.isEmpty { Text(suffix).foregroundStyle(.secondary) }
        }
    }
}

struct GiriNamesField: View {
    let title: String
    @Binding var names: [String]
    /// この会で入力済みの名前。先頭に候補として出す（同じ欄に入っている名前は除く）。
    var priorityNames: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty { Text(title).font(.subheadline).foregroundStyle(.secondary) }
            ForEach(Array(names.indices), id: \.self) { index in
                HStack(alignment: .top, spacing: 8) {
                    GiriPlayerSuggestionField(title: "名前", text: Binding(get: {
                        names.indices.contains(index) ? names[index] : ""
                    }, set: { value in
                        if names.indices.contains(index) { names[index] = value }
                    }), priorityNames: unusedPriorityNames)
                    Button(role: .destructive) {
                        if names.indices.contains(index) { names.remove(at: index) }
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).accessibilityLabel("名前を削除")
                }
            }
            Button { names.append("") } label: { Label("名前を追加", systemImage: "plus.circle") }
                .buttonStyle(.borderless).tint(accentActionColor)
        }
    }

    private var unusedPriorityNames: [String] {
        let used = Set(names.map(playerSearchKey))
        return priorityNames.filter { !used.contains(playerSearchKey($0)) }
    }
}

/// A future period remains a draft until the user explicitly saves it.
enum GiriRoundDraftAction: String, Identifiable {
    case nextStage, sameStage
    var id: String { rawValue }
}

struct GiriNextRoundEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    let eventID: String
    var sameStage = false
    @State private var round = EventRound()
    @State private var original: EventRound?
    @State private var automatic: Set<String> = ["submissionEnd", "votingStart", "votingEnd"]
    @State private var loaded = false
    @State private var saving = false
    @State private var discardQuestion = false

    private var event: GiriEvent? { store.events.first { $0.id == eventID } }
    private var changed: Bool { original.map { $0 != round } ?? false }

    var body: some View {
        Form {
            if let event {
                Section {
                    AppCardSectionTitle(title: sameStage ? "同じ段階の次回" : "次の段階", systemImage: "calendar.badge.plus", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                    GiriRoundFields(round: $round, automatic: $automatic, tournament: event.meetingType == .tournament)
                }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            } else { Text("この会は削除されています。").foregroundStyle(.secondary) }
        }
        .appEditorFormStyle()
        .navigationTitle(sameStage ? "次回を追加" : "次の段階を追加")
        .navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { if changed { discardQuestion = true } else { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save).disabled(!loaded || event == nil || round.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
            }
        }
        .onAppear {
            guard !loaded, let event else { return }
            round = nextEventRound(rounds: event.effectiveRounds, preferences: store.preferences, sameStage: sameStage, tournament: event.meetingType == .tournament, referenceDate: event.eventDate ?? Date())
            original = round
            loaded = true
        }
        .interactiveDismissDisabled(changed)
        .giriDiscardChangesAlert(isPresented: $discardQuestion) { dismiss() }
    }

    private func save() {
        guard !saving, var event else { return }
        saving = true
        defer { saving = false }
        do {
            var rounds = event.effectiveRounds
            guard !rounds.contains(where: { $0.id == round.id }) else { dismiss(); return }
            if sameStage {
                for index in rounds.indices where rounds[index].effectiveStageId == round.effectiveStageId { rounds[index].name = round.name }
            }
            rounds.append(round)
            event.rounds = rounds
            if event.onlineSiteId != nil { event.siteScheduleCustomized = true }
            try giriEditorValidate(event)
            try store.saveEvent(event)
            playLiveStairSaveFeedback()
            dismiss()
        } catch { store.errorMessage = error.localizedDescription }
    }
}

/// Cycle results retain the league played in and schedule an explicitly
/// confirmed change. Qualifying for a special period does not change leagues.
struct GiriCycleResultEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    let eventID: String
    @State private var result = ""
    @State private var placement: Int?
    @State private var affiliation = ""
    @State private var nextAffiliation = ""
    @State private var movement: LeagueMovement = .unchanged
    @State private var qualification: SiteQualification = .none
    @State private var effectiveDate: Date?
    @State private var manualNextLeague = false
    @State private var loaded = false
    @State private var originalResult = ""
    @State private var originalPlacement: Int?
    @State private var originalAffiliation = ""
    @State private var originalNextAffiliation = ""
    @State private var originalMovement: LeagueMovement = .unchanged
    @State private var originalQualification: SiteQualification = .none
    @State private var originalEffectiveDate: Date?
    @State private var discardQuestion = false
    @State private var block = ""
    @State private var originalBlock = ""
    /// 0.28：この回のタッグの相手（空はシングル）。
    @State private var tagPartner = ""
    @State private var originalTagPartner = ""
    @State private var keepBlock = false

    private var event: GiriEvent? { store.events.first { $0.id == eventID } }
    private var site: OnlineSite? { store.onlineSites.first { $0.id == event?.onlineSiteId } }
    private var leagues: [String] { site?.cycleSettings?.leagues ?? [] }
    private var hasLeagues: Bool {
        site?.hasAffiliations == true || !(event?.affiliation.isEmpty ?? true)
    }
    private var hasLeagueChange: Bool {
        movement != .unchanged || (!nextAffiliation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            playerSearchKey(nextAffiliation) != playerSearchKey(affiliation))
    }
    private var changed: Bool {
        result != originalResult || placement != originalPlacement || affiliation != originalAffiliation ||
            nextAffiliation != originalNextAffiliation || movement != originalMovement ||
            qualification != originalQualification || effectiveDate != originalEffectiveDate || block != originalBlock || keepBlock ||
            tagPartner != originalTagPartner
    }

    var body: some View {
        Form {
            resultSection
            if hasLeagues { leagueSection }
            qualificationSection
            if let event, !event.hasCycleResult {
                Section {
                    Button("この回は結果を記録しない", systemImage: "xmark.circle") {
                        store.run {
                            try store.markResultPrompted(eventID: event.id, key: "cycle-result-skipped")
                            dismiss()
                        }
                    }
                    .tint(accentActionColor)
                }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
            }
        }
        .appEditorFormStyle()
        .navigationTitle("結果を記録")
        .navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
        .navigationBarBackButtonHidden(changed)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if changed { Button { discardQuestion = true } label: { Image(systemName: "chevron.left") }.accessibilityLabel("戻る") }
            }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(event == nil || !loaded) }
        }
        .onAppear(perform: load)
        .interactiveDismissDisabled(changed)
        .giriDiscardChangesAlert(isPresented: $discardQuestion) { dismiss() }
    }

    private var resultSection: some View {
        Section {
            AppCardSectionTitle(title: "この回の結果", systemImage: "chart.bar", accentColor: AppSectionAccent.ticket)
                .listRowSeparator(.hidden)
            if let event {
                Text(event.title).font(.headline)
                if !event.siteSeason.isEmpty { resultValue("シーズン", event.siteSeason) }
                if event.sitePeriodKind != .regular {
                    resultValue("日程", event.sitePeriodKind.title)
                } else if let number = event.siteCycleNumber {
                    resultValue("対象の回", "第\(number)回")
                }
                if let date = event.participationStartDate {
                    Text(GiriDateText.day(date)).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            GiriIntegerField(title: "順位（任意）", value: $placement, suffix: "位")
            HStack(spacing: 12) {
                GiriEditorLabel("ブロック")
                TextField("任意", text: $block).multilineTextAlignment(.trailing)
            }
            if let site, block.trimmingCharacters(in: .whitespacesAndNewlines) != site.block {
                Toggle("次の回からもこのブロック", isOn: $keepBlock).tint(AppSectionAccent.ticket)
            }
            // 0.28：タッグ部門のあるサイトは、この回の相手（空はシングル）を直せる。
            if let site, site.currentRuleID.flatMap({ store.rule($0) })?.tagDivision != nil || !tagPartner.isEmpty {
                GiriPlayerSuggestionField(title: "タッグの相手", text: $tagPartner, showsLabel: true, textAlignment: .trailing)
                    .id(site.id)
            }
            TextField("結果・メモ", text: $result, axis: .vertical).lineLimit(3...10)
        }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
    }

    private var leagueSection: some View {
        Section {
            AppCardSectionTitle(title: "リーグの結果", systemImage: "person.crop.rectangle", accentColor: AppSectionAccent.artist)
                .listRowSeparator(.hidden)
            HStack {
                GiriEditorLabel("今回のリーグ")
                TextField("リーグ", text: Binding(get: { affiliation }, set: { value in
                    let previous = affiliation
                    affiliation = value
                    if movement != .unchanged { applyMovement(movement) }
                    else if playerSearchKey(nextAffiliation) == playerSearchKey(previous) {
                        nextAffiliation = value
                        effectiveDate = nil
                    }
                })).multilineTextAlignment(.trailing)
            }
            Picker("昇降格", selection: Binding(get: { movement }, set: applyMovement)) {
                ForEach(LeagueMovement.allCases) { value in Text(value.title).tag(value) }
            }.pickerStyle(.menu).tint(.primary)
            if !leagues.isEmpty && !manualNextLeague {
                Picker("変更後のリーグ", selection: nextLeagueBinding) {
                    ForEach(leagueChoices, id: \.self) { name in Text(name).tag(name) }
                }.pickerStyle(.menu).tint(.primary)
            } else {
                HStack {
                    GiriEditorLabel("変更後のリーグ")
                    TextField("リーグ", text: nextLeagueBinding).multilineTextAlignment(.trailing)
                }
            }
            if !leagues.isEmpty {
                Toggle("変更後のリーグを手入力", isOn: $manualNextLeague).tint(AppSectionAccent.artist)
            }
            if hasLeagueChange {
                OptionalDateRow(title: "反映する日時", selection: $effectiveDate)
                if site?.cycleSettings?.leagueChangesPerSeason == true {
                    Text("実際にリーグが変わる日時を指定します。シーズン終了が未定の場合は推測しません。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    private var qualificationSection: some View {
        Section {
            AppCardSectionTitle(title: "特別戦への出場", systemImage: "flag.checkered", accentColor: AppSectionAccent.ticket)
                .listRowSeparator(.hidden)
            Picker("出場", selection: $qualification) {
                ForEach(SiteQualification.allCases) { value in Text(value.title).tag(value) }
            }.pickerStyle(.menu).tint(.primary)
            if qualification != .none {
                Text("出場後の昇降格は、試合結果が出てから記録します。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
    }

    private var leagueChoices: [String] {
        var values = leagues
        for value in [affiliation, nextAffiliation] where !value.isEmpty && !values.contains(value) {
            values.append(value)
        }
        return values.isEmpty ? [""] : values
    }

    private var nextLeagueBinding: Binding<String> {
        Binding(get: { nextAffiliation }, set: { value in
            nextAffiliation = value
            if hasLeagueChange { fillEffectiveDate() }
            else { effectiveDate = nil }
        })
    }

    private func resultValue(_ title: String, _ value: String) -> some View {
        HStack {
            GiriEditorLabel(title)
            Spacer(minLength: 8)
            Text(value).font(.body.weight(.semibold)).multilineTextAlignment(.trailing)
        }
    }

    private func applyMovement(_ value: LeagueMovement) {
        movement = value
        if value == .unchanged {
            nextAffiliation = affiliation
            effectiveDate = nil
            manualNextLeague = !leagues.contains(affiliation)
        } else {
            let suggestion = site.flatMap { siteLeagueAfterMovement($0, from: affiliation, movement: value) }
            nextAffiliation = suggestion ?? ""
            manualNextLeague = suggestion == nil
            fillEffectiveDate()
        }
    }

    private func fillEffectiveDate() {
        guard effectiveDate == nil, let event else { return }
        if let site {
            if site.cycleSettings?.leagueChangesPerSeason == true,
               event.siteSeasonEnd == nil, site.cycleSettings?.seasonEndsAt == nil { return }
            effectiveDate = siteLeagueEffectiveDate(site, after: event)
        }
        else { effectiveDate = event.participationEndDate ?? Date() }
    }

    private func load() {
        guard !loaded, let event else { return }
        result = event.cycleResult
        placement = event.cyclePlacement
        affiliation = event.affiliation
        nextAffiliation = event.nextAffiliation.isEmpty ? event.affiliation : event.nextAffiliation
        movement = event.leagueMovement
        qualification = event.siteQualification
        effectiveDate = event.nextLeagueEffectiveDate
        block = event.block
        originalBlock = block
        tagPartner = event.tagPartner
        originalTagPartner = tagPartner
        if hasLeagueChange { fillEffectiveDate() }
        manualNextLeague = !leagues.contains(nextAffiliation)
        originalResult = result
        originalPlacement = placement
        originalAffiliation = affiliation
        originalNextAffiliation = nextAffiliation
        originalMovement = movement
        originalQualification = qualification
        originalEffectiveDate = effectiveDate
        loaded = true
    }

    private func save() {
        guard var event else { return }
        do {
            if let placement, placement < 1 {
                throw GiriEditorValidationError.schedule("順位は1以上で入力してください。")
            }
            let nextLeague = nextAffiliation.trimmingCharacters(in: .whitespacesAndNewlines)
            if hasLeagues && hasLeagueChange {
                guard !nextLeague.isEmpty, playerSearchKey(nextLeague) != playerSearchKey(affiliation) else {
                    throw GiriEditorValidationError.schedule("昇降格後のリーグを入力してください。")
                }
                guard effectiveDate != nil else {
                    throw GiriEditorValidationError.schedule("リーグの変更を反映する日時を入力してください。")
                }
            }
            event.cycleResult = result.trimmingCharacters(in: .whitespacesAndNewlines)
            event.cyclePlacement = placement
            event.siteQualification = qualification
            let next: String?
            if hasLeagues {
                event.affiliation = affiliation.trimmingCharacters(in: .whitespacesAndNewlines)
                event.leagueMovement = movement
                event.nextAffiliation = hasLeagueChange ? nextLeague : ""
                event.nextLeagueEffectiveDate = hasLeagueChange ? effectiveDate : nil
                next = hasLeagueChange ? nextLeague : nil
            } else { next = nil }
            event.block = block.trimmingCharacters(in: .whitespacesAndNewlines)
            event.tagPartner = tagPartner.trimmingCharacters(in: .whitespacesAndNewlines)
            try store.saveCycleResult(event: event, nextAffiliation: next)
            // ブロックが回ごとに変わるサイトは、次の回の初期値も変える。
            if keepBlock, var updated = store.onlineSiteById(event.onlineSiteId) {
                updated.block = event.block
                try store.saveOnlineSite(updated)
            }
            playLiveStairSaveFeedback()
            dismiss()
        } catch { store.errorMessage = error.localizedDescription }
    }
}

struct GiriBracketDraft: Identifiable {
    let id = UUID()
    var names: [String]
}

/// トーナメント表の並びを確認・修正する。読み取りの誤りは直し、順番は上の山から。
/// 自分の位置から、各回戦で当たりうる相手を候補に出す。
struct GiriBracketEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    @State private var names: [String]
    @State private var original: [String]
    @State private var discard = false
    let onApply: ([String]) -> Void

    init(names: [String], onApply: @escaping ([String]) -> Void) {
        _names = State(initialValue: names.isEmpty ? [""] : names)
        _original = State(initialValue: names.isEmpty ? [""] : names)
        self.onApply = onApply
    }

    private var cleaned: [String] { names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
    private var changed: Bool { names != original }
    private var selfIndex: Int? { cleaned.firstIndex(where: store.preferences.isSelf) }

    var body: some View {
        Form {
            Section {
                AppCardSectionTitle(title: "トーナメント表", systemImage: "list.number", accentColor: AppSectionAccent.ticket,
                                    infoTitle: "トーナメント表について",
                                    infoMessage: "上の山から順に並べます。左右に山がある表は左→右です。自分の位置から、各回戦で当たりうる相手を候補に出します。")
                    .listRowSeparator(.hidden)
                Text(summary).font(.subheadline).foregroundStyle(selfIndex == nil ? AppSectionAccent.ticket : Color.secondary)
                ForEach(names.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24, alignment: .trailing)
                        TextField("名前", text: $names[index])
                        if store.preferences.isSelf(names[index]) {
                            Text("自分").font(.caption2.weight(.semibold)).foregroundStyle(AppSectionAccent.ticket)
                        }
                        Menu {
                            if index > 0 { Button("上へ", systemImage: "arrow.up") { names.swapAt(index, index - 1) } }
                            if index + 1 < names.count { Button("下へ", systemImage: "arrow.down") { names.swapAt(index, index + 1) } }
                            Button("この下に追加", systemImage: "plus") { names.insert("", at: index + 1) }
                            Button("削除", systemImage: "trash", role: .destructive) { names.remove(at: index); if names.isEmpty { names = [""] } }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .tint(accentActionColor)
                    }
                }
                Button { names.append("") } label: { Label("名前を追加", systemImage: "plus.circle") }
                    .tint(accentActionColor)
            }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
            if selfIndex != nil {
                Section {
                    AppCardSectionTitle(title: "自分の山", systemImage: "arrow.triangle.branch", accentColor: AppSectionAccent.artist)
                        .listRowSeparator(.hidden)
                    ForEach(Array(giriBracketStageNames(cleaned.count).enumerated()), id: \.offset) { offset, name in
                        HStack(alignment: .firstTextBaseline) {
                            GiriEditorLabel(name)
                            Spacer(minLength: 8)
                            Text(giriBracketOpponents(cleaned, round: offset + 1, isSelf: store.preferences.isSelf).joined(separator: "・"))
                                .font(.subheadline).multilineTextAlignment(.trailing)
                        }
                    }
                }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            }
        }
        .appEditorFormStyle()
        .navigationTitle("トーナメント表").navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { if changed { discard = true } else { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) {
                Button("使う") { onApply(cleaned); dismiss() }.fontWeight(.bold).disabled(cleaned.count < 2)
            }
        }
        .interactiveDismissDisabled(changed)
        .giriDiscardChangesAlert(isPresented: $discard) { dismiss() }
    }

    private var summary: String {
        let rounds = giriBracketRoundCount(cleaned.count)
        guard let index = selfIndex else { return "\(cleaned.count)人・自分の名前が見つかりません（読み取りを直してください）" }
        return "\(cleaned.count)人・\(rounds)回戦・自分は\(index + 1)番目"
    }
}

/// 0.14：生大喜利の段階の入力。段階の形式（お題数・投票の仕方・周の数）→ 周ごとの結果
/// （ブロック・対戦相手・お題ごとの点・ほかの人の点）→ 総合結果（合計・通過ライン・結果）→ この段階のお題。
/// 対戦相手の候補は、その会に来ている人だけ。通過ラインと点が入れば通過・敗退は自動で入る。
struct GiriLiveStageSections: View {
    @EnvironmentObject private var store: GiriStore
    @EnvironmentObject private var navigation: GiriNavigation
    let event: GiriEvent
    @Binding var stage: ResultStage
    var team = false
    /// トーナメント表などから先に出す相手の候補。
    var namePriority: [String] = []
    @State private var blockPhoto: PhotosPickerItem?
    @State private var blockLap = 0
    @State private var readingBlock = false
    @State private var blockChoices: [GiriBlockEntry] = []

    private var attendees: [String] { namePriority + event.everyone }
    private var slotCount: Int? { giriOpponentSlotCount(stage.lineup) }
    private var isFinal: Bool { stage.effectiveKind == .final }
    private var promptSlots: Int { stage.votesPerPrompt ? max(1, stage.promptCount ?? 1) : 1 }
    private var showsVoteChoice: Bool { giriJudgingCategory(stage.judging) == "印象審査" && (stage.promptCount ?? 1) >= 2 }
    private var prompts: [ThoughtNote] {
        store.notes.filter { $0.eventId == event.id && $0.kind == .answers && $0.resultStageId == stage.id }
            .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
    }
    private var outcomeChoices: [TournamentOutcome] {
        var values = giriStageOutcomeChoices(stage.effectiveKind)
        if !values.contains(stage.outcome) { values.append(stage.outcome) }
        return values
    }

    var body: some View {
        Group {
            formatSection
            ForEach(stage.laps.indices, id: \.self) { index in lapSection(index) }
            totalSection
            promptSection
        }
        .onAppear { if stage.laps.isEmpty { stage.laps = giriNormalizedLaps(stage, lapCount: 1) } }
        .onChange(of: stage.laps) { _, _ in syncFromLaps() }
        .onChange(of: stage.borderScore) { _, _ in syncFromLaps() }
        .onChange(of: stage.votesPerPrompt) { _, _ in stage.laps = giriNormalizedLaps(stage, lapCount: stage.laps.count) }
        .onChange(of: stage.promptCount) { _, _ in stage.laps = giriNormalizedLaps(stage, lapCount: stage.laps.count) }
        .onChange(of: blockPhoto) { _, item in readBlockTable(item) }
        .confirmationDialog("自分のブロックを選んでください", isPresented: Binding(get: { !blockChoices.isEmpty }, set: { if !$0 { blockChoices = [] } }), titleVisibility: .visible) {
            ForEach(blockChoices.indices, id: \.self) { index in
                Button(blockChoices[index].name + "（" + blockChoices[index].members.joined(separator: "・") + "）") { applyBlock(blockChoices[index], lap: blockLap) }
            }
            Button("キャンセル", role: .cancel) { blockChoices = [] }
        }
    }

    // MARK: 段階の形式

    private var formatSection: some View {
        Section {
            AppCardSectionTitle(title: "段階", systemImage: "flag", accentColor: AppSectionAccent.artist)
                .listRowSeparator(.hidden)
            presetRow("段階名", placeholder: "予選・決勝など", text: $stage.name, presets: GiriStageEditor.stageNames)
            Picker(selection: Binding(get: { stage.effectiveKind }, set: { stage.kind = $0 })) {
                ForEach(StageKind.allCases) { Text($0.title).tag($0) }
            } label: { GiriEditorLabel("種類") }
            .pickerStyle(.menu).tint(.primary)
            presetRow("形式", placeholder: "横並び5人など", text: $stage.lineup, presets: GiriStageEditor.lineups)
            Picker(selection: $stage.judging) {
                Text("未設定").tag("")
                ForEach(giriJudgingChoices, id: \.self) { Text($0).tag($0) }
                if !stage.judging.isEmpty && !giriJudgingChoices.contains(stage.judging) { Text(stage.judging).tag(stage.judging) }
            } label: { GiriEditorLabel("審査方法") }
            .pickerStyle(.menu).tint(.primary)
            Stepper(value: Binding(get: { stage.promptCount ?? 1 }, set: { stage.promptCount = $0 }), in: 1...20) {
                HStack {
                    GiriEditorLabel("お題数")
                    Spacer(minLength: 8)
                    Text("\(stage.promptCount ?? 1)題").font(.body.weight(.semibold)).monospacedDigit()
                }
            }
            if showsVoteChoice {
                Picker(selection: $stage.votesPerPrompt) {
                    Text("全お題で1回").tag(false)
                    Text("お題ごと").tag(true)
                } label: { GiriEditorLabel("投票") }
                .pickerStyle(.menu).tint(.primary)
            }
            Stepper(value: lapCountBinding, in: 1...6) {
                HStack {
                    GiriEditorLabel("周（違うブロック）")
                    Spacer(minLength: 8)
                    Text("\(max(1, stage.laps.count))周").font(.body.weight(.semibold)).monospacedDigit()
                }
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    private var lapCountBinding: Binding<Int> {
        Binding(get: { max(1, stage.laps.count) }, set: { count in
            if count < stage.laps.count { stage.laps = Array(stage.laps.prefix(count)) }
            else { stage.laps = giriNormalizedLaps(stage, lapCount: count) }
        })
    }

    // MARK: 周ごとの結果

    private func lapSection(_ index: Int) -> some View {
        Section {
            AppCardSectionTitle(title: stage.laps.count > 1 ? "\(index + 1)周目" : "ブロックと結果", systemImage: "square.grid.2x2", accentColor: AppSectionAccent.venue)
                .listRowSeparator(.hidden)
            HStack(spacing: 12) {
                GiriEditorLabel("ブロック")
                TextField("Aブロックなど", text: lapBinding(index).group).multilineTextAlignment(.trailing)
            }
            PhotosPicker(selection: Binding(get: { blockPhoto }, set: { item in blockLap = index; blockPhoto = item }), matching: .images, photoLibrary: .shared()) {
                Label(readingBlock ? "読み取り中" : "ブロック表から読み取る", systemImage: "text.viewfinder")
            }
            .disabled(readingBlock)
            .tint(accentActionColor)
            // 対戦相手は1人ずつ行を分ける（横並び5人なら4人、タイマンは1人）。
            ForEach(0..<opponentRowCount(index), id: \.self) { slot in opponentRow(index, slot: slot) }
            ForEach(0..<promptSlots, id: \.self) { prompt in pointRow(index, prompt: prompt) }
            optionalNumberRow("投票人数", value: lapBinding(index).voterCount, suffix: "人")
            placementRow(index)
            if !namedOpponents(index).isEmpty {
                DisclosureGroup("ほかの人の点（任意）") {
                    ForEach(namedOpponents(index), id: \.self) { name in otherScoreRow(index, name: name) }
                }
                .tint(accentActionColor)
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.venue)
    }

    private func lapBinding(_ index: Int) -> Binding<StageLap> {
        Binding(get: { stage.laps.indices.contains(index) ? stage.laps[index] : StageLap() }, set: { value in
            if stage.laps.indices.contains(index) { stage.laps[index] = value }
        })
    }

    private func opponentRowCount(_ index: Int) -> Int {
        let current = stage.laps.indices.contains(index) ? stage.laps[index].opponents.count : 0
        if let slotCount { return max(slotCount, current) }
        return current + 1
    }

    private func opponent(_ index: Int, slot: Int) -> String {
        guard stage.laps.indices.contains(index), stage.laps[index].opponents.indices.contains(slot) else { return "" }
        return stage.laps[index].opponents[slot]
    }

    private func setOpponent(_ index: Int, slot: Int, name: String) {
        guard stage.laps.indices.contains(index) else { return }
        var names = stage.laps[index].opponents
        while names.count <= slot { names.append("") }
        names[slot] = name
        while let last = names.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { names.removeLast() }
        stage.laps[index].opponents = names
    }

    private func namedOpponents(_ index: Int) -> [String] {
        guard stage.laps.indices.contains(index) else { return [] }
        return stage.laps[index].opponents.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// 対戦相手1人の行。名前を打つか、その会に来ている人から選ぶ。
    private func opponentRow(_ index: Int, slot: Int) -> some View {
        let current = opponent(index, slot: slot)
        let chosen = namedOpponents(index).filter { playerSearchKey($0) != playerSearchKey(current) }
        let choices = giriOpponentCandidates(attendees: attendees, chosen: chosen, isSelf: store.preferences.isSelf)
        return HStack(spacing: 8) {
            GiriEditorLabel(slotCount == 1 ? "対戦相手" : "相手\(slot + 1)")
            TextField(choices.isEmpty ? "名前" : "選ぶか入力", text: Binding(get: { current }, set: { setOpponent(index, slot: slot, name: $0) }))
                .multilineTextAlignment(.trailing)
            if !choices.isEmpty {
                Menu {
                    ForEach(choices, id: \.self) { name in Button(name) { setOpponent(index, slot: slot, name: name) } }
                } label: {
                    Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.medium))
                }
                .tint(.primary)
                .accessibilityLabel("この会の参加者から選ぶ")
            }
        }
    }

    private func pointBinding(_ index: Int, prompt: Int) -> Binding<Double?> {
        Binding(get: {
            guard stage.laps.indices.contains(index), stage.laps[index].points.indices.contains(prompt) else { return nil }
            return stage.laps[index].points[prompt]
        }, set: { value in
            guard stage.laps.indices.contains(index) else { return }
            while stage.laps[index].points.count <= prompt { stage.laps[index].points.append(nil) }
            stage.laps[index].points[prompt] = value
        })
    }

    /// お題ごとの点（お題ごとの投票の時）。お題/回答で入れたお題があれば、その文も出す。
    private func pointRow(_ index: Int, prompt: Int) -> some View {
        let order = index * max(1, stage.promptCount ?? 1) + prompt
        let note = stage.votesPerPrompt && prompts.indices.contains(order) ? prompts[order] : nil
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                GiriEditorLabel(promptSlots > 1 ? "お題\(prompt + 1)の点" : "点")
                Spacer(minLength: 8)
                TextField("未入力", value: pointBinding(index, prompt: prompt), format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 100)
                Text("点").foregroundStyle(.secondary)
            }
            if let note {
                Text(note.prompt.isEmpty ? note.title : note.prompt).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    @ViewBuilder private func placementRow(_ index: Int) -> some View {
        let lap = stage.laps.indices.contains(index) ? stage.laps[index] : StageLap()
        if !lap.others.compactMap(\.points).isEmpty, let automatic = giriLapPlacement(lap) {
            valueRow("ブロックの順位", "\(automatic)位")
        } else {
            optionalNumberRow("ブロックの順位", value: lapBinding(index).placement, suffix: "位")
        }
    }

    private func otherScoreRow(_ index: Int, name: String) -> some View {
        let binding = Binding<Double?>(get: {
            guard stage.laps.indices.contains(index) else { return nil }
            return stage.laps[index].others.first { playerSearchKey($0.name) == playerSearchKey(name) }?.points
        }, set: { value in
            guard stage.laps.indices.contains(index) else { return }
            if let position = stage.laps[index].others.firstIndex(where: { playerSearchKey($0.name) == playerSearchKey(name) }) {
                stage.laps[index].others[position].points = value
            } else {
                stage.laps[index].others.append(StageOtherScore(name: name, points: value))
            }
        })
        return HStack(spacing: 8) {
            Text(name).font(.subheadline).lineLimit(1)
            Spacer(minLength: 8)
            TextField("未入力", value: binding, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 90)
            Text("点").foregroundStyle(.secondary)
        }
    }

    // MARK: 総合結果

    private var totalSection: some View {
        Section {
            AppCardSectionTitle(title: "総合結果", systemImage: "trophy", accentColor: AppSectionAccent.ticket,
                                infoTitle: "総合結果について",
                                infoMessage: "周・お題ごとの点を足して合計を出します。通過ラインを入れると、通過・敗退が自動で入ります（あとで変えられます）。")
                .listRowSeparator(.hidden)
            if let total = giriStageTotal(stage) { valueRow("合計", giriScoreText(total) + "点") }
            if !isFinal {
                HStack(spacing: 8) {
                    GiriEditorLabel("通過ライン（任意）")
                    Spacer(minLength: 8)
                    TextField("未入力", value: $stage.borderScore, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 100)
                    Text("点").foregroundStyle(.secondary)
                }
            }
            Picker(selection: $stage.outcome) {
                ForEach(outcomeChoices, id: \.self) { Text($0.title).tag($0) }
            } label: { GiriEditorLabel(isFinal ? "結果" : "通過・敗退") }
            .pickerStyle(.menu).tint(.primary)
            if stage.laps.count > 1 || isFinal {
                optionalNumberRow(isFinal ? "順位" : "全体の順位", value: $stage.placement, suffix: "位")
            }
            if !isFinal { optionalNumberRow("通過枠", value: $stage.advanceCount, suffix: "人") }
            if team {
                optionalNumberRow("チーム順位", value: $stage.teamPlacement, suffix: "位")
                optionalNumberRow("個人順位", value: $stage.individualPlacement, suffix: "位")
            }
            if stage.outcome == .advanced {
                GiriNamesField(title: "一緒に通過した人（任意）", names: $stage.advancedWith, priorityNames: event.everyone.filter { !store.preferences.isSelf($0) })
            }
            TextField("メモ（対戦・手応えなど）", text: $stage.memo, axis: .vertical).lineLimit(2...8)
        }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
    }

    // MARK: お題

    private var promptSection: some View {
        Section {
            AppCardSectionTitle(title: "この段階のお題", systemImage: "text.bubble", accentColor: AppSectionAccent.memo)
                .listRowSeparator(.hidden)
            if prompts.isEmpty {
                Text("お題と回答は、お題/回答でこの段階を選んで入れます。").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(prompts.enumerated()), id: \.element.id) { offset, note in
                Button { navigation.openThought(noteID: note.id) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("お題\(offset + 1)").font(.caption.weight(.semibold)).foregroundStyle(AppSectionAccent.memo)
                        Text(note.prompt.isEmpty ? note.title : note.prompt).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button { navigation.openThoughts(eventID: event.id) } label: { Label("お題/回答を開く", systemImage: "text.bubble") }
                .tint(accentActionColor)
        }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
    }

    // MARK: 自動の結果

    /// 周の記録から段階の組・相手・合計を合わせ、通過ラインがあれば通過・敗退を入れる（未入力の時だけ）。
    private func syncFromLaps() {
        var value = giriStageSyncedFromLaps(stage)
        if value.outcome == .unrecorded, let suggestion = giriSuggestedStageOutcome(value) { value.outcome = suggestion }
        if value != stage { stage = value }
    }

    // MARK: ブロック表

    private func readBlockTable(_ item: PhotosPickerItem?) {
        guard let item else { return }
        readingBlock = true
        let lap = blockLap
        Task {
            defer { readingBlock = false; blockPhoto = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw GiriParticipantReadError.unreadable }
                let blocks = giriBlockTable(try await GiriParticipantOCR.recognizeLines(data))
                if blocks.isEmpty { store.errorMessage = "ブロック表を読み取れませんでした。ブロック名（Aブロック・1組など）が写るようにしてください。"; return }
                if let mine = blocks.first(where: { $0.members.contains(where: store.preferences.isSelf) }) {
                    applyBlock(mine, lap: lap)
                } else {
                    blockChoices = blocks
                }
            } catch { store.errorMessage = error.localizedDescription }
        }
    }

    /// 読み取ったブロックを、その周のブロック名と対戦相手にする（参加者の名前があればそちらに合わせる）。
    private func applyBlock(_ block: GiriBlockEntry, lap: Int) {
        guard stage.laps.indices.contains(lap) else { return }
        let known = event.everyone
        var names = block.members.filter { !store.preferences.isSelf($0) }.map { name in
            known.first { playerSearchKey($0) == playerSearchKey(name) } ?? name
        }
        if let slotCount, names.count > slotCount { names = Array(names.prefix(slotCount)) }
        stage.laps[lap].group = block.name
        stage.laps[lap].opponents = names
        blockChoices = []
    }

    // MARK: 行の部品

    private func presetRow(_ title: String, placeholder: String, text: Binding<String>, presets: [String]) -> some View {
        HStack(spacing: 8) {
            GiriEditorLabel(title)
            TextField(placeholder, text: text).multilineTextAlignment(.trailing)
            Menu {
                ForEach(presets, id: \.self) { value in Button(value) { text.wrappedValue = value } }
            } label: {
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.medium))
            }
            .tint(.primary)
            .accessibilityLabel("\(title)の候補")
        }
    }

    private func optionalNumberRow(_ title: String, value: Binding<Int?>, suffix: String) -> some View {
        HStack(spacing: 8) {
            GiriEditorLabel(title)
            Spacer(minLength: 8)
            TextField("未入力", value: value, format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 100)
            Text(suffix).foregroundStyle(.secondary)
        }
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack {
            GiriEditorLabel(title)
            Spacer(minLength: 8)
            Text(value).font(.body.weight(.semibold)).multilineTextAlignment(.trailing)
        }
    }
}

/// 0.19：組手の結果。対戦ごとに主役側・相手側（人数は自由）と、主役から見た勝敗を入れ、通算の成績を出す。
@MainActor
struct GiriKumiteResultEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    let eventID: String
    /// 0.24：対戦相手の出順（参加者の中から並べ替える）。
    @State private var order: [String] = []
    /// 各戦の勝敗（その戦の最初の相手の名前の照合キー → win・lose・draw）。
    @State private var outcomes: [String: String] = [:]
    @State private var originalOrder: [String] = []
    @State private var originalOutcomes: [String: String] = [:]
    @State private var loaded = false
    @State private var discard = false
    private var event: GiriEvent? { store.events.first { $0.id == eventID } }
    private var changed: Bool { order != originalOrder || outcomes != originalOutcomes }
    private var size: Int { event?.kumiteBoutSize ?? 1 }
    private var bouts: [KumiteBout] { giriKumiteBouts(order: order, size: size, outcomes: outcomes, previous: event?.kumiteBouts ?? []) }

    var body: some View {
        List {
            if let event {
                summarySection(event)
                orderSection(event)
            } else {
                CenteredEmptyMessage(systemImage: "person.2", title: "この会は削除されています")
            }
        }
        .environment(\.editMode, .constant(.active))
        .environment(\.defaultMinListRowHeight, settingsMinimumListRowHeight)
        .appIndexListStyle()
        .navigationTitle("組手の結果").navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
        .navigationBarBackButtonHidden(changed)
        .interactiveDismissDisabled(changed)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if changed { Button { discard = true } label: { Image(systemName: "chevron.left") }.accessibilityLabel("戻る") }
            }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).fontWeight(.bold).disabled(!changed) }
        }
        .giriDiscardChangesAlert(isPresented: $discard) { dismiss() }
        .onAppear(perform: load)
    }

    private func summarySection(_ event: GiriEvent) -> some View {
        let record = giriKumiteRecord(bouts)
        let selfBouts = bouts.filter { event.kumiteIncludesSelf($0, isSelf: store.preferences.isSelf) }.count
        return Section {
            AppCardSectionTitle(title: "通算", systemImage: "star", accentColor: AppSectionAccent.favorite,
                                infoTitle: "組手の結果",
                                infoMessage: "対戦相手を≡で出順に並べ、主役から見た勝ち・負け・引き分けを選びます。主役の人数ずつで1戦です。")
                .listRowSeparator(.hidden)
            HStack {
                Text(event.kumiteMains.isEmpty ? "主役未設定" : event.kumiteMains.joined(separator: "・"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(record.text).font(.title3.weight(.bold)).foregroundStyle(AppSectionAccent.ticket).monospacedDigit()
            }
            if selfBouts > 0 {
                HStack { GiriEditorLabel("自分が出た対戦"); Spacer(); Text("\(selfBouts)戦").font(.subheadline) }
            }
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.favorite)
    }

    private func orderSection(_ event: GiriEvent) -> some View {
        Section {
            AppCardSectionTitle(title: size > 1 ? "出順（\(size)人ずつ）" : "出順", systemImage: "list.number", accentColor: AppSectionAccent.artist)
                .listRowSeparator(.hidden)
                .moveDisabled(true)
            if order.isEmpty {
                Text("会の登録の「対戦相手」に名前を入れると、ここに並びます。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .moveDisabled(true)
            }
            ForEach(Array(order.enumerated()), id: \.element) { index, name in
                opponentRow(event, index: index, name: name)
            }
            .onMove { from, to in order.move(fromOffsets: from, toOffset: to) }
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    /// 1人分の行。主役の人数ずつで1戦にし、その戦の最後の人の行で勝敗を選ぶ。
    private func opponentRow(_ event: GiriEvent, index: Int, name: String) -> some View {
        let boutIndex = index / size
        let start = boutIndex * size
        let isLastOfBout = index % size == size - 1 || index == order.count - 1
        let key = playerSearchKey(order[start])
        let isSelf = store.preferences.isSelf(name)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(index % size == 0 ? "第\(boutIndex + 1)戦" : "")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)
                Text(name).font(.body)
                if isSelf {
                    Text("自分").font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(AppSectionAccent.favorite))
                }
                Spacer(minLength: 0)
            }
            if isLastOfBout {
                Picker("第\(boutIndex + 1)戦の勝敗", selection: Binding(get: { outcomes[key] ?? "" }, set: { outcomes[key] = $0.isEmpty ? nil : $0 })) {
                    Text("未").tag("")
                    ForEach(KumiteOutcome.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.vertical, 2)
    }

    private func load() {
        guard !loaded, let event else { return }
        loaded = true
        order = event.kumiteOpponentOrder
        var values: [String: String] = [:]
        for bout in event.kumiteBouts {
            guard let first = bout.opponents.first, KumiteOutcome(rawValue: bout.outcome) != nil else { continue }
            values[playerSearchKey(first)] = bout.outcome
        }
        // 以前の版で、主役の人数と違う人数で記録した対戦は、出順の区切りに合わせて読み直す。
        outcomes = values
        originalOrder = order
        originalOutcomes = outcomes
    }

    private func save() {
        guard var event else { return }
        let saved = bouts
        event.kumiteBouts = saved
        // 対戦相手（参加者）も出順に並べる。主役など出順にない名前は後ろに残す。
        let ordered = Set(order.map(playerSearchKey))
        event.participants = order + event.participants.filter { !ordered.contains(playerSearchKey($0)) }
        store.run {
            try store.saveEvent(event)
            playLiveStairSaveFeedback()
            originalOrder = order
            originalOutcomes = outcomes
            dismiss()
        }
    }
}
