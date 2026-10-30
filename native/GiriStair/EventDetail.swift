import SwiftUI
import UIKit

/// Native detail rows reuse LiveDetailView's Form sections and toolbar editing.
struct GiriEventDetail: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    let eventID: String
    @State private var deleteQuestion = false

    private var event: GiriEvent? { store.events.first { $0.id == eventID } }

    var body: some View {
        Group {
            if let event {
                Form {
                    basic(event)
                    if !event.participants.isEmpty { participants(event) }
                    teams(event)
                    if event.kind == .online {
                        ForEach(event.effectiveRounds) { round in
                            GiriRoundWorkspaceSections(eventID: eventID, roundID: round.id)
                        }
                        Section {
                            Button { addRound(event, sameStage: false) } label: { Label(event.meetingType == .tournament ? "次の段階を追加" : "日程を追加", systemImage: "plus.circle") }
                            if event.meetingType == .tournament && !event.effectiveRounds.isEmpty {
                                Button { addRound(event, sameStage: true) } label: { Label("同じ段階のお題を追加", systemImage: "plus.square.on.square") }
                            }
                        }.appEventDetailCardStyle(accentColor: AppSectionAccent.artist)
                    }
                    if event.meetingType == .tournament { resultSections(event) }
                    if !event.memo.isEmpty {
                        Section {
                            GiriEventCardSectionTitle(title: "振り返り", systemImage: "text.alignleft", accentColor: AppSectionAccent.memo).listRowSeparator(.hidden)
                            Text(event.memo).textSelection(.enabled)
                        }.appEventDetailCardStyle(accentColor: AppSectionAccent.memo)
                    }
                    Section {
                        Button("この記録を削除", role: .destructive) { deleteQuestion = true }
                    }.appEventDetailCardStyle(accentColor: AppSectionAccent.live)
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
                    ShareLink(item: shareText(event)) { Image(systemName: "square.and.arrow.up") }
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
    }

    private func basic(_ event: GiriEvent) -> some View {
        Section {
            GiriEventCardSectionTitle(title: "基本情報", systemImage: "slider.horizontal.3", accentColor: AppSectionAccent.live).listRowSeparator(.hidden)
            detailValue("形式", event.kind.title)
            detailValue("会の種類", event.meetingType.title)
            if !event.isParticipating {
                Button {
                    guard var current = self.event else { return }
                    current.isParticipating = true
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
            Picker(selection: Binding(get: { self.event?.status ?? event.status }, set: { value in
                guard var current = self.event else { return }
                current.status = value
                store.run { try store.saveEvent(current) }
            })) {
                ForEach(EventStatus.allCases) { Text($0.title).tag($0) }
            } label: { Text("参加状況").foregroundStyle(.secondary) }
            .pickerStyle(.menu).tint(.primary)
            adaptiveName(event.title)
            if !event.organizer.isEmpty {
                if let player = store.playerByName(event.organizer) {
                    NavigationLink { GiriPlayerDetail(playerID: player.id) } label: {
                        HStack { Text("主催者").foregroundStyle(.secondary); Spacer(); detailValueText(event.organizer) }
                    }
                } else { detailValue("主催者", event.organizer) }
            }
            if event.kind == .live {
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
                if let venue = store.venueDirectory.first(where: { $0.id == event.venueId || $0.name == event.venue && !event.venue.isEmpty }) {
                    NavigationLink { GiriVenueDetail(venueID: venue.id) } label: {
                        HStack {
                            Text("会場").foregroundStyle(.secondary)
                            Spacer()
                            detailValueText(venue.name + (venue.prefecture.isEmpty ? "" : "（\(venue.prefecture)）"))
                                .lineLimit(1).minimumScaleFactor(0.62).allowsTightening(true)
                        }
                    }
                } else { detailValue("会場", event.venue.isEmpty ? "未設定" : event.venue) }
            } else {
                if !event.siteUrl.isEmpty, let url = URL(string: event.siteUrl), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                    Link(destination: url) { Label(event.siteUrl, systemImage: "globe").lineLimit(2) }
                }
                if !event.affiliation.isEmpty { detailValue("所属・部", event.affiliation) }
                if !event.block.isEmpty { detailValue("自分のブロック", event.block) }
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
            detailValue("最終結果", event.tournamentResult?.outcome.title ?? (event.placement == nil ? "未記録" : "\(event.placement ?? 0)位"))
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

    private func addRound(_ event: GiriEvent, sameStage: Bool) {
        var updated = event
        updated.rounds = event.effectiveRounds
        let next = nextEventRound(rounds: updated.rounds, id: UUID().uuidString, preferences: store.preferences, sameStage: sameStage, tournament: event.meetingType == .tournament, referenceDate: event.eventDate ?? Date())
        updated.rounds.append(next)
        store.run { try store.saveEvent(updated) }
    }

    private func shareText(_ event: GiriEvent) -> String {
        var lines = [event.title, event.kind.title + "・" + event.meetingType.title]
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
