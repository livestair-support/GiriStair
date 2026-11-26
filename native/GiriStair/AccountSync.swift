import CloudKit
import Combine
import CryptoKit
import Foundation
import UIKit

struct AccountSyncLocalSnapshot {
    let data: Data
    let lastModified: Date?
    let isPristine: Bool
    let deviceName: String
}

struct AccountSyncConflict: Identifiable {
    let id = UUID()
    let cloudName: String
    let cloudDate: Date
    let usesCloud: Bool

    var message: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d H:mm"
        let source = "\(cloudName)（最終更新 \(formatter.string(from: cloudDate))）"
        if usesCloud {
            return "この端末のデータが\(source)の内容で上書きされます。よろしいですか？"
        }
        return "\(source)のデータが、この端末の内容で上書きされます。よろしいですか？"
    }
}

@MainActor
final class AccountSyncCoordinator: ObservableObject {
    @Published private(set) var isLoggedIn: Bool
    @Published private(set) var isBusy = false
    @Published private(set) var isApplying = false
    @Published private(set) var pendingConflict: AccountSyncConflict?
    @Published private(set) var status: String?

    let isAvailable: Bool

    private struct Baseline: Codable {
        let account: String
        let revision: String?
        let deletionGeneration: String?
        let localVersion: String
    }

    private let cloud: AccountSyncCloud?
    private let defaults: UserDefaults
    private let key: String
    private var baseline: Baseline?
    private var localVersion: String
    private var localModified: Date?
    private var makeSnapshot: (@MainActor () async throws -> AccountSyncLocalSnapshot)?
    private var applySnapshot: (@MainActor (Data?) async throws -> Void)?
    private var deviceName: @MainActor () -> String = { UIDevice.current.model }
    private var pendingLogin: (account: String, cloudRevision: String?, localVersion: String)?
    private var isActive = false
    private var isWorking = false
    private var session = UUID()
    private var polling: Task<Void, Never>?
    private var scheduledSync: Task<Void, Never>?
    private var backgroundSync: (token: UUID, id: UIBackgroundTaskIdentifier, work: Task<Void, Never>)?

    init(app: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = "accountSync.\(app)."
        let identifier = Bundle.main.object(forInfoDictionaryKey: "AccountSyncCloudContainer") as? String
        cloud = identifier.map { AccountSyncCloud(containerIdentifier: $0) }
        isAvailable = identifier != nil
        let storedBaseline = defaults.data(forKey: "\(key)baseline")
            .flatMap { try? JSONDecoder().decode(Baseline.self, from: $0) }
        baseline = storedBaseline
        isLoggedIn = isAvailable && storedBaseline != nil
        localVersion = defaults.string(forKey: "\(key)localVersion") ?? ""
        localModified = defaults.object(forKey: "\(key)localModified") as? Date
    }

    func connect(
        snapshot: @escaping @MainActor () async throws -> AccountSyncLocalSnapshot,
        apply: @escaping @MainActor (Data?) async throws -> Void,
        deviceName: @escaping @MainActor () -> String = { UIDevice.current.model }
    ) {
        makeSnapshot = snapshot
        applySnapshot = apply
        self.deviceName = deviceName
        scheduleSync()
    }

    func setActive(_ active: Bool) {
        isActive = active
        polling?.cancel()
        polling = nil
        if active {
            startPolling()
        } else {
            flushBeforeSuspension()
        }
    }

    func localDidChange() {
        guard isAvailable, !isApplying else { return }
        localVersion = UUID().uuidString
        defaults.set(localVersion, forKey: "\(key)localVersion")
        setLocalModified(Date())
        scheduleSync()
    }

    func beginSignIn() async {
        guard !isLoggedIn, let cloud else { return }
        guard !isWorking else {
            status = AccountSyncError.notReady.localizedDescription
            return
        }
        isWorking = true
        isBusy = true
        defer { isWorking = false; isBusy = false }
        status = nil
        do {
            let account = try await cloud.accountIdentifier()
            do {
                try await prepareLogin(account: account, cloud: cloud)
            } catch AccountSyncError.cloudChanged {
                try await prepareLogin(account: account, cloud: cloud)
            }
        } catch {
            status = error.localizedDescription
        }
    }

