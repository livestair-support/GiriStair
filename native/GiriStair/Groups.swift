import SwiftUI

// MARK: - 主催団体（プレイヤーとは別の一覧。LiveStair IndexViews と同じ一覧の形）

struct GiriGroupsView: View {
    @EnvironmentObject private var store: GiriStore
    @State private var query = ""
    @State private var isHeaderCollapsed = false
    @State private var adding = false
    private var groups: [GiriGroup] {
        store.groupDirectory.filter { query.isEmpty || "\($0.name) \($0.furigana) \($0.members.joined(separator: " "))".localizedStandardContains(query) }
    }
    private var sections: [GiriIndexSection<GiriGroup>] {
        let values = Dictionary(grouping: groups) { giriKanaSectionTitle($0.furigana.isEmpty ? $0.name : $0.furigana) }
        return values.keys.sorted { giriKanaSectionOrder($0) < giriKanaSectionOrder($1) }
            .map { GiriIndexSection(id: $0, title: $0, items: values[$0] ?? []) }
    }
    var body: some View {
        let values = sections
        List {
            if values.isEmpty {
                Section {
                    CenteredEmptyMessage(systemImage: "person.3", title: query.isEmpty ? "団体がありません" : "該当する団体がありません")
                }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            }
            ForEach(values) { section in
                Section {
                    AppIndexSectionTitle(title: section.title, count: section.items.count, systemImage: "person.3.fill", accentColor: AppSectionAccent.artist)
                        .listRowSeparator(.hidden)
                    ForEach(section.items) { group in groupRow(group) }
                }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            }
        }
        .appIndexListStyle()
        .safeAreaInset(edge: .top, spacing: 0) {
            GiriIndexHeader(accentColor: AppSectionAccent.artist, count: groups.count, search: $query,
                            placeholder: "団体名・フリガナ・メンバーで検索", isCollapsed: $isHeaderCollapsed)
        }
        .navigationTitle("主催団体一覧").navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("団体を追加")
            }
        }
        .sheet(isPresented: $adding) { NavigationStack { GiriGroupEditor() } }
    }

    private func groupRow(_ group: GiriGroup) -> some View {
        let hosted = store.eventsHosted(byGroup: group.name).count
        // LiveStair IndexViews と同じく、主催した会のない団体だけ削除できる。
        let deletable = !group.id.hasPrefix("history:") && hosted == 0
        return NavigationLink { GiriGroupDetail(groupID: group.id) } label: {
            HStack(spacing: 12) {
                AppIndexItemBadge(systemImage: "person.3", color: AppSectionAccent.artist)
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.name).font(.headline.weight(.semibold)).lineLimit(1)
                    let caption = [group.furigana, group.members.isEmpty ? "" : "メンバー\(group.members.count)人"].filter { !$0.isEmpty }
                    if !caption.isEmpty { Text(caption.joined(separator: "・")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }.frame(minHeight: 46, alignment: .center).layoutPriority(1)
                Spacer(minLength: 8)
                if hosted > 0 { Text("主催\(hosted)件").font(.caption).foregroundStyle(.secondary) }
            }.frame(minHeight: 48).padding(.vertical, 2)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if deletable {
                Button(role: .destructive) { delete(group) } label: { Label("削除", systemImage: "trash") }
            }
        }
        .contextMenu {
            if deletable {
                Button(role: .destructive) { delete(group) } label: { Label("団体を削除", systemImage: "trash") }
            }
        }
    }

    private func delete(_ group: GiriGroup) {
        store.run {
            try store.deleteGroup(group.id)
            playLiveStairDeleteFeedback()
        }
    }
}

// MARK: - 団体詳細（プレイヤー詳細と同じ見出し・カード）

struct GiriGroupDetail: View {
    @EnvironmentObject private var store: GiriStore
    @EnvironmentObject private var navigation: GiriNavigation
    let groupID: String
    @State private var resolvedID: String?
    @State private var editing = false

    private var group: GiriGroup? { store.groupDirectory.first { $0.id == (resolvedID ?? groupID) } }

