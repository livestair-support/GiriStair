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
            }.onChange(of: round.name) { _, name in onRename?(name) }
            Stepper("お題　\(round.promptNumber)", value: $round.promptNumber, in: 1...999)
        }
        TextField("自分のブロック・担当お題", text: $round.block)
        OptionalDateRow(title: "投稿開始", selection: dateBinding("submissionStart"))
        OptionalDateRow(title: "投稿締切", selection: dateBinding("submissionEnd"))
        OptionalDateRow(title: "投票開始", selection: dateBinding("votingStart"))
        OptionalDateRow(title: "投票締切", selection: dateBinding("votingEnd"))
        Toggle("投稿に参加する", isOn: $round.submissionEnabled).tint(AppSectionAccent.artist)
        Toggle("投票が必要", isOn: $round.votingRequired).tint(AppSectionAccent.artist)
    }

    private func addDays(_ date: Date?, _ days: Int) -> Date? {
        date.flatMap { Calendar.current.date(byAdding: .day, value: days, to: $0) }
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
            switch field {
            case "submissionStart":
                round.submissionStart = value
                if automatic.contains("submissionEnd") { round.submissionEnd = nil }
                if automatic.contains("votingStart") { round.votingStart = nil }
                if automatic.contains("votingEnd") { round.votingEnd = nil }
                guard let value else { return }
                if round.submissionEnd == nil {
                    round.submissionEnd = addDays(value, store.preferences.submissionDays)
                    automatic.insert("submissionEnd")
                }
                if round.votingStart == nil {
                    round.votingStart = round.submissionEnd
                    automatic.insert("votingStart")
                }
                if round.votingEnd == nil {
                    round.votingEnd = addDays(round.votingStart, store.preferences.votingDays)
                    automatic.insert("votingEnd")
                }
            case "submissionEnd":
                automatic.remove("submissionEnd")
                round.submissionEnd = value
                if automatic.contains("votingStart") {
                    round.votingStart = value
                    if automatic.contains("votingEnd") { round.votingEnd = addDays(value, store.preferences.votingDays) }
                }
            case "votingStart":
                automatic.remove("votingStart")
                round.votingStart = value
                if automatic.contains("votingEnd") { round.votingEnd = addDays(value, store.preferences.votingDays) }
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

    private var event: GiriEvent? { store.events.first { $0.id == eventID } }
    private var changed: Bool { result != originalResult || placement != originalPlacement || standings != originalStandings }
    private var stageIndex: Int? { result.stages.firstIndex { $0.id == selectedID } }

    var body: some View {
        Form {
            if let event {
                finalSection(event)
                if !result.stages.isEmpty {
                    Section {
                        AppCardSectionTitle(title: "段階・お題の結果", systemImage: "list.number", accentColor: AppSectionAccent.ticket).listRowSeparator(.hidden)
                        Picker("記録する結果", selection: $selectedID) {
                            ForEach(result.stages) { stage in
                                Text(stage.name + (stage.roundId == nil ? "（段階全体）" : "")).tag(stage.id)
                            }
                        }.pickerStyle(.menu).tint(.primary)
                        if let index = stageIndex {
                            GiriStageResultFields(stage: $result.stages[index], team: result.format != .individual)
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
    }

    private func finalSection(_ event: GiriEvent) -> some View {
        Section {
            AppCardSectionTitle(title: "自分の最終結果", systemImage: "trophy", accentColor: AppSectionAccent.ticket).listRowSeparator(.hidden)
            Picker("最終結果", selection: $result.outcome) {
                ForEach([TournamentOutcome.unrecorded, .champion, .runnerUp, .placed, .eliminated, .other] + (result.outcome == .advanced ? [.advanced] : []), id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.menu).tint(.primary)
            GiriIntegerField(title: "最終順位（任意）", value: $placement, suffix: "位")
            if result.format != .individual {
                TextField("自分のチーム名", text: $result.teamName)
                GiriNamesField(title: "チームメンバー", names: $result.members)
            }
            TextField("結果のメモ", text: $result.memo, axis: .vertical).lineLimit(3...10)
        }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
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
                prompt.name = "\(round.name) お題\(round.promptNumber)"
                prompt.roundId = round.id
                prompt.stageId = round.effectiveStageId
                result.stages.append(prompt)
            }
        }
        selectedID = result.stages.first(where: { $0.id == initialStageID })?.id ?? result.stages.first(where: { $0.roundId == initialRoundID && initialRoundID != nil })?.id ?? result.stages.first?.id ?? ""
        originalResult = result
        originalPlacement = placement
        originalStandings = standings
        loaded = true
    }

    private func requestSave() {
        guard let event else { return }
        let wasEliminated = event.tournamentResult?.outcome == .eliminated
        let oldStageIDs = Set((event.tournamentResult?.stages ?? []).filter { $0.roundId == nil && $0.outcome == .eliminated }.map(\.id))
        let newElimination = result.outcome == .eliminated && !wasEliminated || result.stages.contains { $0.roundId == nil && $0.outcome == .eliminated && !oldStageIDs.contains($0.id) }
        if event.kind == .online && newElimination && !event.effectiveRounds.isEmpty { votingOnlyQuestion = true }
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
            event.standings = standings
            if votingOnly {
                var rounds = event.effectiveRounds
                let eliminatedStages = Set(result.stages.filter { $0.roundId == nil && $0.outcome == .eliminated }.compactMap(\.stageId))
                let cutoff = rounds.lastIndex(where: { eliminatedStages.contains($0.effectiveStageId) }) ?? -1
                for index in rounds.indices where index > cutoff {
                    if (rounds[index].submissionEnd ?? rounds[index].submissionStart ?? .distantPast) > Date() { rounds[index].submissionEnabled = false }
                }
                event.rounds = rounds
            }
            try store.saveEvent(event)
            playLiveStairSaveFeedback()
            dismiss()
        } catch { store.errorMessage = error.localizedDescription }
    }
}

struct GiriStageResultFields: View {
    @Binding var stage: ResultStage
    var team = false
    var body: some View {
        TextField("段階・お題名", text: $stage.name)
        if stage.roundId == nil {
            Picker("結果", selection: $stage.outcome) {
                ForEach([TournamentOutcome.unrecorded, .champion, .runnerUp, .placed, .advanced, .eliminated, .other], id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.menu).tint(.primary)
        }
        GiriIntegerField(title: stage.roundId == nil ? "この段階の順位（任意）" : "このお題の順位（任意）", value: $stage.placement, suffix: "位")
        if team {
            GiriIntegerField(title: "チーム順位（任意）", value: $stage.teamPlacement, suffix: "位")
            GiriIntegerField(title: "個人順位（任意）", value: $stage.individualPlacement, suffix: "位")
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
    @State private var draft: String

    init(title: String, names: Binding<[String]>) {
        self.title = title
        _names = names
        _draft = State(initialValue: names.wrappedValue.joined(separator: "、"))
    }

    var body: some View {
        TextField(title + "（改行・、区切り）", text: $draft, axis: .vertical)
            .lineLimit(1...8)
            .onChange(of: draft) { _, value in names = giriParseParticipantNames(value) }
    }
}