    func cancelSignIn() {
        pendingConflict = nil
        pendingLogin = nil
        status = nil
    }

    func confirmSignIn() async {
        guard !isLoggedIn, !isWorking, let cloud,
              let conflict = pendingConflict, let candidate = pendingLogin else { return }
        pendingConflict = nil
        pendingLogin = nil
        isWorking = true
        isBusy = true
        defer { isWorking = false; isBusy = false }
        do {
            try await cloud.checkAccount(candidate.account)
            let remote = try await cloud.latest()
            let version = localVersion
            guard let makeSnapshot else { throw AccountSyncError.notReady }
            let local = try await makeSnapshot()
            guard candidate.cloudRevision == remote?.revision,
                  candidate.localVersion == version, version == localVersion else {
                try await prepareLogin(account: candidate.account, cloud: cloud)
                return
            }
            if conflict.usesCloud, let remote {
                try await pull(remote, cloud: cloud, account: candidate.account, localVersion: version)
                finishLogin(account: candidate.account, remote: remote, version: version)
            } else {
                let updated = try await push(local, version: version, replacing: remote, cloud: cloud, account: candidate.account)
                finishLogin(account: candidate.account, remote: updated, version: version)
            }
        } catch AccountSyncError.cloudChanged {
            do {
                try await prepareLogin(account: candidate.account, cloud: cloud)
            } catch {
                status = error.localizedDescription
            }
        } catch {
            status = error.localizedDescription
        }
    }

    func signOut() {
        guard !isBusy, !isApplying else { return }
        clearSession()
        status = nil
    }

    func deleteAllData() async throws {
        guard let cloud, let baseline, isLoggedIn, !isBusy, !isApplying else {
            throw AccountSyncError.notReady
        }
        isBusy = true
        defer { isBusy = false }
        scheduledSync?.cancel()
        while isWorking {
            try await Task.sleep(for: .milliseconds(100))
        }
        isWorking = true
        defer { isWorking = false }
        let version = localVersion
        try await cloud.checkAccount(baseline.account)
        let remote = try await cloud.latest()
        let deleted = try await cloud.save(
            nil, replacing: remote, modified: Date(), deviceName: deviceName(),
            deletionGeneration: UUID().uuidString, account: baseline.account
        )
        try await cloud.checkAccount(baseline.account)
        try await apply(nil)
        setLocalModified(deleted.modified)
        saveBaseline(account: baseline.account, remote: deleted, version: version)
        status = nil
    }

    private func prepareLogin(account: String, cloud: AccountSyncCloud) async throws {
        guard let makeSnapshot else { throw AccountSyncError.notReady }
        let remote = try await cloud.latest()
        let version = localVersion
        let local = try await makeSnapshot()
        guard version == localVersion else { throw AccountSyncError.localChanged }
        try await cloud.checkAccount(account)
        guard version == localVersion else { throw AccountSyncError.localChanged }

        guard let remote else {
            let uploaded = local.isPristine ? nil : try await push(local, version: version, replacing: nil, cloud: cloud, account: account)
            finishLogin(account: account, remote: uploaded, version: version)
            return
        }
        let matches = await remote.matches(local.data)
        guard version == localVersion else { throw AccountSyncError.localChanged }
        if matches || (remote.isDeleted && local.isPristine) {
            setLocalModified(remote.modified)
            finishLogin(account: account, remote: remote, version: version)
        } else {
            pendingLogin = (account, remote.revision, version)
            pendingConflict = AccountSyncConflict(
                cloudName: remote.deviceName, cloudDate: remote.modified,
                usesCloud: (local.isPristine && localModified == nil) || date(for: local) <= remote.modified
            )
        }
    }

    private func finishLogin(account: String, remote: AccountSyncCloud.Record?, version: String) {
        saveBaseline(account: account, remote: remote, version: version)
        isLoggedIn = true
        status = nil
        startPolling()
    }

