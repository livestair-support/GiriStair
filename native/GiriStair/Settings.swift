import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct GiriSettingsView: View {
    @EnvironmentObject private var store: GiriStore
    @State private var collapsed: Set<String> = ["notifications", "data"]
    @State private var importing = false
    @State private var restoreData: Data?
    @State private var confirmRestore = false
    @State private var shareURL: URL?
    @State private var sharing = false
    @State private var notificationBusy = false

    var body: some View {
        Form {
            settingSection("profile", "自分のプロフィール", "person.crop.circle", AppSectionAccent.artist) {
                NavigationLink("自分の名前") { GiriSelfProfileEditor() }
            }
            settingSection("share", "共有ページ", "square.and.arrow.up", AppSectionAccent.live) {
                NavigationLink("Giri Summary") { GiriSharingView(initialList: false) }
                NavigationLink("Giri List") { GiriSharingView(initialList: true) }
            }
            settingSection("statistics", "集計", "chart.bar", AppSectionAccent.ticket) {
                NavigationLink("参加回数・会場・参加者") { GiriStatisticsView() }
            }
            settingSection("directories", "一覧", "person.2", AppSectionAccent.artist) {
                NavigationLink("大喜利プレイヤー一覧") { GiriPlayersView() }
                NavigationLink("会場一覧") { GiriVenuesView() }
                NavigationLink("ネット大喜利サイト一覧") { GiriSitesView() }
            }
            settingSection("defaults", "デフォルト設定", "slider.horizontal.3", AppSectionAccent.live) {
                Picker("テーマ", selection: preference(\.theme)) {
                    Text("端末に合わせる").tag("system")
                    Text("ライト").tag("light")
                    Text("ダーク").tag("dark")
                    Text("GiriStair").tag("stair")
                }.pickerStyle(.menu).tint(.primary)
                Picker("プレイヤーのアイコン", selection: preference(\.playerIconMode)) {
                    Text("自動").tag("auto")
                    Text("表示").tag("show")
                    Text("非表示").tag("hide")
                }.pickerStyle(.menu).tint(.primary)
                Stepper("投稿期間　\(store.preferences.submissionDays)日", value: preference(\.submissionDays), in: 1...365)
                Stepper("投票期間　\(store.preferences.votingDays)日", value: preference(\.votingDays), in: 1...365)
                Picker("投稿開始の日", selection: preference(\.submissionStartDayOffset)) {
                    ForEach(Array(Set(Array(-7...1) + [store.preferences.submissionStartDayOffset])).sorted(), id: \.self) { offset in
                        Text(offset == -1 ? "開催日の前日" : offset == 0 ? "開催日当日" : offset == 1 ? "翌日" : "\(-offset)日前").tag(offset)
                    }
                }.pickerStyle(.menu).tint(.primary)
                OptionalDateRow(title: "投稿開始の時刻", selection: defaultStartTime, components: .hourAndMinute)
            }
            settingSection("notifications", "通知", "bell", AppSectionAccent.scan) {
                Toggle("予定・締切の通知", isOn: Binding(get: { store.preferences.notificationsEnabled }, set: enableNotifications))
                    .tint(AppSectionAccent.scan).disabled(notificationBusy)
                if store.preferences.notificationsEnabled {
                    Picker("開始・締切の前", selection: preference(\.reminderMinutes)) {
                        ForEach(Array(Set([0, 15, 30, 60, 120, 1440, store.preferences.reminderMinutes])).sorted(), id: \.self) { minute in
                            Text(minute == 0 ? "時刻ちょうど" : minute < 60 ? "\(minute)分" : minute == 1440 ? "1日" : "\(minute / 60)時間").tag(minute)
                        }
                    }.pickerStyle(.menu).tint(.primary)
                    OptionalDateRow(title: "時刻未定の当日通知", selection: morningTime, components: .hourAndMinute)
                }
            }
            settingSection("data", "データ管理", "externaldrive", AppSectionAccent.memo) {
                Button("バックアップを書き出す", action: exportBackup)
                Button("バックアップから復元") { importing = true }
                if let backup = store.document.lastBackupAt {
                    LabeledContent("最終書き出し", value: backup.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            settingSection("support", "サポート", "questionmark.circle", AppSectionAccent.venue) {
                NavigationLink("はじめにガイド") { GiriGuideView() }
                Link("使い方ガイド", destination: URL(string: "https://github.com/livestair-support/GiriStair/blob/main/docs/SPEC.md")!)
                NavigationLink("プライバシーについて") { GiriPrivacyView() }
                Link("サポート・お問い合わせ", destination: URL(string: "https://github.com/livestair-support/GiriStair/issues")!)
                LabeledContent("バージョン", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    .foregroundStyle(.secondary)
            }
        }
        .appEditorFormStyle()
        .safeAreaInset(edge: .top, spacing: 0) {
            AppPageHeader(title: "設定", systemImage: "slider.horizontal.3", accentColor: AppSectionAccent.memo)
        }
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false, onCompletion: importBackup)
        .confirmationDialog("現在の記録をバックアップの内容に置き換えますか？", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("復元", role: .destructive) {
                guard let data = restoreData else { return }
                store.run { try store.restoreBackup(data) }
                restoreData = nil
            }
            Button("キャンセル", role: .cancel) { restoreData = nil }
        }
        .sheet(isPresented: $sharing) {
            if let shareURL {
                GiriShareSheet(items: [shareURL]) { completed in
                    if completed { store.run { try store.recordBackupExported() } }
                }
            }
        }
    }

    @ViewBuilder private func settingSection<Content: View>(_ id: String, _ title: String, _ icon: String, _ accent: Color, @ViewBuilder content: () -> Content) -> some View {
        Section {
            Button {
                withAnimation { if !collapsed.insert(id).inserted { collapsed.remove(id) } }
            } label: {
                HStack {
                    AppCardSectionTitle(title: title, systemImage: icon, accentColor: accent)
                    Image(systemName: collapsed.contains(id) ? "chevron.down.circle" : "chevron.up.circle").foregroundStyle(accent)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).listRowSeparator(.hidden)
            if !collapsed.contains(id) { content() }
        }.appSectionCardStyle(accentColor: accent)
    }
    private func preference<T>(_ key: WritableKeyPath<AppPreferences, T>) -> Binding<T> {
        Binding(get: { store.preferences[keyPath: key] }, set: { value in
            var preferences = store.preferences
            preferences[keyPath: key] = value
            store.run { try store.savePreferences(preferences) }
        })
    }
    private var defaultStartTime: Binding<Date?> {
        Binding(get: { Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: store.preferences.submissionStartHour, minute: store.preferences.submissionStartMinute)) }, set: { date in
            guard let date else { return }
            var preferences = store.preferences
            preferences.submissionStartHour = Calendar.current.component(.hour, from: date)
            preferences.submissionStartMinute = Calendar.current.component(.minute, from: date)
            store.run { try store.savePreferences(preferences) }
        })
    }
    private var morningTime: Binding<Date?> {
        Binding(get: { Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: store.preferences.reminderHour, minute: store.preferences.reminderMinute)) }, set: { date in
            guard let date else { return }
            var preferences = store.preferences
            preferences.reminderHour = Calendar.current.component(.hour, from: date)
            preferences.reminderMinute = Calendar.current.component(.minute, from: date)
            store.run { try store.savePreferences(preferences) }
        })
    }
    private func enableNotifications(_ enabled: Bool) {
        notificationBusy = true
        Task { @MainActor in
            defer { notificationBusy = false }
            do {
                if enabled {
                    let granted = try await NotificationsCoordinator.requestAuthorization()
                    if !granted {
                        store.errorMessage = "端末の「設定」からGiriStairの通知を許可してください。"
                        return
                    }
                }
                var preferences = store.preferences
                preferences.notificationsEnabled = enabled
                try store.savePreferences(preferences)
                await NotificationsCoordinator.sync(store: store)
            } catch { store.errorMessage = error.localizedDescription }
        }
    }
    private func exportBackup() {
        store.run {
            let data = try store.exportBackup()
            let name = "GiriStair-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            shareURL = url
            sharing = true
        }
    }
    private func importBackup(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 32 * 1024 * 1024 else { throw GiriSettingsError.invalidBackup }
            let data = try Data(contentsOf: url)
            guard data.count <= 32 * 1024 * 1024 else { throw GiriSettingsError.invalidBackup }
            _ = try JSONSerialization.jsonObject(with: data)
            restoreData = data
            confirmRestore = true
        } catch { store.errorMessage = error.localizedDescription }
    }
}

