import SwiftUI

/// 0.23：通知の種類（LiveStair SettingsView の notificationKindHeader／notificationOptionRow と同じ形）。
/// 見出しの行に名前・ⓘ・オンオフ、その下に少し下げて設定の行を出す。
@MainActor
struct GiriNotificationKindRows: View {
    @EnvironmentObject private var store: GiriStore
    @State private var showingBeforePicker = false

    private var preferences: AppPreferences { store.preferences }

    var body: some View {
        Group {
            kindHeader("当日通知", systemImage: "sun.max", isOn: preference(\.dayNotify),
                       info: "大喜利会の当日、設定した時刻に、その日の会を知らせます。時刻が決まっていない会も知らせます。\n\nキャンセル・興味ありの会には通知しません。")
            if preferences.dayNotify {
                optionRow("時刻") { GiriTimeCapsulePicker(selection: morningTime) { Date() } }
            }

            kindHeader("会の前の通知", systemImage: "clock", isOn: preference(\.beforeNotify),
                       info: "生大喜利・短考・スプシ系の会の、開場または開始の設定した時間前に知らせます。\n\n「タイミング」をタップすると、基準（開場・開始）と何分前かを変えられます。")
            if preferences.beforeNotify {
                Button { showingBeforePicker = true } label: {
                    optionRow("タイミング") {
                        HStack(spacing: 4) {
                            Text(beforeDisplayText)
                            Image(systemName: "chevron.up.chevron.down").font(.caption)
                        }
                        .font(.subheadline)
                        .foregroundStyle(AppSectionAccent.scan)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            kindHeader("長考の締切前通知", systemImage: "hourglass", isOn: preference(\.deadlineBeforeNotify),
                       info: "長考などの投稿締切・投票締切の、設定した時間前に知らせます。参加を決めていないサイトの回は、投稿締切だけ知らせます。")
            if preferences.deadlineBeforeNotify {
                optionRow("どのくらい前") { leadPicker(deadlineLead, options: [5, 10, 15, 30, 60, 120, 180, 360, 720, 1440]) }
            }

            kindHeader("長考の締切通知", systemImage: "bell.badge", isOn: preference(\.deadlineAtNotify),
                       info: "長考などの投稿締切・投票締切の時刻ちょうどに知らせます。")

            kindHeader("募集開始前の通知", systemImage: "calendar.badge.clock", isOn: preference(\.entryNotifyBefore),
                       info: "大喜利会の「募集期間」に入れた募集開始の、設定した時間前に知らせます。")
            if preferences.entryNotifyBefore {
                optionRow("どのくらい前") { leadPicker(entryLead, options: [5, 10, 15, 30, 60, 120, 180, 360, 720, 1440, 2880]) }
            }

            kindHeader("募集開始時の通知", systemImage: "calendar", isOn: preference(\.entryNotifyAtStart),
                       info: "大喜利会の「募集期間」に入れた募集開始の時刻ちょうどに知らせます。")
        }
        .sheet(isPresented: $showingBeforePicker) { beforePickerSheet }
    }

    // MARK: Rows

    private func kindHeader(_ title: String, systemImage: String, isOn: Binding<Bool>, info: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: appFontSize(15), weight: .semibold))
                .foregroundStyle(AppSectionAccent.scan)
                .frame(width: 22)
            HStack(spacing: 6) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                AppInfoButton(title: "\(title)について", message: info, tintColor: AppSectionAccent.scan)
            }
            Spacer(minLength: 6)
            Toggle("", isOn: isOn).labelsHidden().tint(AppSectionAccent.scan)
        }
        .padding(.vertical, 2)
    }

    private func optionRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            content()
        }
        .padding(.leading, 32)
    }

    private func leadPicker(_ selection: Binding<Int>, options: [Int]) -> some View {
        Picker("どのくらい前", selection: selection) {
            ForEach(Array(Set(options + [selection.wrappedValue])).sorted(), id: \.self) { minute in
                Text(giriLeadText(minute) + "前").tag(minute)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(AppSectionAccent.scan)
    }

    // MARK: 会の前の通知のタイミング（LiveStair beforeNotificationPickerSheet）

    private var beforeDisplayText: String {
        (preferences.beforeBase == "open" ? "開場" : "開始") + " " + "\(beforeMinutes.wrappedValue)分前"
    }

    private var beforePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Picker("基準", selection: preference(\.beforeBase)) {
                        Text("開場").tag("open")
                        Text("開始").tag("start")
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    Picker("通知時間", selection: beforeMinutes) {
                        ForEach(Array(Set(Array(stride(from: 0, through: 180, by: 5)) + [beforeMinutes.wrappedValue])).sorted(), id: \.self) { minutes in
                            Text("\(minutes)分前").tag(minutes)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 12)
                Spacer()
            }
            .navigationTitle("会の前の通知")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { showingBeforePicker = false } }
            }
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }

    // MARK: Bindings

    private func preference<T>(_ key: WritableKeyPath<AppPreferences, T>) -> Binding<T> {
        Binding(get: { store.preferences[keyPath: key] }, set: { value in
            var updated = store.preferences
            updated[keyPath: key] = value
            store.run { try store.savePreferences(updated) }
        })
    }

    private func minutesBinding(_ key: WritableKeyPath<AppPreferences, Int?>, fallbackMinimum: Int) -> Binding<Int> {
        Binding(get: {
            let value = store.preferences[keyPath: key] ?? store.preferences.reminderMinutes
            return value < fallbackMinimum ? max(fallbackMinimum, 60) : value
        }, set: { value in
            var updated = store.preferences
            updated[keyPath: key] = value
            store.run { try store.savePreferences(updated) }
        })
    }

    /// 会の前の通知の分数（0 は時刻ちょうど）。
    private var beforeMinutes: Binding<Int> {
        Binding(get: { max(0, store.preferences.beforeMinutes ?? store.preferences.reminderMinutes) }, set: { value in
            var updated = store.preferences
            updated.beforeMinutes = value
            store.run { try store.savePreferences(updated) }
        })
    }
    /// 締切前の通知の分数（以前の版の値が 0 の時は60分にする。ちょうどの通知は別の種類）。
    private var deadlineLead: Binding<Int> { minutesBinding(\.deadlineLeadMinutes, fallbackMinimum: 5) }
    /// 募集開始前の通知の分数。
    private var entryLead: Binding<Int> { minutesBinding(\.entryLeadMinutes, fallbackMinimum: 5) }

    private var morningTime: Binding<Date?> {
        Binding(get: { Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: store.preferences.reminderHour, minute: store.preferences.reminderMinute)) }, set: { date in
            guard let date else { return }
            var updated = store.preferences
            updated.reminderHour = Calendar.current.component(.hour, from: date)
            updated.reminderMinute = Calendar.current.component(.minute, from: date)
            store.run { try store.savePreferences(updated) }
        })
    }
}
