import SwiftUI
import PhotosUI
import MapKit
import UIKit

// LiveStair ArtistDetailView / VenueDetailView を基準にした、プレイヤー・会場の一覧・詳細・編集。
// 詳細は名前の見出し → セグメント → ページ（カード）の構成。編集は各カードの「編集」から
// シートで開き、詳細には削除ボタンを置かない（記録のない項目だけ一覧から削除できる）。

// MARK: - 共通のカード・行

/// `.artist` は ArtistDetailCardTitle（28ptバッジ）と spacing 12、
/// `.venue` は VenueDetailCardTitle（16ptアイコン）と見出し下の区切り線。
enum GiriDetailCardKind { case artist, venue }

struct GiriDetailCard<Trailing: View, Content: View>: View {
    let title: String
    let systemImage: String
    let accentColor: Color
    let kind: GiriDetailCardKind
    let infoTitle: String?
    let infoMessage: String?
    private let trailing: Trailing
    private let content: Content

    init(title: String, systemImage: String, accentColor: Color, kind: GiriDetailCardKind = .artist,
         infoTitle: String? = nil, infoMessage: String? = nil,
         @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.accentColor = accentColor
        self.kind = kind
        self.infoTitle = infoTitle
        self.infoMessage = infoMessage
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        switch kind {
        case .artist:
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    AppCardSectionTitle(title: title, systemImage: systemImage, accentColor: accentColor,
                                        infoTitle: infoTitle, infoMessage: infoMessage)
                    trailing
                }
                content
            }
            .padding(16)
            .appTintedCard(accentColor: accentColor, cornerRadius: 20, railVerticalInset: 14, lightTintOpacity: 0.065)
            .padding(.horizontal, 18)
        case .venue:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    GiriVenueCardTitle(title: title, systemImage: systemImage, accentColor: accentColor)
                    Spacer(minLength: 8)
                    trailing
                }
                Divider().overlay(appSeparatorColor)
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .appTintedCard(accentColor: accentColor, cornerRadius: 20, railVerticalInset: 14, lightTintOpacity: 0.065)
            .padding(.horizontal, 18)
        }
    }
}

extension GiriDetailCard where Trailing == EmptyView {
    init(title: String, systemImage: String, accentColor: Color, kind: GiriDetailCardKind = .artist,
         infoTitle: String? = nil, infoMessage: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, systemImage: systemImage, accentColor: accentColor, kind: kind,
                  infoTitle: infoTitle, infoMessage: infoMessage, trailing: { EmptyView() }, content: content)
    }
}

