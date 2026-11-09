import SwiftUI
import EventKit
import EventKitUI
import UniformTypeIdentifiers

// MARK: - 0.19 自動バックアップ（LiveStair と同じく1日1回・最新と1つ前の2つ）

/// 自動バックアップの保存先。端末の中か、選んだフォルダ（iCloud Drive など）。
enum GiriBackupDestination: String, CaseIterable, Identifiable {
    case device, folder
    var id: String { rawValue }
    var title: String { self == .device ? "端末" : "iCloud Drive（フォルダ）" }
}

struct GiriAutoBackupFile: Identifiable, Equatable {
    var url: URL
    var date: Date
    var size: Int
    var id: String { url.path }
}

@MainActor
enum GiriAutoBackup {
    static let destinationKey = "giriAutoBackupDestination"
    static let folderBookmarkKey = "giriAutoBackupFolderBookmark"
    static let monthlyKey = "giriAutoBackupMonthlyToFolder"
    private static let lastDayKey = "giriAutoBackupLastDay"
    private static let lastMonthKey = "giriAutoBackupLastMonth"
    private static let prefix = "GiriStair-auto-"

    static var destination: GiriBackupDestination {
        GiriBackupDestination(rawValue: UserDefaults.standard.string(forKey: destinationKey) ?? "") ?? .device
    }

    /// 端末の中の保存場所（アプリの書類とは別のフォルダ）。
    static var deviceFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("AutoBackups", isDirectory: true)
    }

    /// 選んだフォルダ（iCloud Drive など）。使う間だけアクセスを開く。
    static func withFolder<T>(_ body: (URL) throws -> T) rethrows -> T? {
        guard let bookmark = UserDefaults.standard.data(forKey: folderBookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale) else { return nil }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }

    static func setFolder(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: folderBookmarkKey)
    }

    static var folderName: String? {
        withFolder { $0.lastPathComponent }
    }

    /// 1日1回、最初に開いた時に作る。月1回はフォルダにも残す（設定した時だけ）。
    static func runIfNeeded(store: GiriStore, now: Date = Date()) {
        guard store.loaded else { return }
        let day = dayKey(now)
        if UserDefaults.standard.string(forKey: lastDayKey) != day {
            if (try? save(store: store, now: now)) != nil { UserDefaults.standard.set(day, forKey: lastDayKey) }
        }
        let month = String(day.prefix(6))
        if UserDefaults.standard.bool(forKey: monthlyKey), destination == .device,
           UserDefaults.standard.string(forKey: lastMonthKey) != month,
           let data = try? store.exportBackup().compressedForBackup() {
            let saved = (try? withFolder { folder -> Bool in
                try data.write(to: folder.appendingPathComponent("GiriStair-monthly-\(month).giribackup"), options: .atomic)
                return true
            }) ?? nil
            if saved == true { UserDefaults.standard.set(month, forKey: lastMonthKey) }
        }
    }

    /// 今すぐ保存する。最新と1つ前の2つまで残し、それより古いものは消す。保存先のフォルダに書けない時は端末に保存する。
    @discardableResult
    static func save(store: GiriStore, now: Date = Date()) throws -> URL {
        let data = try store.exportBackup().compressedForBackup()
        let name = prefix + fileStamp(now) + ".giribackup"
        if destination == .folder, let url = try? withFolder({ folder -> URL in
            let target = folder.appendingPathComponent(name)
            try data.write(to: target, options: .atomic)
            try prune(in: folder)
            return target
        }) {
            return url
        }
        try FileManager.default.createDirectory(at: deviceFolder, withIntermediateDirectories: true)
        let target = deviceFolder.appendingPathComponent(name)
        try data.write(to: target, options: .atomic)
        try prune(in: deviceFolder)
        return target
    }

    /// 保存先にある自動バックアップ（新しい順）。
    static func files() -> [GiriAutoBackupFile] {
        func list(_ folder: URL) -> [GiriAutoBackupFile] {
            let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
            return urls.filter { $0.lastPathComponent.hasPrefix(prefix) }.compactMap { url in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                return GiriAutoBackupFile(url: url, date: values?.contentModificationDate ?? .distantPast, size: values?.fileSize ?? 0)
            }.sorted { $0.date > $1.date }
        }
        if destination == .folder, let found = withFolder(list), !found.isEmpty { return found }
        return list(deviceFolder)
    }

    /// 自動バックアップの中身（圧縮を戻した JSON）。
    static func data(of file: GiriAutoBackupFile) throws -> Data {
        let raw: Data
        if destination == .folder, let folderData = try withFolder({ _ in try Data(contentsOf: file.url) }) { raw = folderData }
        else { raw = try Data(contentsOf: file.url) }
        return try raw.decompressedBackup()
    }

    private static func prune(in folder: URL) throws {
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for url in urls.dropFirst(2) { try? FileManager.default.removeItem(at: url) }
    }

    private static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func fileStamp(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02d-%02d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }
}