private enum GiriSettingsError: LocalizedError {
    case invalidBackup
    var errorDescription: String? { "バックアップを読み込めませんでした。GiriStairで書き出した32MB以下のJSONファイルを選んでください。" }
}

struct GiriSelfProfileEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    var body: some View {
        Form {
            Section {
                AppCardSectionTitle(title: "自分のプロフィール", systemImage: "person.crop.circle", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                TextField("自分の名前", text: $name).textContentType(.nickname)
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
        }.appEditorFormStyle().toolbar(.visible, for: .navigationBar).navigationTitle("自分の名前").navigationBarTitleDisplayMode(.inline)
            .onAppear { name = store.preferences.selfName }
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    store.run {
                        var preferences = store.preferences
                        preferences.selfName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        preferences.onboardingCompleted = true
                        try store.savePreferences(preferences)
                        playLiveStairSaveFeedback()
                        dismiss()
                    }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } }
    }
}

private struct GiriGuideView: View {
    var body: some View {
        Form {
            guide("予定と参加記録", "plus.circle", "登録から生大喜利やネット大喜利の予定を保存します。参加後は詳細で「参加済み」に変更すると集計に反映されます。")
            guide("継続するネット大喜利", "globe", "サイトを一度登録すると、一覧から今週・来週の回を開けます。参加してからお題と回答を記録します。投稿と投票の日程はそれぞれ管理できます。")
            guide("大会の結果", "trophy", "詳細画面で段階ごとの通過・敗退や得点、自分の最終結果と大会全体の優勝者を分けて保存します。敗退後も必要な投票は残せます。")
            guide("思考", "lightbulb", "お題ごとに回答案を並べたり、主催会に向けたお題を1つずつ保存できます。画像お題や使用済みの管理にも対応します。")
            guide("バックアップ", "externaldrive", "設定のデータ管理からJSONを書き出し、「ファイルに保存」を選びます。復元時は現在の記録を置き換えるため、必要な記録を先に保存してください。")
        }.appEditorFormStyle().toolbar(.visible, for: .navigationBar).navigationTitle("はじめにガイド").navigationBarTitleDisplayMode(.inline)
    }
    private func guide(_ title: String, _ icon: String, _ text: String) -> some View {
        Section {
            AppCardSectionTitle(title: title, systemImage: icon, accentColor: AppSectionAccent.memo).listRowSeparator(.hidden)
            Text(text).font(.body)
        }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
    }
}

