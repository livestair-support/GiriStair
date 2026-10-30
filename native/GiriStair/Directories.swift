import SwiftUI
import PhotosUI
import MapKit
import UIKit

struct GiriPlayerAvatar: View {
    @EnvironmentObject private var store: GiriStore
    var name: String
    var size: CGFloat = 32
    var body: some View {
        if store.showPlayerIcons {
            Group {
                if let player = store.playerDirectory.first(where: { $0.name == name }),
                   let data = Data(base64Encoded: player.iconDataBase64), let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else { Image(systemName: "person.fill").resizable().scaledToFit().padding(size * 0.2).foregroundStyle(AppSectionAccent.artist).background(AppSectionAccent.artist.opacity(0.12)) }
            }.frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
        }
    }
}

struct GiriPlayersView: View {
    @EnvironmentObject private var store: GiriStore
    @State private var query = ""
    private var players: [GiriPlayer] {
        store.playerDirectory.filter { query.isEmpty || "\($0.name) \($0.furigana) \($0.region)".localizedStandardContains(query) }
            .sorted { ($0.furigana.isEmpty ? $0.name : $0.furigana).localizedStandardCompare($1.furigana.isEmpty ? $1.name : $1.furigana) == .orderedAscending }
    }
    var body: some View {
        List {
            Section {
                AppCardSectionTitle(title: "大喜利プレイヤー", systemImage: "person.2", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                if players.isEmpty { CenteredEmptyMessage(systemImage: "person.2", title: "プレイヤーがいません") }
                ForEach(players) { player in
                    NavigationLink { GiriPlayerDetail(playerID: player.id) } label: {
                        HStack(spacing: 12) {
                            GiriPlayerAvatar(name: player.name, size: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(player.name).font(.headline.weight(.semibold)).lineLimit(1)
                                if !player.furigana.isEmpty { Text(player.furigana).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }.frame(minHeight: 46, alignment: .center).layoutPriority(1)
                            Spacer(minLength: 8)
                        }.frame(minHeight: 48).padding(.vertical, 2)
                    }
                }
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
        }.appIndexListStyle().toolbar(.visible, for: .navigationBar).navigationTitle("大喜利プレイヤー一覧").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "名前・フリガナ・地域")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { GiriPlayerEditor() } label: { Image(systemName: "plus") }.accessibilityLabel("プレイヤーを追加") } }
    }
}

