import SwiftUI

/// Date dependencies match TicketScheduleViews: only untouched derived fields move.
struct GiriRoundFields: View {
    @EnvironmentObject private var store: GiriStore
    @Binding var round: EventRound
    @Binding var automatic: Set<String>
    var tournament = true
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
                Menu {
                    ForEach(1...max(20, round.promptNumber + 1), id: \.self) { number in
                        Button("\(number)回目") { round.promptNumber = number }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("\(round.promptNumber)回目")
                        Image(systemName: "chevron.up.chevron.down").font(.caption)
                    }.font(.body.weight(.semibold)).fixedSize()
                }.tint(.primary)
            }.onChange(of: round.name) { _, name in onRename?(name) }
        }
        TextField("ブロック", text: $round.block)
        GiriSchedulePeriodRow(title: "投稿", start: dateBinding("submissionStart"), end: dateBinding("submissionEnd"))
        GiriSchedulePeriodRow(title: "投票", start: dateBinding("votingStart"), end: dateBinding("votingEnd"))
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
    @State private var advanceQuestion = false
    @State private var nextDraft: GiriRoundDraftAction?
    @State private var resultSaved = false
    @State private var editingStageID: String?


    private var event: GiriEvent? { store.events.first { $0.id == eventID } }
    private var changed: Bool { result != originalResult || placement != originalPlacement || standings != originalStandings || answerNotes != originalAnswerNotes }
    private var stageIndex: Int? { result.stages.firstIndex { $0.id == selectedID } }

    var body: some View {
        Form {
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
            } else {
                Text("この会は削除されています。").foregroundStyle(.secondary)
            }
        }
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
        .alert("通過後の日程を追加しますか？", isPresented: $advanceQuestion) {
            Button("次の段階を追加") { nextDraft = .nextStage }
            Button("同じ段階の次回を追加") { nextDraft = .sameStage }
            Button("後で追加", role: .cancel) { dismiss() }
        } message: { Text("直前の日程を引き継いだ入力欄を開きます。保存するまで予定は追加されません。") }
        .sheet(item: $nextDraft, onDismiss: { if resultSaved { dismiss() } }) { action in
            NavigationStack { GiriNextRoundEditor(eventID: eventID, sameStage: action == .sameStage) }
        }
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

    /// トーナメント表から「1回戦〜決勝」の段階を作る（1回戦の相手も入れる）。
    private func addBracketStages(_ event: GiriEvent) {
        let names = bracket(event)
        let firstOpponents = giriBracketOpponents(names, round: 1, isSelf: store.preferences.isSelf)
        for (offset, name) in giriBracketStageNames(names.count).enumerated() {
            var stage = ResultStage()
            stage.name = name
            stage.lineup = "タイマン"
            stage.judging = event.judging
            if offset == 0 { stage.opponents = firstOpponents }
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
                                infoMessage: "予選・本戦などの段階ごとに、形式・審査方法と通過／敗退・順位を残します。何人中・通過枠は分かる時だけで大丈夫です。")
                .listRowSeparator(.hidden)
            if wide.isEmpty && rounds.isEmpty {
                Text("段階がまだありません").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(wide) { stage in
                Button { editingStageID = stage.id } label: { stageRow(stage, nested: false) }
                    .buttonStyle(.plain)
                ForEach(rounds.filter { $0.stageId != nil && $0.stageId == stage.stageId }) { round in
                    Button { editingStageID = round.id } label: { stageRow(round, nested: true) }
                        .buttonStyle(.plain)
                }
            }
            // 段階に結び付かない旧データの回
            ForEach(rounds.filter { round in round.stageId == nil || !wide.contains { $0.stageId == round.stageId } }) { round in
                Button { editingStageID = round.id } label: { stageRow(round, nested: true) }
                    .buttonStyle(.plain)
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
                stage.name = wide.isEmpty ? "予選" : giriEditorNextStage(wide.last?.name ?? "")
                // 基本情報の審査方法・対戦形式を初期値にする（段階ごとに変えられる）。
                stage.judging = event.judging
                if event.knockout { stage.lineup = "タイマン" }
                result.stages.append(stage)
                existing.insert(stage.id)
                editingStageID = stage.id
            } label: { Label("段階を追加", systemImage: "plus.circle") }
            .tint(accentActionColor)
        }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
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
                let format = [stage.group, stage.lineup, stage.judging].filter { !$0.isEmpty }
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
            Picker(selection: finalChoice) {
                ForEach(GiriFinalResultChoice.allCases) { Text($0.title).tag($0) }
            } label: { GiriEditorLabel("最終結果") }
            .pickerStyle(.menu).tint(.primary)
            // 段階の記録（準々決勝で敗退→ベスト8 など）から候補を出す。押した時だけ反映する。
            if let suggestion = giriSuggestedFinalChoice(result.stages),
               [.unrecorded, .eliminated].contains(finalChoice.wrappedValue), suggestion != finalChoice.wrappedValue {
                Button { finalChoice.wrappedValue = suggestion } label: {
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
                prompt.name = "\(round.name) \(round.promptNumber)回目"
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
            event.resultText = result.memo
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
            let notes = mergedAnswerResults()
            try store.saveResult(event: event, notes: notes)
            navigation.markResultEntry(eventID, unsaved: false)
            playLiveStairSaveFeedback()
            resultSaved = true
            if shouldOfferNextRound(event) { advanceQuestion = true }
            else { dismiss() }
        } catch { store.errorMessage = error.localizedDescription }
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
    let event: GiriEvent
    @Binding var stage: ResultStage
    @Binding var answerNotes: [ThoughtNote]
    var team = false
    /// この大会で入力済みの名前（自分以外）。対戦相手の候補に先に出す。
    var namePriority: [String] = []
    let onDelete: () -> Void
    @State private var deleting = false

    private var isStageWide: Bool { stage.roundId == nil }
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
    /// 審査方法は段階ごとに選ぶ（挙手・拍手などは印象審査のやり方なので分けない）。
    static let judgings = giriJudgingChoices

    var body: some View {
        Form {
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
                                    infoMessage: "通過・敗退と順位だけでも記録できます。何人中・通過枠は分かる時だけ入れてください。")
                    .listRowSeparator(.hidden)
                Picker(selection: $stage.outcome) {
                    ForEach([TournamentOutcome.unrecorded, .advanced, .eliminated, .champion, .runnerUp, .placed, .other], id: \.self) { Text($0.title).tag($0) }
                } label: { GiriEditorLabel(isStageWide ? "通過・敗退" : "この回の結果") }
                .pickerStyle(.menu).tint(.primary)
                numberRow("順位", value: $stage.placement, suffix: "位")
                numberRow("何人中", value: $stage.entrantCount, suffix: "人")
                if isStageWide { numberRow("通過枠", value: $stage.advanceCount, suffix: "人") }
                if team {
                    numberRow("チーム順位", value: $stage.teamPlacement, suffix: "位")
                    numberRow("個人順位", value: $stage.individualPlacement, suffix: "位")
                }
                if !isStageWide || !isOnline {
                    scoreRows(points: $stage.points, voters: $stage.voterCount, perVoter: stage.pointsPerVoter)
                }
                TextField("メモ（対戦・手応えなど）", text: $stage.memo, axis: .vertical).lineLimit(2...8)
            }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)

            if isOnline && isStageWide { onlineTotalsSection }

            if !noteIndices.isEmpty {
                ForEach(noteIndices, id: \.self) { index in
                    Section {
                        AppCardSectionTitle(title: "提出した回答の結果", systemImage: "text.bubble", accentColor: AppSectionAccent.memo)
                            .listRowSeparator(.hidden)
                        Text(answerNotes[index].prompt.isEmpty ? answerNotes[index].title : answerNotes[index].prompt)
                            .font(.subheadline.weight(.semibold)).lineLimit(4)
                        GiriAnswerResultFields(records: $answerNotes[index].answerRecords)
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
            Text(title).font(.subheadline).foregroundStyle(.secondary)
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
            qualification != originalQualification || effectiveDate != originalEffectiveDate || block != originalBlock || keepBlock
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
