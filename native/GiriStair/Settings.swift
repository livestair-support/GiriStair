import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct GiriSettingsView: View {
    @EnvironmentObject private var store: GiriStore
    // LiveStair SettingsView と同じく、折りたたんだセクションは次に開いた時も保つ。
    @AppStorage("giriSettingsCollapsedSections") private var collapsedRaw = "data,notifications"
    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: ",").map(String.init)) }
    @State private var notificationBusy = false

    var body: some View {
        List {
            settingSection("profile", "自分のプロフィール", "person.crop.circle", AppSectionAccent.artist) {
                NavigationLink("自分の名前・別名義") { GiriSelfProfileEditor() }
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
                NavigationLink("主催団体一覧") { GiriGroupsView() }
                NavigationLink("会場一覧") { GiriVenuesView() }
                NavigationLink("ネット大喜利サイト一覧") { GiriSitesView() }
            }
            settingSection("defaults", "デフォルト設定", "slider.horizontal.3", AppSectionAccent.live) {
                defaultSettingsGroupTitle("表示", systemImage: "eye")
                NavigationLink("使用する形式・並び順") { GiriFormatOrderEditor() }
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
                defaultSettingsGroupTitle("ネット大喜利の日程", systemImage: "calendar")
                Stepper("投稿期間　\(store.preferences.submissionDays)日", value: preference(\.submissionDays), in: 1...365)
                Stepper("投票期間　\(store.preferences.votingDays)日", value: preference(\.votingDays), in: 1...365)
                // 0.19：分かりにくい「投稿開始の日」は出さない（保存済みの値はそのまま使う）。
                settingsTimeRow("投稿開始の時刻", selection: defaultStartTime)
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
                    settingsTimeRow("時刻未定の当日通知", selection: morningTime)
                    // 0.19：募集期間の通知（LiveStair のチケット通知と同じく、開始前と開始時を分ける）。
                    defaultSettingsGroupTitle("募集期間", systemImage: "calendar.badge.clock")
                    Toggle("募集開始前の通知", isOn: preference(\.entryNotifyBefore)).tint(AppSectionAccent.scan)
                    if store.preferences.entryNotifyBefore {
                        Picker("どのくらい前", selection: entryLead) {
                            ForEach(Array(Set([5, 10, 15, 30, 60, 120, 180, 360, 720, 1440, 2880, entryLead.wrappedValue])).sorted(), id: \.self) { minute in
                                Text(giriLeadText(minute) + "前").tag(minute)
                            }
                        }.pickerStyle(.menu).tint(.primary)
                    }
                    Toggle("募集開始時の通知", isOn: preference(\.entryNotifyAtStart)).tint(AppSectionAccent.scan)
                }
            }
            settingSection("data", "データ管理", "externaldrive", AppSectionAccent.memo) {
                // 0.19：LiveStair と同じく自動バックアップ・最近削除・カレンダー・詳細データ管理を並べる。
                GiriDataSettingsRows()
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
    }

    /// 0.19：ほかの設定の行と同じ濃さの名前で、時刻を選ぶ。
    private func settingsTimeRow(_ title: String, selection: Binding<Date?>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.body).foregroundStyle(.primary)
            Spacer(minLength: 8)
            GiriTimeCapsulePicker(selection: selection) { Date() }
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

    // LiveStair SettingsView.settingsSectionTitleRow：見出しの右に折りたたみのボタン。
    @ViewBuilder private func settingSection<Content: View>(_ id: String, _ title: String, _ icon: String, _ accent: Color, @ViewBuilder content: () -> Content) -> some View {
        Section {
            HStack(spacing: 8) {
                AppCardSectionTitle(title: title, systemImage: icon, accentColor: accent)
                AppHeaderCollapseButton(isCollapsed: collapseBinding(id), tintColor: accent, subject: title)
            }
            .listRowSeparator(.hidden)
            if !collapsed.contains(id) { content() }
        }.appSectionCardStyle(accentColor: accent)
    }

    private func collapseBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { collapsed.contains(id) }, set: { isCollapsed in
            var values = collapsed
            if isCollapsed { values.insert(id) } else { values.remove(id) }
            collapsedRaw = values.sorted().joined(separator: ",")
        })
    }

    // LiveStair SettingsView.defaultSettingsGroupTitle
    private func defaultSettingsGroupTitle(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(AppSectionAccent.live)
            Text(title).foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.top, 8)
        .padding(.bottom, 4)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
    /// 募集開始前の通知の分数（以前の版の値がなければ「開始・締切の前」の分数。0 は60分にする）。
    private var entryLead: Binding<Int> {
        Binding(get: { max(5, store.preferences.entryLeadMinutes ?? (store.preferences.reminderMinutes == 0 ? 60 : store.preferences.reminderMinutes)) },
                set: { value in
                    var preferences = store.preferences
                    preferences.entryLeadMinutes = value
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
}

struct GiriSelfProfileEditor: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var aliases: [String] = []
    @State private var loaded = false
    @State private var discard = false
    private var cleanAliases: [String] { aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
    private var changed: Bool {
        loaded && (name.trimmingCharacters(in: .whitespacesAndNewlines) != store.preferences.selfName || cleanAliases != store.preferences.selfAliases)
    }
    var body: some View {
        Form {
            Section {
                AppCardSectionTitle(title: "自分のプロフィール", systemImage: "person.crop.circle", accentColor: AppSectionAccent.artist).listRowSeparator(.hidden)
                GiriProfileTextRow(title: "自分の名前", placeholder: "必須", text: $name).textContentType(.nickname)
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            Section {
                AppCardSectionTitle(title: "別名義", systemImage: "person.2.badge.gearshape", accentColor: AppSectionAccent.artist,
                                    infoTitle: "別名義について",
                                    infoMessage: "別の名前でも出ている場合に追加します。参加者や回答者にこの名前があると自分として扱います。")
                    .listRowSeparator(.hidden)
                ForEach(aliases.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        TextField("別名義", text: Binding(get: { aliases.indices.contains(index) ? aliases[index] : "" },
                                                        set: { if aliases.indices.contains(index) { aliases[index] = $0 } }))
                        Button(role: .destructive) { if aliases.indices.contains(index) { aliases.remove(at: index) } } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.borderless).accessibilityLabel("別名義を外す")
                    }
                }
                Button { aliases.append("") } label: { Label("別名義を追加", systemImage: "plus.circle") }.tint(accentActionColor)
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
        }
        .appEditorFormStyle().giriNavigationBarStyle().navigationTitle("自分の名前").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(changed)
        .onAppear {
            guard !loaded else { return }
            name = store.preferences.selfName
            aliases = store.preferences.selfAliases
            loaded = true
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if changed { Button { discard = true } label: { Image(systemName: "chevron.left") }.accessibilityLabel("戻る") }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    store.run {
                        var preferences = store.preferences
                        preferences.selfName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        preferences.selfAliases = cleanAliases
                        preferences.onboardingCompleted = true
                        try store.savePreferences(preferences)
                        playLiveStairSaveFeedback()
                        dismiss()
                    }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .giriDiscardChangesAlert(isPresented: $discard) { dismiss() }
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

/// 使う形式のチェックと並び順。先頭の形式が一覧・戦績で最初に開く。
/// チェックを外しても記録は消さず、タブと登録の選択肢にだけ出さない。
private struct GiriFormatOrderEditor: View {
    @EnvironmentObject private var store: GiriStore

    private var hidden: Set<EventFormat> { Set(store.preferences.hiddenFormats) }

    var body: some View {
        List {
            Section {
                AppCardSectionTitle(
                    title: "使用する形式",
                    systemImage: "square.grid.2x2",
                    accentColor: AppSectionAccent.live,
                    infoTitle: "使用する形式について",
                    infoMessage: "チェックを外した形式は、一覧・戦績のタブと登録の選択肢に出しません。記録は消えません。右の≡で並べ替えると、先頭の形式が最初に開きます。"
                )
                .listRowSeparator(.hidden)
                ForEach(store.preferences.effectiveFormatOrder) { format in
                    formatRow(format)
                }
                .onMove(perform: move)
            } footer: {
                Text("1つ以上の形式を選んでください。")
            }
            .appSectionCardStyle(accentColor: AppSectionAccent.live)
        }
        .environment(\.defaultMinListRowHeight, settingsMinimumListRowHeight)
        .appIndexListStyle()
        .environment(\.editMode, .constant(.active))
        .giriNavigationBarStyle()
        .navigationTitle("使用する形式・並び順")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formatRow(_ format: EventFormat) -> some View {
        let isVisible = !hidden.contains(format)
        let isLastVisible = isVisible && hidden.count >= EventFormat.allCases.count - 1
        return Button {
            toggle(format)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isVisible ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: appFontSize(20), weight: .semibold))
                    .foregroundStyle(isVisible ? GiriEventPresentation.accent(format) : Color.secondary)
                    .frame(width: 26)
                Text(format.title)
                    .font(.body)
                    .foregroundStyle(isVisible ? Color.primary : Color.secondary)
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(isLastVisible)
        .accessibilityLabel(format.title)
        .accessibilityValue(isVisible ? "使用する" : "使用しない")
    }

    private func toggle(_ format: EventFormat) {
        var preferences = store.preferences
        var values = Set(preferences.hiddenFormats)
        if values.contains(format) { values.remove(format) } else { values.insert(format) }
        guard values.count < EventFormat.allCases.count else { return }
        preferences.hiddenFormats = EventFormat.allCases.filter { values.contains($0) }
        store.run {
            try store.savePreferences(preferences)
            playLiveStairSaveFeedback()
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var preferences = store.preferences
        var order = preferences.effectiveFormatOrder
        order.move(fromOffsets: source, toOffset: destination)
        preferences.formatOrder = order
        store.run { try store.savePreferences(preferences) }
    }
}
