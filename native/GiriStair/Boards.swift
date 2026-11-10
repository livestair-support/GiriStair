import SwiftUI
import PhotosUI

// MARK: - 0.25 組み合わせ（ブロック・トーナメント）の編集
// LiveStair のタイムテーブル作成と同じく、≡で人を入れ替えて組を作り、名前を押して勝ち上がりを決める。

@MainActor
struct GiriStageBoardEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Binding var board: GiriStageBoard
    let stage: ResultStage
    /// 組む元の名前（最初の段階は参加者、あとの段階は前の段階の勝ち上がり）。
    let sourceNames: [String]
    let sourceTitle: String
    let knockout: Bool
    /// 次の段階の名前（ある時だけ。なければ足す）。
    let nextStageName: String?
    /// 勝ち上がりを次の段階の組み合わせに入れる。
    let onAdvance: ([String]) -> Void
    @State private var size = 4
    @State private var photo: PhotosPickerItem?
    @State private var reading = false
    @State private var confirmRebuild = false
    @State private var initialized = false

    private var winners: [String] { giriBoardWinners(board) }

    var body: some View {
        List {
            setupSection
            boardSection
            advanceSection
        }
        .environment(\.editMode, .constant(.active))
        .environment(\.defaultMinListRowHeight, settingsMinimumListRowHeight)
        .appIndexListStyle()
        .navigationTitle((stage.name.isEmpty ? "段階" : stage.name) + "の組み合わせ")
        .navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
        .onAppear {
            guard !initialized else { return }
            initialized = true
            size = giriBoardBlockSize(stage, knockout: knockout)
            if board.blocks.isEmpty && !sourceNames.isEmpty { board.blocks = giriBoardBlocks(members: sourceNames, size: size) }
        }
        .onChange(of: photo) { _, item in if let item { read(item) } }
        .alert("組み直しますか？", isPresented: $confirmRebuild) {
            Button("キャンセル", role: .cancel) {}
            Button("組み直す", role: .destructive) { board.blocks = giriBoardBlocks(members: sourceNames, size: size) }
        } message: { Text("今の組と勝ち上がりを消して、" + sourceTitle + "から\(size)人ずつで組み直します。") }
    }

    private var setupSection: some View {
        Section {
            AppCardSectionTitle(title: "組み合わせを作る", systemImage: "square.grid.2x2", accentColor: AppSectionAccent.ticket,
                                infoTitle: "組み合わせについて",
                                infoMessage: "≡で人を入れ替えて組を作り、名前を押すと勝ち上がりになります。勝ち上がりは次の段階の組み合わせに入れられます。")
                .listRowSeparator(.hidden)
                .moveDisabled(true)
            Stepper("1組　\(size)人" + (size == 2 ? "（対戦）" : ""), value: $size, in: 2...20)
                .moveDisabled(true)
            Button {
                if board.blocks.isEmpty { board.blocks = giriBoardBlocks(members: sourceNames, size: size) } else { confirmRebuild = true }
            } label: { Label(sourceTitle + "から組む（\(sourceNames.count)人）", systemImage: "person.3.sequence") }
            .disabled(sourceNames.isEmpty)
            .tint(accentActionColor)
            .moveDisabled(true)
            PhotosPicker(selection: $photo, matching: .images) {
                Label(reading ? "読み取り中…" : "画像から読み取る（ブロック表・トーナメント表）", systemImage: "text.viewfinder")
            }
            .disabled(reading)
            .tint(accentActionColor)
            .moveDisabled(true)
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.ticket)
    }

    private var boardSection: some View {
        let rows = giriBoardRows(board.blocks)
        return Section {
            AppCardSectionTitle(title: "組と勝ち上がり", systemImage: "list.number", accentColor: AppSectionAccent.artist)
                .listRowSeparator(.hidden)
                .moveDisabled(true)
            if board.blocks.isEmpty {
                Text("まだ組がありません。上の「から組む」か画像の読み取りで作ります。").font(.subheadline).foregroundStyle(.secondary)
                    .moveDisabled(true)
            }
            ForEach(rows) { row in rowView(row) }
                .onMove { from, to in
                    var moved = rows
                    moved.move(fromOffsets: from, toOffset: to)
                    board.blocks = giriBoardBlocks(rows: moved, previous: board.blocks)
                }
            Button {
                board.blocks.append(GiriBoardBlock(name: giriBoardBlockName(board.blocks.count, size: size)))
            } label: { Label(size == 2 ? "試合を追加" : "組を追加", systemImage: "plus.circle") }
            .tint(accentActionColor)
            .moveDisabled(true)
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    @ViewBuilder private func rowView(_ row: GiriBoardRow) -> some View {
        switch row {
        case .header(let id):
            if let index = board.blocks.firstIndex(where: { $0.id == id }) {
                HStack(spacing: 8) {
                    TextField("組の名前", text: Binding(get: { board.blocks.indices.contains(index) ? board.blocks[index].name : "" },
                                                     set: { if board.blocks.indices.contains(index) { board.blocks[index].name = $0 } }))
                        .font(.subheadline.weight(.bold))
                    Spacer(minLength: 8)
                    Text("\(board.blocks[index].members.count)人・勝ち上がり\(board.blocks[index].winners.count)人").font(.caption).foregroundStyle(.secondary)
                    Button(role: .destructive) { removeBlock(id) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("この組を削除")
                }
                .moveDisabled(true)
                .listRowBackground(AppSectionAccent.artist.opacity(0.08))
            }
        case .member(let name):
            let blockIndex = board.blocks.firstIndex { block in block.members.contains { playerSearchKey($0) == playerSearchKey(name) } }
            let won = blockIndex.map { board.blocks[$0].winners.contains { playerSearchKey($0) == playerSearchKey(name) } } ?? false
            Button {
                if let blockIndex { board.blocks[blockIndex] = giriBoardTogglingWinner(board.blocks[blockIndex], name: name) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: won ? "crown.fill" : "circle")
                        .foregroundStyle(won ? AppSectionAccent.ticket : Color.secondary)
                        .frame(width: 22)
                    Text(name).font(won ? .body.weight(.bold) : .body).foregroundStyle(.primary)
                    if store.preferences.isSelf(name) {
                        Text("自分").font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(AppSectionAccent.favorite))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(name + (won ? "（勝ち上がり）" : ""))
        }
    }

    private var advanceSection: some View {
        Section {
            AppCardSectionTitle(title: "勝ち上がり", systemImage: "crown", accentColor: AppSectionAccent.ticket)
                .listRowSeparator(.hidden)
                .moveDisabled(true)
            Text(winners.isEmpty ? "名前を押すと勝ち上がりになります。" : winners.joined(separator: "・"))
                .font(.subheadline).foregroundStyle(winners.isEmpty ? Color.secondary : Color.primary)
                .moveDisabled(true)
            if stage.effectiveKind != .final {
                Button {
                    onAdvance(winners)
                    playLiveStairSaveFeedback()
                } label: {
                    Label((nextStageName.map { "「\($0)」" } ?? "次の段階") + "の組み合わせに入れる（\(winners.count)人）", systemImage: "arrow.right.circle")
                }
                .disabled(winners.isEmpty)
                .tint(accentActionColor)
                .moveDisabled(true)
            }
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.ticket)
    }

    private func removeBlock(_ id: String) {
        guard let index = board.blocks.firstIndex(where: { $0.id == id }) else { return }
        let members = board.blocks[index].members
        board.blocks.remove(at: index)
        // 組を消しても人は消さず、前の組（なければ次の組）に移す。
        if !members.isEmpty {
            if index > 0 { board.blocks[index - 1].members += members }
            else if !board.blocks.isEmpty { board.blocks[0].members.insert(contentsOf: members, at: 0) }
        }
    }

    private func read(_ item: PhotosPickerItem) {
        reading = true
        Task { @MainActor in
            defer { reading = false; photo = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw GiriParticipantReadError.unreadable }
                let lines = try await GiriParticipantOCR.recognizeLines(data)
                let known = sourceNames + giriParticipantKnownNames(store)
                let blocks = giriBoardBlocks(lines: lines, known: known, size: size)
                guard !blocks.isEmpty else { throw GiriParticipantReadError.noText }
                board.blocks = blocks
                if let first = blocks.first, blocks.allSatisfy({ $0.members.count == first.members.count }) { size = max(2, first.members.count) }
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - 0.25 トーナメント表（組み合わせの表示）

/// 段階ごとの組み合わせを左から右へ並べる（トーナメントは勝ち上がりが右へ進む）。
struct GiriBoardBracketView: View {
    @EnvironmentObject private var store: GiriStore
    let event: GiriEvent

    private var columns: [(stage: ResultStage, board: GiriStageBoard)] {
        event.stageResults.compactMap { stage in
            guard let board = event.stageBoards.first(where: { $0.id == stage.id }), !board.blocks.isEmpty else { return nil }
            return (stage, board)
        }
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(columns, id: \.stage.id) { column in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(column.stage.name.isEmpty ? column.stage.effectiveKind.title : column.stage.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppSectionAccent.ticket)
                        ForEach(column.board.blocks) { block in blockCard(block) }
                    }
                    .frame(width: 168, alignment: .leading)
                }
            }
            .padding(18)
        }
        .background(appBackgroundColor)
        .navigationTitle("トーナメント表")
        .navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
    }

    private func blockCard(_ block: GiriBoardBlock) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(block.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(block.members, id: \.self) { name in
                let won = block.winners.contains { playerSearchKey($0) == playerSearchKey(name) }
                HStack(spacing: 4) {
                    if won { Image(systemName: "crown.fill").font(.caption2).foregroundStyle(AppSectionAccent.ticket) }
                    Text(name)
                        .font(won ? .subheadline.weight(.bold) : .subheadline)
                        .foregroundStyle(won || block.winners.isEmpty ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if store.preferences.isSelf(name) {
                        Circle().fill(AppSectionAccent.favorite).frame(width: 6, height: 6)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppSectionAccent.ticket.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - 0.25 会の中の結果（ミニトナメ・ミニ組手・総当たりなど）

@MainActor
struct GiriSideResultEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    let eventID: String
    let candidates: [String]
    @State private var draft: GiriSideResult
    @State private var original: GiriSideResult
    @State private var deleting = false
    @State private var discard = false

    init(eventID: String, item: GiriSideResult, candidates: [String]) {
        self.eventID = eventID
        self.candidates = candidates
        _draft = State(initialValue: item)
        _original = State(initialValue: item)
    }

    private var event: GiriEvent? { store.events.first { $0.id == eventID } }
    private var isNew: Bool { !(event?.sideResults.contains { $0.id == draft.id } ?? false) }
    private var changed: Bool { draft != original }

    /// 種類ごとのよくある結果（押すと入る。自由に書ける）。
    private var quickResults: [String] {
        switch draft.kind {
        case "tournament": return ["優勝", "準優勝", "ベスト4", "1回戦敗退"]
        case "kumite": return ["勝ち", "負け", "引き分け"]
        case "roundRobin": return ["1位", "2位", "3位"]
        default: return []
        }
    }

    var body: some View {
        Form {
            Section {
                AppCardSectionTitle(title: "会の中の結果", systemImage: "flag.checkered", accentColor: AppSectionAccent.ticket,
                                    infoTitle: "会の中の結果", infoMessage: "通常会・企画の中で行ったミニトナメ・ミニ組手・総当たりなどの結果です。戦績・集計には入れません。")
                    .listRowSeparator(.hidden)
                Picker(selection: $draft.kind) {
                    ForEach(GiriSideResult.kinds, id: \.value) { Text($0.title).tag($0.value) }
                } label: { GiriEditorLabel("種類") }
                .pickerStyle(.menu).tint(Color.primary)
                TextField("名前（任意。例：ミニトナメ「〇〇杯」）", text: $draft.title)
                TextField("結果（例：優勝・2勝1敗）", text: $draft.result)
                if !quickResults.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(quickResults, id: \.self) { value in
                                Button(value) { draft.result = value }
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Capsule().fill(accentActionColor.opacity(0.1)))
                                    .buttonStyle(.plain)
                                    .foregroundStyle(accentActionColor)
                            }
                        }
                    }
                }
            }
            .appSectionCardStyle(accentColor: AppSectionAccent.ticket)
            Section {
                AppCardSectionTitle(title: "一緒に出た人", systemImage: "person.2", accentColor: AppSectionAccent.artist)
                    .listRowSeparator(.hidden)
                GiriNamesField(title: "", names: $draft.members, priorityNames: candidates.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            }
            .appSectionCardStyle(accentColor: AppSectionAccent.artist)
            Section {
                TextField("メモ", text: $draft.memo, axis: .vertical).lineLimit(2...6)
            }
            .appSectionCardStyle(accentColor: AppSectionAccent.memo)
            if !isNew {
                Section { Button("この結果を削除", role: .destructive) { deleting = true } }
                    .appSectionCardStyle(accentColor: AppSectionAccent.memo)
            }
        }
        .appEditorFormStyle()
        .giriNavigationBarStyle()
        .navigationTitle(isNew ? "結果を追加" : "結果を編集")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(changed)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { if changed { discard = true } else { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).fontWeight(.bold) }
        }
        .giriDiscardChangesAlert(isPresented: $discard) { dismiss() }
        .giriDeleteAlert("結果を削除しますか？", isPresented: $deleting, message: "「\(draft.displayTitle)」の結果を削除します。") {
            guard var event else { return }
            event.sideResults.removeAll { $0.id == draft.id }
            store.run { try store.saveEvent(event); playLiveStairDeleteFeedback(); dismiss() }
        }
    }

    private func save() {
        guard var event else { return }
        var value = draft
        value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.result = value.result.trimmingCharacters(in: .whitespacesAndNewlines)
        value.memo = value.memo.trimmingCharacters(in: .whitespacesAndNewlines)
        value.members = value.members.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if let index = event.sideResults.firstIndex(where: { $0.id == value.id }) { event.sideResults[index] = value } else { event.sideResults.append(value) }
        store.run { try store.saveEvent(event); playLiveStairSaveFeedback(); dismiss() }
    }
}
