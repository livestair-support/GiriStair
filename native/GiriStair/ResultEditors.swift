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
        .toolbar(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(changed)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if changed { Button { leave = true } label: { Image(systemName: "chevron.left") }.accessibilityLabel("戻る") }
            }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
        }
        .interactiveDismissDisabled(changed)
        .alert("変更を保存せず戻りますか？", isPresented: $leave) {
            Button("編集を続ける", role: .cancel) {}
            Button("変更を破棄", role: .destructive) { dismiss() }
        }
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


    private var event: GiriEvent? { store.events.first { $0.id == eventID } }
    private var changed: Bool { result != originalResult || placement != originalPlacement || standings != originalStandings || answerNotes != originalAnswerNotes }
    private var stageIndex: Int? { result.stages.firstIndex { $0.id == selectedID } }

    var body: some View {
        Form {
            if let event {
                if !result.stages.isEmpty {
                    Section {
                        AppCardSectionTitle(title: "段階・各回の結果", systemImage: "list.number", accentColor: AppSectionAccent.ticket).listRowSeparator(.hidden)
                        Picker("記録する結果", selection: $selectedID) {
                            ForEach(result.stages) { stage in
                                Text(stage.name + (stage.roundId == nil ? "（段階全体）" : "")).tag(stage.id)
                            }
                        }.pickerStyle(.menu).tint(.primary)
                        if let index = stageIndex {
                            GiriStageResultFields(stage: $result.stages[index], team: result.format != .individual, multipleAnswers: submittedAnswerCount > 1)
                            Button("この結果を削除", role: .destructive) {
                                existing.remove(result.stages[index].id)
                                result.stages.remove(at: index)
                                selectedID = result.stages.first?.id ?? ""
                            }
                        }
                    }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
                }
                Section {
                    Button {
                        var stage = ResultStage()
                        stage.name = "予選\(result.stages.filter { $0.roundId == nil }.count + 1)回戦"
                        result.stages.append(stage)
                        existing.insert(stage.id)
                        selectedID = stage.id
                    } label: { Label("段階の結果を追加", systemImage: "plus.circle") }
                }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
                submittedAnswerSections
                Section {
                    DisclosureGroup("大会の最終結果", isExpanded: $showFinalResult) { finalFields(event) }
                }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
                standingSections
            } else {
                Text("この会は削除されています。").foregroundStyle(.secondary)
            }
        }
        .appEditorFormStyle()
        .navigationTitle("結果を記録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(changed)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if changed { Button { leave = true } label: { Image(systemName: "chevron.left") }.accessibilityLabel("戻る") }
            }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: requestSave).disabled(event == nil) }
        }
        .onAppear { if !loaded { load() } }
        .interactiveDismissDisabled(changed)
        .alert("以後の投稿・投票", isPresented: $votingOnlyQuestion) {
            Button("そのまま") { save(votingOnly: false) }
            Button("投票だけにする") { save(votingOnly: true) }
            Button("キャンセル", role: .cancel) {}
        } message: { Text("以後の投稿を止め、必要な投票の日程と通知を残しますか？") }
        .alert("変更を保存せず戻りますか？", isPresented: $leave) {
            Button("編集を続ける", role: .cancel) {}
            Button("変更を破棄", role: .destructive) { dismiss() }
        }
        .confirmationDialog("通過後の日程を追加しますか？", isPresented: $advanceQuestion, titleVisibility: .visible) {
            Button("次の段階を追加") { nextDraft = .nextStage }
            Button("同じ段階の次回を追加") { nextDraft = .sameStage }
            Button("後で追加", role: .cancel) { dismiss() }
        } message: { Text("直前の日程を引き継いだ入力欄を開きます。保存するまで予定は追加されません。") }
        .sheet(item: $nextDraft, onDismiss: { if resultSaved { dismiss() } }) { action in
            NavigationStack { GiriNextRoundEditor(eventID: eventID, sameStage: action == .sameStage) }
        }
    }

    @ViewBuilder private func finalFields(_ event: GiriEvent) -> some View {
            Picker("最終結果", selection: $result.outcome) {
                ForEach([TournamentOutcome.unrecorded, .champion, .runnerUp, .placed, .eliminated, .other] + (result.outcome == .advanced ? [.advanced] : []), id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.menu).tint(.primary)
            GiriIntegerField(title: "最終順位（任意）", value: $placement, suffix: "位")
            if result.format != .individual {
                TextField("自分のチーム名", text: $result.teamName)
                GiriNamesField(title: "チームメンバー", names: $result.members)
            }
            TextField("結果のメモ", text: $result.memo, axis: .vertical).lineLimit(3...10)
    }

    @ViewBuilder private var submittedAnswerSections: some View {
        ForEach(answerNotes.indices, id: \.self) { index in
            if matchesSelectedRound(answerNotes[index]) && !answerNotes[index].isOthersAnswer {
                Section {
                    AppCardSectionTitle(title: "提出した回答の結果", systemImage: "text.bubble", accentColor: AppSectionAccent.memo).listRowSeparator(.hidden)
                    Text(answerNotes[index].prompt.isEmpty ? answerNotes[index].title : answerNotes[index].prompt).font(.headline)
                    GiriAnswerResultFields(records: $answerNotes[index].answerRecords)
                }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
            }
        }
    }

    private func matchesSelectedRound(_ note: ThoughtNote) -> Bool {
        guard let index = stageIndex else { return true }
        let selected = result.stages[index]
        if let roundID = selected.roundId {
            return note.roundId == roundID || (roundID == "legacy" && note.roundId == nil)
        }
        if let stageID = selected.stageId, let event {
            let rounds = event.effectiveRounds.filter { $0.effectiveStageId == stageID }
            return rounds.contains { $0.id == note.roundId || ($0.id == "legacy" && note.roundId == nil) }
        }
        return true
    }
    private var submittedAnswerCount: Int {
        answerNotes.filter { matchesSelectedRound($0) && !$0.isOthersAnswer }.flatMap(\.answerRecords).filter(\.isSubmitted).count
    }

    @ViewBuilder private var standingSections: some View {
        ForEach(standings.indices, id: \.self) { index in
            Section {
                HStack {
                    AppCardSectionTitle(title: "大会の上位成績", systemImage: "medal", accentColor: AppSectionAccent.ticket)
                    Button(role: .destructive) { standings.remove(at: index) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }.listRowSeparator(.hidden)
                Stepper("\(standings[index].placement)位", value: $standings[index].placement, in: 1...9999)
                TextField("チーム名（任意）", text: $standings[index].teamName)
                GiriNamesField(title: "プレイヤー名", names: $standings[index].playerNames)
                TextField("メモ", text: $standings[index].memo, axis: .vertical).lineLimit(1...5)
            }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
        }
        Section {
            Button {
                var standing = TournamentStanding()
                standing.placement = (standings.map(\.placement).max() ?? 0) + 1
                standings.append(standing)
            } label: { Label("優勝・準優勝などを追加", systemImage: "plus.circle") }
        }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
    }

    private func load() {
        guard let event else { return }
        result = event.tournamentResult ?? TournamentResult()
        if event.tournamentFormat != .individual || event.tournamentResult == nil {
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

struct GiriStageResultFields: View {
    @Binding var stage: ResultStage
    var team = false
    var multipleAnswers = false
    var body: some View {
        TextField("段階・回の名前", text: $stage.name)
        Picker(stage.roundId == nil ? "段階全体の結果" : "この回の結果", selection: $stage.outcome) {
                ForEach([TournamentOutcome.unrecorded, .champion, .runnerUp, .placed, .advanced, .eliminated, .other], id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.menu).tint(.primary)
        GiriIntegerField(title: stage.roundId == nil ? "この段階の順位（任意）" : "この回の順位（任意）", value: $stage.placement, suffix: "位")
        if team {
            GiriIntegerField(title: "チーム順位（任意）", value: $stage.teamPlacement, suffix: "位")
        }
        if team || multipleAnswers {
            GiriIntegerField(title: multipleAnswers ? "複数回答の個人総合順位（任意）" : "個人順位（任意）", value: $stage.individualPlacement, suffix: "位")
        }
        GiriIntegerField(title: "投票人数（任意）", value: $stage.voterCount, suffix: "人")
        HStack {
            TextField("得点（任意）", value: $stage.points, format: .number).keyboardType(.decimalPad)
            Text("点").foregroundStyle(.secondary)
        }
        Stepper("1人あたりの満点　\(stage.maxPointsPerVoter)点", value: $stage.maxPointsPerVoter, in: 1...100)
        HStack {
            GiriEditorLabel("得票率")
            Spacer()
            if let rate = stage.voteRate { Text(rate.formatted(.number.precision(.fractionLength(2))) + "%").font(.headline) }
            else { Text("—").foregroundStyle(.secondary) }
        }
        TextField("対戦・回答などのメモ", text: $stage.memo, axis: .vertical).lineLimit(2...8)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            ForEach(Array(names.indices), id: \.self) { index in
                HStack(alignment: .top, spacing: 8) {
                    GiriPlayerSuggestionField(title: "名前", text: Binding(get: {
                        names.indices.contains(index) ? names[index] : ""
                    }, set: { value in
                        if names.indices.contains(index) { names[index] = value }
                    }))
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
        .toolbar(.visible, for: .navigationBar)
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
        .alert("入力を保存せず閉じますか？", isPresented: $discardQuestion) {
            Button("編集を続ける", role: .cancel) {}
            Button("破棄して閉じる", role: .destructive) { dismiss() }
        }
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
            try giriEditorValidate(event)
            try store.saveEvent(event)
            playLiveStairSaveFeedback()
            dismiss()
        } catch { store.errorMessage = error.localizedDescription }
    }
}

/// A site's weekly affiliation is a snapshot; the next affiliation updates only
/// future, unjoined cycles through the store's single durable mutation.
struct GiriCycleResultEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    let eventID: String
    @State private var result = ""
    @State private var placement: Int?
    @State private var affiliation = ""
    @State private var nextAffiliation = ""
    @State private var loaded = false
    @State private var originalResult = ""
    @State private var originalPlacement: Int?
    @State private var originalAffiliation = ""
    @State private var originalNextAffiliation = ""
    @State private var discardQuestion = false

    private var event: GiriEvent? { store.events.first { $0.id == eventID } }
    private var site: OnlineSite? { store.onlineSites.first { $0.id == event?.onlineSiteId } }
    private var changed: Bool {
        result != originalResult || placement != originalPlacement || affiliation != originalAffiliation || nextAffiliation != originalNextAffiliation
    }

    var body: some View {
        Form {
            Section {
                AppCardSectionTitle(title: "この回の結果", systemImage: "chart.bar", accentColor: AppSectionAccent.ticket).listRowSeparator(.hidden)
                if let event {
                    Text(event.title).font(.headline)
                    if let date = event.participationStartDate { Text(GiriDateText.day(date)).font(.subheadline).foregroundStyle(.secondary) }
                }
                GiriIntegerField(title: "順位（任意）", value: $placement, suffix: "位")
                TextField("結果・メモ", text: $result, axis: .vertical).lineLimit(3...10)
            }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
            if site?.hasAffiliations == true {
                Section {
                    AppCardSectionTitle(title: "所属", systemImage: "person.crop.rectangle", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                    HStack {
                        GiriEditorLabel("今回の所属")
                        TextField("所属", text: $affiliation).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        GiriEditorLabel("次回の所属")
                        TextField("次回の所属", text: $nextAffiliation).multilineTextAlignment(.trailing)
                    }
                }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            }
        }
        .appEditorFormStyle()
        .navigationTitle("結果を記録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(changed)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if changed { Button { discardQuestion = true } label: { Image(systemName: "chevron.left") }.accessibilityLabel("戻る") }
            }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(event == nil || !loaded) }
        }
        .onAppear {
            guard !loaded, let event else { return }
            result = event.cycleResult
            placement = event.cyclePlacement
            affiliation = event.affiliation
            nextAffiliation = event.nextAffiliation.isEmpty ? site?.affiliation ?? "" : event.nextAffiliation
            originalResult = result
            originalPlacement = placement
            originalAffiliation = affiliation
            originalNextAffiliation = nextAffiliation
            loaded = true
        }
        .interactiveDismissDisabled(changed)
        .alert("変更を保存せず戻りますか？", isPresented: $discardQuestion) {
            Button("編集を続ける", role: .cancel) {}
            Button("変更を破棄", role: .destructive) { dismiss() }
        }
    }

    private func save() {
        guard var event else { return }
        do {
            if let placement, placement < 1 { throw GiriEditorValidationError.schedule("順位は1以上で入力してください。") }
            event.cycleResult = result.trimmingCharacters(in: .whitespacesAndNewlines)
            event.cyclePlacement = placement
            let next: String?
            if site?.hasAffiliations == true {
                event.affiliation = affiliation.trimmingCharacters(in: .whitespacesAndNewlines)
                event.nextAffiliation = nextAffiliation.trimmingCharacters(in: .whitespacesAndNewlines)
                next = event.nextAffiliation
            } else { next = nil }
            try store.saveCycleResult(event: event, nextAffiliation: next)
            playLiveStairSaveFeedback()
            dismiss()
        } catch { store.errorMessage = error.localizedDescription }
    }
}