struct GiriPlayerDetail: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    var playerID: String
    @State private var resolvedID: String?
    @State private var deleting = false
    private var player: GiriPlayer? { store.playerDirectory.first { $0.id == (resolvedID ?? playerID) } }
    var body: some View {
        Group {
            if let player {
                playerForm(player)
            } else { CenteredEmptyMessage(systemImage: "person", title: "プレイヤーが見つかりません") }
        }.toolbar(.visible, for: .navigationBar).navigationTitle(player?.name ?? "プレイヤー").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { if let player { NavigationLink("編集") { GiriPlayerEditor(player: player, onSaved: { resolvedID = $0.id }) } } } }
            .confirmationDialog("プロフィールを削除しますか？参加記録の名前と入賞記録は残ります。", isPresented: $deleting, titleVisibility: .visible) {
                Button("削除", role: .destructive) { store.run { try store.deletePlayer(resolvedID ?? playerID); playLiveStairDeleteFeedback(); dismiss() } }
            }
    }
    private func playerForm(_ player: GiriPlayer) -> some View {
        Form {
            Section {
                AppCardSectionTitle(title: "プロフィール", systemImage: "person.crop.circle", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                HStack { GiriPlayerAvatar(name: player.name, size: 64); Text(player.name).font(.title2.bold()) }
                if !player.furigana.isEmpty { GiriProfileInfoRow(title: "フリガナ", value: player.furigana) }
                if !player.region.isEmpty { GiriProfileInfoRow(title: "地域", value: player.region) }
                if let url = giriWebURL(player.twitterUrl) { Link("X / Twitter", destination: url) }
                if !player.memo.isEmpty { Text(player.memo).textSelection(.enabled) }
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            Section {
                AppCardSectionTitle(title: "参加記録", systemImage: "clock", accentColor: AppSectionAccent.memo).listRowSeparator(.hidden)
                LabeledContent("一緒に参加", value: "\(relatedEvents(player).filter { $0.participants.contains(player.name) }.count)回")
                LabeledContent("主催", value: "\(relatedEvents(player).filter { $0.organizer == player.name }.count)回")
                ForEach(relatedEvents(player)) { event in NavigationLink(event.title) { GiriEventDetail(eventID: event.id) } }
            }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
            Section {
                AppCardSectionTitle(title: "大会の上位成績", systemImage: "trophy", accentColor: AppSectionAccent.ticket).listRowSeparator(.hidden)
                let records = podiumRecords(player)
                if records.isEmpty { Text("上位成績の記録がありません").foregroundStyle(.secondary) }
                ForEach(records) { record in
                    NavigationLink { GiriEventDetail(eventID: record.eventID) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(record.placement == 1 ? "優勝" : record.placement == 2 ? "準優勝" : "\(record.placement)位").font(.headline).foregroundStyle(AppSectionAccent.ticket); Text(record.title) }
                            if !record.team.isEmpty { Text(record.team).font(.subheadline).foregroundStyle(.secondary) }
                            if !record.memo.isEmpty { Text(record.memo).font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                }
            }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
            if !player.id.hasPrefix("history:") { Button("プロフィールを削除", role: .destructive) { deleting = true } }
        }.appEditorFormStyle()
    }
    private func relatedEvents(_ player: GiriPlayer) -> [GiriEvent] {
        store.events.filter { $0.isCountableParticipation() && ($0.participants.contains(player.name) || $0.organizer == player.name) }
            .sorted { (giriAnalyticsDate($0) ?? .distantPast) > (giriAnalyticsDate($1) ?? .distantPast) }
    }
    private func podiumRecords(_ player: GiriPlayer) -> [PlayerPodiumRecord] {
        store.events.filter { $0.isCountableParticipation() }.flatMap { event in
            event.standings.filter { $0.playerNames.contains(player.name) }.map { standing in
                PlayerPodiumRecord(id: event.id + ":" + standing.id, eventID: event.id, title: event.title, placement: standing.placement, team: standing.teamName, memo: standing.memo)
            }
        }.sorted { $0.placement < $1.placement }
    }
}
private struct PlayerPodiumRecord: Identifiable { var id: String; var eventID: String; var title: String; var placement: Int; var team: String; var memo: String }

struct GiriPlayerEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GiriPlayer
    @State private var photo: PhotosPickerItem?
    private let isNew: Bool
    private var onSaved: ((GiriPlayer) -> Void)?
    init(player: GiriPlayer? = nil, onSaved: ((GiriPlayer) -> Void)? = nil) { _draft = State(initialValue: player ?? GiriPlayer()); isNew = player == nil; self.onSaved = onSaved }
    var body: some View {
        Form {
            Section {
                AppCardSectionTitle(title: "プロフィール", systemImage: "person.crop.circle", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                TextField("プレイヤー名", text: $draft.name).textContentType(.nickname)
                TextField("フリガナ", text: $draft.furigana)
                TextField("地域", text: $draft.region)
                TextField("X / TwitterのURL", text: $draft.twitterUrl).textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                PhotosPicker(selection: $photo, matching: .images) {
                    HStack {
                        if let data = Data(base64Encoded: draft.iconDataBase64), let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill().frame(width: 52, height: 52).clipShape(Circle()) }
                        Label("アイコンを選ぶ", systemImage: "photo")
                    }
                }
                if !draft.iconDataBase64.isEmpty { Button("アイコンを外す", role: .destructive) { draft.iconDataBase64 = "" } }
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            Section {
                AppCardSectionTitle(title: "メモ", systemImage: "note.text", accentColor: AppSectionAccent.memo).listRowSeparator(.hidden)
                TextField("メモ", text: $draft.memo, axis: .vertical).lineLimit(4...12)
            }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
        }.appEditorFormStyle().toolbar(.visible, for: .navigationBar).navigationTitle(isNew ? "プレイヤーを追加" : "プロフィールを編集").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
            .onChange(of: photo) { _, item in Task { await loadPhoto(item) } }
    }
    private func save() {
        store.run {
            draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            try store.savePlayer(draft)
            onSaved?(store.players.first { playerSearchKey($0.name) == playerSearchKey(draft.name) } ?? draft)
            playLiveStairSaveFeedback()
            dismiss()
        }
    }
    @MainActor private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw DirectoryError.image }
            let size = image.size
            guard size.width > 0 && size.height > 0 else { throw DirectoryError.image }
            let ratio = min(1, 512 / max(size.width, size.height))
            let targetSize = CGSize(width: size.width * ratio, height: size.height * ratio)
            let renderer = UIGraphicsImageRenderer(size: targetSize)
            guard let reduced = renderer.image(actions: { _ in image.draw(in: CGRect(origin: .zero, size: targetSize)) }).jpegData(compressionQuality: 0.85) else { throw DirectoryError.image }
            draft.iconDataBase64 = reduced.base64EncodedString()
        } catch { store.errorMessage = error.localizedDescription }
    }
}