/// VenueDetailView.VenueDetailCardTitle
struct GiriVenueCardTitle: View {
    let title: String
    let systemImage: String
    let accentColor: Color
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: appFontSize(16), weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 22)
            Text(title)
                .font(.system(size: appFontSize(18), weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// カード見出しの右に置く「編集」。ArtistDetailView は semibold、VenueDetailView は通常の太さ。
struct GiriCardEditButton: View {
    var kind: GiriDetailCardKind = .artist
    let action: () -> Void
    var body: some View {
        Button("編集", action: action)
            .font(kind == .artist ? Font.subheadline.weight(.semibold) : Font.subheadline)
            .foregroundStyle(accentActionColor)
    }
}

/// ArtistDetailView の名前見出し（ロゴなし）と VenueDetailView.venueNameHeader。
struct GiriProfileNameHeader: View {
    let name: String
    var kind: GiriDetailCardKind = .artist
    var body: some View {
        if kind == .artist {
            Text(name)
                .font(.system(size: appFontSize(26), weight: .heavy, design: .rounded))
                .tracking(-0.5)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.42)
                .allowsTightening(true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .frame(height: 88)
                .background(appBackgroundColor)
                .accessibilityAddTraits(.isHeader)
        } else {
            Text(name)
                .font(.system(size: appFontSize(30), weight: .heavy, design: .rounded))
                .tracking(-0.6)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 44)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(appBackgroundColor)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// VenueDetailView.venueLinkRow。押すと確認してから外部アプリで開く。
struct GiriProfileLinkRow: View {
    let title: String
    let displayText: String
    let url: URL?
    var iconName: String? = nil
    @State private var confirming = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let url {
            Button { confirming = true } label: {
                HStack {
                    Text(title).font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    if !displayText.isEmpty {
                        Text(displayText).font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    if let iconName {
                        Image(systemName: iconName).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .alert("外部リンクを開きます", isPresented: $confirming) {
                Button("キャンセル", role: .cancel) {}
                Button("開く") { openURL(url) }
            } message: { Text("外部アプリで\(title)を開きます。") }
        } else {
            HStack {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("未設定").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }
}

/// ArtistDetailView.artistQuickLinkRow（遷移先はこのアプリ内の記録一覧）。
struct GiriProfileShortcutRow<Destination: View>: View {
    let title: String
    let systemImage: String
    let accentColor: Color
    var countText: String = ""
    @ViewBuilder let destination: () -> Destination
    var body: some View {
        NavigationLink {
            destination()
        } label: {
            GiriProfileShortcutLabel(title: title, systemImage: systemImage, accentColor: accentColor, countText: countText)
        }
        .buttonStyle(.plain)
    }
}

/// 一覧タブなど、画面を切り替えるショートカット。
struct GiriProfileShortcutButton: View {
    let title: String
    let systemImage: String
    let accentColor: Color
    var countText: String = ""
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            GiriProfileShortcutLabel(title: title, systemImage: systemImage, accentColor: accentColor, countText: countText)
        }
        .buttonStyle(.plain)
    }
}

struct GiriProfileShortcutLabel: View {
    let title: String
    let systemImage: String
    let accentColor: Color
    var countText: String = ""
    var body: some View {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: appFontSize(16), weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: appFontSize(15), weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 8)
                if !countText.isEmpty {
                    Text(countText).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                }
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
    }
}

/// ArtistDetailView.artistLiveCountLine / VenueDetailView.venueLiveCountLine を縦に並べた集計の列。
struct GiriCountColumn: View {
    let title: String
    let count: Int
    var total: Int? = nil
    var caption: String = ""
    var accentColor: Color = AppSectionAccent.artist
    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(count)")
                    .font(.system(size: appFontSize(28), weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                Text("回").font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                if let total {
                    Text("/ 全\(total)回").font(.subheadline.weight(.bold)).foregroundStyle(accentColor)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .allowsTightening(true)
            .frame(maxWidth: .infinity, alignment: .trailing)
            if !caption.isEmpty {
                Text(caption).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// ArtistDetailView.artistLiveDateRow。記録があれば押すとその会の詳細を開く。
struct GiriProfileDateRow: View {
    let title: String
    let event: GiriEvent?
    var body: some View {
        if let event {
            NavigationLink { GiriEventDetail(eventID: event.id) } label: { label(event) }
                .buttonStyle(.plain)
        } else {
            label(nil)
        }
    }
    private func label(_ event: GiriEvent?) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            Spacer()
            Text(event.flatMap(giriAnalyticsDate).map { GiriDateText.day($0, compact: true) } ?? (event == nil ? "--" : "日付未定"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if event != nil {
                Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

/// 年の選択（ArtistDetailView.artistLiveAnalyticsSummarySection の Picker）。
struct GiriYearMenu: View {
    @Binding var selection: String
    let years: [String]
    /// ArtistDetailView は primary、VenueDetailView は accentActionColor。
    var tint: Color = .primary
    var body: some View {
        Picker("年", selection: $selection) {
            Text("全期間").tag("all")
            ForEach(years, id: \.self) { year in Text(year).tag(year) }
        }
        .pickerStyle(.menu)
        .tint(tint)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct GiriRankItem: Identifiable, Equatable {
    let rank: Int
    let name: String
    let count: Int
    var id: String { playerSearchKey(name) }
}

/// LiveStair の上位表示と同じく、同数は同順位、10位までを出す。1つの会では同じ名前を1回だけ数える。
func giriRankItems(_ groups: [[String]], excluding excluded: Set<String> = [], limit: Int = 10) -> [GiriRankItem] {
    var counts: [String: Int] = [:]
    var names: [String: String] = [:]
    for group in groups {
        var seen = Set<String>()
        for raw in group {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = playerSearchKey(name)
            guard !key.isEmpty, !excluded.contains(key), seen.insert(key).inserted else { continue }
            counts[key, default: 0] += 1
            if names[key] == nil { names[key] = name }
        }
    }
    let sorted = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
    var result: [GiriRankItem] = []
    var previous: Int?
    var rank = 0
    for (index, item) in sorted.enumerated() {
        if previous != item.value { rank = index + 1; previous = item.value }
        guard rank <= limit else { break }
        result.append(GiriRankItem(rank: rank, name: names[item.key] ?? item.key, count: item.value))
    }
    return result
}

/// VenueDetailView の「出演アーティスト上位」と ArtistDetailView の各ランキングの枠。
struct GiriRankingCard<Row: View>: View {
    let title: String
    let systemImage: String
    let accentColor: Color
    var kind: GiriDetailCardKind = .artist
    let unit: String
    let items: [GiriRankItem]
    @ViewBuilder let row: (GiriRankItem) -> Row
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if kind == .artist {
                    AppCardSectionTitle(title: title, systemImage: systemImage, accentColor: accentColor)
                } else {
                    GiriVenueCardTitle(title: title, systemImage: systemImage, accentColor: accentColor)
                    Spacer()
                }
                Text("\(items.count)\(unit)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            Divider().overlay(appSeparatorColor).padding(.horizontal, 16)
            if items.isEmpty {
                Text("データがありません")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(items) { item in
                    row(item)
                    if item.id != items.last?.id {
                        Divider().overlay(appSeparatorColor).padding(.horizontal, 18)
                    }
                }
            }
        }
        .appTintedCard(accentColor: accentColor, cornerRadius: 20, railVerticalInset: 14, lightTintOpacity: 0.065)
        .padding(.horizontal, 18)
    }
}

/// ランキングの1行（VenueDetailView の上位行から「ライブへ」を除いたもの）。
struct GiriRankRowLabel<Leading: View>: View {
    let item: GiriRankItem
    @ViewBuilder let leading: () -> Leading
    var body: some View {
        HStack(spacing: 8) {
            RankNumberView(rank: item.rank, width: 28)
            leading()
            Text(item.name)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1).truncationMode(.tail)
                .minimumScaleFactor(0.65).allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(3)
            Spacer(minLength: 2)
            Text("\(item.count)回")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false).layoutPriority(1)
            Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.secondary).frame(width: 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 15).padding(.leading, 12).padding(.trailing, 12)
        .contentShape(Rectangle())
    }
}

/// ショートカットの遷移先。保存データの変更（削除など）をその場で反映する。
struct GiriProfileRecordsPage: View {
    @EnvironmentObject private var store: GiriStore
    let title: String
    var accentColor: Color = AppSectionAccent.live
    let includes: (GiriEvent) -> Bool
    private var records: [GiriEvent] {
        store.events.filter { $0.isActualParticipant && includes($0) }
            .sorted { (GiriEventPresentation.date($0) ?? $0.createdAt) > (GiriEventPresentation.date($1) ?? $1.createdAt) }
    }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let values = records
                if values.isEmpty {
                    CenteredEmptyMessage(systemImage: "calendar.badge.exclamationmark", title: "記録がありません")
                        .frame(maxWidth: .infinity, minHeight: 145)
                        .appTintedCard(accentColor: accentColor)
                        .padding(.horizontal, 18)
                }
                ForEach(values) { event in
                    NavigationLink { GiriEventDetail(eventID: event.id) } label: { GiriEventCard(event: event) }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 18).padding(.vertical, 6)
                }
            }
            .padding(.top, 8).padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(appBackgroundColor)
        .giriNavigationBarStyle()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 編集シートで開く項目。nil は新規追加（すべての項目）。
enum GiriProfileEditSection: String, Identifiable {
    case basic, links, memo
    var id: String { rawValue }
}

/// LiveStair の入力行：左に小さく灰色の項目名、右に入力。
struct GiriProfileTextRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 12) {
            GiriEditorLabel(title)
            TextField(placeholder, text: $text).multilineTextAlignment(.trailing)
        }
    }
}

/// 「@ID」や「x.com/ID」を開けるURLとして保存する。URL以外の入力はそのまま残す。
func giriNormalizedXURL(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, giriWebURL(trimmed) == nil else { return trimmed }
    let lower = trimmed.lowercased()
    if lower.hasPrefix("x.com/") || lower.hasPrefix("twitter.com/") || lower.hasPrefix("www.x.com/") || lower.hasPrefix("www.twitter.com/") {
        return "https://" + trimmed
    }
    let handle = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
    guard handle.range(of: #"^[A-Za-z0-9_]{1,15}$"#, options: .regularExpression) != nil else { return trimmed }
    return "https://x.com/" + handle
}

/// X / Twitter のURLなら「@ID」。それ以外のURLは空（行にはアイコンを出す）。
func giriXDisplayText(_ urlString: String) -> String {
    guard let url = giriWebURL(urlString), let host = url.host?.lowercased(),
          ["x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com", "mobile.x.com"].contains(host),
          let handle = url.pathComponents.dropFirst().first, !handle.isEmpty else { return "" }
    return "@" + handle
}

enum GiriProfileImageError: LocalizedError {
    case image
    var errorDescription: String? { "画像を読み込めませんでした。別の写真を選んでください。" }
}

/// プレイヤーのアイコンは長辺512pxのJPEGに縮小して保存する（従来と同じ）。
@MainActor
func giriPlayerIconBase64(from item: PhotosPickerItem) async throws -> String {
    guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw GiriProfileImageError.image }
    let size = image.size
    guard size.width > 0 && size.height > 0 else { throw GiriProfileImageError.image }
    let ratio = min(1, 512 / max(size.width, size.height))
    let targetSize = CGSize(width: size.width * ratio, height: size.height * ratio)
    let renderer = UIGraphicsImageRenderer(size: targetSize)
    guard let reduced = renderer.image(actions: { _ in image.draw(in: CGRect(origin: .zero, size: targetSize)) }).jpegData(compressionQuality: 0.85) else { throw GiriProfileImageError.image }
    return reduced.base64EncodedString()
}

/// 会の参加者・チームのメンバー（主催者を含めない）。
func giriEventPeople(_ event: GiriEvent) -> [String] {
    event.participants + event.teams.flatMap(\.members)
}

// MARK: - 一覧（LiveStair IndexViews のヘッダーとセクション）

/// LiveStair IndexViews の一覧ヘッダー：一覧表示・件数・折りたたみ・検索。
struct GiriIndexHeader: View {
    let accentColor: Color
    let count: Int
    @Binding var search: String
    let placeholder: String
    @Binding var isCollapsed: Bool
    var body: some View {
        AppIndexHeaderCard(accentColor: accentColor) {
            HStack {
                AppCardSectionTitle(title: "一覧表示", systemImage: "slider.horizontal.3", accentColor: accentColor)
                Spacer(minLength: 8)
                Text("\(count)件").font(.caption).foregroundStyle(.secondary)
                AppHeaderCollapseButton(isCollapsed: $isCollapsed, tintColor: accentColor)
            }
            .padding(.bottom, isCollapsed ? 0 : 8)
            if isCollapsed {
                // 畳んだときは、検索している文字だけを出す
                AppHeaderConditionSummary(conditions: [appSearchConditionText(search)].compactMap { $0 }, topPadding: 4)
            } else {
                Divider().overlay(appSeparatorColor)
                AppSearchField(text: $search, placeholder: placeholder).padding(.bottom, 4)
            }
        }
    }
}

struct GiriIndexSection<Item: Identifiable>: Identifiable {
    let id: String
    let title: String
    let items: [Item]
}

/// LiveStair IndexViews の見出し（あ行〜わ行・A〜Z・数字・その他）。
func giriKanaSectionTitle(_ reading: String) -> String {
    let trimmed = reading.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.first else { return "未設定" }
    let value = String(first)
    let half = value.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? value
    if half.range(of: #"^[0-9]$"#, options: .regularExpression) != nil { return "数字" }
    if half.range(of: #"^[A-Za-z]$"#, options: .regularExpression) != nil { return half.uppercased() }
    let kana = value.applyingTransform(.hiraganaToKatakana, reverse: false) ?? value
    if "アイウエオァィゥェォヴ".contains(kana) { return "あ行" }
    if "カキクケコガギグゲゴ".contains(kana) { return "か行" }
    if "サシスセソザジズゼゾ".contains(kana) { return "さ行" }
    if "タチツテトダヂヅデドッ".contains(kana) { return "た行" }
    if "ナニヌネノ".contains(kana) { return "な行" }
    if "ハヒフヘホバビブベボパピプペポ".contains(kana) { return "は行" }
    if "マミムメモ".contains(kana) { return "ま行" }
    if "ヤユヨャュョ".contains(kana) { return "や行" }
    if "ラリルレロ".contains(kana) { return "ら行" }
    if "ワヲン".contains(kana) { return "わ行" }
    return "その他"
}

func giriKanaSectionOrder(_ title: String) -> Int {
    let kana = ["あ行", "か行", "さ行", "た行", "な行", "は行", "ま行", "や行", "ら行", "わ行"]
    if let index = kana.firstIndex(of: title) { return index }
    if title.count == 1, let scalar = title.unicodeScalars.first, (65...90).contains(scalar.value) { return 100 + Int(scalar.value - 65) }
    switch title {
    case "数字": return 200
    case "その他": return 201
    default: return 202
    }
}

struct GiriPlayersView: View {
    @EnvironmentObject private var store: GiriStore
    @State private var query = ""
    @State private var isHeaderCollapsed = false
    @State private var adding = false
    private var players: [GiriPlayer] {
        store.playerDirectory.filter { query.isEmpty || "\($0.name) \($0.furigana) \($0.region)".localizedStandardContains(query) }
            .sorted { ($0.furigana.isEmpty ? $0.name : $0.furigana).localizedStandardCompare($1.furigana.isEmpty ? $1.name : $1.furigana) == .orderedAscending }
    }
    private var sections: [GiriIndexSection<GiriPlayer>] {
        let groups = Dictionary(grouping: players) { giriKanaSectionTitle($0.furigana.isEmpty ? $0.name : $0.furigana) }
        return groups.keys.sorted { giriKanaSectionOrder($0) < giriKanaSectionOrder($1) }
            .map { GiriIndexSection(id: $0, title: $0, items: groups[$0] ?? []) }
    }
    var body: some View {
        let used = store.referencedPlayerKeys
        let selfKeys = store.preferences.selfKeys
        let values = sections
        List {
            if values.isEmpty {
                Section {
                    CenteredEmptyMessage(systemImage: "person.2", title: query.isEmpty ? "プレイヤーがいません" : "該当するプレイヤーがいません")
                }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            }
            ForEach(values) { section in
                Section {
                    AppIndexSectionTitle(title: section.title, count: section.items.count, systemImage: "person.2.fill", accentColor: AppSectionAccent.artist)
                        .listRowSeparator(.hidden)
                    ForEach(section.items) { player in
                        playerRow(player, deletable: !player.id.hasPrefix("history:") && !selfKeys.contains(playerSearchKey(player.name)) && !used.contains(playerSearchKey(player.name)))
                    }
                }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            }
        }
        .appIndexListStyle()
        .safeAreaInset(edge: .top, spacing: 0) {
            GiriIndexHeader(accentColor: AppSectionAccent.artist, count: players.count, search: $query,
                            placeholder: "名前・フリガナ・地域で検索", isCollapsed: $isHeaderCollapsed)
        }
        .navigationTitle("大喜利プレイヤー一覧").navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("プレイヤーを追加")
            }
        }
        .sheet(isPresented: $adding) { NavigationStack { GiriPlayerEditor() } }
    }

    private func playerRow(_ player: GiriPlayer, deletable: Bool) -> some View {
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
        // LiveStair IndexViews と同じく、記録のないプレイヤーだけ削除できる。
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if deletable {
                Button(role: .destructive) { delete(player) } label: { Label("削除", systemImage: "trash") }
            }
        }
        .contextMenu {
            if deletable {
                Button(role: .destructive) { delete(player) } label: { Label("プレイヤーを削除", systemImage: "trash") }
            }
        }
    }

    private func delete(_ player: GiriPlayer) {
        store.run {
            try store.deletePlayer(player.id)
            playLiveStairDeleteFeedback()
        }
    }
}

// MARK: - プレイヤー詳細（ArtistDetailView）

struct GiriPlayerDetail: View {
    @EnvironmentObject private var store: GiriStore
    @EnvironmentObject private var navigation: GiriNavigation
    var playerID: String
    @State private var resolvedID: String?
    @State private var page = 0
    @State private var year = "all"
    @State private var editing: GiriProfileEditSection?
    @State private var photo: PhotosPickerItem?
    @State private var deletingIcon = false
    @State private var loadingIcon = false

    private var player: GiriPlayer? { store.playerDirectory.first { $0.id == (resolvedID ?? playerID) } }

    var body: some View {
        Group {
            if let player {
                VStack(spacing: 0) {
                    GiriProfileNameHeader(name: player.name, kind: .artist)
                    Picker("表示", selection: $page) {
                        Text("基本情報").tag(0)
                        Text("参加集計").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .tint(AppSectionAccent.artist)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
                    TabView(selection: $page) {
                        basicPage(player).tag(0)
                        analyticsPage(player).tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
                .sheet(item: $editing) { section in
                    NavigationStack { GiriPlayerEditor(player: player, section: section, onSaved: { resolvedID = $0.id }) }
                }
                .onChange(of: photo) { _, item in
                    guard let item else { return }
                    Task { await saveIcon(item, player: player) }
                }
                .alert("アイコンを削除しますか？", isPresented: $deletingIcon) {
                    Button("キャンセル", role: .cancel) {}
                    Button("削除", role: .destructive) { removeIcon(player) }
                } message: { Text("このプレイヤーのアイコンを削除します。") }
            } else {
                CenteredEmptyMessage(systemImage: "person", title: "プレイヤーが見つかりません")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("プレイヤー詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(appBackgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .background { appBackgroundColor.ignoresSafeArea() }
    }

    // MARK: 基本情報

    private func basicPage(_ player: GiriPlayer) -> some View {
        let key = playerSearchKey(player.name)
        let together = store.events.filter { $0.isActualParticipant && giriEventPeople($0).contains { playerSearchKey($0) == key } }
        let hosted = store.events.filter { $0.isActualParticipant && playerSearchKey($0.organizer) == key }
        let favorites = store.notes.flatMap(\.otherAnswerRecords).filter { playerSearchKey($0.answerer) == key }
        let authored = store.notes.filter { playerSearchKey($0.promptAuthor) == key }
        return ScrollView {
            VStack(spacing: 14) {
                GiriDetailCard(title: "基本情報", systemImage: "person.text.rectangle", accentColor: AppSectionAccent.artist,
                               trailing: { GiriCardEditButton { editing = .basic } }) {
                    VStack(spacing: 0) {
                        GiriProfileInfoRow(title: "プレイヤー名", value: player.name)
                        Divider().overlay(appSeparatorColor)
                        GiriProfileInfoRow(title: "フリガナ", value: player.furigana.isEmpty ? "未設定" : player.furigana)
                        Divider().overlay(appSeparatorColor)
                        GiriProfileInfoRow(title: "地域", value: player.region)
                    }
                }
                iconCard(player)
                GiriDetailCard(title: "ショートカット", systemImage: "arrow.up.right.square", accentColor: AppSectionAccent.live) {
                    VStack(spacing: 0) {
                        GiriProfileShortcutButton(title: "このプレイヤーと参加した会", systemImage: "list.bullet", accentColor: AppSectionAccent.live,
                                                  countText: "\(together.count)件") {
                            navigation.openList(players: [player.name])
                        }
                        Divider().overlay(appSeparatorColor)
                        GiriProfileShortcutButton(title: "好きな回答", systemImage: "text.bubble", accentColor: AppSectionAccent.live,
                                                  countText: "\(favorites.count)件") {
                            navigation.openThoughts(answerer: player.name)
                        }
                        Divider().overlay(appSeparatorColor)
                        GiriProfileShortcutButton(title: "作ったお題", systemImage: "lightbulb", accentColor: AppSectionAccent.live,
                                                  countText: "\(authored.count)件") {
                            navigation.openThoughts(author: player.name)
                        }
                        Divider().overlay(appSeparatorColor)
                        GiriProfileShortcutRow(title: "主催した会", systemImage: "person.crop.circle", accentColor: AppSectionAccent.live,
                                               countText: "\(hosted.count)件") {
                            GiriProfileRecordsPage(title: "\(player.name)の主催") { event in
                                playerSearchKey(event.organizer) == key
                            }
                        }
                    }
                }
                GiriDetailCard(title: "リンク", systemImage: "link", accentColor: AppSectionAccent.memo,
                               trailing: { GiriCardEditButton { editing = .links } }) {
                    let url = giriWebURL(player.twitterUrl)
                    let handle = giriXDisplayText(player.twitterUrl)
                    GiriProfileLinkRow(title: "X", displayText: handle, url: url, iconName: url != nil && handle.isEmpty ? "safari" : nil)
                }
                GiriDetailCard(title: "メモ", systemImage: "note.text", accentColor: AppSectionAccent.memo,
                               trailing: { GiriCardEditButton { editing = .memo } }) {
                    if player.memo.isEmpty {
                        Text("未設定").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
                    } else {
                        Text(player.memo).font(.subheadline).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                    }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: アイコン（ArtistDetailView.artistPhotoSection を小さなアイコン用にしたもの）

    private func iconCard(_ player: GiriPlayer) -> some View {
        let accent = AppSectionAccent.ticket
        let image = Data(base64Encoded: player.iconDataBase64).flatMap(UIImage.init(data:))
        return GiriDetailCard(title: "アイコン", systemImage: "photo", accentColor: accent,
                              infoTitle: "アイコンについて",
                              infoMessage: "一覧や会の参加者に表示します。表示するかは設定の「プレイヤーのアイコン」で選べます。",
                              trailing: {
            if image != nil {
                Button(role: .destructive) { deletingIcon = true } label: {
                    Label("削除", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accentActionColor)
                }
                .buttonStyle(.plain)
            }
        }) {
            PhotosPicker(selection: $photo, matching: .images) {
                HStack(spacing: 14) {
                    ZStack {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())
                                .overlay { Circle().stroke(accent.opacity(0.28), lineWidth: 1) }
                        } else {
                            Circle().fill(accent.opacity(0.10)).frame(width: 64, height: 64)
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: appFontSize(22), weight: .semibold))
                                .foregroundStyle(accent)
                        }
                        if loadingIcon { ProgressView() }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(image == nil ? "アイコンを選択" : "アイコンを変更")
                            .font(.system(size: appFontSize(16), weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text(image == nil ? "プレイヤーのアイコンとして保存されます" : "タップして別の写真を選びます")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                }
                .padding(10)
                .background(accent.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(accent.opacity(0.22), lineWidth: 1) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(loadingIcon)
        }
    }

    @MainActor private func saveIcon(_ item: PhotosPickerItem, player: GiriPlayer) async {
        loadingIcon = true
        defer { loadingIcon = false; photo = nil }
        do {
            var updated = player
            updated.iconDataBase64 = try await giriPlayerIconBase64(from: item)
            try store.savePlayer(updated)
            resolvedID = store.playerByName(updated.name)?.id ?? resolvedID
            playLiveStairSaveFeedback()
        } catch { store.errorMessage = error.localizedDescription }
    }

    private func removeIcon(_ player: GiriPlayer) {
        var updated = player
        updated.iconDataBase64 = ""
        store.run {
            try store.savePlayer(updated)
            resolvedID = store.playerByName(updated.name)?.id ?? resolvedID
            playLiveStairDeleteFeedback()
        }
    }

    // MARK: 参加集計（ArtistDetailView.artistAnalyticsSlide）

    private func analyticsPage(_ player: GiriPlayer) -> some View {
        let now = Date()
        let key = playerSearchKey(player.name)
        let selfKeys = store.preferences.selfKeys
        let together = store.events.filter { $0.isActualParticipant && giriEventPeople($0).contains { playerSearchKey($0) == key } }
        let completed = together.filter { $0.isCountableParticipation(now: now) }
        let mine = store.events.filter { $0.isCountableParticipation(now: now) }
        let years = Array(Set(completed.compactMap(giriAnalyticsDate).map { String(Calendar(identifier: .gregorian).component(.year, from: $0)) })).sorted(by: >)
        func inYear(_ event: GiriEvent) -> Bool {
            year == "all" || giriAnalyticsDate(event).map { String(Calendar(identifier: .gregorian).component(.year, from: $0)) } == year
        }
        let period = completed.filter(inYear)
        let hosted = store.events.filter { $0.isCountableParticipation(now: now) && playerSearchKey($0.organizer) == key && inYear($0) }
        let ordered = completed.filter { giriAnalyticsDate($0) != nil }.sorted { (giriAnalyticsDate($0) ?? .distantPast) < (giriAnalyticsDate($1) ?? .distantPast) }
        let upcoming = together.filter { [.upcoming, .ongoing].contains($0.participationState(now: now)) }
            .sorted { (giriAnalyticsDate($0) ?? .distantFuture) < (giriAnalyticsDate($1) ?? .distantFuture) }
        let podiums = store.events.filter { $0.isCountableParticipation(now: now) && inYear($0) }.flatMap { event -> [(GiriEvent, TournamentStanding)] in
            event.standings.filter { standing in standing.playerNames.contains { playerSearchKey($0) == key } }.map { (event, $0) }
        }.sorted { $0.1.placement < $1.1.placement }
        let venues = giriRankItems(period.filter { $0.eventFormat.hasLiveTiming }.map { [$0.venue] })
        let coPlayers = giriRankItems(period.map(giriEventPeople), excluding: selfKeys.union([key]))
        let accent = AppSectionAccent.artist
        return ScrollView {
            VStack(spacing: 14) {
                GiriDetailCard(title: "参加集計", systemImage: "chart.bar.xaxis", accentColor: accent,
                               trailing: { GiriYearMenu(selection: $year, years: years) }) {
                    Divider().overlay(appSeparatorColor)
                    HStack(alignment: .center, spacing: 0) {
                        if year != "all" {
                            GiriCountColumn(title: "全期間", count: completed.count, total: mine.count, caption: "一緒に参加", accentColor: accent)
                            Divider().overlay(appSeparatorColor).frame(height: 66).padding(.horizontal, 12)
                        }
                        GiriCountColumn(title: year == "all" ? "全期間" : "\(year)年", count: period.count,
                                        total: mine.filter(inYear).count, caption: "一緒に参加", accentColor: accent)
                    }
                    HStack {
                        Text("主催した会").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(hosted.count)回").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    }
                    Divider().overlay(appSeparatorColor)
                    GiriProfileDateRow(title: "初めて一緒に参加した日", event: ordered.first)
                    GiriProfileDateRow(title: "最近一緒に参加した日", event: ordered.last)
                    GiriProfileDateRow(title: "次に一緒に参加する会", event: upcoming.first)
                }
                GiriDetailCard(title: "大会の上位成績", systemImage: "trophy", accentColor: AppSectionAccent.ticket) {
                    if podiums.isEmpty {
                        Text("データがありません").font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(podiums.enumerated()), id: \.offset) { index, record in
                                NavigationLink { GiriEventDetail(eventID: record.0.id) } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text(record.1.placement == 1 ? "優勝" : record.1.placement == 2 ? "準優勝" : "\(record.1.placement)位")
                                            .font(.subheadline.weight(.bold)).foregroundStyle(AppSectionAccent.ticket)
                                            .frame(width: 52, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(record.0.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                                            if !record.1.teamName.isEmpty { Text(record.1.teamName).font(.caption).foregroundStyle(.secondary) }
                                        }
                                        Spacer(minLength: 8)
                                        Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if index < podiums.count - 1 { Divider().overlay(appSeparatorColor) }
                            }
                        }
                    }
                }
                GiriRankingCard(title: "よく一緒になる会場", systemImage: "building.2", accentColor: AppSectionAccent.venue,
                                unit: "件", items: venues) { item in
                    if let venue = store.venueDirectory.first(where: { playerSearchKey($0.name) == item.id }) {
                        NavigationLink { GiriVenueDetail(venueID: venue.id) } label: {
                            GiriRankRowLabel(item: item) { EmptyView() }
                        }.buttonStyle(.plain)
                    } else {
                        GiriRankRowLabel(item: item) { EmptyView() }
                    }
                }
                GiriRankingCard(title: "よく一緒に参加するプレイヤー", systemImage: "person.2", accentColor: AppSectionAccent.song,
                                unit: "人", items: coPlayers) { item in
                    if let other = store.playerByName(item.name) {
                        NavigationLink { GiriPlayerDetail(playerID: other.id) } label: {
                            GiriRankRowLabel(item: item) { GiriPlayerAvatar(name: other.name, size: 40) }
                        }.buttonStyle(.plain)
                    } else {
                        GiriRankRowLabel(item: item) { EmptyView() }
                    }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - プレイヤーの編集（ArtistInfoEditor / ArtistLinkEditor をシートで開く）

struct GiriPlayerEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GiriPlayer
    @State private var photo: PhotosPickerItem?
    @State private var discard = false
    @State private var renaming = false
    private let original: GiriPlayer
    private let isNew: Bool
    private let section: GiriProfileEditSection?
    private var onSaved: ((GiriPlayer) -> Void)?

    init(player: GiriPlayer? = nil, section: GiriProfileEditSection? = nil, onSaved: ((GiriPlayer) -> Void)? = nil) {
        let value = player ?? GiriPlayer()
        _draft = State(initialValue: value)
        original = value
        isNew = player == nil
        self.section = section
        self.onSaved = onSaved
    }

    private func shows(_ value: GiriProfileEditSection) -> Bool { section == nil || section == value }
    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var changed: Bool { draft != original }
    private var title: String {
        if isNew { return "プレイヤーを追加" }
        switch section {
        case .links: return "リンクを編集"
        case .memo: return "メモを編集"
        default: return "基本情報を編集"
        }
    }

    var body: some View {
        Form {
            if shows(.basic) {
                Section {
                    AppCardSectionTitle(title: "基本情報", systemImage: "person.text.rectangle", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                    GiriProfileTextRow(title: "プレイヤー名", placeholder: "必須", text: $draft.name).textContentType(.nickname)
                    GiriProfileTextRow(title: "フリガナ", placeholder: "未入力", text: $draft.furigana)
                    GiriProfileTextRow(title: "地域", placeholder: "未入力", text: $draft.region)
                }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            }
            if isNew {
                Section {
                    AppCardSectionTitle(title: "アイコン", systemImage: "photo", accentColor: AppSectionAccent.ticket).listRowSeparator(.hidden)
                    PhotosPicker(selection: $photo, matching: .images) {
                        HStack(spacing: 12) {
                            if let data = Data(base64Encoded: draft.iconDataBase64), let image = UIImage(data: data) {
                                Image(uiImage: image).resizable().scaledToFill().frame(width: 52, height: 52).clipShape(Circle())
                            }
                            Label(draft.iconDataBase64.isEmpty ? "アイコンを選ぶ" : "アイコンを変更", systemImage: "photo")
                        }
                    }
                    if !draft.iconDataBase64.isEmpty { Button("アイコンを外す", role: .destructive) { draft.iconDataBase64 = "" } }
                }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
            }
            if shows(.links) {
                Section {
                    AppCardSectionTitle(title: "リンク", systemImage: "link", accentColor: AppSectionAccent.memo).listRowSeparator(.hidden)
                    GiriProfileTextRow(title: "X", placeholder: "@ID またはURL", text: $draft.twitterUrl)
                        .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
            }
            if shows(.memo) {
                Section {
                    AppCardSectionTitle(title: "メモ", systemImage: "note.text", accentColor: AppSectionAccent.memo).listRowSeparator(.hidden)
                    TextField("メモ", text: $draft.memo, axis: .vertical).lineLimit(4...12)
                }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
            }
        }
        .appEditorFormStyle()
        .giriNavigationBarStyle()
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { if changed { discard = true } else { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: requestSave).fontWeight(.bold).disabled(trimmedName.isEmpty)
            }
        }
        .interactiveDismissDisabled(changed)
        .giriDiscardChangesAlert(isPresented: $discard) { dismiss() }
        .alert("名前を変更しますか？", isPresented: $renaming) {
            Button("キャンセル", role: .cancel) {}
            Button("変更する") { save() }
        } message: {
            Text("「\(original.name)」を「\(trimmedName)」へ変更すると、これまでの記録の名前もすべて変更されます。")
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { @MainActor in
                do { draft.iconDataBase64 = try await giriPlayerIconBase64(from: item) }
                catch { store.errorMessage = error.localizedDescription }
                photo = nil
            }
        }
    }

    private func requestSave() {
        if !isNew && trimmedName != original.name { renaming = true } else { save() }
    }

    private func save() {
        store.run {
            var value = draft
            value.name = trimmedName
            value.twitterUrl = giriNormalizedXURL(value.twitterUrl)
            try store.savePlayer(value)
            onSaved?(store.playerByName(value.name) ?? value)
            playLiveStairSaveFeedback()
            dismiss()
        }
    }
}

// MARK: - 会場一覧

struct GiriVenuesView: View {
    @EnvironmentObject private var store: GiriStore
    @State private var query = ""
    @State private var isHeaderCollapsed = false
    @State private var adding = false
    private var venues: [GiriVenue] {
        store.venueDirectory.filter { query.isEmpty || "\($0.name) \($0.prefecture) \($0.mapAddress)".localizedStandardContains(query) }
    }
    /// LiveStair の会場一覧の「都道府県」順と同じく、都道府県ごとにまとめる。
    private var sections: [GiriIndexSection<GiriVenue>] {
        let groups = Dictionary(grouping: venues) { $0.prefecture.isEmpty ? "未設定" : $0.prefecture }
        func order(_ title: String) -> Int {
            if title == "未設定" { return 1000 }
            return GiriVenueEditor.prefectures.firstIndex(of: title) ?? 500
        }
        return groups.keys.sorted { order($0) == order($1) ? $0 < $1 : order($0) < order($1) }
            .map { GiriIndexSection(id: $0, title: $0, items: groups[$0] ?? []) }
    }
    var body: some View {
        let used = store.referencedVenueKeys
        let values = sections
        List {
            if values.isEmpty {
                Section {
                    CenteredEmptyMessage(systemImage: "mappin.and.ellipse", title: query.isEmpty ? "会場がありません" : "該当する会場がありません")
                }.appSectionCardStyle(accentColor: AppSectionAccent.venue)
            }
            ForEach(values) { section in
                Section {
                    AppIndexSectionTitle(title: section.title, count: section.items.count, systemImage: "mappin.and.ellipse", accentColor: AppSectionAccent.venue)
                        .listRowSeparator(.hidden)
                    ForEach(section.items) { venue in
                        venueRow(venue, deletable: !venue.id.hasPrefix("history:") && !used.ids.contains(venue.id) && !used.names.contains(playerSearchKey(venue.name)))
                    }
                }.appSectionCardStyle(accentColor: AppSectionAccent.venue)
            }
        }
        .appIndexListStyle()
        .safeAreaInset(edge: .top, spacing: 0) {
            GiriIndexHeader(accentColor: AppSectionAccent.venue, count: venues.count, search: $query,
                            placeholder: "会場名・都道府県・住所で検索", isCollapsed: $isHeaderCollapsed)
        }
        .navigationTitle("会場一覧").navigationBarTitleDisplayMode(.inline)
        .giriNavigationBarStyle()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("会場を追加")
            }
        }
        .sheet(isPresented: $adding) { NavigationStack { GiriVenueEditor() } }
    }

    private func venueRow(_ venue: GiriVenue, deletable: Bool) -> some View {
        NavigationLink { GiriVenueDetail(venueID: venue.id) } label: {
            HStack(spacing: 12) {
                AppIndexItemBadge(systemImage: "mappin.and.ellipse", color: AppSectionAccent.venue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(venue.name).font(.headline.weight(.semibold)).lineLimit(1)
                    if !venue.mapAddress.isEmpty { Text(venue.mapAddress).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }.layoutPriority(1)
                Spacer(minLength: 8)
            }.frame(minHeight: 48).padding(.vertical, 2)
        }
        // LiveStair IndexViews と同じく、記録のない会場だけ削除できる。
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if deletable {
                Button(role: .destructive) { delete(venue) } label: { Label("削除", systemImage: "trash") }
            }
        }
        .contextMenu {
            if deletable {
                Button(role: .destructive) { delete(venue) } label: { Label("会場を削除", systemImage: "trash") }
            }
        }
    }

    private func delete(_ venue: GiriVenue) {
        store.run {
            try store.deleteVenue(venue.id)
            playLiveStairDeleteFeedback()
        }
    }
}

// MARK: - 会場詳細（VenueDetailView）

struct GiriVenueDetail: View {
    @EnvironmentObject private var store: GiriStore
    @EnvironmentObject private var navigation: GiriNavigation
    var venueID: String
    @State private var resolvedID: String?
    @State private var page = 0
    @State private var year = "all"
    @State private var editing: GiriProfileEditSection?
    @State private var searchingMap = false
    @State private var choosingMapApp = false
    @Environment(\.openURL) private var openURL

    private var venue: GiriVenue? { store.venueDirectory.first { $0.id == (resolvedID ?? venueID) } }

    var body: some View {
        Group {
            if let venue {
                VStack(spacing: 0) {
                    GiriProfileNameHeader(name: venue.name, kind: .venue)
                    Picker("表示", selection: $page) {
                        Text("プロフィール").tag(0)
                        Text("参加集計").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .tint(page == 0 ? AppSectionAccent.venue : AppSectionAccent.song)
                    .labelsHidden()
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
                    TabView(selection: $page) {
                        profilePage(venue).tag(0)
                        analyticsPage(venue).tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
                .sheet(item: $editing) { section in
                    NavigationStack { GiriVenueEditor(venue: venue, section: section, onSaved: { resolvedID = $0.id }) }
                }
                .sheet(isPresented: $searchingMap) {
                    NavigationStack {
                        GiriMapSearchView(query: venue.name, showsClose: true) { item in applyMap(item, to: venue) }
                    }
                }
                .alert("地図アプリを選択", isPresented: $choosingMapApp) {
                    if let latitude = venue.latitude, let longitude = venue.longitude {
                        Button("Appleマップで開く") { openAppleMaps(venue, latitude: latitude, longitude: longitude) }
                        Button("Googleマップで開く") { openGoogleMaps(latitude: latitude, longitude: longitude) }
                    }
                    Button("キャンセル", role: .cancel) {}
                } message: { Text("外部アプリで地図を開きます。") }
            } else {
                CenteredEmptyMessage(systemImage: "mappin.and.ellipse", title: "会場が見つかりません")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("会場詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .scrollContentBackground(.hidden)
        .background { appBackgroundColor.ignoresSafeArea() }
        .toolbarBackground(appHeaderColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func matches(_ event: GiriEvent, venue: GiriVenue) -> Bool {
        event.eventFormat.hasLiveTiming && (event.venueId == venue.id || (!event.venue.isEmpty && playerSearchKey(event.venue) == playerSearchKey(venue.name)))
    }

    // MARK: プロフィール

    private func profilePage(_ venue: GiriVenue) -> some View {
        let count = store.events.filter { $0.isActualParticipant && matches($0, venue: venue) }.count
        return ScrollView {
            VStack(spacing: 14) {
                mapCard(venue)
                GiriDetailCard(title: "ショートカット", systemImage: "arrow.up.right.square", accentColor: AppSectionAccent.live, kind: .venue) {
                    Button {
                        navigation.openList(venue: venue.name)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "list.bullet").foregroundStyle(AppSectionAccent.live).frame(width: 24)
                            Text("この会場の参加記録").font(.body.weight(.semibold)).foregroundStyle(.primary)
                            Spacer()
                            Text("\(count)件").font(.subheadline).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                GiriDetailCard(title: "基本情報", systemImage: "building.2", accentColor: AppSectionAccent.artist, kind: .venue,
                               trailing: { GiriCardEditButton(kind: .venue) { editing = .basic } }) {
                    VStack(spacing: 0) {
                        GiriProfileInfoRow(title: "都道府県", value: venue.prefecture, labelWidth: 80, verticalPadding: 8)
                        Divider().overlay(appSeparatorColor)
                        GiriProfileInfoRow(title: "住所", value: venue.mapAddress, labelWidth: 80, verticalPadding: 8)
                    }
                }
                GiriDetailCard(title: "リンク", systemImage: "link", accentColor: AppSectionAccent.memo, kind: .venue,
                               trailing: { GiriCardEditButton(kind: .venue) { editing = .links } }) {
                    GiriProfileLinkRow(title: "地図のURL", displayText: "", url: giriWebURL(venue.mapUrl), iconName: "safari")
                }
                GiriDetailCard(title: "メモ", systemImage: "note.text", accentColor: AppSectionAccent.memo, kind: .venue,
                               trailing: { GiriCardEditButton(kind: .venue) { editing = .memo } }) {
                    if venue.memo.isEmpty {
                        Text("未設定").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
                    } else {
                        Text(venue.memo).font(.subheadline).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
    }

    /// VenueDetailView.venueMapSection
    private func mapCard(_ venue: GiriVenue) -> some View {
        let accent = AppSectionAccent.venue
        return GiriDetailCard(title: "マップ", systemImage: "mappin.and.ellipse", accentColor: accent, kind: .venue, trailing: {
            if venue.latitude != nil {
                HStack(spacing: 12) {
                    Button("変更") { searchingMap = true }
                    Button("解除") { removeMap(venue) }
                }
                .font(.subheadline)
                .foregroundStyle(accentActionColor)
            }
        }) {
            if let latitude = venue.latitude, let longitude = venue.longitude {
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)))) {
                    Marker(venue.name, coordinate: coordinate)
                }
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(accent.opacity(0.22), lineWidth: 1) }
                .contentShape(Rectangle())
                .onTapGesture { choosingMapApp = true }
                VStack(alignment: .leading, spacing: 4) {
                    Text(venue.name).font(.headline)
                    if !venue.mapAddress.isEmpty { Text(venue.mapAddress).font(.caption).foregroundStyle(.secondary) }
                }
            } else {
                Button { searchingMap = true } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: appFontSize(42)))
                        Text("地図情報を紐付け").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .background(appSubCardColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(accent.opacity(0.22), lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func applyMap(_ item: MKMapItem, to venue: GiriVenue) {
        var value = venue
        value.latitude = item.placemark.coordinate.latitude
        value.longitude = item.placemark.coordinate.longitude
        value.mapAddress = [item.placemark.administrativeArea, item.placemark.locality, item.placemark.thoroughfare, item.placemark.subThoroughfare].compactMap { $0 }.joined()
        if value.prefecture.isEmpty, let prefecture = item.placemark.administrativeArea { value.prefecture = prefecture }
        save(value)
    }

    private func removeMap(_ venue: GiriVenue) {
        var value = venue
        value.latitude = nil
        value.longitude = nil
        value.mapAddress = ""
        save(value)
    }

    private func save(_ value: GiriVenue) {
        store.run {
            try store.saveVenue(value)
            resolvedID = store.venueDirectory.first { playerSearchKey($0.name) == playerSearchKey(value.name) }?.id ?? resolvedID
            playLiveStairSaveFeedback()
        }
    }

    private func openAppleMaps(_ venue: GiriVenue, latitude: Double, longitude: Double) {
        let query = venue.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)&q=\(query)") { openURL(url) }
    }

    private func openGoogleMaps(latitude: Double, longitude: Double) {
        if let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(latitude),\(longitude)") { openURL(url) }
    }

    // MARK: 参加集計（VenueDetailView.venueArtistRankingSlide）

    private func analyticsPage(_ venue: GiriVenue) -> some View {
        let now = Date()
        let selfKeys = store.preferences.selfKeys
        let all = store.events.filter { $0.isCountableParticipation(now: now) && matches($0, venue: venue) }
        let years = Array(Set(all.compactMap(giriAnalyticsDate).map { String(Calendar(identifier: .gregorian).component(.year, from: $0)) })).sorted(by: >)
        let period = all.filter { event in
            year == "all" || giriAnalyticsDate(event).map { String(Calendar(identifier: .gregorian).component(.year, from: $0)) } == year
        }
        let latest = all.filter { giriAnalyticsDate($0) != nil }.max { (giriAnalyticsDate($0) ?? .distantPast) < (giriAnalyticsDate($1) ?? .distantPast) }
        let players = giriRankItems(period.map(giriEventPeople), excluding: selfKeys)
        let accent = AppSectionAccent.artist
        return ScrollView {
            VStack(spacing: 14) {
                GiriDetailCard(title: "参加集計", systemImage: "chart.bar.xaxis", accentColor: accent, kind: .venue,
                               trailing: { GiriYearMenu(selection: $year, years: years, tint: accentActionColor) }) {
                    VStack(spacing: 10) {
                        HStack(alignment: .center, spacing: 0) {
                            if year != "all" {
                                GiriCountColumn(title: "全期間", count: all.count, caption: "参加回数", accentColor: accent)
                                Rectangle().fill(appSeparatorColor).frame(width: 1, height: 72).padding(.horizontal, 14)
                            }
                            GiriCountColumn(title: year == "all" ? "全期間" : "\(year)年", count: period.count, caption: "参加回数", accentColor: accent)
                        }
                        Divider().overlay(appSeparatorColor)
                        GiriProfileDateRow(title: "最近参加した日", event: latest)
                    }
                }
                GiriRankingCard(title: "よく一緒に参加したプレイヤー", systemImage: "person.2", accentColor: AppSectionAccent.song,
                                kind: .venue, unit: "人", items: players) { item in
                    if let player = store.playerByName(item.name) {
                        NavigationLink { GiriPlayerDetail(playerID: player.id) } label: {
                            GiriRankRowLabel(item: item) { GiriPlayerAvatar(name: player.name, size: 40) }
                        }.buttonStyle(.plain)
                    } else {
                        GiriRankRowLabel(item: item) { EmptyView() }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - 会場の編集（VenueBasicInfoEditor / VenueLinkEditor をシートで開く）

struct GiriVenueEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GiriVenue
    @State private var discard = false
    @State private var renaming = false
    private let original: GiriVenue
    private let isNew: Bool
    private let section: GiriProfileEditSection?
    private var onSaved: ((GiriVenue) -> Void)?

    init(venue: GiriVenue? = nil, section: GiriProfileEditSection? = nil, onSaved: ((GiriVenue) -> Void)? = nil) {
        let value = venue ?? GiriVenue()
        _draft = State(initialValue: value)
        original = value
        isNew = venue == nil
        self.section = section
        self.onSaved = onSaved
    }

    private func shows(_ value: GiriProfileEditSection) -> Bool { section == nil || section == value }
    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var changed: Bool { draft != original }
    private var title: String {
        if isNew { return "会場を追加" }
        switch section {
        case .links: return "リンクを編集"
        case .memo: return "メモを編集"
        default: return "会場基本情報編集"
        }
    }

    var body: some View {
        Form {
            if shows(.basic) {
                Section {
                    AppCardSectionTitle(title: "会場名", systemImage: "mappin.and.ellipse", accentColor: AppSectionAccent.venue).listRowSeparator(.hidden)
                    GiriProfileTextRow(title: "会場名", placeholder: "必須", text: $draft.name)
                }.appSectionCardStyle(accentColor: AppSectionAccent.venue)
                Section {
                    AppCardSectionTitle(title: "基本情報", systemImage: "building.2", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                    Picker(selection: $draft.prefecture) {
                        Text("未設定").tag("")
                        ForEach(Self.prefectures, id: \.self) { Text($0).tag($0) }
                        if !draft.prefecture.isEmpty && !Self.prefectures.contains(draft.prefecture) { Text(draft.prefecture).tag(draft.prefecture) }
                    } label: { GiriEditorLabel("都道府県") }
                    .pickerStyle(.menu).tint(.primary)
                    if isNew {
                        NavigationLink {
                            GiriMapSearchView(query: draft.name) { item in
                                draft.latitude = item.placemark.coordinate.latitude
                                draft.longitude = item.placemark.coordinate.longitude
                                draft.mapAddress = [item.placemark.administrativeArea, item.placemark.locality, item.placemark.thoroughfare, item.placemark.subThoroughfare].compactMap { $0 }.joined()
                                if draft.prefecture.isEmpty, let prefecture = item.placemark.administrativeArea { draft.prefecture = prefecture }
                            }
                        } label: { Label("マップを検索して登録", systemImage: "map") }
                        if draft.latitude != nil {
                            LabeledContent("地図", value: draft.mapAddress.isEmpty ? "登録済み" : draft.mapAddress)
                            Button("マップの登録を外す", role: .destructive) { draft.latitude = nil; draft.longitude = nil; draft.mapAddress = "" }
                        }
                    }
                }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            }
            if shows(.links) {
                Section {
                    AppCardSectionTitle(title: "リンク", systemImage: "link", accentColor: AppSectionAccent.memo).listRowSeparator(.hidden)
                    GiriProfileTextRow(title: "地図のURL", placeholder: "https://", text: $draft.mapUrl)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
            }
            if shows(.memo) {
                Section {
                    AppCardSectionTitle(title: "メモ", systemImage: "note.text", accentColor: AppSectionAccent.memo).listRowSeparator(.hidden)
                    TextField("メモ", text: $draft.memo, axis: .vertical).lineLimit(3...8)
                }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
            }
        }
        .appEditorFormStyle()
        .giriNavigationBarStyle()
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { if changed { discard = true } else { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: requestSave).fontWeight(.bold).disabled(trimmedName.isEmpty)
            }
        }
        .interactiveDismissDisabled(changed)
        .giriDiscardChangesAlert(isPresented: $discard) { dismiss() }
        .alert("会場名を変更しますか？", isPresented: $renaming) {
            Button("キャンセル", role: .cancel) {}
            Button("変更する") { save() }
        } message: {
            Text("「\(original.name)」を「\(trimmedName)」へ変更すると、これまでの記録の会場名もすべて変更されます。")
        }
    }

    private func requestSave() {
        if !isNew && trimmedName != original.name { renaming = true } else { save() }
    }

    private func save() {
        store.run {
            var value = draft
            value.name = trimmedName
            value.mapUrl = value.mapUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            try store.saveVenue(value)
            onSaved?(store.venueDirectory.first { playerSearchKey($0.name) == playerSearchKey(value.name) } ?? value)
            playLiveStairSaveFeedback()
            dismiss()
        }
    }

    static let prefectures = ["北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県", "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県", "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県", "岐阜県", "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府", "兵庫県", "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県", "広島県", "山口県", "徳島県", "香川県", "愛媛県", "高知県", "福岡県", "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県"]
}

/// VenueMapSearchView。シートで開いた場合は「閉じる」を出す。
struct GiriMapSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: GiriStore
    @State var query: String
    var showsClose = false
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
                    Button { onSelect(item); dismiss() } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name ?? "名称未設定").foregroundStyle(.primary)
                            Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.appSectionCardStyle(accentColor: AppSectionAccent.venue)
        }
        .appIndexListStyle()
        .giriNavigationBarStyle()
        .navigationTitle("マップ検索").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsClose {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
        }
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
