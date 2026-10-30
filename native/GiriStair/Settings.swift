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
        List {
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
                NavigationLink("形式タブの並び順") { GiriFormatOrderEditor() }
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
                    settingsValueRow(title: "最終書き出し", value: GiriDateText.backupDateTime(backup))
                }
            }
            settingSection("support", "サポート", "questionmark.circle", AppSectionAccent.venue) {
                settingsValueRow(title: "使い方ガイド", value: "準備中")
                settingsValueRow(title: "利用規約・プライバシーポリシー", value: "準備中")
                settingsValueRow(title: "サポート・お問い合わせ", value: "準備中")
                settingsValueRow(title: "バージョン", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            }
        }
        .environment(\.defaultMinListRowHeight, 48)
        .appIndexListStyle()
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

    // LiveStair SettingsView.settingsValueRow: preserve the body label and
    // trailing subheadline value instead of shrinking the entire row.
    private func settingsValueRow(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.body).foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .multilineTextAlignment(.trailing)
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

/// Standard iOS reordering; the first format is the default on list/results.
private struct GiriFormatOrderEditor: View {
    @EnvironmentObject private var store: GiriStore

    var body: some View {
        List {
            Section {
                ForEach(store.preferences.effectiveFormatOrder) { format in
                    Text(format.title).font(.body)
                }
                .onMove(perform: move)
            }
        }
        .appIndexListStyle()
        .environment(\.editMode, .constant(.active))
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle("形式タブの並び順")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func move(from source: IndexSet, to destination: Int) {
        var preferences = store.preferences
        var order = preferences.effectiveFormatOrder
        order.move(fromOffsets: source, toOffset: destination)
        preferences.formatOrder = order
        store.run { try store.savePreferences(preferences) }
    }
}