    private func saveBaseline(account: String, remote: AccountSyncCloud.Record?, version: String) {
        let value = Baseline(
            account: account, revision: remote?.revision,
            deletionGeneration: remote?.deletionGeneration, localVersion: version
        )
        baseline = value
        defaults.set(try? JSONEncoder().encode(value), forKey: "\(key)baseline")
    }

    private func clearSession() {
        session = UUID()
        scheduledSync?.cancel()
        polling?.cancel()
        polling = nil
        if let backgroundSync { finishBackgroundSync(backgroundSync.token, cancel: true) }
        baseline = nil
        defaults.removeObject(forKey: "\(key)baseline")
        isLoggedIn = false
    }

    private func startPolling() {
        guard isActive, isLoggedIn else { return }
        polling?.cancel()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.synchronize()
                do { try await Task.sleep(for: .seconds(20)) }
                catch { return }
            }
        }
    }

    private func scheduleSync() {
        guard isLoggedIn, isActive else { return }
        scheduledSync?.cancel()
        scheduledSync = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) }
            catch { return }
            self?.scheduledSync = nil
            await self?.synchronize()
        }
    }

    private func flushBeforeSuspension() {
        guard let baseline, isLoggedIn, baseline.localVersion != localVersion, backgroundSync == nil else { return }
        scheduledSync?.cancel()
        let token = UUID()
        let id = UIApplication.shared.beginBackgroundTask(withName: "Account sync") { [weak self] in
            self?.finishBackgroundSync(token, cancel: true)
        }
        guard id != .invalid else { return }
        let work = Task { [weak self] in
            guard let self else { return }
            defer { finishBackgroundSync(token, cancel: false) }
            while isWorking {
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            await synchronize(flushing: true)
        }
        backgroundSync = (token, id, work)
    }

    private func finishBackgroundSync(_ token: UUID, cancel: Bool) {
        guard let backgroundSync, token == backgroundSync.token else { return }
        self.backgroundSync = nil
        if cancel { backgroundSync.work.cancel() }
        UIApplication.shared.endBackgroundTask(backgroundSync.id)
    }

    private func synchronize(flushing: Bool = false) async {
        guard let cloud, let baseline, let makeSnapshot, isLoggedIn, isActive || flushing,
              !isWorking, !isBusy else { return }
        isWorking = true
        defer { isWorking = false }
        let currentSession = session
        do {
            try await cloud.checkAccount(baseline.account)
            let remote = try await cloud.latest()
            try checkSession(currentSession)
            let remoteChanged = baseline.revision != remote?.revision
            let version = localVersion
            let localChanged = baseline.localVersion != version
            let deletionChanged = baseline.deletionGeneration != remote?.deletionGeneration

            if let remote, remoteChanged && (deletionChanged || !localChanged) {
                try await pull(remote, cloud: cloud, account: baseline.account, localVersion: version, session: currentSession)
                guard currentSession == session else { return }
                saveBaseline(account: baseline.account, remote: remote, version: version)
            } else if localChanged {
                let local = try await makeSnapshot()
                try checkSession(currentSession)
                guard version == localVersion else { throw AccountSyncError.localChanged }
                let matches = await remote?.matches(local.data) == true
                try checkSession(currentSession)
                guard version == localVersion else { throw AccountSyncError.localChanged }
                if let remote, matches {
                    saveBaseline(account: baseline.account, remote: remote, version: version)
                } else if let remote, remoteChanged, date(for: local) <= remote.modified {
                    try await pull(remote, cloud: cloud, account: baseline.account, localVersion: version, session: currentSession)
                    guard currentSession == session else { return }
                    saveBaseline(account: baseline.account, remote: remote, version: version)
                } else if remote != nil || !remoteChanged {
                    let updated = try await push(local, version: version, replacing: remote, cloud: cloud, account: baseline.account, session: currentSession)
                    saveBaseline(account: baseline.account, remote: updated, version: version)
                } else {
                    // A previously synced record disappeared outside the app. Require explicit login.
                    throw AccountSyncError.cloudRecordRemoved
                }
            } else if remoteChanged {
                throw AccountSyncError.cloudRecordRemoved
            }
            status = nil
        } catch AccountSyncError.accountChanged {
            guard currentSession == session else { return }
            clearSession()
            status = AccountSyncError.accountChanged.localizedDescription
        } catch AccountSyncError.cloudRecordRemoved {
            guard currentSession == session else { return }
            clearSession()
            status = AccountSyncError.cloudRecordRemoved.localizedDescription
        } catch AccountSyncError.localChanged {
            scheduleSync()
        } catch AccountSyncError.cloudChanged {
            scheduleSync()
        } catch is CancellationError {
            return
        } catch {
            if currentSession == session { status = error.localizedDescription }
        }
    }

    private func checkSession(_ expected: UUID?) throws {
        try Task.checkCancellation()
        if let expected, expected != session { throw CancellationError() }
    }

    private func pull(
        _ record: AccountSyncCloud.Record, cloud: AccountSyncCloud, account: String,
        localVersion expectedVersion: String, session: UUID? = nil
    ) async throws {
        let data = record.isDeleted ? nil : try await cloud.payload(for: record)
        try await cloud.checkAccount(account)
        try checkSession(session)
        guard expectedVersion == localVersion else { throw AccountSyncError.localChanged }
        try await apply(data)
        if expectedVersion == localVersion { setLocalModified(record.modified) }
    }

    private func apply(_ data: Data?) async throws {
        guard let applySnapshot else { throw AccountSyncError.notReady }
        isApplying = true
        defer { isApplying = false }
        try await applySnapshot(data)
    }

    private func push(
        _ local: AccountSyncLocalSnapshot, version: String, replacing remote: AccountSyncCloud.Record?,
        cloud: AccountSyncCloud, account: String, session: UUID? = nil
    ) async throws -> AccountSyncCloud.Record {
        try checkSession(session)
        guard version == localVersion else { throw AccountSyncError.localChanged }
        let saved = try await cloud.save(
            local.data, replacing: remote, modified: localModified ?? local.lastModified ?? Date(),
            deviceName: local.deviceName,
            deletionGeneration: remote?.deletionGeneration ?? "initial", account: account
        )
        // Once the server has accepted a save, keep its baseline even if a newer edit
        // cancelled the debounce task while the write was in flight.
        if let session, session != self.session { throw CancellationError() }
        return saved
    }

    private func date(for local: AccountSyncLocalSnapshot) -> Date {
        localModified ?? local.lastModified ?? Date(timeIntervalSince1970: 0)
    }

    private func setLocalModified(_ date: Date) {
        localModified = date
        defaults.set(date, forKey: "\(key)localModified")
    }
}