struct GiriVenuesView: View {
    @EnvironmentObject private var store: GiriStore
    @State private var query = ""
    var body: some View {
        List {
            Section {
                AppCardSectionTitle(title: "会場", systemImage: "mappin.and.ellipse", accentColor: AppSectionAccent.venue).listRowSeparator(.hidden)
                let venues = store.venueDirectory.filter { query.isEmpty || "\($0.name) \($0.prefecture)".localizedStandardContains(query) }
                if venues.isEmpty { CenteredEmptyMessage(systemImage: "mappin.and.ellipse", title: "会場がありません") }
                ForEach(venues) { venue in
                    NavigationLink { GiriVenueDetail(venueID: venue.id) } label: {
                        HStack(spacing: 12) {
                            AppIndexItemBadge(systemImage: "mappin.and.ellipse", color: AppSectionAccent.venue)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(venue.name).font(.headline.weight(.semibold)).lineLimit(1)
                                if !venue.prefecture.isEmpty { Text(venue.prefecture).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }.layoutPriority(1)
                            Spacer(minLength: 8)
                        }.frame(minHeight: 48).padding(.vertical, 2)
                    }
                }
            }.appSectionCardStyle(accentColor: AppSectionAccent.venue)
        }.appIndexListStyle().searchable(text: $query, prompt: "会場名・都道府県").toolbar(.visible, for: .navigationBar).navigationTitle("会場一覧").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { GiriVenueEditor() } label: { Image(systemName: "plus") }.accessibilityLabel("会場を追加") } }
    }
}

struct GiriVenueDetail: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    var venueID: String
    @State private var resolvedID: String?
    @State private var deleting = false
    private var venue: GiriVenue? { store.venueDirectory.first { $0.id == (resolvedID ?? venueID) } }
    var body: some View {
        Group {
            if let venue {
                Form {
                    Section {
                        AppCardSectionTitle(title: "会場", systemImage: "mappin.and.ellipse", accentColor: AppSectionAccent.venue).listRowSeparator(.hidden)
                        GiriProfileInfoRow(title: "会場名", value: venue.name, labelWidth: 80, verticalPadding: 8)
                        if !venue.prefecture.isEmpty { GiriProfileInfoRow(title: "都道府県", value: venue.prefecture, labelWidth: 80, verticalPadding: 8) }
                        if !venue.mapAddress.isEmpty { Text(venue.mapAddress).foregroundStyle(.secondary) }
                        if let latitude = venue.latitude, let longitude = venue.longitude {
                            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)))) { Marker(venue.name, coordinate: coordinate) }
                                .frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 16))
                            Link("マップで開く", destination: URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)")!)
                        }
                        if let url = giriWebURL(venue.mapUrl) { Link("登録した地図を開く", destination: url) }
                        if !venue.memo.isEmpty { Text(venue.memo).textSelection(.enabled) }
                    }.appSectionCardStyle(accentColor: AppSectionAccent.venue)
                    Section {
                        AppCardSectionTitle(title: "参加記録", systemImage: "clock", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                        let events = store.events.filter { $0.eventFormat.hasLiveTiming && ($0.venueId == venue.id || $0.venue == venue.name) && $0.isCountableParticipation() }
                        LabeledContent("参加回数", value: "\(events.count)回")
                        ForEach(events) { event in NavigationLink(event.title) { GiriEventDetail(eventID: event.id) } }
                    }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
                    if !venue.id.hasPrefix("history:") { Button("会場の登録を削除", role: .destructive) { deleting = true } }
                }.appEditorFormStyle()
            } else { CenteredEmptyMessage(systemImage: "mappin.and.ellipse", title: "会場が見つかりません") }
        }.toolbar(.visible, for: .navigationBar).navigationTitle(venue?.name ?? "会場").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { if let venue { NavigationLink("編集") { GiriVenueEditor(venue: venue, onSaved: { resolvedID = $0.id }) } } } }
            .confirmationDialog("会場の登録を削除しますか？過去の記録は残ります。", isPresented: $deleting, titleVisibility: .visible) {
                Button("削除", role: .destructive) { store.run { try store.deleteVenue(resolvedID ?? venueID); playLiveStairDeleteFeedback(); dismiss() } }
            }
    }
}

