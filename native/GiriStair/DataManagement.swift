import SwiftUI
import EventKit
import EventKitUI
import UniformTypeIdentifiers

// MARK: - 0.19 自動バックアップ（LiveStair と同じく1日1回・最新と1つ前の2つ）

/// 自動バックアップの保存先。端末の中か、選んだフォルダ（iCloud Drive など）。
enum GiriBackupDestination: String, CaseIterable, Identifiable {
    case device, folder
    var id: String { rawValue }
    var title: String { self == .device ? "端末" : "iCloud Drive" }
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
    private static let lastMonthlyDateKey = "giriAutoBackupLastMonthlyDate"
    /// 前回、月1回のバックアップをフォルダに保存した日時。
    static var lastMonthlyDate: Date? { UserDefaults.standard.object(forKey: lastMonthlyDateKey) as? Date }
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
            if saved == true {
                UserDefaults.standard.set(month, forKey: lastMonthKey)
                UserDefaults.standard.set(now, forKey: lastMonthlyDateKey)
            }
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

    /// 0.23：端末内の自動バックアップをすべて消す（LiveStair「端末内バックアップを削除」）。消した数を返す。
    @discardableResult
    static func deleteDeviceBackups() -> Int {
        let urls = (try? FileManager.default.contentsOfDirectory(at: deviceFolder, includingPropertiesForKeys: nil)) ?? []
        var count = 0
        for url in urls where url.lastPathComponent.hasPrefix(prefix) {
            if (try? FileManager.default.removeItem(at: url)) != nil { count += 1 }
        }
        return count
    }