private enum AccountSyncError: LocalizedError {
    case noAccount, accountUnavailable, accountChanged, notReady, localChanged, cloudChanged, invalidData, cloudRecordRemoved

    var errorDescription: String? {
        switch self {
        case .noAccount: "端末の「設定」でApple Accountにサインインしてからお試しください。"
        case .accountUnavailable: "iCloudに接続できません。通信やiCloudの設定を確認してからお試しください。"
        case .accountChanged: "端末のApple Accountが変更されました。同期するにはもう一度ログインしてください。"
        case .notReady: "同期の準備ができていません。少し待ってからお試しください。"
        case .localChanged: "比較中にこの端末のデータが更新されました。もう一度お試しください。"
        case .cloudChanged: "処理中に別の端末でデータが更新されました。もう一度お試しください。"
        case .invalidData: "iCloudのデータを確認できませんでした。少し待ってからお試しください。"
        case .cloudRecordRemoved: "iCloudの同期データが見つかりません。同期するにはもう一度ログインしてください。"
        }
    }
}

@MainActor
private struct AccountSyncCloud {
    struct Record {
        let record: CKRecord
        let revision: String
        let deletionGeneration: String
        let modified: Date
        let deviceName: String
        let digest: String
        let isDeleted: Bool

        init(_ record: CKRecord) throws {
            guard let revision = record["revision"] as? String,
                  let deletionGeneration = record["deletionGeneration"] as? String,
                  let modified = record["updatedAt"] as? Date,
                  let deviceName = record["deviceName"] as? String,
                  let digest = record["digest"] as? String,
                  let deleted = record["deleted"] as? NSNumber else {
                throw AccountSyncError.invalidData
            }
            self.record = record
            self.revision = revision
            self.deletionGeneration = deletionGeneration
            self.modified = modified
            self.deviceName = deviceName
            self.digest = digest
            isDeleted = deleted.boolValue
        }

