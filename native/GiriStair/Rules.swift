import SwiftUI
import PhotosUI

// MARK: - 0.23 ルール（保存して使い回す。ネット大喜利はシーズンごと、生大喜利は大会ごとに選ぶ）

/// 設定 → 一覧 →「ルール一覧」。
@MainActor
struct GiriRulesView: View {
    @EnvironmentObject private var store: GiriStore
    @State private var kind: GiriRuleKind = .online
    /// 0.27：ネット大喜利は通常（シーズン）と大会でルールを分ける。
    @State private var scope: GiriRuleScope = .regular
    @State private var creating: GiriRule?
    @State private var deleting: GiriRule?

    private var rules: [GiriRule] {
        store.rules.filter { $0.kind == kind && $0.effectiveScope == effectiveScope }.sorted { $0.updatedAt > $1.updatedAt }
    }
    private var effectiveScope: GiriRuleScope { kind == .live ? .tournament : scope }

    var body: some View {
        List {
            Section {
                Picker("種類", selection: $kind) {
                    ForEach(GiriRuleKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                if kind == .online {
                    Picker("通常・大会", selection: $scope) {
                        ForEach(GiriRuleScope.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            Section {
                AppCardSectionTitle(title: "自分のルール",
                                    systemImage: "list.bullet.rectangle", accentColor: AppSectionAccent.memo,
                                    infoTitle: "ルールについて",
                                    infoMessage: effectiveScope == .regular
                                        ? "日程・リーグ・規定数・プレーオフなどをまとめて保存し、サイトのシーズンごとに選びます。"
                                        : kind == .online
                                            ? "ネットの大会の参加形式・日程・流れ（段階）と勝ち抜けをまとめて保存し、大会の登録で選びます。"
                                            : "大会の参加形式・審査方法・流れ（段階）をまとめて保存し、大会の登録で選びます。生大喜利とスプシ系で同じルールを使えます。長押しで複製できます。")
                    .listRowSeparator(.hidden)
                if rules.isEmpty {
                    Text("ルールがありません").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(rules) { rule in
                    NavigationLink { GiriRuleEditor(rule: rule) } label: { ruleRow(rule) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { deleting = rule } label: { Label("削除", systemImage: "trash") }
                            Button { duplicate(rule) } label: { Label("複製", systemImage: "plus.square.on.square") }.tint(AppSectionAccent.artist)
                        }
                        .contextMenu {
                            Button("複製", systemImage: "plus.square.on.square") { duplicate(rule) }
                            Button("削除", systemImage: "trash", role: .destructive) { deleting = rule }
                        }
                }
            }
            .appSectionCardStyle(accentColor: AppSectionAccent.memo)
            // 0.24：よくあるルール。選ぶとコピーを自分のルールとして作る。
            Section {
                AppCardSectionTitle(title: "テンプレート", systemImage: "square.on.square", accentColor: AppSectionAccent.artist,
                                    infoTitle: "テンプレートについて", infoMessage: "よくあるルールです。選ぶと、そのコピーを自分のルールとして直して保存できます。")
                    .listRowSeparator(.hidden)
                ForEach(giriRuleTemplates.filter { $0.kind == kind && $0.effectiveScope == effectiveScope }) { template in
                    Button { creating = giriRuleFromTemplate(template) } label: {
                        HStack(spacing: 8) {
                            ruleRow(template)
                            Spacer(minLength: 8)
                            Image(systemName: "plus.circle").foregroundStyle(accentActionColor)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .appSectionCardStyle(accentColor: AppSectionAccent.artist)
        }
        .environment(\.defaultMinListRowHeight, settingsMinimumListRowHeight)
        .appIndexListStyle()
        .giriNavigationBarStyle()
        .navigationTitle("ルール一覧")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = GiriRule(kind: kind, scope: effectiveScope) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("ルールを追加")
            }
        }
        .sheet(item: $creating) { rule in NavigationStack { GiriRuleEditor(rule: rule, isNew: true) } }
        .giriDeleteAlert("ルールを削除しますか？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                         message: "「\(deleting?.displayName ?? "")」を削除します。このルールを選んでいたシーズン・大会の日程や結果はそのまま残ります。") {
            if let rule = deleting { store.run { try store.deleteRule(rule.id); playLiveStairDeleteFeedback() } }
            deleting = nil
        }
    }

    /// 0.24：ルールを複製する（生大喜利とスプシ系で少し違うルールを作る時など）。
    private func duplicate(_ rule: GiriRule) {
        store.run { try store.saveRule(rule.duplicated()); playLiveStairSaveFeedback() }
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
        switch rule.effectiveScope {
        case .regular:
            let sites = store.onlineSites.filter { $0.seasonRuleIDs.values.contains(rule.id) }
            return sites.isEmpty ? "" : "使っているサイト：" + sites.map(\.name).joined(separator: "・")
        case .tournament:
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
    /// 0.24：大会の流れで選んでいる段階。
    @State private var selectedStageID: String?
    /// 0.27：ルールのページの画像から読み取る。
    @State private var photo: PhotosPickerItem?
    @State private var reading = false
    @State private var readSummary: String?
    private let isNew: Bool
    private let onSaved: ((GiriRule) -> Void)?

    init(rule: GiriRule, isNew: Bool = false, onSaved: ((GiriRule) -> Void)? = nil) {
        // リーグの決まりは名前と同じ順で持つ（テンプレートなど名前だけのリーグも直せるようにする）。
        var value = rule
        if value.leagueDetails.map(\.name) != value.leagues || (value.tagDivision.map { $0.leagueDetails.map(\.name) != value.leagues } ?? false) {
            value.setLeagues(value.leagues)
        }
        _draft = State(initialValue: value)
        _original = State(initialValue: value)
        self.isNew = isNew
        self.onSaved = onSaved
    }

    private var changed: Bool { draft != original }
    private var isTournament: Bool { draft.effectiveScope == .tournament }

    var body: some View {
        Form {
            basicSection
            if isTournament {
                tournamentSection
                entrySection
                if draft.kind == .online { scheduleSection }
                stageSection
                scoringSection
            } else {
                scheduleSection
                leagueSection
                // 0.28：タッグ部門（リーグのあるサイト）。
                if !draft.leagueDetails.isEmpty || draft.tagDivision != nil { tagSection }
                // 0.27：成績の出し方は、リーグ・シーズンのある通常だけ（1回答で終わるサイトには平均がない）。
                if draft.usesScoring { scoringSection }
                planSection
            }
            if !isNew {
                Section {
                    Button("このルールを複製", systemImage: "plus.square.on.square") {
                        store.run { try store.saveRule(normalized(draft).duplicated()); playLiveStairSaveFeedback() }
                    }
                    .tint(accentActionColor)
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
        .toolbar { toolbarContent }
        .onChange(of: photo) { _, item in if let item { read(item) } }
        .giriDiscardChangesAlert(isPresented: $discard) { dismiss() }
        .giriDeleteAlert("ルールを削除しますか？", isPresented: $deleting,
                         message: "「\(draft.displayName)」を削除します。このルールを選んでいたシーズン・大会の日程や結果はそのまま残ります。") {
            store.run { try store.deleteRule(draft.id); playLiveStairDeleteFeedback(); dismiss() }
        }
        .alert("読み取りました", isPresented: Binding(get: { readSummary != nil }, set: { if !$0 { readSummary = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(readSummary ?? "") }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if isNew {
                Button("キャンセル") { if changed { discard = true } else { dismiss() } }
            } else if changed {
                Button { discard = true } label: { Image(systemName: "chevron.left") }.accessibilityLabel("戻る")
            }
        }
        ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).fontWeight(.bold) }
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
                if draft.kind == .online {
                    Picker(selection: $draft.scope) {
                        ForEach(GiriRuleScope.allCases) { Text($0.title).tag($0) }
                    } label: { GiriEditorLabel("使う所") }
                    .pickerStyle(.menu).tint(Color.primary)
                }
            }
            TextField("メモ（ルールの細かい点など）", text: $draft.memo, axis: .vertical).lineLimit(2...6)
            // 0.27：ルールのページの画像から、日程・回数・リーグ・段階などを読み取る。
            PhotosPicker(selection: $photo, matching: .images) {
                Label(reading ? "読み取り中…" : "ルールの画像から読み取る", systemImage: "text.viewfinder")
            }
            .disabled(reading)
            .tint(accentActionColor)
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.memo)
    }

    private var scoringSection: some View {
        Section {
            AppCardSectionTitle(title: "成績の出し方", systemImage: "chart.bar", accentColor: AppSectionAccent.ticket,
                                infoTitle: "成績の出し方",
                                infoMessage: "順位の決め方と、勝ち抜けの条件です。「規定回答数の上位の平均」は、得票率の高い規定回答数分だけを平均します。")
                .listRowSeparator(.hidden)
            Picker(selection: $draft.scoring) {
                ForEach(GiriRuleScoring.allCases) { Text($0.title).tag($0) }
            } label: { GiriEditorLabel("順位の決め方") }
            .pickerStyle(.menu).tint(Color.primary)
            if draft.scoring == .topRequired {
                Stepper("規定回答数　\(draft.requiredAnswerCount ?? 8)回答",
                        value: Binding(get: { draft.requiredAnswerCount ?? 8 }, set: { draft.requiredAnswerCount = $0 }), in: 1...200)
            }
            // 0.24：上位○人が勝ち抜け（記録用。自動では判定しない）。0.27：割合（上位半数など）でも決められる。
            GiriAdvanceRows(count: $draft.advanceCount, fraction: $draft.advanceFraction, accent: AppSectionAccent.ticket, title: isTournament ? "勝ち抜け" : "シーズンの勝ち抜け")
            HStack(spacing: 12) {
                GiriEditorLabel("同率の時")
                TextField("例：投稿数が多い方を上位", text: $draft.tieBreak).multilineTextAlignment(.trailing)
            }
            Toggle(isOn: Binding(get: { draft.voteBonusPoints != nil }, set: { draft.voteBonusPoints = $0 ? (draft.voteBonusPoints ?? 3) : nil })) {
                GiriEditorLabel("投票ボーナス")
            }
            .tint(AppSectionAccent.ticket)
            if let bonus = draft.voteBonusPoints {
                Stepper("投票ボーナス　\(bonus)点", value: Binding(get: { bonus }, set: { draft.voteBonusPoints = $0 }), in: 0...100)
            }
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.ticket)
    }

    private var scheduleSection: some View {
        Section {
            AppCardSectionTitle(title: "投稿・投票", systemImage: "arrow.triangle.2.circlepath", accentColor: AppSectionAccent.artist)
                .listRowSeparator(.hidden)
            if !isTournament {
                Picker(selection: $draft.nextPrompt) {
                    ForEach(SiteNextPromptTiming.allCases) { Text($0.title).tag($0.rawValue) }
                } label: { GiriEditorLabel("次のお題") }
                .pickerStyle(.menu).tint(Color.primary)
            }
            Stepper("投稿期間　\(draft.submissionDays)日", value: $draft.submissionDays, in: 1...365)
            Stepper("投票期間　\(draft.votingDays)日", value: $draft.votingDays, in: 1...365)
            if !isTournament {
                if draft.timing == .interval {
                    Stepper("お題の間隔　\(draft.intervalDays)日", value: $draft.intervalDays, in: 1...365)
                }
                Toggle("1シーズンの回数が決まっている", isOn: Binding(get: { draft.regularCycleCount != nil }, set: { draft.regularCycleCount = $0 ? (draft.regularCycleCount ?? 10) : nil }))
                    .tint(AppSectionAccent.artist)
                if let count = draft.regularCycleCount {
                    Stepper("全\(count)回で1シーズン", value: Binding(get: { count }, set: { draft.regularCycleCount = $0 }), in: 1...200)
                }
            }
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    /// 0.27：リーグごとに、規定数・お題の選び方・昇格／降格の人数を入れる。
    /// 0.28：上から何回答の平均・残留の人数・足りない時の扱い・リーグごとの日程とエントリーも入れる。
    private var leagueSection: some View {
        Section {
            AppCardSectionTitle(title: "リーグ", systemImage: "list.number", accentColor: AppSectionAccent.memo,
                                infoTitle: "リーグについて", infoMessage: "上位から順に入れます。リーグごとに成績の出し方・規定数・入れ替えの人数・日程を入れられます。リーグがないサイトは空のままにします。")
                .listRowSeparator(.hidden)
            ForEach(Array(draft.leagueDetails.indices), id: \.self) { index in
                leagueRow(index, tag: false)
            }
            Button("リーグを追加", systemImage: "plus.circle") {
                draft.leagueDetails.append(GiriRuleLeague(name: "\(draft.leagueDetails.count + 1)部"))
                draft.leagues = draft.leagueDetails.map(\.name)
                draft.tagDivision?.leagueDetails.append(GiriRuleLeague(name: draft.leagues.last ?? ""))
            }
            .buttonStyle(.borderless).tint(accentActionColor)
            if !draft.leagueDetails.isEmpty {
                HStack(spacing: 12) {
                    GiriEditorLabel("エントリーの決まり")
                    TextField("例：先着順・定員まで", text: $draft.entryNote, axis: .vertical).multilineTextAlignment(.trailing).lineLimit(1...4)
                }
            }
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.memo)
    }

    /// シングル（tag == false）かタッグのリーグの決まりへの入力。タッグのリーグ名はシングルと同じにする。
    private func leagueBinding(_ index: Int, tag: Bool) -> Binding<GiriRuleLeague> {
        Binding(get: {
            let list = tag ? (draft.tagDivision?.leagueDetails ?? []) : draft.leagueDetails
            return list.indices.contains(index) ? list[index] : GiriRuleLeague(name: draft.leagues.indices.contains(index) ? draft.leagues[index] : "")
        }, set: { value in
            if tag {
                guard draft.tagDivision != nil else { return }
                var list = draft.tagDivision?.leagueDetails ?? []
                while list.count <= index { list.append(GiriRuleLeague(name: draft.leagues.indices.contains(list.count) ? draft.leagues[list.count] : "")) }
                list[index] = value
                draft.tagDivision?.leagueDetails = list
            } else {
                guard draft.leagueDetails.indices.contains(index) else { return }
                draft.leagueDetails[index] = value
                draft.leagues = draft.leagueDetails.map(\.name)
                // タッグのリーグ名もそろえる。
                if let count = draft.tagDivision?.leagueDetails.count, index < count { draft.tagDivision?.leagueDetails[index].name = value.name }
            }
        })
    }

    private func leagueRow(_ index: Int, tag: Bool) -> some View {
        let league = leagueBinding(index, tag: tag)
        let unit = tag ? "組" : "人"
        let requiredMode = Binding(get: { league.wrappedValue.requiredCount != nil ? "count" : league.wrappedValue.requiredFraction != nil ? "fraction" : "" },
                                   set: { mode in
                                       league.wrappedValue.requiredCount = mode == "count" ? (league.wrappedValue.requiredCount ?? 4) : nil
                                       league.wrappedValue.requiredFraction = mode == "fraction" ? (league.wrappedValue.requiredFraction ?? "1/2") : nil
                                   })
        let shortfall = Binding(get: { league.wrappedValue.unqualifiedRanksLast ? "last" : league.wrappedValue.unqualifiedExcluded ? "excluded" : "" },
                                set: { mode in
                                    league.wrappedValue.unqualifiedRanksLast = mode == "last"
                                    league.wrappedValue.unqualifiedExcluded = mode == "excluded"
                                })
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(index + 1)").font(.caption).foregroundStyle(.secondary).frame(width: 18)
                if tag {
                    Text(league.wrappedValue.name.isEmpty ? "リーグ\(index + 1)" : league.wrappedValue.name).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                } else {
                    TextField("上位からリーグ名", text: league.name).font(.subheadline.weight(.semibold))
                    TextField("呼び名（任意）", text: league.subtitle).font(.caption).multilineTextAlignment(.trailing).frame(maxWidth: 110)
                    Button(role: .destructive) {
                        draft.leagueDetails.remove(at: index)
                        draft.leagues = draft.leagueDetails.map(\.name)
                        if let count = draft.tagDivision?.leagueDetails.count, index < count { draft.tagDivision?.leagueDetails.remove(at: index) }
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                }
            }
            GiriOptionalStepper(title: "成績　上から", unit: "回答の平均", value: league.topAnswerCount, range: 1...100, initial: 8)
            Picker(selection: requiredMode) {
                Text("なし").tag("")
                Text("回数").tag("count")
                Text("結果お題数の割合").tag("fraction")
            } label: { GiriEditorLabel("規定数") }
            .pickerStyle(.menu).tint(Color.primary)
            if let count = league.wrappedValue.requiredCount {
                Stepper("\(count)回以上", value: Binding(get: { count }, set: { league.wrappedValue.requiredCount = $0 }), in: 1...200)
            }
            if league.wrappedValue.requiredFraction != nil {
                Picker(selection: Binding(get: { league.wrappedValue.requiredFraction ?? "1/2" }, set: { league.wrappedValue.requiredFraction = $0 })) {
                    ForEach(["1/2", "1/3", "1/4", "1/8", "2/3", "3/4"], id: \.self) { Text($0 + "以上").tag($0) }
                } label: { GiriEditorLabel("割合") }
                .pickerStyle(.menu).tint(Color.primary)
            }
            Picker(selection: shortfall) {
                Text("決めない").tag("")
                Text("最下位扱い").tag("last")
                Text("集計対象外").tag("excluded")
            } label: { GiriEditorLabel(tag ? "組んでいない・足りない時" : "回答が足りない時") }
            .pickerStyle(.menu).tint(Color.primary)
            if index > 0 { GiriOptionalStepper(title: "上位", unit: unit + "が昇格", value: league.promotionCount, range: 1...200, initial: 10) }
            GiriOptionalStepper(title: "上位", unit: unit + "が残留", value: league.stayCount, range: 1...500, initial: 30)
            if index + 1 < max(draft.leagueDetails.count, draft.leagues.count) { GiriOptionalStepper(title: "下位", unit: unit + "が降格", value: league.relegationCount, range: 1...200, initial: 10) }
            if !tag {
                GiriOptionalStepper(title: "お題", unit: "題から1題", value: league.promptChoices, range: 2...20, initial: 2)
                GiriOptionalStepper(title: "1題につき", unit: "回答", value: league.answersPerPrompt, range: 1...20, initial: 1)
                GiriOptionalStepper(title: "エントリー", unit: "日", value: league.entryDays, range: 1...60, initial: 1)
                GiriOptionalStepper(title: "投稿", unit: "日（空ならルールの日数）", value: league.submissionDays, range: 1...365, initial: 7)
                GiriOptionalStepper(title: "投票", unit: "日（空ならルールの日数）", value: league.votingDays, range: 1...365, initial: 4)
            }
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }

    /// 0.28：通常のサイトの「タッグ」部門（2人で組み、2人の成績を合わせて別に順位を付ける）。
    private var tagSection: some View {
        Section {
            AppCardSectionTitle(title: "タッグ部門", systemImage: "person.2", accentColor: AppSectionAccent.favorite,
                                infoTitle: "タッグ部門", infoMessage: "シングルとは別に、2人で組んで順位を付けるサイトで使います。リーグの名前はシングルと同じで、入れ替えの組数などはここで入れます。")
                .listRowSeparator(.hidden)
            Toggle(isOn: Binding(get: { draft.tagDivision != nil }, set: { on in
                draft.tagDivision = on ? GiriRuleTagDivision(leagueDetails: draft.leagues.map { GiriRuleLeague(name: $0) }) : nil
            })) { GiriEditorLabel("タッグ部門がある") }
            .tint(AppSectionAccent.favorite)
            if draft.tagDivision != nil {
                Stepper(value: tagBinding(\.memberCount, 2), in: 2...6) {
                    HStack { GiriEditorLabel("1組の人数"); Spacer(minLength: 8); Text("\(draft.tagDivision?.memberCount ?? 2)人").font(.subheadline) }
                }
                Picker(selection: tagBinding(\.teamScoring, "sum")) {
                    ForEach(GiriRuleTagDivision.scorings, id: \.value) { Text($0.title).tag($0.value) }
                } label: { GiriEditorLabel("組の成績") }
                .pickerStyle(.menu).tint(Color.primary)
                Toggle(isOn: tagBinding(\.memberShortfallZero, false)) { GiriEditorLabel("回答が足りない人の値は0") }
                    .tint(AppSectionAccent.favorite)
                HStack(spacing: 12) {
                    GiriEditorLabel("同率の時")
                    TextField("例：投稿数が多い組を上位", text: tagBinding(\.tieBreak, "")).multilineTextAlignment(.trailing)
                }
                GiriOptionalStepper(title: "プレーオフ　上位", unit: "組", value: tagBinding(\.playoffEntrants, nil), range: 1...50, initial: 4)
                TextField("組む・解消するの決まり（任意）", text: tagBinding(\.formationNote, ""), axis: .vertical).lineLimit(1...5)
                ForEach(Array(draft.leagues.indices), id: \.self) { index in
                    leagueRow(index, tag: true)
                }
            }
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.favorite)
    }

    private func tagBinding<Value>(_ keyPath: WritableKeyPath<GiriRuleTagDivision, Value>, _ fallback: Value) -> Binding<Value> {
        Binding(get: { draft.tagDivision?[keyPath: keyPath] ?? fallback },
                set: { value in draft.tagDivision?[keyPath: keyPath] = value })
    }

    /// 0.28：エントリー（申し込み）の期間・定員。大会で使う（通常のサイトはリーグごとに入れる）。
    private var entrySection: some View {
        Section {
            AppCardSectionTitle(title: "エントリー", systemImage: "person.badge.plus", accentColor: AppSectionAccent.scan,
                                infoTitle: "エントリー", infoMessage: "申し込みの期間がある大会で使います。大会にこのルールを選ぶと、エントリーの期間を最初の投稿開始（生大喜利は開始）の前に入れます。")
                .listRowSeparator(.hidden)
            Toggle(isOn: Binding(get: { draft.entryDays != nil }, set: { draft.entryDays = $0 ? (draft.entryDays ?? 7) : nil })) {
                GiriEditorLabel("エントリーの期間がある")
            }
            .tint(AppSectionAccent.scan)
            if let days = draft.entryDays {
                Stepper(value: Binding(get: { days }, set: { draft.entryDays = $0 }), in: 1...365) {
                    HStack { GiriEditorLabel("期間"); Spacer(minLength: 8); Text("\(days)日").font(.subheadline) }
                }
                GiriOptionalStepper(title: "定員", unit: "人", value: $draft.capacity, range: 1...10000, initial: 32)
                HStack(spacing: 12) {
                    GiriEditorLabel("決まり")
                    TextField("例：先着順・取り下げ不可", text: $draft.entryNote, axis: .vertical).multilineTextAlignment(.trailing).lineLimit(1...4)
                }
            }
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.scan)
    }

    private var planSection: some View {
        Section {
            AppCardSectionTitle(title: "プレーオフ・入れ替え戦", systemImage: "trophy", accentColor: AppSectionAccent.favorite,
                                infoTitle: "プレーオフ・入れ替え戦",
                                infoMessage: "最後の通常回の投票締切から何日後に始まるかで決めます。シーズンを始める時に日程を自動で作ります（1シーズンの回数が決まっている時）。")
                .listRowSeparator(.hidden)
            ForEach($draft.specialPlans) { $plan in
                planRow($plan)
            }
            Button("プレーオフ・入れ替え戦を追加", systemImage: "plus.circle") {
                draft.specialPlans.append(GiriRuleSpecialPlan(submissionDays: draft.submissionDays, votingDays: draft.votingDays))
            }
            .buttonStyle(.borderless).tint(accentActionColor)
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.favorite)
    }

    private func planRow(_ plan: Binding<GiriRuleSpecialPlan>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("種類", selection: plan.kind) {
                    ForEach(SitePeriodKind.allCases.filter { $0 != .regular }) { Text($0.title).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).tint(Color.primary)
                TextField("名前（任意）", text: plan.title)
                Button(role: .destructive) { draft.specialPlans.removeAll { $0.id == plan.wrappedValue.id } } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
            }
            Stepper("最後の回の投票締切から　\(plan.wrappedValue.startOffsetDays)日後", value: plan.startOffsetDays, in: 0...365)
            Stepper("投稿　\(plan.wrappedValue.submissionDays)日", value: plan.submissionDays, in: 1...365)
            Stepper("投票　\(plan.wrappedValue.votingDays)日", value: plan.votingDays, in: 1...365)
            Stepper("回数　\(plan.wrappedValue.count)回", value: plan.count, in: 1...20)
            // 0.27：出る人（上位何人・どのリーグから）・順位の決め方・シーズンの成績に含めるか。
            GiriOptionalStepper(title: "出る人　上位", unit: "人", value: plan.entrantCount, range: 1...200, initial: 8)
            if !draft.leagues.isEmpty {
                Picker(selection: plan.entrantLeague) {
                    Text("すべて").tag("")
                    ForEach(draft.leagues.filter { !$0.isEmpty }, id: \.self) { Text($0).tag($0) }
                } label: { GiriEditorLabel("出るリーグ") }
                .pickerStyle(.menu).tint(Color.primary)
            }
            Picker(selection: plan.ranking) {
                Text("シーズンと同じ").tag("")
                ForEach(GiriRuleScoring.allCases) { Text($0.title).tag($0.rawValue) }
            } label: { GiriEditorLabel("順位の決め方") }
            .pickerStyle(.menu).tint(Color.primary)
            GiriOptionalStepper(title: "1人", unit: "回答まで", value: plan.answersPerEntrant, range: 1...20, initial: 2)
            Toggle(isOn: plan.countsInSeason) { GiriEditorLabel("シーズンの成績に含める") }
                .tint(AppSectionAccent.favorite)
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }

    private var tournamentSection: some View {
        Section {
            AppCardSectionTitle(title: "大会", systemImage: "trophy", accentColor: AppSectionAccent.live)
                .listRowSeparator(.hidden)
            Picker(selection: $draft.tournamentFormat) {
                ForEach(TournamentFormat.allCases) { Text($0.title).tag($0) }
            } label: { GiriEditorLabel("参加形式") }
            .pickerStyle(.menu).tint(Color.primary)
            if draft.kind == .online && draft.tournamentFormat != .individual {
                // 0.27：ネットのチーム戦は、チームで回答を出すか、各自の回答を合計するか。
                Picker(selection: Binding(get: { draft.teamAnswerStyle ?? "" }, set: { draft.teamAnswerStyle = $0.isEmpty ? nil : $0 })) {
                    Text("未設定").tag("")
                    ForEach(GiriRule.teamAnswerStyles, id: \.value) { Text($0.title).tag($0.value) }
                } label: { GiriEditorLabel("チームの回答") }
                .pickerStyle(.menu).tint(Color.primary)
            }
            if draft.kind == .live {
                Toggle("トーナメント", isOn: $draft.knockout).tint(AppSectionAccent.live)
            }
            if draft.tournamentFormat != .individual {
                // 0.28：途中でメンバーを増やせる・入れ替えられる大会（段階ごとに決める）。
                Toggle(isOn: $draft.hasMemberChanges) { GiriEditorLabel("途中でメンバーが変わる") }
                    .tint(AppSectionAccent.live)
            }
            TextField("審査方法（例：拍手審査・投票）", text: $draft.judging)
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.live)
    }

    /// 0.24：大会の流れ（予選→本戦→決勝など）を見ながら組み立てる。
    /// 0.28：流れは上から下へ縦に並べ、段階を押すとその下に詳しい入力の行を出す。
    private var stageSection: some View {
        Section {
            AppCardSectionTitle(title: "大会の流れ", systemImage: "arrow.triangle.branch", accentColor: AppSectionAccent.ticket,
                                infoTitle: "大会の流れ", infoMessage: "上から順に進みます。下のボタンで段階を足すと、決勝の前など流れに合う場所に入ります。段階を押すと、名前・形式・勝ち抜けの条件を直せます。")
                .listRowSeparator(.hidden)
            if draft.stages.isEmpty {
                Text("段階がありません").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(draft.stages.enumerated()), id: \.element.id) { index, stage in
                stageListRow(index, stage)
                if stage.id == selectedStageID { stageDetailRows(index) }
            }
            addStageRow
            Menu {
                ForEach(giriRuleTemplates.filter { $0.kind == draft.kind && $0.effectiveScope == .tournament && !$0.stages.isEmpty }) { template in
                    Button(template.name) {
                        draft.stages = template.stages.map { var stage = $0; stage.id = UUID().uuidString; return stage }
                        selectedStageID = nil
                    }
                }
            } label: {
                Label("よくある流れから選ぶ", systemImage: "square.on.square").font(.subheadline)
            }
            .tint(accentActionColor)
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.ticket)
    }

    private func stageAccent(_ stage: GiriRuleStage) -> Color {
        stage.stageKind == .repechage ? AppSectionAccent.favorite : stage.stageKind == .final ? AppSectionAccent.live : AppSectionAccent.ticket
    }

    /// 段階の1行（番号・名前・形式と勝ち抜け）。押すと下に詳しい入力を開く。
    private func stageListRow(_ index: Int, _ stage: GiriRuleStage) -> some View {
        let selected = stage.id == selectedStageID
        let accent = stageAccent(stage)
        let caption = [stage.lineup.isEmpty ? nil : stage.lineup,
                       stage.promptCount.map { "お題\($0)問" },
                       stage.advanceText.map { $0 + "が勝ち抜け" },
                       draft.hasMemberChanges ? stage.memberChangeText : nil].compactMap { $0 }.joined(separator: "・")
        return Button { selectedStageID = selected ? nil : stage.id } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 2) {
                    Text("\(index + 1)")
                        .font(.subheadline.weight(.bold)).monospacedDigit()
                        .foregroundStyle(selected ? Color.white : accent)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(selected ? accent : accent.opacity(0.14)))
                    if index + 1 < draft.stages.count {
                        Image(systemName: "arrow.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(stageTitle(stage)).font(.body.weight(.semibold)).foregroundStyle(.primary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    if !caption.isEmpty {
                        Text(caption).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(index + 1)番目の段階：" + stageTitle(stage))
    }

    private var addStageRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StageKind.allCases) { kind in
                    Button {
                        let stage = giriRuleStage(kind, name: kind == .repechage ? "敗者復活戦" : nil)
                        draft.stages = giriRuleInsertingStage(stage, into: draft.stages)
                        selectedStageID = stage.id
                    } label: {
                        Label(kind.title, systemImage: "plus").font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(accentActionColor.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(accentActionColor)
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// 0.28：選んだ段階の詳しい入力。ライブ登録と同じく、名前は左に小さく、入力は右に置いた行にする。
    @ViewBuilder private func stageDetailRows(_ index: Int) -> some View {
        let stage = Binding(get: { draft.stages.indices.contains(index) ? draft.stages[index] : GiriRuleStage() },
                            set: { if draft.stages.indices.contains(index) { draft.stages[index] = $0 } })
        HStack(spacing: 12) {
            GiriEditorLabel("段階の名前")
            TextField("例：予選1回戦", text: stage.name).multilineTextAlignment(.trailing)
        }
        .padding(.leading, 40)
        Picker(selection: Binding(get: { stage.wrappedValue.kind ?? "" }, set: { stage.wrappedValue.kind = $0.isEmpty ? nil : $0 })) {
            Text("未設定").tag("")
            ForEach(StageKind.allCases) { Text($0.title).tag($0.rawValue) }
        } label: { GiriEditorLabel("種類") }
        .pickerStyle(.menu).tint(Color.primary)
        .padding(.leading, 40)
        HStack(spacing: 12) {
            GiriEditorLabel("形式")
            TextField("例：横並び5人", text: stage.lineup).multilineTextAlignment(.trailing)
            Menu {
                ForEach(giriRuleStageLineups, id: \.self) { lineup in Button(lineup) { stage.wrappedValue.lineup = lineup } }
            } label: { Image(systemName: "list.bullet.circle").font(.body) }
            .accessibilityLabel("形式を選ぶ")
            .tint(accentActionColor)
        }
        .padding(.leading, 40)
        HStack(spacing: 12) {
            GiriEditorLabel("審査方法")
            TextField("大会と同じ", text: stage.judging).multilineTextAlignment(.trailing)
        }
        .padding(.leading, 40)
        Stepper(value: Binding(get: { stage.wrappedValue.promptCount ?? 0 }, set: { stage.wrappedValue.promptCount = $0 == 0 ? nil : $0 }), in: 0...30) {
            HStack {
                GiriEditorLabel("お題の数")
                Spacer(minLength: 8)
                Text(stage.wrappedValue.promptCount.map { "\($0)問" } ?? "未定").font(.subheadline).monospacedDigit()
            }
        }
        .padding(.leading, 40)
        GiriAdvanceRows(count: stage.advanceCount, fraction: stage.advanceFraction, accent: AppSectionAccent.ticket, title: "勝ち抜け")
            .padding(.leading, 40)
        HStack(spacing: 12) {
            GiriEditorLabel("ほかの条件")
            TextField("例：得票率○%以上", text: stage.advanceNote).multilineTextAlignment(.trailing)
        }
        .padding(.leading, 40)
        if draft.hasMemberChanges && draft.tournamentFormat != .individual {
            Picker(selection: stage.memberChange) {
                Text("変えない").tag("")
                ForEach(giriRuleMemberChanges, id: \.value) { Text($0.title).tag($0.value) }
            } label: { GiriEditorLabel("メンバー") }
            .pickerStyle(.menu).tint(Color.primary)
            .padding(.leading, 40)
            if !stage.wrappedValue.memberChange.isEmpty {
                GiriOptionalStepper(title: "人数", unit: "人まで", value: stage.memberChangeCount, range: 1...10, initial: 1)
                    .padding(.leading, 40)
            }
        }
        HStack(spacing: 20) {
            Button { moveStage(index, by: -1) } label: { Label("上へ", systemImage: "arrow.up") }
                .disabled(index == 0)
            Button { moveStage(index, by: 1) } label: { Label("下へ", systemImage: "arrow.down") }
                .disabled(index + 1 >= draft.stages.count)
            Spacer(minLength: 8)
            Button(role: .destructive) {
                draft.stages.remove(at: index)
                selectedStageID = nil
            } label: { Label("削除", systemImage: "trash") }
        }
        .buttonStyle(.borderless)
        .font(.subheadline)
        .tint(accentActionColor)
        .padding(.leading, 40)
    }

    private func stageTitle(_ stage: GiriRuleStage) -> String {
        let name = stage.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? (stage.stageKind?.title ?? "段階") : name
    }

    private func moveStage(_ index: Int, by offset: Int) {
        let target = index + offset
        guard draft.stages.indices.contains(index), draft.stages.indices.contains(target) else { return }
        draft.stages.swapAt(index, target)
    }

    /// 0.27：リーグ名の空欄を外し、決まりを名前と同じ順にそろえる。
    private func normalized(_ rule: GiriRule) -> GiriRule {
        var value = rule
        var details = value.leagueDetails
        for index in details.indices { details[index].name = details[index].name.trimmingCharacters(in: .whitespacesAndNewlines) }
        value.leagueDetails = details.filter { !$0.name.isEmpty }
        value.leagues = value.leagueDetails.map(\.name)
        if let tag = value.tagDivision {
            // 0.28：タッグのリーグの決まりも、シングルのリーグ名の順にそろえる。
            value.tagDivision?.leagueDetails = value.leagues.map { tag.leagueDetail($0) }
            value.tagDivision?.tieBreak = tag.tieBreak.trimmingCharacters(in: .whitespacesAndNewlines)
            value.tagDivision?.formationNote = tag.formationNote.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        value.entryNote = value.entryNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.entryDays == nil && value.effectiveScope == .tournament { value.capacity = nil }
        value.tieBreak = value.tieBreak.trimmingCharacters(in: .whitespacesAndNewlines)
        for index in value.stages.indices { value.stages[index].advanceNote = value.stages[index].advanceNote.trimmingCharacters(in: .whitespacesAndNewlines) }
        if value.kind == .live { value.scope = .tournament }
        return value
    }

    private func read(_ item: PhotosPickerItem) {
        reading = true
        Task { @MainActor in
            defer { reading = false; photo = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw GiriParticipantReadError.unreadable }
                // 0.29：ツイプラなどの縦に長いページは、縦に分けて読む（小さい文字も読めるように）。
                let lines = try await GiriParticipantOCR.recognizeLines(data)
                let text = giriOCRText(lines)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GiriParticipantReadError.noText }
                let result = giriRuleReadingText(text, into: draft)
                selectedStageID = nil
                if result.found.isEmpty {
                    readSummary = "ルールの項目（日程・段階・勝ち抜けなど）は見つかりませんでした。ルールの説明が写っている部分の画像で試してください。"
                } else {
                    draft = result.rule
                    readSummary = result.found.joined(separator: "・") + " を入れました。違う所は直してから保存してください。"
                }
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        store.run {
            let value = normalized(draft)
            try store.saveRule(value)
            playLiveStairSaveFeedback()
            onSaved?(store.rule(value.id) ?? value)
            original = value
            draft = value
            dismiss()
        }
    }
}

/// 0.27：勝ち抜けの条件（未定・上位○人・上位の割合）。
struct GiriAdvanceRows: View {
    @Binding var count: Int?
    @Binding var fraction: String?
    let accent: Color
    var title = "勝ち抜け"

    private var mode: Binding<String> {
        Binding(get: { count != nil ? "count" : fraction != nil ? "fraction" : "" }, set: { value in
            count = value == "count" ? (count ?? 8) : nil
            fraction = value == "fraction" ? (fraction ?? "1/2") : nil
        })
    }

    var body: some View {
        Picker(selection: mode) {
            Text("未定").tag("")
            Text("上位○人").tag("count")
            Text("上位の割合").tag("fraction")
        } label: { GiriEditorLabel(title) }
        .pickerStyle(.menu).tint(Color.primary)
        if let value = count {
            Stepper(value: Binding(get: { value }, set: { count = $0 }), in: 1...500) {
                HStack {
                    GiriEditorLabel("人数")
                    Spacer(minLength: 8)
                    Text("上位\(value)人").font(.subheadline).monospacedDigit()
                }
            }
        }
        if fraction != nil {
            Picker(selection: Binding(get: { fraction ?? "1/2" }, set: { fraction = $0 })) {
                ForEach(giriAdvanceFractions, id: \.value) { Text("上位" + $0.title).tag($0.value) }
            } label: { GiriEditorLabel("割合") }
            .pickerStyle(.menu).tint(Color.primary)
        }
    }
}

/// 0.27：入れない時は「なし」になる数のステッパー（0 で「なし」）。
struct GiriOptionalStepper: View {
    let title: String
    let unit: String
    @Binding var value: Int?
    let range: ClosedRange<Int>
    let initial: Int

    var body: some View {
        Stepper(title + "　" + (value.map { "\($0)" + unit } ?? "なし"),
                value: Binding(get: { value ?? (range.lowerBound - 1) }, set: { value = $0 < range.lowerBound ? nil : $0 }),
                in: (range.lowerBound - 1)...range.upperBound)
    }
}

/// ルールを選ぶメニュー（なし・保存したルール・新しく作る）。
struct GiriRuleMenuPicker: View {
    @EnvironmentObject private var store: GiriStore
    let kind: GiriRuleKind
    /// 0.27：通常（サイトのシーズン）か大会か。
    var scope: GiriRuleScope = .regular
    let selectedID: String?
    var noneTitle = "選ばない"
    let onSelect: (String?) -> Void
    let onCreate: () -> Void

    var body: some View {
        Menu {
            Button(noneTitle) { onSelect(nil) }
            ForEach(store.rules.filter { $0.kind == kind && $0.effectiveScope == (kind == .live ? .tournament : scope) }.sorted { $0.updatedAt > $1.updatedAt }) { rule in
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

// MARK: - 0.29 ルールの中身（登録・詳細・読み取りの確認で同じ書き方にする）

/// ルールの中身を、ルールの編集画面で入れた項目と同じ順に並べて見せる。
struct GiriRuleDetailRows: View {
    let rule: GiriRule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            line("種類", rule.kind.title + "・" + rule.effectiveScope.title)
            if rule.effectiveScope == .tournament {
                line("参加形式", rule.tournamentFormat.title)
                if rule.kind == .live && rule.knockout { line("対戦形式", "トーナメント") }
                if let style = rule.teamAnswerStyle, let title = GiriRule.teamAnswerStyles.first(where: { $0.value == style })?.title { line("チームの回答", title) }
                if rule.hasMemberChanges { line("メンバー", "途中で変わる") }
            }
            if !rule.judging.isEmpty { line("審査方法", rule.judging) }
            if rule.kind == .online {
                line("日程", (rule.effectiveScope == .regular ? rule.timing.title + "・" : "") + "投稿\(rule.submissionDays)日・投票\(rule.votingDays)日")
                if let count = rule.regularCycleCount { line("1シーズン", "全\(count)回") }
            }
            if let days = rule.entryDays {
                line("エントリー", "\(days)日" + (rule.capacity.map { "・定員\($0)人" } ?? ""))
            }
            if !rule.entryNote.isEmpty { note(rule.entryNote) }
            if !rule.stages.isEmpty {
                heading("大会の流れ")
                ForEach(Array(rule.stages.enumerated()), id: \.element.id) { index, stage in
                    stageLine(index, stage)
                }
            }
            if !rule.leagueDetails.isEmpty || !rule.leagues.isEmpty {
                heading("リーグ")
                ForEach(rule.leagues, id: \.self) { name in
                    let detail = rule.leagueDetail(name)
                    line(name, detail.summary.isEmpty ? "決まりなし" : detail.summary)
                }
            }
            if let tag = rule.tagDivision {
                heading(tag.name + "部門")
                note(tag.summary)
                ForEach(rule.leagues, id: \.self) { name in
                    let detail = tag.leagueDetail(name)
                    if !detail.summary.isEmpty { line(name, detail.summary) }
                }
                if !tag.tieBreak.isEmpty { note(tag.tieBreak) }
                if !tag.formationNote.isEmpty { note(tag.formationNote) }
            }
            if rule.usesScoring {
                heading("成績の出し方")
                line("順位の決め方", rule.scoring.title)
                if rule.scoring == .topRequired, let required = rule.requiredAnswerCount { line("規定回答数", "\(required)回答") }
                if let advance = giriAdvanceText(count: rule.advanceCount, fraction: rule.advanceFraction) { line("勝ち抜け", advance) }
                if !rule.tieBreak.isEmpty { line("同率の時", rule.tieBreak) }
                if let bonus = rule.voteBonusPoints { line("投票ボーナス", "\(bonus)点") }
            }
            if !rule.specialPlans.isEmpty {
                heading("プレーオフ・入れ替え戦など")
                ForEach(rule.specialPlans) { plan in line(plan.displayTitle, plan.detailText) }
            }
            if !rule.memo.isEmpty { note(rule.memo) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.bold)).foregroundStyle(AppSectionAccent.ticket).padding(.top, 4)
    }

    private func line(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .leading)
            Text(value).font(.subheadline).foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .trailing).multilineTextAlignment(.trailing)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func stageLine(_ index: Int, _ stage: GiriRuleStage) -> some View {
        let name = stage.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (stage.stageKind?.title ?? "段階") : stage.name
        let details = [stage.lineup.isEmpty ? nil : stage.lineup,
                       stage.judging.isEmpty ? nil : stage.judging,
                       stage.promptCount.map { "お題\($0)問" },
                       stage.advanceText.map { $0 + "が勝ち抜け" },
                       stage.advanceNote.isEmpty ? nil : stage.advanceNote,
                       rule.hasMemberChanges ? stage.memberChangeText : nil].compactMap { $0 }
        return HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)").font(.caption.weight(.bold)).monospacedDigit()
                .foregroundStyle(AppSectionAccent.ticket)
                .frame(width: 22, height: 22)
                .background(Circle().fill(AppSectionAccent.ticket.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.semibold))
                if !details.isEmpty {
                    Text(details.joined(separator: "・")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