    var body: some View {
        Group {
            if let group {
                ScrollView {
                    VStack(spacing: 14) {
                        GiriProfileNameHeader(name: group.name, kind: .artist)
                        basicCard(group)
                        membersCard(group)
                        if !group.memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            GiriDetailCard(title: "メモ", systemImage: "text.alignleft", accentColor: AppSectionAccent.memo,
                                           trailing: { GiriCardEditButton { editing = true } }) {
                                Text(group.memo).font(.subheadline).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)
                .sheet(isPresented: $editing) {
                    NavigationStack { GiriGroupEditor(group: group) { resolvedID = $0.id } }
                }
            } else {
                CenteredEmptyMessage(systemImage: "person.3", title: "団体が見つかりません")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("団体詳細")
        .navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
        .background { appBackgroundColor.ignoresSafeArea() }
    }

    private func basicCard(_ group: GiriGroup) -> some View {
        let hosted = store.eventsHosted(byGroup: group.name).filter(\.isActualParticipant)
        return GiriDetailCard(title: "基本情報", systemImage: "person.text.rectangle", accentColor: AppSectionAccent.artist,
                              trailing: { GiriCardEditButton { editing = true } }) {
            VStack(spacing: 0) {
                Divider().overlay(appSeparatorColor)
                GiriProfileInfoRow(title: "フリガナ", value: group.furigana)
                if let url = giriWebURL(group.url) {
                    Divider().overlay(appSeparatorColor)
                    Link(destination: url) {
                        HStack {
                            Text("URL").font(.subheadline).foregroundStyle(.secondary)
                            Spacer(minLength: 12)
                            Text(group.url).font(.subheadline).lineLimit(1).truncationMode(.middle)
                        }.padding(.vertical, 10)
                    }
                }
                Divider().overlay(appSeparatorColor)
                // 一覧タブで、この団体の主催を選んだ状態で開く。
                GiriProfileShortcutButton(title: "主催した会", systemImage: "person.crop.circle", accentColor: AppSectionAccent.live,
                                          countText: "\(hosted.count)件") {
                    navigation.openList(organizer: group.name)
                }
            }
        }
    }

    private func membersCard(_ group: GiriGroup) -> some View {
        GiriDetailCard(title: "所属メンバー", systemImage: "person.2", accentColor: AppSectionAccent.artist,
                       trailing: { GiriCardEditButton { editing = true } }) {
            if group.members.isEmpty {
                Text("まだ登録されていません").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(group.members.enumerated()), id: \.offset) { index, name in
                        if index > 0 { Divider().overlay(appSeparatorColor) }
                        memberRow(name)
                    }
                }
            }
        }
    }

    @ViewBuilder private func memberRow(_ name: String) -> some View {
        if let player = store.playerByName(name) {
            NavigationLink { GiriPlayerDetail(playerID: player.id) } label: {
                HStack(spacing: 10) {
                    GiriPlayerAvatar(name: player.name, size: 32)
                    Text(player.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Text(name).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        }
    }
}

// MARK: - 団体の編集（プレイヤーの編集と同じ入力行）

struct GiriGroupEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GiriGroup
    @State private var original: GiriGroup
    @State private var discard = false
    private let isNew: Bool
    private let onSaved: ((GiriGroup) -> Void)?

    init(group: GiriGroup? = nil, onSaved: ((GiriGroup) -> Void)? = nil) {
        var value = group ?? GiriGroup()
        if value.members.isEmpty { value.members = [""] }
        _draft = State(initialValue: value)
        _original = State(initialValue: value)
        isNew = group == nil
        self.onSaved = onSaved
    }

    private var changed: Bool { draft != original }

    var body: some View {
        Form {
            Section {
                AppCardSectionTitle(title: "団体", systemImage: "person.3", accentColor: AppSectionAccent.artist)
                    .listRowSeparator(.hidden)
                GiriProfileTextRow(title: "団体名", placeholder: "必須", text: $draft.name)
                GiriProfileTextRow(title: "フリガナ", placeholder: "任意", text: $draft.furigana)
                GiriProfileTextRow(title: "URL", placeholder: "任意", text: $draft.url)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            Section {
                AppCardSectionTitle(title: "所属メンバー", systemImage: "person.2", accentColor: AppSectionAccent.artist,
                                    infoTitle: "所属メンバーについて",
                                    infoMessage: "団体に所属しているプレイヤーです。プレイヤー詳細に所属団体として出ます。")
                    .listRowSeparator(.hidden)
                GiriNamesField(title: "メンバー", names: $draft.members)
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            Section {
                AppCardSectionTitle(title: "メモ", systemImage: "text.alignleft", accentColor: AppSectionAccent.memo)
                    .listRowSeparator(.hidden)
                TextField("メモ", text: $draft.memo, axis: .vertical).lineLimit(3...10)
            }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
        }
        .appEditorFormStyle()
        .navigationTitle(isNew ? "団体を追加" : "団体を編集").navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { if changed { discard = true } else { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save).fontWeight(.bold)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .interactiveDismissDisabled(changed)
        .giriDiscardChangesAlert(isPresented: $discard) { dismiss() }
    }

    private func save() {
        store.run {
            try store.saveGroup(draft)
            let saved = store.groupByName(draft.name) ?? draft
            onSaved?(saved)
            playLiveStairSaveFeedback()
            dismiss()
        }
    }
}