struct GiriShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    var completion: ((Bool) -> Void)?
    init(items: [Any], completion: ((Bool) -> Void)? = nil) { self.items = items; self.completion = completion }
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in completion?(completed) }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct GiriPrivacyView: View {
    var body: some View {
        Form {
            Section {
                AppCardSectionTitle(title: "記録の保存", systemImage: "externaldrive", accentColor: AppSectionAccent.memo).listRowSeparator(.hidden)
                Text("参加記録、思考メモ、プレイヤーと設定は、この端末のアプリ専用領域に保存します。アカウントの作成や自動クラウド同期はありません。")
            }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
            Section {
                AppCardSectionTitle(title: "共有とバックアップ", systemImage: "square.and.arrow.up", accentColor: AppSectionAccent.live).listRowSeparator(.hidden)
                Text("共有・バックアップを選んだときは、選択したアプリや保存先へデータを渡します。参加者名やメモなど、画像・ファイルに含まれる内容を確認してから共有してください。")
            }.appSectionCardStyle(accentColor: AppSectionAccent.live)
            Section {
                AppCardSectionTitle(title: "画像の読み取りとマップ", systemImage: "viewfinder", accentColor: AppSectionAccent.venue).listRowSeparator(.hidden)
                Text("参加者の画像は端末上で文字を認識し、確認して追加するまで記録に保存しません。マップの検索・表示にはAppleの地図サービスへ検索語などを送信します。")
            }.appSectionCardStyle(accentColor: AppSectionAccent.venue)
        }.appEditorFormStyle().toolbar(.visible, for: .navigationBar).navigationTitle("プライバシーについて").navigationBarTitleDisplayMode(.inline)
    }
}