struct GiriVenueEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GiriVenue
    private var onSaved: ((GiriVenue) -> Void)?
    init(venue: GiriVenue? = nil, onSaved: ((GiriVenue) -> Void)? = nil) { _draft = State(initialValue: venue ?? GiriVenue()); self.onSaved = onSaved }
    var body: some View {
        Form {
            Section {
                AppCardSectionTitle(title: "会場", systemImage: "mappin.and.ellipse", accentColor: AppSectionAccent.venue).listRowSeparator(.hidden)
                TextField("会場名", text: $draft.name)
                Picker("都道府県", selection: $draft.prefecture) { Text("未設定").tag(""); ForEach(Self.prefectures, id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu).tint(.primary)
                NavigationLink { GiriMapSearchView(query: draft.name) { item in
                    draft.latitude = item.placemark.coordinate.latitude
                    draft.longitude = item.placemark.coordinate.longitude
                    draft.mapAddress = [item.placemark.administrativeArea, item.placemark.locality, item.placemark.thoroughfare, item.placemark.subThoroughfare].compactMap { $0 }.joined()
                    if let prefecture = item.placemark.administrativeArea { draft.prefecture = prefecture }
                } } label: { Label("マップを検索して登録", systemImage: "map") }
                if draft.latitude != nil { LabeledContent("地図", value: draft.mapAddress.isEmpty ? "登録済み" : draft.mapAddress); Button("マップの登録を外す", role: .destructive) { draft.latitude = nil; draft.longitude = nil; draft.mapAddress = "" } }
                TextField("地図のURL", text: $draft.mapUrl).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("メモ", text: $draft.memo, axis: .vertical).lineLimit(3...8)
            }.appSectionCardStyle(accentColor: AppSectionAccent.venue)
        }.appEditorFormStyle().toolbar(.visible, for: .navigationBar).navigationTitle("会場を編集").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存") { store.run { try store.saveVenue(draft); onSaved?(store.venues.first { playerSearchKey($0.name) == playerSearchKey(draft.name) } ?? draft); playLiveStairSaveFeedback(); dismiss() } }.disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
    }
    static let prefectures = ["北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県", "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県", "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県", "岐阜県", "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府", "兵庫県", "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県", "広島県", "山口県", "徳島県", "香川県", "愛媛県", "高知県", "福岡県", "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県"]
}

private struct GiriMapSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: GiriStore
    @State var query: String
    var onSelect: (MKMapItem) -> Void
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    var body: some View {
        List {
            Section {
                AppCardSectionTitle(title: "会場を検索", systemImage: "magnifyingglass", accentColor: AppSectionAccent.venue).listRowSeparator(.hidden)
                TextField("会場名・住所", text: $query).submitLabel(.search).onSubmit { Task { await search() } }
                Button("検索") { Task { await search() } }.disabled(searching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if searching { ProgressView() }
                ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                    Button { onSelect(item); dismiss() } label: { VStack(alignment: .leading, spacing: 4) { Text(item.name ?? "名称未設定").foregroundStyle(.primary); Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary) } }
                }
            }.appSectionCardStyle(accentColor: AppSectionAccent.venue)
        }.appIndexListStyle().toolbar(.visible, for: .navigationBar).navigationTitle("マップ検索").navigationBarTitleDisplayMode(.inline)
    }
    @MainActor private func search() async {
        searching = true
        defer { searching = false }
        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            let response = try await MKLocalSearch(request: request).start()
            results = response.mapItems
        } catch { store.errorMessage = error.localizedDescription }
    }
}

