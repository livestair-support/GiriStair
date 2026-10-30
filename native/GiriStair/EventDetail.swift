import SwiftUI
import UIKit

/// Native detail rows reuse LiveDetailView's Form sections and toolbar editing.
struct GiriEventDetail: View {
    @EnvironmentObject private var store: GiriStore
    @EnvironmentObject private var navigation: GiriNavigation
    @Environment(\.dismiss) private var dismiss
    let eventID: String
    @State private var deleteQuestion = false
    @State private var showResultPrompt = false
    @State private var promptRoundID: String?
    @State private var showResultEditor = false
    @State private var showCycleEditor = false
    @State private var nextDraft: GiriRoundDraftAction?

    private var event: GiriEvent? { store.events.first { $0.id == eventID } }

    var body: some View {
        Group {
            if let event {
                Form {
                    basic(event)
                    if !event.participants.isEmpty && !(event.eventFormat.isOnline && event.meetingType == .tournament) { participants(event) }
                    teams(event)
                    thoughtsLink(event)
                    if event.eventFormat.hasOnlineRounds {
                        ForEach(event.effectiveRounds) { round in
                            roundSection(event, round: round)
                        }
                        if event.meetingType == .tournament {
                            Section {
                                Button { nextDraft = .nextStage } label: { Label("次の段階を追加", systemImage: "plus.circle") }
                                if !event.effectiveRounds.isEmpty {
                                    Button { nextDraft = .sameStage } label: { Label("同じ段階の次回を追加", systemImage: "plus.square.on.square") }
                                }
                            }.appEventDetailCardStyle(accentColor: AppSectionAccent.artist)
                        }
                    }
                    if event.meetingType == .casual && event.onlineSiteId != nil { cycleResults(event) }
                    if event.meetingType == .tournament { resultSections(event) }
                    if !event.memo.isEmpty {
                        Section {
                            GiriEventCardSectionTitle(title: "メモ", systemImage: "text.alignleft", accentColor: AppSectionAccent.memo).listRowSeparator(.hidden)
                            Text(event.memo).textSelection(.enabled)
                        }.appEventDetailCardStyle(accentColor: AppSectionAccent.memo)
                    }
                }
                .appEditorFormStyle()
            } else {
                CenteredEmptyMessage(systemImage: "calendar", title: "記録がありません")
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(appBackgroundColor)
            }
        }
        .navigationTitle("詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if let event {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { GiriEventEditor(event: event) } label: { Text("編集") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ShareLink(item: shareText(event)) { Label("共有", systemImage: "square.and.arrow.up") }
                        Divider()
                        Button("削除", systemImage: "trash", role: .destructive) { deleteQuestion = true }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("記録の操作")
                }
            }
        }
        .confirmationDialog("この記録を削除しますか？", isPresented: $deleteQuestion, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                do {
                    try store.deleteEvent(eventID)
                    playLiveStairDeleteFeedback()
                    dismiss()
                } catch { store.errorMessage = error.localizedDescription }
            }
            Button("キャンセル", role: .cancel) {}
        } message: { Text("お題と回答のメモは残ります。") }
        .task { offerResultIfNeeded() }
        .alert("結果を入力しますか？", isPresented: $showResultPrompt) {
            Button("後で", role: .cancel) {}
            Button("入力する") {
                if event?.meetingType == .casual && event?.onlineSiteId != nil { showCycleEditor = true }
                else { showResultEditor = true }
            }
        } message: { Text(resultPromptMessage) }
        .sheet(isPresented: $showResultEditor) {
            NavigationStack { GiriResultEntry(eventID: eventID, initialRoundID: promptRoundID) }
        }
        .sheet(isPresented: $showCycleEditor) { NavigationStack { GiriCycleResultEditor(eventID: eventID) } }
        .sheet(item: $nextDraft) { action in
            NavigationStack { GiriNextRoundEditor(eventID: eventID, sameStage: action == .sameStage) }
        }
    }

    private func basic(_ event: GiriEvent) -> some View {
        Section {
            GiriEventCardSectionTitle(title: "基本情報", systemImage: "slider.horizontal.3", accentColor: AppSectionAccent.live).listRowSeparator(.hidden)
            detailValue("形式", event.eventFormat.title)
            detailValue("会の種類", event.meetingType.title)
            if !event.isActualParticipant && event.status != .canceled {
                Button {
                    guard var current = self.event else { return }
                    current.isParticipating = true
                    current.isInterested = false
                    if current.status == .canceled { current.status = .planned }
                    let me = store.preferences.selfName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !me.isEmpty && !current.participants.contains(where: { playerSearchKey($0) == playerSearchKey(me) }) {
                        current.participants.append(me)
                    }
                    store.run {
                        try store.saveEvent(current)
                        playLiveStairSaveFeedback()
                    }
                } label: { Label("この回に参加する", systemImage: "person.badge.plus") }
                    .tint(accentActionColor)
            }
            if event.eventFormat == .live {
                Picker("参加", selection: participationChoice) {
                    Text("参加").tag("participating")
                    Text("興味あり").tag("interested")
                    Text("キャンセル").tag("canceled")
                }.pickerStyle(.menu).tint(.primary)
            }
            detailValue("参加状況", event.participationState().title)
            adaptiveName(event.title)
            if !event.organizer.isEmpty {
                if let player = store.playerByName(event.organizer) {
                    NavigationLink { GiriPlayerDetail(playerID: player.id) } label: {
                        HStack { Text("主催者").foregroundStyle(.secondary); Spacer(); detailValueText(event.organizer) }
                    }
                } else { detailValue("主催者", event.organizer) }
            }
            if event.eventFormat.hasLiveTiming {
                if let day = event.eventDate ?? event.startsAt {
                    HStack {
                        Text("日付").foregroundStyle(.secondary)
                        Spacer()
                        Text(giriDetailDate(day))
                            .font(.body.weight(.semibold))
                            .foregroundColor(liveDateWeekdayColor(day))
                            .multilineTextAlignment(.trailing)
                    }
                } else { detailValue("日付", "未定") }
                NavigationLink { GiriLiveTimingEditor(eventID: eventID) } label: {
                    HStack {
                        Text("開始").foregroundStyle(.secondary)
                        Spacer()
                        detailValueText(giriDetailTime(event.startsAt))
                        Text("終了").foregroundStyle(.secondary).padding(.leading, 16)
                        Spacer()
                        detailValueText(giriDetailTime(event.endsAt))
                    }
                }
                if (event.eventFormat == .live || event.eventFormat == .hybrid), let venue = store.venueDirectory.first(where: { $0.id == event.venueId || $0.name == event.venue && !event.venue.isEmpty }) {
                    NavigationLink { GiriVenueDetail(venueID: venue.id) } label: {
                        HStack {
                            Text("会場").foregroundStyle(.secondary)
                            Spacer()
                            detailValueText(venue.name + (venue.prefecture.isEmpty ? "" : "（\(venue.prefecture)）"))
                                .lineLimit(1).minimumScaleFactor(0.62).allowsTightening(true)
                        }
                    }
                } else if event.eventFormat == .live || event.eventFormat == .hybrid { detailValue("会場", event.venue.isEmpty ? "未設定" : event.venue) }
            }
            if event.eventFormat != .live {
                if !event.siteUrl.isEmpty, let url = URL(string: event.siteUrl), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                    Link(destination: url) { Label(event.siteUrl, systemImage: "globe").lineLimit(2) }
                }
                if !event.affiliation.isEmpty { detailValue("所属・部", event.affiliation) }
                if !event.block.isEmpty { detailValue("ブロック", event.block) }
            }
        }.appEventDetailCardStyle(accentColor: AppSectionAccent.live)
    }

    private func participants(_ event: GiriEvent) -> some View {
        Section {
            GiriEventCardSectionTitle(title: "参加者", systemImage: "person.2", accentColor: AppSectionAccent.artist)
                .overlay(alignment: .trailing) { Text("\(event.participants.count)人").font(.subheadline).foregroundStyle(.secondary) }
                .listRowSeparator(.hidden)
            ForEach(Array(event.participants.enumerated()), id: \.offset) { _, name in
                playerRow(name)
            }
        }.appEventDetailCardStyle(accentColor: AppSectionAccent.artist)
    }

    @ViewBuilder private func teams(_ event: GiriEvent) -> some View {
        ForEach(event.teams) { team in
            Section {
                GiriEventCardSectionTitle(title: team.name.isEmpty ? (team.isMine || event.myTeamId == team.id ? "自分のチーム" : "チーム") : team.name,
                                    systemImage: team.isMine || event.myTeamId == team.id ? "person.3.fill" : "person.3", accentColor: AppSectionAccent.artist)
                    .listRowSeparator(.hidden)
                ForEach(Array(team.members.enumerated()), id: \.offset) { _, name in playerRow(name) }
            }.appEventDetailCardStyle(accentColor: AppSectionAccent.artist)
        }
        if event.teams.isEmpty, let legacy = event.tournamentResult, legacy.format != .individual,
           !legacy.members.isEmpty || !legacy.teamName.isEmpty {
            Section {
                GiriEventCardSectionTitle(title: legacy.teamName.isEmpty ? "自分のチーム" : legacy.teamName, systemImage: "person.3.fill", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                ForEach(Array(legacy.members.enumerated()), id: \.offset) { _, name in playerRow(name) }
            }.appEventDetailCardStyle(accentColor: AppSectionAccent.artist)
        }
    }

    @ViewBuilder private func playerRow(_ name: String) -> some View {
        if let player = store.playerByName(name) {
            NavigationLink { GiriPlayerDetail(playerID: player.id) } label: {
                HStack(spacing: 10) {
                    if store.showPlayerIcons {
                        if let data = Data(base64Encoded: player.iconDataBase64), let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 32, height: 32).clipShape(Circle())
                        } else {
                            Image(systemName: "person.fill").foregroundStyle(AppSectionAccent.artist).frame(width: 32, height: 32)
                                .background(AppSectionAccent.artist.opacity(0.14)).clipShape(Circle())
                        }
                    }
                    Text(name).foregroundStyle(.primary)
                }
            }
        } else { Text(name) }
    }

    @ViewBuilder private func resultSections(_ event: GiriEvent) -> some View {
        Section {
            HStack {
                GiriEventCardSectionTitle(title: "自分の結果", systemImage: "trophy", accentColor: AppSectionAccent.ticket)
                NavigationLink { GiriResultEntry(eventID: eventID) } label: { Text(event.hasRecordedResult ? "編集" : "記録").font(.subheadline) }
                    .tint(accentActionColor)
            }.listRowSeparator(.hidden)
            if event.hasFinalResult {
                detailValue("最終結果", event.tournamentResult?.outcome.title ?? (event.placement == nil ? "未記録" : "\(event.placement ?? 0)位"))
            } else {
                detailValue("進行状況", latestProgress(event))
            }
            if let rank = event.effectivePlacement { detailValue("最終順位", "\(rank)位") }
            if let result = event.tournamentResult, !result.memo.isEmpty { Text(result.memo).textSelection(.enabled) }
            else if !event.resultText.isEmpty { Text(event.resultText).textSelection(.enabled) }
            ForEach(event.tournamentResult?.stages ?? []) { stage in
                NavigationLink { GiriResultEntry(eventID: eventID, initialRoundID: stage.roundId, initialStageID: stage.id) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stage.name).font(.headline).foregroundStyle(.primary)
                        HStack(spacing: 10) {
                            if stage.outcome != .unrecorded { Text(stage.outcome.title) }
                            if let rank = stage.placement { Text("\(rank)位") }
                            if let rank = stage.teamPlacement { Text("チーム\(rank)位") }
                            if let rank = stage.individualPlacement { Text("個人\(rank)位") }
                        }.font(.subheadline).foregroundStyle(.secondary)
                        if let rate = stage.voteRate {
                            Text("得票率 " + rate.formatted(.number.precision(.fractionLength(2))) + "%")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        if !stage.memo.isEmpty { Text(stage.memo).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
            }
        }.appEventDetailCardStyle(accentColor: AppSectionAccent.ticket)
        if !event.standings.isEmpty {
            Section {
                GiriEventCardSectionTitle(title: "大会の上位成績", systemImage: "medal", accentColor: AppSectionAccent.ticket).listRowSeparator(.hidden)
                ForEach(event.standings.sorted { $0.placement < $1.placement }) { standing in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(standing.placement == 1 ? "優勝" : standing.placement == 2 ? "準優勝" : "\(standing.placement)位").font(.headline)
                            if !standing.teamName.isEmpty { Text(standing.teamName).font(.headline) }
                        }
                        ForEach(Array(standing.playerNames.enumerated()), id: \.offset) { _, name in playerRow(name) }
                        if !standing.memo.isEmpty { Text(standing.memo).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
            }.appEventDetailCardStyle(accentColor: AppSectionAccent.ticket)
        }
    }

    // LiveDetailView.swift adaptiveEventNameRow and detailValueText.
    private func adaptiveName(_ value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text("会・大会名").foregroundStyle(.secondary)
                Spacer(minLength: 16)
                detailValueText(value)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("会・大会名").foregroundStyle(.secondary)
                detailValueText(value)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
        }
        .textSelection(.enabled)
    }

    private func detailValueText(_ value: String) -> some View {
        Text(value.isEmpty ? "未設定" : value)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.trailing)
    }

    private func detailValue(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            detailValueText(value)
        }
    }

    private var participationChoice: Binding<String> {
        Binding(get: {
            guard let event else { return "participating" }
            return event.status == .canceled ? "canceled" : event.isInterested ? "interested" : "participating"
        }, set: { value in
            guard var current = event else { return }
            current.isInterested = value == "interested"
            current.isParticipating = value == "participating"
            if value == "canceled" { current.status = .canceled }
            else if current.status == .canceled || value == "interested" { current.status = .planned }
            store.run { try store.saveEvent(current) }
        })
    }

    private func roundTitle(_ round: EventRound) -> String { "\(round.name) \(round.promptNumber)回目" }

    private func thoughtsLink(_ event: GiriEvent) -> some View {
        Section {
            GiriEventCardSectionTitle(title: "お題・回答", systemImage: "lightbulb", accentColor: AppSectionAccent.memo).listRowSeparator(.hidden)
            Button { navigation.openThoughts(eventID: event.id) } label: {
                HStack {
                    Label("思考でお題・回答を開く", systemImage: "arrow.up.forward.square")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
            }.tint(accentActionColor)
        }.appEventDetailCardStyle(accentColor: AppSectionAccent.memo)
    }

    private func roundSection(_ event: GiriEvent, round: EventRound) -> some View {
        Section {
            GiriEventCardSectionTitle(title: roundTitle(round), systemImage: "calendar", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
            if !round.block.isEmpty { detailValue("ブロック", round.block) }
            scheduleValue("投稿開始", round.submissionStart)
            scheduleValue("投稿締切", round.submissionEnd)
            scheduleValue("投票開始", round.votingStart)
            scheduleValue("投票締切", round.votingEnd)
            NavigationLink("日程を編集") { GiriRoundEditor(eventID: eventID, round: round) }
            Button { navigation.openThoughts(eventID: eventID, roundID: round.id) } label: {
                Label("この回のお題・回答を思考で開く", systemImage: "lightbulb")
            }.tint(accentActionColor)
            if event.meetingType == .tournament {
                NavigationLink { GiriResultEntry(eventID: eventID, initialRoundID: round.id) } label: {
                    HStack {
                        Text("この回の結果")
                        Spacer()
                        Text(roundResult(event, round: round)).foregroundStyle(.secondary)
                    }
                }
            }
        }.appEventDetailCardStyle(accentColor: AppSectionAccent.artist)
    }

    private func scheduleValue(_ title: String, _ date: Date?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(GiriDateText.dateTime(date)).font(.subheadline).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
    }

    private func cycleResults(_ event: GiriEvent) -> some View {
        Section {
            GiriEventCardSectionTitle(title: "この回の結果", systemImage: "chart.bar", accentColor: AppSectionAccent.ticket).listRowSeparator(.hidden)
            if !event.affiliation.isEmpty { detailValue("今回の所属", event.affiliation) }
            if let placement = event.cyclePlacement { detailValue("順位", "\(placement)位") }
            if !event.cycleResult.isEmpty { Text(event.cycleResult).textSelection(.enabled) }
            if !event.nextAffiliation.isEmpty { detailValue("次回の所属", event.nextAffiliation) }
            NavigationLink(event.cycleResult.isEmpty && event.cyclePlacement == nil ? "結果を入力" : "結果を編集") { GiriCycleResultEditor(eventID: eventID) }
        }.appEventDetailCardStyle(accentColor: AppSectionAccent.ticket)
    }

    private func roundResult(_ event: GiriEvent, round: EventRound) -> String {
        guard let stage = event.tournamentResult?.stages.first(where: { $0.roundId == round.id && $0.hasRecord }) else { return "未入力" }
        var values: [String] = []
        if stage.outcome != .unrecorded { values.append(stage.outcome.title) }
        if let placement = stage.placement { values.append("\(placement)位") }
        return values.isEmpty ? "入力済み" : values.joined(separator: "・")
    }

    private func latestProgress(_ event: GiriEvent) -> String {
        let stages = event.tournamentResult?.stages ?? []
        for round in event.effectiveRounds.reversed() {
            if let stage = stages.first(where: { $0.roundId == round.id && $0.outcome != .unrecorded }) { return stage.outcome.title }
        }
        return stages.last(where: { $0.outcome != .unrecorded })?.outcome.title ?? "未記録"
    }

    private func offerResultIfNeeded() {
        guard let event, event.isActualParticipant else { return }
        guard event.meetingType == .tournament || event.onlineSiteId != nil else { return }
        let now = Date()
        if event.eventFormat.hasOnlineRounds && !event.effectiveRounds.isEmpty {
            let finished = event.effectiveRounds.filter { round in
                guard let end = round.votingEnd, end <= now else { return false }
                let key = "round:" + round.id
                guard !event.promptedResultKeys.contains(key) else { return false }
                if event.meetingType == .casual { return event.cycleResult.isEmpty && event.cyclePlacement == nil }
                return !event.hasRecordedResult(for: round)
            }.sorted { ($0.votingEnd ?? .distantPast) > ($1.votingEnd ?? .distantPast) }
            guard let round = finished.first else { return }
            do {
                try store.markResultPrompted(eventID: eventID, key: "round:" + round.id)
                promptRoundID = round.id
                showResultPrompt = true
            } catch { store.errorMessage = error.localizedDescription }
        } else if event.meetingType == .tournament && event.hasEnded() && !event.hasFinalResult && !event.promptedResultKeys.contains("final") {
            do {
                try store.markResultPrompted(eventID: eventID, key: "final")
                promptRoundID = nil
                showResultPrompt = true
            } catch { store.errorMessage = error.localizedDescription }
        }
    }

    private var resultPromptMessage: String {
        if let id = promptRoundID, let round = event?.effectiveRounds.first(where: { $0.id == id }) { return roundTitle(round) }
        return event?.title ?? ""
    }

    private func shareText(_ event: GiriEvent) -> String {
        var lines = [event.title, event.eventFormat.title + "・" + event.meetingType.title]
        if let day = event.eventDate ?? event.startsAt { lines.append(giriDetailDate(day)) }
        if !event.venue.isEmpty { lines.append(event.venue) }
        if !event.siteUrl.isEmpty { lines.append(event.siteUrl) }
        if let outcome = event.tournamentResult?.outcome, outcome != .unrecorded { lines.append(outcome.title) }
        if !event.memo.isEmpty { lines.append(event.memo) }
        return lines.joined(separator: "\n")
    }
}

struct GiriLiveTimingEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    let eventID: String
    @State private var day: Date?
    @State private var start: Date?
    @State private var end: Date?
    @State private var loaded = false
    @State private var originalDay: Date?
    @State private var originalStart: Date?
    @State private var originalEnd: Date?
    @State private var leave = false

    private var dirty: Bool { day != originalDay || start != originalStart || end != originalEnd }
    var body: some View {
        Form {
            Section {
                GiriEventCardSectionTitle(title: "日付・時刻", systemImage: "calendar", accentColor: AppSectionAccent.live).listRowSeparator(.hidden)
                OptionalDateRow(title: "日付", selection: $day, components: .date)
                OptionalDateRow(title: "開始", selection: $start)
                OptionalDateRow(title: "終了", selection: $end)
            }.appEventDetailCardStyle(accentColor: AppSectionAccent.live)
        }.appEditorFormStyle()
            .navigationTitle("日程を編集").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .navigationBarBackButtonHidden(dirty)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if dirty { Button { leave = true } label: { Image(systemName: "chevron.left") }.accessibilityLabel("戻る") }
                }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .onAppear {
                if !loaded, let event = store.events.first(where: { $0.id == eventID }) {
                    day = event.eventDate; start = event.startsAt; end = event.endsAt
                    originalDay = day; originalStart = start; originalEnd = end; loaded = true
                }
            }
            .interactiveDismissDisabled(dirty)
            .alert("変更を保存せず戻りますか？", isPresented: $leave) {
                Button("編集を続ける", role: .cancel) {}
                Button("変更を破棄", role: .destructive) { dismiss() }
            }
    }
    private func save() {
        guard var event = store.events.first(where: { $0.id == eventID }) else { return }
        event.eventDate = day; event.startsAt = start; event.endsAt = end
        do { try giriEditorValidate(event); try store.saveEvent(event); playLiveStairSaveFeedback(); dismiss() }
        catch { store.errorMessage = error.localizedDescription }
    }
}

private func giriDetailDate(_ day: Date) -> String {
    GiriDateText.day(day)
}

private func giriDetailTime(_ date: Date?) -> String {
    GiriDateText.time(date)
}