        func matches(_ data: Data) async -> Bool {
            guard !isDeleted else { return false }
            let hash = await Task.detached(priority: .utility) { AccountSyncCloud.hash(data) }.value
            return digest == hash
        }
    }

    private let container: CKContainer
    private let id = CKRecord.ID(recordName: "account-snapshot-v1")
    private let fields = ["revision", "deletionGeneration", "updatedAt", "deviceName", "digest", "deleted"]

    init(containerIdentifier: String) {
        container = CKContainer(identifier: containerIdentifier)
    }

    func accountIdentifier() async throws -> String {
        switch try await container.accountStatus() {
        case .available:
            let id = try await container.userRecordID()
            return Self.hash(Data(id.recordName.utf8))
        case .noAccount, .restricted:
            throw AccountSyncError.noAccount
        default:
            throw AccountSyncError.accountUnavailable
        }
    }

    func checkAccount(_ expected: String) async throws {
        do {
            let identifier = try await accountIdentifier()
            guard identifier == expected else { throw AccountSyncError.accountChanged }
        } catch AccountSyncError.noAccount {
            throw AccountSyncError.accountChanged
        }
    }

    func latest() async throws -> Record? {
        do {
            let records = try await container.privateCloudDatabase.records(for: [id], desiredKeys: fields)
            guard let result = records[id] else { throw AccountSyncError.invalidData }
            return try Record(result.get())
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func payload(for record: Record) async throws -> Data {
        let received = try await container.privateCloudDatabase.record(for: id)
        guard try Record(received).revision == record.revision else { throw AccountSyncError.cloudChanged }
        guard let url = (received["payload"] as? CKAsset)?.fileURL else {
            throw AccountSyncError.invalidData
        }
        let data = try await Task.detached(priority: .utility) {
            try Data(contentsOf: url, options: .mappedIfSafe)
        }.value
        guard await record.matches(data) else { throw AccountSyncError.invalidData }
        return data
    }

    func save(
        _ data: Data?, replacing previous: Record?, modified: Date,
        deviceName: String, deletionGeneration: String, account: String
    ) async throws -> Record {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        // Replacing the asset with a one-byte marker removes the previous snapshot on deletion.
        let digest = try await Task.detached(priority: .utility) {
            let contents = data ?? Data([0])
            try contents.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return Self.hash(contents)
        }.value
        try await checkAccount(account)
        try Task.checkCancellation()
        let record = previous?.record ?? CKRecord(recordType: "AccountSnapshot", recordID: id)
        record["payload"] = CKAsset(fileURL: file)
        record["revision"] = UUID().uuidString as NSString
        record["deletionGeneration"] = deletionGeneration as NSString
        record["updatedAt"] = modified as NSDate
        record["deviceName"] = deviceName as NSString
        record["digest"] = digest as NSString
        record["deleted"] = NSNumber(value: data == nil ? 1 : 0)
        do {
            let results = try await container.privateCloudDatabase.modifyRecords(
                saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false
            )
            guard let result = results.saveResults[id] else { throw AccountSyncError.invalidData }
            return try Record(result.get())
        } catch let error as CKError where error.code == .serverRecordChanged {
            throw AccountSyncError.cloudChanged
        }
    }

    nonisolated static func hash(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).base64EncodedString()
    }
}