    /// 端末内の自動バックアップ（保存先にかかわらず、この端末の中にある分）。
    static func deviceFiles() -> [GiriAutoBackupFile] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: deviceFolder, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix(prefix) }.map { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return GiriAutoBackupFile(url: url, date: values?.contentModificationDate ?? .distantPast, size: values?.fileSize ?? 0)
        }
    }

    /// 0.23：JSONを書き出す時などに作った一時ファイル（GiriStair-…）。
    static func temporaryFiles() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: FileManager.default.temporaryDirectory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix("GiriStair-") }
    }

    @discardableResult
    static func clearTemporaryFiles() -> Int {
        var count = 0
        for url in temporaryFiles() where (try? FileManager.default.removeItem(at: url)) != nil { count += 1 }
        return count
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

// MARK: - 0.23 詳細データ管理（LiveStair DetailDataManagementView と同じ並び・文言。CSV はなし）

private let giriBackupRestoreHelpText = """
【自動バックアップ】
1日1回、最初に開いたときに自動で作ります（設定の「自動バックアップを保存」でも作れます）。登録した画像も含みます。
最新と1つ前の2つを残し、3つ目ができたときにいちばん古いものを削除します。
容量を減らすため、自動バックアップ（月1回の分も含む）は圧縮して保存します。

【保存先】
・端末：この端末の中に保存します。iPhone本体のiCloudバックアップがオンなら、そこにも含まれます。
・iCloud Drive：「ファイル」アプリのiCloud Driveから選んだフォルダに保存します。端末が壊れたり無くしたりしても、ほかの端末から復元できます。

【月1回 iCloud Drive にも保存】
保存先が「端末」のときに選べます。月が変わってから最初に開いたときに、選んだフォルダへバックアップを1つ保存します。

【端末が壊れたとき・ほかの端末へ移すとき】
移行先の端末で「JSONから復元」を選び、iCloud Driveのフォルダにあるバックアップ（GiriStair-auto-… または GiriStair-monthly-… で始まるファイル）を選択してください。

【JSON】
「JSONファイルを書き出す」で、今のデータをJSONファイルとして保存・送信できます。機種変更や別の端末への移行に使えます。移行先の端末で「JSONから復元」を選択してください。
"""

@MainActor
struct GiriDataManagementView: View {
    @EnvironmentObject private var store: GiriStore
    @AppStorage(GiriAutoBackup.destinationKey) private var destinationRaw = GiriBackupDestination.device.rawValue
    @AppStorage(GiriAutoBackup.monthlyKey) private var monthlyToFolder = false
    @State private var backups: [GiriAutoBackupFile] = []
    @State private var deviceBackupCount = 0
    @State private var folderName: String?
    // fileImporter は1つの画面に1つだけ付ける（2つ付けると片方が開かないため、選ぶものを切り替える）。
    @State private var pickKind = GiriDataPick.backup
    @State private var pickerShown = false
    @State private var importData: Data?
    @State private var restorePrevious = false
    @State private var deletingDeviceBackups = false
    @State private var shareURL: URL?
    @State private var sharing = false
    @State private var message: String?

    private var destination: GiriBackupDestination { GiriBackupDestination(rawValue: destinationRaw) ?? .device }

    var body: some View {
        List {
            storageSection
            backupRestoreSection
            fileCleanupSection
            backupCleanupSection
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
        .modifier(GiriDataManagementAlerts(importData: $importData, restorePrevious: $restorePrevious, deletingDeviceBackups: $deletingDeviceBackups,
                                           message: $message, previous: backups.count > 1 ? backups[1] : nil, onRestored: refresh))
        .sheet(isPresented: $sharing) {
            if let shareURL {
                GiriShareSheet(items: [shareURL]) { completed in
                    if completed { store.run { try store.recordBackupExported() } }
                    try? FileManager.default.removeItem(at: shareURL)
                }
            }
        }
    }

    private var storageSection: some View {
        Section {
            AppCardSectionTitle(title: "ストレージ", systemImage: "internaldrive", accentColor: AppSectionAccent.photo)
                .listRowSeparator(.hidden)
            NavigationLink { GiriStorageUsageView() } label: { managementRow("ストレージ使用状況") }
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.photo)
    }

    private var backupRestoreSection: some View {
        Section {
            HStack(spacing: 4) {
                AppCardSectionTitle(title: "バックアップ・復元", systemImage: "clock.arrow.circlepath", accentColor: AppSectionAccent.artist)
                AppInfoButton(title: "バックアップ・復元について", message: giriBackupRestoreHelpText, tintColor: AppSectionAccent.artist)
                Spacer(minLength: 0)
            }
            .listRowSeparator(.hidden)
            destinationRow
            // 端末に保存するときだけ、月1回 iCloud Drive にも保存するかを選べる
            if destination == .device { monthlyRow }
            if destination == .folder || monthlyToFolder { folderRow }
            Button { restorePrevious = true } label: {
                managementRow("1つ前の自動バックアップから復元", textColor: backups.count > 1 ? .primary : .secondary)
            }
            .disabled(backups.count < 2)
            Button { exportJSON() } label: { managementRow("JSONファイルを書き出す") }
            Button { pick(.backup) } label: { managementRow("JSONから復元") }
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    private var destinationRow: some View {
        HStack(spacing: 6) {
            Text("自動バックアップの保存先").font(.body).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Picker("自動バックアップの保存先", selection: Binding(get: { destination }, set: changeDestination)) {
                ForEach(GiriBackupDestination.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(AppSectionAccent.artist)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var monthlyRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(isOn: Binding(get: { monthlyToFolder }, set: { value in
                monthlyToFolder = value
                if value && folderName == nil { pick(.folder) }
            })) {
                Text("月1回 iCloud Drive にも保存").font(.body).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .tint(AppSectionAccent.artist)
            if monthlyToFolder {
                Text(GiriAutoBackup.lastMonthlyDate.map { "前回：" + GiriDateText.backupDateTime($0) } ?? "まだ保存していません")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var folderRow: some View {
        Button { pick(.folder) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("保存フォルダ").font(.body).foregroundStyle(.primary).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(folderName ?? "選ぶ")
                        .font(.subheadline)
                        .foregroundStyle(folderName == nil ? AppSectionAccent.artist : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                if folderName == nil {
                    Text(destination == .folder ? "フォルダを選ぶまでは、端末に保存します。" : "フォルダを選ぶまでは、月1回のバックアップは保存しません。")
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    }

    private var fileCleanupSection: some View {
        Section {
            HStack(spacing: 4) {
                AppCardSectionTitle(title: "ファイル整理", systemImage: "folder", accentColor: AppSectionAccent.memo)
                AppInfoButton(title: "一時ファイルについて",
                              message: "JSONを書き出す際などに作成された一時ファイルを削除します。\n\n書き出したJSONのファイルは、共有画面を閉じたときに自動で削除します。共有画面を開いたままアプリが終了したときなどに残った分は、ここで削除できます。",
                              tintColor: AppSectionAccent.memo)
                Spacer(minLength: 0)
            }
            .listRowSeparator(.hidden)
            Button(role: .destructive) {
                GiriAutoBackup.clearTemporaryFiles()
                message = "一時ファイルを削除しました。"
            } label: { managementRow("一時ファイルを削除", textColor: accentActionColor) }
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.memo)
    }

    private var backupCleanupSection: some View {
        Section {
            AppCardSectionTitle(title: "端末内バックアップ", systemImage: "externaldrive.badge.timemachine", accentColor: AppSectionAccent.ticket)
                .listRowSeparator(.hidden)
            Button(role: .destructive) { deletingDeviceBackups = true } label: {
                managementRow("端末内バックアップを削除", textColor: deviceBackupCount > 0 ? accentActionColor : .secondary)
            }
            .disabled(deviceBackupCount == 0)
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.ticket)
    }

    private func managementRow(_ title: String, textColor: Color = .primary) -> some View {
        Text(title)
            .font(.body)
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

    private func refresh() {
        backups = GiriAutoBackup.files()
        deviceBackupCount = GiriAutoBackup.deviceFiles().count
        folderName = GiriAutoBackup.folderName
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
    @Binding var deletingDeviceBackups: Bool
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
            } message: { Text("今のGiriStairのデータと設定（通知・表示など）を、選んだバックアップの内容に置き換えます。そのあとに登録・編集した内容は元に戻せません。") }
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
            } message: { Text("今のGiriStairのデータと設定（通知・表示など）を、1つ前の自動バックアップ" + (previous.map { "（" + GiriDateText.backupDateTime($0.date) + "）" } ?? "") + "の内容に置き換えます。そのあとに登録・編集した内容は元に戻せません。") }
            .alert("端末内バックアップの削除", isPresented: $deletingDeviceBackups) {
                Button("キャンセル", role: .cancel) {}
                Button("削除する", role: .destructive) {
                    let count = GiriAutoBackup.deleteDeviceBackups()
                    message = count > 0 ? "端末内バックアップを\(count)件削除しました。" : "削除できる端末内バックアップはありません。"
                    onRestored()
                }
            } message: { Text("アプリ内の復元用バックアップをすべて削除します。現在のデータ、画像、設定、ファイルアプリへ書き出したJSONは削除されません。") }
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

// MARK: - 0.23 ストレージ使用状況（LiveStair StorageUsageView）

/// 内訳の1行。
struct GiriStorageEntry: Identifiable {
    var title: String
    var detail: String
    var systemImage: String
    var accent: Color
    var bytes: Int
    var id: String { title }
}

struct GiriStorageSnapshot {
    var entries: [GiriStorageEntry] = []
    var total: Int { entries.reduce(0) { $0 + $1.bytes } }

    @MainActor
    static func measure(store: GiriStore) -> GiriStorageSnapshot {
        func size(_ url: URL) -> Int { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        let documentBytes = size(store.fileURL)
        let promptImages = store.notes.filter { !$0.imageDataBase64.isEmpty }
        let icons = store.players.filter { !$0.iconDataBase64.isEmpty }
        // 画像は記録（JSON）の中に入っているので、記録から画像の分を分けて出す。
        let imageBytes = min(documentBytes, promptImages.reduce(0) { $0 + $1.imageDataBase64.utf8.count } + icons.reduce(0) { $0 + $1.iconDataBase64.utf8.count })
        let backups = GiriAutoBackup.deviceFiles()
        let spare = [store.migrationBackupURL, store.directory.appendingPathComponent("giristair.json.bak")]
        let temporary = GiriAutoBackup.temporaryFiles()
        var snapshot = GiriStorageSnapshot()
        snapshot.entries = [
            GiriStorageEntry(title: "記録と設定", detail: "\(store.events.count)件の会・\(store.notes.count)件のお題・各種設定", systemImage: "doc.text", accent: AppSectionAccent.live, bytes: documentBytes - imageBytes),
            GiriStorageEntry(title: "画像", detail: "お題の画像・アイコン \(promptImages.count + icons.count)枚", systemImage: "photo", accent: AppSectionAccent.photo, bytes: imageBytes),
            GiriStorageEntry(title: "自動バックアップ", detail: "最新と1つ前・登録画像も含む", systemImage: "clock.arrow.circlepath", accent: AppSectionAccent.artist, bytes: backups.reduce(0) { $0 + $1.size }),
            GiriStorageEntry(title: "保存の予備", detail: "前回の保存・移行前のデータ", systemImage: "externaldrive", accent: AppSectionAccent.ticket, bytes: spare.reduce(0) { $0 + size($1) }),
            GiriStorageEntry(title: "一時ファイル", detail: "\(temporary.count)ファイル", systemImage: "folder", accent: AppSectionAccent.memo, bytes: temporary.reduce(0) { $0 + size($1) }),
        ]
        return snapshot
    }
}

@MainActor
struct GiriStorageUsageView: View {
    @EnvironmentObject private var store: GiriStore
    @State private var snapshot = GiriStorageSnapshot()
    @State private var loaded = false

    var body: some View {
        List {
            overviewSection
            if loaded { breakdownSection }
        }
        .environment(\.defaultMinListRowHeight, settingsMinimumListRowHeight)
        .appIndexListStyle()
        .giriNavigationBarStyle()
        .navigationTitle("ストレージ使用状況")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("再集計")
            }
        }
        .onAppear(perform: reload)
        .refreshable { reload() }
    }

    private var overviewSection: some View {
        Section {
            HStack(spacing: 4) {
                AppCardSectionTitle(title: "端末内データ", systemImage: "internaldrive", accentColor: AppSectionAccent.photo)
                AppInfoButton(title: "端末内データについて", message: "アプリ本体を除く、端末内の保存データです。", tintColor: AppSectionAccent.photo)
                Spacer(minLength: 0)
            }
            .listRowSeparator(.hidden)
            HStack(alignment: .firstTextBaseline) {
                Text("GiriStairデータ").font(.body).foregroundStyle(.primary)
                Spacer()
                Text(sizeText(snapshot.total)).font(.title3.bold()).foregroundStyle(AppSectionAccent.photo).monospacedDigit()
            }
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.photo)
    }

    private var breakdownSection: some View {
        Section {
            HStack(spacing: 4) {
                AppCardSectionTitle(title: "使用量の内訳", systemImage: "chart.bar", accentColor: AppSectionAccent.memo)
                AppInfoButton(title: "使用量について",
                              message: "表示している容量は、GiriStairが確認できるファイルから計算した目安です。iOSのストレージ画面には、アプリ本体やシステムが管理している領域も含まれるため、一致しない場合があります。\n\n「自動バックアップ」は、端末に保存した自動バックアップ（最新と1つ前の2つ）です。保存先を「iCloud Drive」にしている場合、iCloud Driveに保存した分はここに含まれません。",
                              tintColor: AppSectionAccent.memo)
                Spacer(minLength: 0)
            }
            .listRowSeparator(.hidden)
            ForEach(snapshot.entries) { entry in row(entry) }
        }
        .appSectionCardStyle(accentColor: AppSectionAccent.memo)
    }

    private func row(_ entry: GiriStorageEntry) -> some View {
        let ratio = snapshot.total > 0 ? Double(entry.bytes) / Double(snapshot.total) : 0
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: entry.systemImage)
                    .font(.system(size: appFontSize(16), weight: .semibold))
                    .foregroundStyle(entry.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title).font(.body).foregroundStyle(.primary)
                    Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(sizeText(entry.bytes)).font(.subheadline.bold()).foregroundStyle(.primary).monospacedDigit()
                    Text(percentText(ratio)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(entry.accent).frame(width: proxy.size.width * CGFloat(min(max(ratio, 0), 1)))
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 4)
    }

    private func reload() {
        snapshot = GiriStorageSnapshot.measure(store: store)
        loaded = true
    }

    private func sizeText(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func percentText(_ ratio: Double) -> String {
        guard ratio > 0 else { return "0%" }
        if ratio < 0.001 { return "<0.1%" }
        return String(format: "%.1f%%", ratio * 100)
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