extension Data {
    /// 自動バックアップは容量を減らすため圧縮して保存する。
    func compressedForBackup() throws -> Data { try (self as NSData).compressed(using: .zlib) as Data }
    /// 圧縮した自動バックアップも、書き出した JSON もそのまま読めるようにする。
    func decompressedBackup() throws -> Data {
        if (try? JSONSerialization.jsonObject(with: self)) != nil { return self }
        return try (self as NSData).decompressed(using: .zlib) as Data
    }
}

// MARK: - 0.19 データ管理（設定のデータ管理セクション。LiveStair SettingsView と同じ並び）

/// 設定の「データ管理」に並べる行：自動バックアップの保存・復元、最近削除した会、カレンダー、詳細データ管理。
@MainActor
struct GiriDataSettingsRows: View {
    @EnvironmentObject private var store: GiriStore
    @State private var latestBackup: GiriAutoBackupFile?
    @State private var confirmSave = false
    @State private var confirmRestore = false
    @State private var message: String?

    var body: some View {
        Group {
            Button { confirmSave = true } label: {
                Text("自動バックアップを保存").font(.body).foregroundStyle(.primary)
            }
            Button { confirmRestore = true } label: {
                Text("自動バックアップから復元").font(.body).foregroundStyle(latestBackup == nil ? Color.secondary : Color.primary)
            }
            .disabled(latestBackup == nil)
            GiriDataValueRow(title: "最終バックアップ", value: latestBackup.map { GiriDateText.backupDateTime($0.date) } ?? "まだありません")
            NavigationLink { GiriRecentlyDeletedEventsView() } label: {
                HStack(spacing: 6) {
                    Text("最近削除した会").font(.body).foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if !store.deletedEvents.isEmpty {
                        Text("\(store.deletedEvents.count)件").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            NavigationLink { GiriCalendarBulkExportView() } label: {
                Text("カレンダーにまとめて追加").font(.body).foregroundStyle(.primary)
            }
            NavigationLink { GiriDataManagementView() } label: {
                HStack(spacing: 4) {
                    Text("詳細データ管理").font(.body).foregroundStyle(.primary).lineLimit(1)
                    AppInfoButton(title: "詳細データ管理について", message: "JSONの書き出し・復元、自動バックアップの保存先、ストレージ使用状況を確認できます。", tintColor: AppSectionAccent.memo)
                    Spacer(minLength: 0)
                }
            }
        }
        .tint(AppSectionAccent.memo)
        .onAppear { latestBackup = GiriAutoBackup.files().first }
        .alert("自動バックアップを保存しますか？", isPresented: $confirmSave) {
            Button("キャンセル", role: .cancel) {}
            Button("保存") {
                store.run {
                    try GiriAutoBackup.save(store: store)
                    latestBackup = GiriAutoBackup.files().first
                    playLiveStairSaveFeedback()
                    message = "自動バックアップを保存しました。"
                }
            }
        } message: { Text("自動バックアップは最新と1つ前の2つまで残します。それより古い分は消えます。1つ前の分は「詳細データ管理」から戻せます。") }
        .alert("自動バックアップから復元しますか？", isPresented: $confirmRestore) {
            Button("キャンセル", role: .cancel) {}
            Button("復元する", role: .destructive) {
                guard let file = latestBackup else { return }
                store.run {
                    try store.restoreBackup(try GiriAutoBackup.data(of: file))
                    message = GiriDateText.backupDateTime(file.date) + "の自動バックアップから復元しました。"
                }
            }
        } message: { Text("今の記録と設定を、最新の自動バックアップ（\(latestBackup.map { GiriDateText.backupDateTime($0.date) } ?? "—")）の内容に置き換えます。") }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        }
    }
}

/// LiveStair SettingsView.settingsValueRow と同じ形（名前は本文・値は右に小さく）。
struct GiriDataValueRow: View {
    let title: String
    let value: String
    var body: some View {
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
}

// MARK: - 0.19 詳細データ管理

@MainActor
struct GiriDataManagementView: View {
    @EnvironmentObject private var store: GiriStore
    @AppStorage(GiriAutoBackup.destinationKey) private var destinationRaw = GiriBackupDestination.device.rawValue
    @AppStorage(GiriAutoBackup.monthlyKey) private var monthlyToFolder = false
    @State private var backups: [GiriAutoBackupFile] = []
    @State private var folderName: String?
    // fileImporter は1つの画面に1つだけ付ける（2つ付けると片方が開かないため、選ぶものを切り替える）。
    @State private var pickKind = GiriDataPick.backup
    @State private var pickerShown = false
    @State private var importData: Data?
    @State private var restorePrevious = false
    @State private var shareURL: URL?
    @State private var sharing = false
    @State private var message: String?
    @State private var usage = GiriStorageUsage()

    private var destination: GiriBackupDestination { GiriBackupDestination(rawValue: destinationRaw) ?? .device }

    var body: some View {
        List {
            jsonSection
            autoBackupSection
            storageSection
        }
        .environment(\.defaultMinListRowHeight, settingsMinimumListRowHeight)
        .appIndexListStyle()
        .giriNavigationBarStyle()
        .navigationTitle("詳細データ管理")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .fileImporter(isPresented: $pickerShown,
                      allowedContentTypes: pickKind == .folder ? [.folder] : [.json, .data],
                      allowsMultipleSelection: false, onCompletion: picked)
        .modifier(GiriDataManagementAlerts(importData: $importData, restorePrevious: $restorePrevious, message: $message, previous: backups.count > 1 ? backups[1] : nil, onRestored: refresh))
        .sheet(isPresented: $sharing) {
            if let shareURL {
                GiriShareSheet(items: [shareURL]) { completed in
                    if completed { store.run { try store.recordBackupExported() } }
                    try? FileManager.default.removeItem(at: shareURL)
                }
            }
        }
    }

    private var jsonSection: some View {
        Section {
            AppCardSectionTitle(title: "JSON", systemImage: "doc.text", accentColor: AppSectionAccent.memo,
                                infoTitle: "JSONについて", infoMessage: "GiriStairのデータを書き出し、機種変更や別の端末への移行・復元に使います。復元すると今のデータは置き換わります。")
                .listRowSeparator(.hidden)
            Button { exportJSON() } label: { Text("JSONファイルを書き出す").font(.body).foregroundStyle(.primary) }
            Button { pick(.backup) } label: { Text("JSONから復元").font(.body).foregroundStyle(.primary) }
            if let date = store.document.lastBackupAt {
                GiriDataValueRow(title: "最終書き出し", value: GiriDateText.backupDateTime(date))
            }
        }
        .tint(AppSectionAccent.memo)
        .appSectionCardStyle(accentColor: AppSectionAccent.memo)
    }

    private var autoBackupSection: some View {
        Section {
            AppCardSectionTitle(title: "自動バックアップ", systemImage: "clock.arrow.circlepath", accentColor: AppSectionAccent.memo,
                                infoTitle: "自動バックアップについて", infoMessage: "1日1回、最初に開いた時に作ります。最新と1つ前の2つまで残し、容量を減らすため圧縮して保存します。")
                .listRowSeparator(.hidden)
            HStack(spacing: 8) {
                Text("保存先").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Picker("保存先", selection: Binding(get: { destination }, set: changeDestination)) {
                    ForEach(GiriBackupDestination.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Color.primary)
            }
            if destination == .folder || monthlyToFolder {
                Button { pick(.folder) } label: {
                    HStack(spacing: 8) {
                        Text("保存するフォルダ").font(.body).foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Text(folderName ?? "選ぶ").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            if destination == .device {
                Toggle("月1回 iCloud Drive にも保存", isOn: Binding(get: { monthlyToFolder }, set: { value in
                    monthlyToFolder = value
                    if value && folderName == nil { pick(.folder) }
                }))
                .tint(AppSectionAccent.memo)
            }
            if let latest = backups.first {
                GiriDataValueRow(title: "最新", value: GiriDateText.backupDateTime(latest.date))
            }
            if backups.count > 1 {
                Button { restorePrevious = true } label: {
                    Text("1つ前の自動バックアップから復元").font(.body).foregroundStyle(.primary)
                }
                GiriDataValueRow(title: "1つ前", value: GiriDateText.backupDateTime(backups[1].date))
            }
        }
        .tint(AppSectionAccent.memo)
        .appSectionCardStyle(accentColor: AppSectionAccent.memo)
    }

    private var storageSection: some View {
        Section {
            AppCardSectionTitle(title: "ストレージ使用状況", systemImage: "internaldrive", accentColor: AppSectionAccent.venue,
                                infoTitle: "ストレージ使用状況", infoMessage: "GiriStairがこの端末で使っている容量の目安です。画像は記録の中に含まれます。")
                .listRowSeparator(.hidden)
            GiriDataValueRow(title: "記録（会・お題・回答など）", value: usage.text(usage.document))
            GiriDataValueRow(title: "うち画像", value: usage.text(usage.images))
            GiriDataValueRow(title: "自動バックアップ", value: usage.text(usage.backups))
            GiriDataValueRow(title: "移行前の元データ・予備", value: usage.text(usage.spare))
            GiriDataValueRow(title: "合計", value: usage.text(usage.total))
            GiriDataValueRow(title: "件数", value: "会\(store.events.count)件・お題\(store.notes.count)件・プレイヤー\(store.players.count)人")
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.venue)
    }

    private func refresh() {
        backups = GiriAutoBackup.files()
        folderName = GiriAutoBackup.folderName
        usage = GiriStorageUsage.measure(store: store)
    }

    private func changeDestination(_ value: GiriBackupDestination) {
        if value == .folder && folderName == nil {
            pick(.folder)
            return
        }
        destinationRaw = value.rawValue
        refresh()
    }

    private func picked(_ result: Result<[URL], Error>) {
        if pickKind == .folder { chooseFolder(result) } else { importJSON(result) }
    }

    private func pick(_ kind: GiriDataPick) {
        pickKind = kind
        pickerShown = true
    }

    private func chooseFolder(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            try GiriAutoBackup.setFolder(url)
            if !monthlyToFolder { destinationRaw = GiriBackupDestination.folder.rawValue }
            refresh()
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func exportJSON() {
        store.run {
            let data = try store.exportBackup()
            let name = "GiriStair-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            shareURL = url
            sharing = true
        }
    }

    private func importJSON(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 32 * 1024 * 1024 else { throw GiriBackupFileError.invalid }
            let data = try Data(contentsOf: url).decompressedBackup()
            guard data.count <= 64 * 1024 * 1024, (try? JSONSerialization.jsonObject(with: data)) != nil else { throw GiriBackupFileError.invalid }
            importData = data
        } catch {
            store.errorMessage = GiriBackupFileError.invalid.localizedDescription
        }
    }
}

private enum GiriDataPick { case backup, folder }

private enum GiriBackupFileError: LocalizedError {
    case invalid
    var errorDescription: String? { "バックアップを読み込めませんでした。GiriStairで書き出したJSON、または自動バックアップのファイルを選んでください。" }
}

/// 詳細データ管理の確認（本体の修飾子を短くするため分ける）。
private struct GiriDataManagementAlerts: ViewModifier {
    @EnvironmentObject private var store: GiriStore
    @Binding var importData: Data?
    @Binding var restorePrevious: Bool
    @Binding var message: String?
    let previous: GiriAutoBackupFile?
    let onRestored: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("JSONから復元しますか？", isPresented: Binding(get: { importData != nil }, set: { if !$0 { importData = nil } })) {
                Button("キャンセル", role: .cancel) { importData = nil }
                Button("復元する", role: .destructive) {
                    if let data = importData {
                        store.run {
                            try store.restoreBackup(data)
                            message = "JSONから復元しました。"
                        }
                    }
                    importData = nil
                    onRestored()
                }
            } message: { Text("今の記録と設定を、選んだバックアップの内容に置き換えます。") }
            .alert("1つ前の自動バックアップから復元しますか？", isPresented: $restorePrevious) {
                Button("キャンセル", role: .cancel) {}
                Button("復元する", role: .destructive) {
                    guard let previous else { return }
                    store.run {
                        try store.restoreBackup(try GiriAutoBackup.data(of: previous))
                        message = GiriDateText.backupDateTime(previous.date) + "の自動バックアップから復元しました。"
                    }
                    onRestored()
                }
            } message: { Text("今の記録と設定を、1つ前の自動バックアップ（\(previous.map { GiriDateText.backupDateTime($0.date) } ?? "—")）の内容に置き換えます。") }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            }
    }
}

// MARK: - 0.19 最近削除した会（30日残す。LiveStair RecentlyDeletedLivesView）

@MainActor
struct GiriRecentlyDeletedEventsView: View {
    @EnvironmentObject private var store: GiriStore
    @State private var purging: GiriDeletedEvent?
    @State private var purgeAll = false

    var body: some View {
        List {
            if store.deletedEvents.isEmpty {
                CenteredEmptyMessage(systemImage: "trash", title: "最近削除した会はありません", message: "削除した会は30日間ここに残ります。")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    AppCardSectionTitle(title: "最近削除した会", systemImage: "trash", accentColor: AppSectionAccent.memo,
                                        infoTitle: "最近削除した会", infoMessage: "削除してから30日たつと完全に削除します。戻すと元の一覧に戻ります。")
                        .listRowSeparator(.hidden)
                    ForEach(store.deletedEvents) { entry in
                        row(entry)
                    }
                    Button(role: .destructive) { purgeAll = true } label: {
                        Text("すべて完全に削除").font(.body)
                    }
                }
                .appSectionCardStyle(accentColor: AppSectionAccent.memo)
            }
        }
        .environment(\.defaultMinListRowHeight, settingsMinimumListRowHeight)
        .appIndexListStyle()
        .giriNavigationBarStyle()
        .navigationTitle("最近削除した会")
        .navigationBarTitleDisplayMode(.inline)
        .alert("完全に削除しますか？", isPresented: Binding(get: { purging != nil }, set: { if !$0 { purging = nil } })) {
            Button("キャンセル", role: .cancel) { purging = nil }
            Button("完全に削除", role: .destructive) {
                if let id = purging?.id { store.run { try store.purgeDeletedEvents(id); playLiveStairDeleteFeedback() } }
                purging = nil
            }
        } message: { Text("この会は元に戻せなくなります。") }
        .alert("すべて完全に削除しますか？", isPresented: $purgeAll) {
            Button("キャンセル", role: .cancel) {}
            Button("完全に削除", role: .destructive) { store.run { try store.purgeDeletedEvents(); playLiveStairDeleteFeedback() } }
        } message: { Text("最近削除した会はすべて元に戻せなくなります。") }
    }

    private func row(_ entry: GiriDeletedEvent) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.event.title.isEmpty ? "名前のない会" : entry.event.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(detailText(entry)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("戻す") {
                store.run { try store.restoreDeletedEvent(entry.id); playLiveStairSaveFeedback() }
            }
            .buttonStyle(.borderless)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(accentActionColor)
        }
        .contextMenu {
            Button("戻す", systemImage: "arrow.uturn.backward") { store.run { try store.restoreDeletedEvent(entry.id) } }
            Button("完全に削除", systemImage: "trash", role: .destructive) { purging = entry }
        }
        .swipeActions {
            Button("完全に削除", role: .destructive) { purging = entry }
        }
    }

    private func detailText(_ entry: GiriDeletedEvent) -> String {
        let days = giriDeletedEventRemainingDays(entry)
        let day = (entry.event.startsAt ?? entry.event.eventDate).map { GiriDateText.day($0, compact: true) }
        return [day, "あと\(days)日"].compactMap { $0 }.joined(separator: "・")
    }
}

// MARK: - 0.19 カレンダーにまとめて追加（LiveStair LiveCalendarBulkExportView）

@MainActor
struct GiriCalendarBulkExportView: View {
    @EnvironmentObject private var store: GiriStore
    @State private var includesPast = false
    @State private var busy = false
    @State private var message: String?

    private var targets: [GiriEvent] { GiriCalendarExport.targets(store.events, includesPast: includesPast) }

    var body: some View {
        List {
            Section {
                AppCardSectionTitle(title: "カレンダーにまとめて追加", systemImage: "calendar.badge.plus", accentColor: AppSectionAccent.live,
                                    infoTitle: "カレンダーに追加", infoMessage: "日付のある会（キャンセル以外）をiPhoneのカレンダーに追加します。追加済みで日時が同じ会は追加しません。")
                    .listRowSeparator(.hidden)
                Toggle("過去の会も追加", isOn: $includesPast).tint(AppSectionAccent.live)
                GiriDataValueRow(title: "追加する会", value: "\(GiriCalendarExport.pending(targets).count)件")
                Button {
                    export()
                } label: {
                    Text(busy ? "追加中…" : "カレンダーに追加").font(.body).foregroundStyle(.primary)
                }
                .disabled(busy || GiriCalendarExport.pending(targets).isEmpty)
            }
            .tint(AppSectionAccent.live)
            .appSectionCardStyle(accentColor: AppSectionAccent.live)
        }
        .environment(\.defaultMinListRowHeight, settingsMinimumListRowHeight)
        .appIndexListStyle()
        .giriNavigationBarStyle()
        .navigationTitle("カレンダーにまとめて追加")
        .navigationBarTitleDisplayMode(.inline)
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        }
    }

    private func export() {
        busy = true
        let events = GiriCalendarExport.pending(targets)
        Task {
            defer { busy = false }
            do {
                let count = try await GiriCalendarExport.export(events)
                playLiveStairSaveFeedback()
                message = "\(count)件の会をカレンダーに追加しました。"
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
    }
}

/// 0.19：ストレージ使用状況。
struct GiriStorageUsage {
    var document = 0
    var images = 0
    var backups = 0
    var spare = 0
    var total: Int { document + backups + spare }
    func text(_ bytes: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }

    @MainActor
    static func measure(store: GiriStore) -> GiriStorageUsage {
        func size(_ url: URL) -> Int { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        var usage = GiriStorageUsage()
        usage.document = size(store.fileURL)
        usage.images = store.notes.reduce(0) { $0 + $1.imageDataBase64.utf8.count } + store.players.reduce(0) { $0 + $1.iconDataBase64.utf8.count }
        usage.backups = GiriAutoBackup.files().reduce(0) { $0 + $1.size }
        usage.spare = size(store.migrationBackupURL) + size(store.directory.appendingPathComponent("giristair.json.bak"))
        return usage
    }
}

// MARK: - 0.19 iPhoneのカレンダー

@MainActor
enum GiriCalendarExport {
    private static let exportedKey = "giriCalendarExported"

    /// 会の予定（開始・終了。時刻がなければ終日）。
    static func makeEvent(_ event: GiriEvent, in eventStore: EKEventStore) -> EKEvent? {
        guard let day = event.startsAt ?? event.eventDate else { return nil }
        let item = EKEvent(eventStore: eventStore)
        item.title = event.title.isEmpty ? "大喜利" : event.title
        item.location = [event.venue, event.venueRoom].filter { !$0.isEmpty }.joined(separator: " ")
        if let start = event.startsAt {
            item.startDate = start
            item.endDate = event.endsAt.flatMap { $0 > start ? $0 : nil } ?? start.addingTimeInterval(2 * 3600)
        } else {
            item.isAllDay = true
            item.startDate = Calendar.current.startOfDay(for: day)
            item.endDate = item.startDate
        }
        var notes = [event.eventFormat.title + "・" + event.meetingTitle]
        if !event.organizer.isEmpty { notes.append("主催：" + event.organizer) }
        if !event.memo.isEmpty { notes.append(event.memo) }
        item.notes = notes.joined(separator: "\n")
        if let url = URL(string: event.siteUrl), url.scheme?.hasPrefix("http") == true { item.url = url }
        return item
    }

    /// 追加の対象（キャンセル以外・日付あり。過去を含めない時は今日以降）。
    static func targets(_ events: [GiriEvent], includesPast: Bool, now: Date = Date()) -> [GiriEvent] {
        let today = Calendar.current.startOfDay(for: now)
        return events.filter { event in
            guard event.status != .canceled, event.eventFormat.hasLiveTiming, let day = event.startsAt ?? event.eventDate else { return false }
            return includesPast || day >= today
        }
    }

    /// まだ追加していない、または日時・名前を変えた会。
    static func pending(_ events: [GiriEvent]) -> [GiriEvent] {
        let exported = exportedSignatures
        return events.filter { exported[$0.id] != signature($0) }
    }

    private static var exportedSignatures: [String: String] {
        (UserDefaults.standard.dictionary(forKey: exportedKey) as? [String: String]) ?? [:]
    }

    private static func signature(_ event: GiriEvent) -> String {
        let day = (event.startsAt ?? event.eventDate).map(GiriDates.timestamp) ?? ""
        return day + "|" + (event.endsAt.map(GiriDates.timestamp) ?? "") + "|" + event.title
    }

    /// まとめて追加する（書き込みだけの許可を求める）。
    static func export(_ events: [GiriEvent]) async throws -> Int {
        let eventStore = EKEventStore()
        guard try await eventStore.requestWriteOnlyAccessToEvents() else {
            throw GiriCalendarExportError.denied
        }
        var exported = exportedSignatures
        var count = 0
        for event in events {
            guard let item = makeEvent(event, in: eventStore) else { continue }
            item.calendar = eventStore.defaultCalendarForNewEvents
            try eventStore.save(item, span: .thisEvent)
            exported[event.id] = signature(event)
            count += 1
        }
        UserDefaults.standard.set(exported, forKey: exportedKey)
        return count
    }
}

enum GiriCalendarExportError: LocalizedError {
    case denied
    var errorDescription: String? { "カレンダーに追加できません。端末の「設定」でGiriStairにカレンダーへの追加を許可してください。" }
}

/// 0.19：1つの会をiPhoneのカレンダーに追加する画面（標準の追加画面。許可は要らない）。
struct GiriCalendarEventEditor: UIViewControllerRepresentable {
    let event: GiriEvent
    let onDone: () -> Void
    private let eventStore = EKEventStore()

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = eventStore
        controller.event = GiriCalendarExport.makeEvent(event, in: eventStore)
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onDone()
        }
    }
}
