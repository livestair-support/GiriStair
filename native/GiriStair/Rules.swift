import SwiftUI

// MARK: - 0.23 ルール（保存して使い回す。ネット大喜利はシーズンごと、生大喜利は大会ごとに選ぶ）

/// 設定 → 一覧 →「大喜利のルール」。
@MainActor
struct GiriRulesView: View {
    @EnvironmentObject private var store: GiriStore
    @State private var kind: GiriRuleKind = .online
    @State private var creating: GiriRule?

    private var rules: [GiriRule] {
        store.rules.filter { $0.kind == kind }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        List {
            Section {
                Picker("種類", selection: $kind) {
                    ForEach(GiriRuleKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            Section {
                AppCardSectionTitle(title: kind == .online ? "ネット大喜利のルール" : "生大喜利のルール",
                                    systemImage: "list.bullet.rectangle", accentColor: AppSectionAccent.memo,
                                    infoTitle: "ルールについて",
                                    infoMessage: kind == .online
                                        ? "日程・成績の出し方・リーグ・プレーオフなどをまとめて保存し、サイトのシーズンごとに選びます。"
                                        : "大会の参加形式・審査方法・段階をまとめて保存し、大会の登録で選びます。")
                    .listRowSeparator(.hidden)
                if rules.isEmpty {
                    Text("ルールがありません").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(rules) { rule in
                    NavigationLink { GiriRuleEditor(rule: rule) } label: { ruleRow(rule) }
                }
            }
            .appSectionCardStyle(accentColor: AppSectionAccent.memo)
        }
        .environment(\.defaultMinListRowHeight, settingsMinimumListRowHeight)
        .appIndexListStyle()
        .giriNavigationBarStyle()
        .navigationTitle("大喜利のルール")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = GiriRule(kind: kind) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("ルールを追加")
            }
        }
        .sheet(item: $creating) { rule in NavigationStack { GiriRuleEditor(rule: rule, isNew: true) } }
    }

    private func ruleRow(_ rule: GiriRule) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rule.displayName).font(.headline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
            Text(rule.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            let usage = usageText(rule)
            if !usage.isEmpty { Text(usage).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 2)
    }

    private func usageText(_ rule: GiriRule) -> String {
        switch rule.kind {
        case .online:
            let sites = store.onlineSites.filter { $0.seasonRuleIDs.values.contains(rule.id) }
            return sites.isEmpty ? "" : "使っているサイト：" + sites.map(\.name).joined(separator: "・")
        case .live:
            let count = store.events.filter { $0.ruleID == rule.id }.count
            return count == 0 ? "" : "使った大会 \(count)件"
        }
    }
}

/// ルールの編集。新しく作る時はシートで開く（保存したら onSaved で選んだ所へ返す）。
@MainActor
struct GiriRuleEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GiriRule
    @State private var original: GiriRule
    @State private var discard = false
    @State private var deleting = false
    private let isNew: Bool
    private let onSaved: ((GiriRule) -> Void)?

    init(rule: GiriRule, isNew: Bool = false, onSaved: ((GiriRule) -> Void)? = nil) {
        _draft = State(initialValue: rule)
        _original = State(initialValue: rule)
        self.isNew = isNew
        self.onSaved = onSaved
    }

    private var changed: Bool { draft != original }

    var body: some View {
        Form {
            basicSection
            if draft.kind == .online {
                scoringSection
                scheduleSection
                leagueSection
                planSection
            } else {
                tournamentSection
                stageSection
            }
            if !isNew {
                Section {
                    Button("このルールを削除", role: .destructive) { deleting = true }
                }
                .appSectionCardStyle(accentColor: AppSectionAccent.memo)
            }
        }
        .appEditorFormStyle()
        .giriNavigationBarStyle()
        .navigationTitle(isNew ? "ルールを作る" : "ルールを編集")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(changed && !isNew)
        .interactiveDismissDisabled(changed)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isNew {
                    Button("キャンセル") { if changed { discard = true } else { dismiss() } }
                } else if changed {
                    Button { discard = true } label: { Image(systemName: "chevron.left") }.accessibilityLabel("戻る")
                }
            }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).fontWeight(.bold) }
        }
        .giriDiscardChangesAlert(isPresented: $discard) { dismiss() }
        .giriDeleteAlert("ルールを削除しますか？", isPresented: $deleting,
                         message: "「\(draft.displayName)」を削除します。このルールを選んでいたシーズン・大会の日程や結果はそのまま残ります。") {
            store.run { try store.deleteRule(draft.id); playLiveStairDeleteFeedback(); dismiss() }
        }
    }

    // MARK: Sections

    private var basicSection: some View {
        Section {
            AppCardSectionTitle(title: "ルール", systemImage: "list.bullet.rectangle", accentColor: AppSectionAccent.memo)
                .listRowSeparator(.hidden)
            TextField("ルールの名前（例：○○ 第5シーズン）", text: $draft.name)
            if isNew {
                Picker(selection: $draft.kind) {
                    ForEach(GiriRuleKind.allCases) { Text($0.title).tag($0) }
                } label: { GiriEditorLabel("種類") }
                .pickerStyle(.menu).tint(Color.primary)
            }
            TextField("メモ（ルールの細かい点など）", text: $draft.memo, axis: .vertical).lineLimit(2...6)
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.memo)
    }

    private var scoringSection: some View {
        Section {
            AppCardSectionTitle(title: "成績の出し方", systemImage: "chart.bar", accentColor: AppSectionAccent.ticket,
                                infoTitle: "成績の出し方",
                                infoMessage: "「規定回答数の上位の平均」は、規定回答数より多く回答した時に、得票率の高い規定回答数分だけを平均します（低い回答は考えません）。")
                .listRowSeparator(.hidden)
            Picker(selection: $draft.scoring) {
                ForEach(GiriRuleScoring.allCases) { Text($0.title).tag($0) }
            } label: { GiriEditorLabel("平均") }
            .pickerStyle(.menu).tint(Color.primary)
            if draft.scoring == .topRequired {
                Stepper("規定回答数　\(draft.requiredAnswerCount ?? 8)回答",
                        value: Binding(get: { draft.requiredAnswerCount ?? 8 }, set: { draft.requiredAnswerCount = $0 }), in: 1...200)
            }
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.ticket)
    }

    private var scheduleSection: some View {
        Section {
            AppCardSectionTitle(title: "投稿・投票", systemImage: "arrow.triangle.2.circlepath", accentColor: AppSectionAccent.artist)
                .listRowSeparator(.hidden)
            Picker(selection: $draft.nextPrompt) {
                ForEach(SiteNextPromptTiming.allCases) { Text($0.title).tag($0.rawValue) }
            } label: { GiriEditorLabel("次のお題") }
            .pickerStyle(.menu).tint(Color.primary)
            Stepper("投稿期間　\(draft.submissionDays)日", value: $draft.submissionDays, in: 1...365)
            Stepper("投票期間　\(draft.votingDays)日", value: $draft.votingDays, in: 1...365)
            if draft.timing == .interval {
                Stepper("お題の間隔　\(draft.intervalDays)日", value: $draft.intervalDays, in: 1...365)
            }
            Toggle("1シーズンの回数が決まっている", isOn: Binding(get: { draft.regularCycleCount != nil }, set: { draft.regularCycleCount = $0 ? (draft.regularCycleCount ?? 10) : nil }))
                .tint(AppSectionAccent.artist)
            if let count = draft.regularCycleCount {
                Stepper("1シーズン　\(count)回", value: Binding(get: { count }, set: { draft.regularCycleCount = $0 }), in: 1...200)
            }
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    private var leagueSection: some View {
        Section {
            AppCardSectionTitle(title: "リーグ", systemImage: "list.number", accentColor: AppSectionAccent.memo,
                                infoTitle: "リーグについて", infoMessage: "上位から順に入れます。リーグがないサイトは空のままにします。")
                .listRowSeparator(.hidden)
            ForEach(Array(draft.leagues.indices), id: \.self) { index in
                HStack(spacing: 8) {
                    Text("\(index + 1)").font(.caption).foregroundStyle(.secondary).frame(width: 18)
                    TextField("上位からリーグ名", text: Binding(get: { draft.leagues.indices.contains(index) ? draft.leagues[index] : "" },
                                                          set: { if draft.leagues.indices.contains(index) { draft.leagues[index] = $0 } }))
                    Button(role: .destructive) { draft.leagues.remove(at: index) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            Button("リーグ名を追加", systemImage: "plus.circle") { draft.leagues.append("") }
                .buttonStyle(.borderless).tint(accentActionColor)
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.memo)
    }

    private var planSection: some View {
        Section {
            AppCardSectionTitle(title: "プレーオフ・入れ替え戦", systemImage: "trophy", accentColor: AppSectionAccent.favorite,
                                infoTitle: "プレーオフ・入れ替え戦",
                                infoMessage: "最後の通常回の投票締切から何日後に始まるかで決めます。シーズンを始める時に日程を自動で作ります（1シーズンの回数が決まっている時）。")
                .listRowSeparator(.hidden)
            ForEach($draft.specialPlans) { $plan in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Picker("種類", selection: $plan.kind) {
                            ForEach(SitePeriodKind.allCases.filter { $0 != .regular }) { Text($0.title).tag($0) }
                        }
                        .labelsHidden().pickerStyle(.menu).tint(Color.primary)
                        TextField("名前（任意）", text: $plan.title)
                        Button(role: .destructive) { draft.specialPlans.removeAll { $0.id == plan.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                    Stepper("最後の回の投票締切から　\(plan.startOffsetDays)日後", value: $plan.startOffsetDays, in: 0...365)
                    Stepper("投稿　\(plan.submissionDays)日", value: $plan.submissionDays, in: 1...365)
                    Stepper("投票　\(plan.votingDays)日", value: $plan.votingDays, in: 1...365)
                    Stepper("回数　\(plan.count)回", value: $plan.count, in: 1...20)
                }
                .font(.subheadline)
                .padding(.vertical, 4)
            }
            Button("プレーオフ・入れ替え戦を追加", systemImage: "plus.circle") {
                draft.specialPlans.append(GiriRuleSpecialPlan(submissionDays: draft.submissionDays, votingDays: draft.votingDays))
            }
            .buttonStyle(.borderless).tint(accentActionColor)
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.favorite)
    }

    private var tournamentSection: some View {
        Section {
            AppCardSectionTitle(title: "大会", systemImage: "trophy", accentColor: AppSectionAccent.live)
                .listRowSeparator(.hidden)
            Picker(selection: $draft.tournamentFormat) {
                ForEach(TournamentFormat.allCases) { Text($0.title).tag($0) }
            } label: { GiriEditorLabel("参加形式") }
            .pickerStyle(.menu).tint(Color.primary)
            Toggle("トーナメント（1対1の勝ち抜き）", isOn: $draft.knockout).tint(AppSectionAccent.live)
            TextField("審査方法（例：拍手審査）", text: $draft.judging)
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.live)
    }

    private var stageSection: some View {
        Section {
            AppCardSectionTitle(title: "段階", systemImage: "list.number", accentColor: AppSectionAccent.ticket,
                                infoTitle: "段階について", infoMessage: "大会の結果を入れる時に、この段階を入れられます。")
                .listRowSeparator(.hidden)
            ForEach($draft.stages) { $stage in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Picker("種類", selection: Binding(get: { stage.kind ?? "" }, set: { stage.kind = $0.isEmpty ? nil : $0 })) {
                            Text("種類").tag("")
                            ForEach(StageKind.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        .labelsHidden().pickerStyle(.menu).tint(Color.primary)
                        TextField("段階の名前（例：予選1回戦）", text: $stage.name)
                        Button(role: .destructive) { draft.stages.removeAll { $0.id == stage.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                    TextField("形式（例：横並び5人・タイマン）", text: $stage.lineup)
                    TextField("審査方法（空なら大会の審査方法）", text: $stage.judging)
                    Stepper("お題　\(stage.promptCount.map { "\($0)問" } ?? "未定")",
                            value: Binding(get: { stage.promptCount ?? 0 }, set: { stage.promptCount = $0 == 0 ? nil : $0 }), in: 0...30)
                    Stepper("通過　\(stage.advanceCount.map { "\($0)人" } ?? "未定")",
                            value: Binding(get: { stage.advanceCount ?? 0 }, set: { stage.advanceCount = $0 == 0 ? nil : $0 }), in: 0...200)
                }
                .font(.subheadline)
                .padding(.vertical, 4)
            }
            Button("段階を追加", systemImage: "plus.circle") { draft.stages.append(GiriRuleStage()) }
                .buttonStyle(.borderless).tint(accentActionColor)
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.ticket)
    }

    private func save() {
        store.run {
            try store.saveRule(draft)
            playLiveStairSaveFeedback()
            onSaved?(store.rule(draft.id) ?? draft)
            original = draft
            dismiss()
        }
    }
}

/// ルールを選ぶメニュー（なし・保存したルール・新しく作る）。
struct GiriRuleMenuPicker: View {
    @EnvironmentObject private var store: GiriStore
    let kind: GiriRuleKind
    let selectedID: String?
    var noneTitle = "選ばない"
    let onSelect: (String?) -> Void
    let onCreate: () -> Void

    var body: some View {
        Menu {
            Button(noneTitle) { onSelect(nil) }
            ForEach(store.rules.filter { $0.kind == kind }.sorted { $0.updatedAt > $1.updatedAt }) { rule in
                Button { onSelect(rule.id) } label: {
                    if rule.id == selectedID { Label(rule.displayName, systemImage: "checkmark") } else { Text(rule.displayName) }
                }
            }
            Divider()
            Button("新しいルールを作る", systemImage: "plus") { onCreate() }
        } label: {
            HStack(spacing: 4) {
                Text(selectedID.flatMap { store.rule($0)?.displayName } ?? noneTitle)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .font(.subheadline)
            .foregroundStyle(Color.primary)
        }
    }
}