struct GiriSitesView: View {
    @EnvironmentObject private var store: GiriStore
    var body: some View {
        List {
            Section {
                AppCardSectionTitle(title: "ネット大喜利サイト", systemImage: "globe", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                if store.onlineSites.isEmpty { CenteredEmptyMessage(systemImage: "globe", title: "サイトがありません") }
                ForEach(store.onlineSites) { site in
                    NavigationLink { GiriSiteDetail(siteID: site.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(site.name).font(.headline.weight(.semibold))
                            Text(site.format.title).font(.caption).foregroundStyle(.secondary)
                            let labels = [site.hasAffiliations ? site.affiliation : "", site.block].filter { !$0.isEmpty }
                            if !labels.isEmpty { Text(labels.joined(separator: "・")).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
        }.appIndexListStyle().toolbar(.visible, for: .navigationBar).navigationTitle("ネット大喜利サイト一覧").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { GiriSiteEditor() } label: { Image(systemName: "plus") }.accessibilityLabel("サイトを追加") } }
    }
}

/// Weekly snapshots belong to each joined cycle, not to today's site settings.
struct GiriSiteDetail: View {
    @EnvironmentObject private var store: GiriStore
    @EnvironmentObject private var navigation: GiriNavigation
    @Environment(\.dismiss) private var dismiss
    let siteID: String
    @State private var deleting = false
    @State private var resultEvent: GiriEvent?

    private var site: OnlineSite? { store.onlineSites.first { $0.id == siteID } }
    private var history: [GiriEvent] {
        store.events.filter { $0.onlineSiteId == siteID && $0.isActualParticipant }
            .sorted { ($0.participationStartDate ?? $0.createdAt) > ($1.participationStartDate ?? $1.createdAt) }
    }

    var body: some View {
        Group {
            if let site {
                Form {
                    siteSection(site)
                    Section {
                        AppCardSectionTitle(title: "週ごとの所属・結果", systemImage: "clock", accentColor: AppSectionAccent.artist)
                            .listRowSeparator(.hidden)
                        if history.isEmpty {
                            Text("参加した回の履歴がありません").foregroundStyle(.secondary)
                        }
                        ForEach(history) { event in
                            Button { navigation.openThoughts(eventID: event.id) } label: { historyRow(event) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if event.hasEnded() {
                                        Button("結果を記録", systemImage: "square.and.pencil") { resultEvent = event }
                                    }
                                }
                        }
                    }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
                    Section {
                        Button { navigation.openThoughts(siteID: siteID) } label: {
                            Label("このサイトのお題・回答を開く", systemImage: "text.bubble")
                        }
                    }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
                }.appEditorFormStyle()
            } else {
                CenteredEmptyMessage(systemImage: "globe", title: "サイトが見つかりません")
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle(site?.name ?? "サイト")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let site { NavigationLink("編集") { GiriSiteEditor(site: site) } }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("サイトの登録を削除", systemImage: "trash", role: .destructive) { deleting = true }
                } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("サイトの操作")
            }
        }
        .confirmationDialog("サイトを削除しますか？過去の参加記録とメモは残ります。", isPresented: $deleting, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                store.run { try store.deleteOnlineSite(siteID); playLiveStairDeleteFeedback(); dismiss() }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .sheet(item: $resultEvent) { event in NavigationStack { GiriCycleResultEditor(eventID: event.id) } }
    }

    private func siteSection(_ site: OnlineSite) -> some View {
        Section {
            AppCardSectionTitle(title: "サイト", systemImage: "globe", accentColor: AppSectionAccent.artist)
                .listRowSeparator(.hidden)
            GiriProfileInfoRow(title: "形式", value: site.format.title)
            if let url = giriWebURL(site.url) { Link("サイトを開く", destination: url) }
            Toggle("所属がある", isOn: Binding(get: { self.site?.hasAffiliations ?? site.hasAffiliations }, set: { enabled in
                guard var current = self.site else { return }
                current.hasAffiliations = enabled
                store.run { try store.saveOnlineSite(current) }
            })).tint(AppSectionAccent.artist)
            if site.hasAffiliations { GiriProfileInfoRow(title: "次の回の所属", value: site.affiliation) }
            if !site.block.isEmpty { GiriProfileInfoRow(title: "ブロック", value: site.block) }
            if !site.memo.isEmpty { Text(site.memo).textSelection(.enabled) }
        }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    private func historyRow(_ event: GiriEvent) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(GiriDateText.day(event.participationStartDate ?? event.eventDate))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(event.participationState().title).font(.caption).foregroundStyle(.secondary)
            }
            if !event.affiliation.isEmpty {
                Text("所属　" + event.affiliation).font(.subheadline).foregroundStyle(.secondary)
            }
            if let rank = event.cyclePlacement {
                Text("\(rank)位").font(.subheadline.weight(.semibold)).foregroundStyle(AppSectionAccent.ticket)
            }
            if !event.cycleResult.isEmpty { Text(event.cycleResult).font(.subheadline).foregroundStyle(.primary) }
            HStack(spacing: 4) {
                Image(systemName: "text.bubble")
                Text("お題・提出した回答・没案")
                Spacer()
                Image(systemName: "chevron.right")
            }.font(.caption).foregroundStyle(AppSectionAccent.memo)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct GiriSiteEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: OnlineSite
    @State private var deleting = false
    @State private var initialized = false
    private var isNew: Bool
    private var onSaved: ((OnlineSite) -> Void)?
    init(site: OnlineSite? = nil, onSaved: ((OnlineSite) -> Void)? = nil) { _draft = State(initialValue: site ?? OnlineSite()); isNew = site == nil; self.onSaved = onSaved }
    var body: some View {
        Form {
            Section {
                AppCardSectionTitle(title: "サイト", systemImage: "globe", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                TextField("サイト名", text: $draft.name)
                TextField("URL", text: $draft.url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("形式", selection: $draft.format) {
                    ForEach(EventFormat.allCases.filter { $0.hasOnlineRounds }) { format in Text(format.title).tag(format) }
                }.pickerStyle(.menu).tint(.primary)
                Picker("開催", selection: $draft.recurrence) { Text("不定期").tag(SiteRecurrence.irregular); Text("毎週").tag(SiteRecurrence.weekly) }.pickerStyle(.menu).tint(.primary)
                if draft.recurrence == .weekly {
                    Picker("投稿開始の曜日", selection: $draft.weekday) { ForEach(1...7, id: \.self) { day in Text(["月", "火", "水", "木", "金", "土", "日"][day - 1] + "曜日").tag(day) } }.pickerStyle(.menu).tint(.primary)
                }
                OptionalDateRow(title: "投稿開始の時刻", selection: startTime, components: .hourAndMinute)
                Stepper("投稿期間　\(draft.submissionDays)日", value: $draft.submissionDays, in: 1...365)
                Stepper("投票期間　\(draft.votingDays)日", value: $draft.votingDays, in: 1...365)
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            Section {
                AppCardSectionTitle(title: "自分の所属・ブロック", systemImage: "person", accentColor: AppSectionAccent.memo).listRowSeparator(.hidden)
                Toggle("所属がある", isOn: $draft.hasAffiliations).tint(AppSectionAccent.memo)
                if draft.hasAffiliations { TextField("次の参加回の所属（一部など）", text: $draft.affiliation) }
                TextField("ブロック", text: $draft.block)
                TextField("メモ", text: $draft.memo, axis: .vertical).lineLimit(3...8)
            }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
            if !isNew { Button("サイトの登録を削除", role: .destructive) { deleting = true } }
        }.appEditorFormStyle().toolbar(.visible, for: .navigationBar).navigationTitle(isNew ? "サイトを登録" : "サイトを編集").navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !initialized else { return }
                initialized = true
                if isNew {
                    draft.startHour = store.preferences.submissionStartHour
                    draft.startMinute = store.preferences.submissionStartMinute
                    draft.submissionDays = store.preferences.submissionDays
                    draft.votingDays = store.preferences.votingDays
                }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存") { store.run { try store.saveOnlineSite(draft); onSaved?(draft); playLiveStairSaveFeedback(); dismiss() } }.disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
            .confirmationDialog("サイトを削除しますか？過去の参加記録とメモは残ります。", isPresented: $deleting, titleVisibility: .visible) {
                Button("削除", role: .destructive) { store.run { try store.deleteOnlineSite(draft.id); playLiveStairDeleteFeedback(); dismiss() } }
            }
    }
    private var startTime: Binding<Date?> {
        Binding(get: { Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: draft.startHour, minute: draft.startMinute)) }, set: { date in
            guard let date else { return }
            draft.startHour = Calendar.current.component(.hour, from: date)
            draft.startMinute = Calendar.current.component(.minute, from: date)
        })
    }
}

private enum DirectoryError: LocalizedError { case image; var errorDescription: String? { "画像を読み込めませんでした。別の写真を選んでください。" } }
func giriWebURL(_ string: String) -> URL? { guard let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }; return url }

// ArtistDetailView.infoRow / VenueDetailView.venueInfoRow from LiveStair.
private struct GiriProfileInfoRow: View {
    let title: String
    let value: String
    var labelWidth: CGFloat = 104
    var verticalPadding: CGFloat = 10
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
                .frame(width: labelWidth, alignment: .leading)
            Spacer(minLength: 12)
            Text(value.isEmpty ? "未設定" : value).font(.subheadline)
                .foregroundStyle(value.isEmpty || value == "未設定" ? Color.secondary : Color.primary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, verticalPadding)
    }
}
