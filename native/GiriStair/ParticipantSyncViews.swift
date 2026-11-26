import SwiftUI
import WebKit

// MARK: - 0.36 イベントページのURL読み取り・参加者の確認

enum GiriEventPageFetchError: LocalizedError {
    case invalidURL
    case status(Int)
    case unreadable
    case noContent
    case noParticipants

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URLを確認してください（https:// から始まるページのURL）。"
        case .status(let code):
            return code == 404 ? "ページが見つかりませんでした（消された・公開されていないページかもしれません）。" : "ページを開けませんでした（\(code)）。"
        case .unreadable: return "ページの文字を読めませんでした。"
        case .noContent: return "ページから会の内容を読み取れませんでした。ログインが必要なページは読めません。"
        case .noParticipants: return "ページに参加者の欄が見つかりませんでした。"
        }
    }
}

/// ページを開いて文字を読む。文字が少なく参加者の欄もないページ（開いてから中身を出すページ）は、端末の中で表示してから読む。
@MainActor
enum GiriEventPageFetcher {
    static func document(for url: URL) async throws -> GiriWebDocument {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("ja,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GiriEventPageFetchError.status(http.statusCode)
        }
        let encodingName = response.textEncodingName
        var document = await Task.detached(priority: .userInitiated) {
            giriWebDocument(html: giriDecodeHTMLData(data, textEncodingName: encodingName))
        }.value
        if giriWebDocumentNeedsRendering(document) {
            let loader = GiriRenderedPageLoader()
            if let html = try? await loader.html(for: response.url ?? url) {
                let rendered = await Task.detached(priority: .userInitiated) { giriWebDocument(html: html) }.value
                if rendered.text.count > document.text.count { document = rendered }
            }
        }
        guard !document.lines.isEmpty else { throw GiriEventPageFetchError.noContent }
        return document
    }
}

/// 画面に出さない WebKit でページを開き、表示し終えた後のページ（HTML）を返す。ほかのページの記録は残さない。
@MainActor
final class GiriRenderedPageLoader: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String, Error>?
    private var timeout: Task<Void, Never>?

    func html(for url: URL) async throws -> String {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        view.navigationDelegate = self
        webView = view
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            self.continuation = continuation
            view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
            timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                self?.finish(.failure(GiriEventPageFetchError.unreadable))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 開いてから中身を出すページのために、少し待ってから読む。
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, let view = self.webView else { return }
            view.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, error in
                if let html = result as? String { self?.finish(.success(html)) }
                else { self?.finish(.failure(error ?? GiriEventPageFetchError.unreadable)) }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        continuation.resume(with: result)
    }
}

/// 読んだページから、登録の確認に出す内容を作る（登録済みのプレイヤー・会場・団体と照合し、XのIDの人・別名義を本名義にする）。
@MainActor
func giriReadEventPage(_ document: GiriWebDocument, url: String, store: GiriStore) -> GiriEventPageDraft {
    let known = giriParticipantKnownNames(store)
    let venues = store.venueDirectory.map(\.name)
    let venueRooms = Dictionary(store.venueDirectory.map { ($0.name, store.rooms(forVenue: $0.name)) }, uniquingKeysWith: { first, _ in first })
    let venueAddresses = Dictionary(store.venueDirectory.filter { !$0.mapAddress.isEmpty }.map { ($0.name, $0.mapAddress) },
                                    uniquingKeysWith: { first, _ in first })
    var organizers = store.playerDirectory.map(\.name)
    organizers.append(contentsOf: store.groupDirectory.map(\.name))
    var page = giriEventPageDraft(web: document, url: url, known: known, venues: venues, organizers: organizers,
                                  venueRooms: venueRooms, venueAddresses: venueAddresses)
    page.participants = giriResolvingAliases(giriResolvingHandles(page.participants, owners: store.xAccountOwners), store: store)
    return page
}

/// 確かめている会のページを読み直し、参加者・キャンセル待ちを返す。参加者の欄が見つからない時は、空として扱わずに失敗にする
/// （ページの作りが変わった・ログインが必要になった時に、全員を「減った」にしない）。
@MainActor
func giriFetchParticipantPage(for event: GiriEvent, store: GiriStore) async throws -> GiriParticipantPage {
    guard let sync = event.participantSync, let url = giriEventPageURL(from: sync.url) else { throw GiriEventPageFetchError.invalidURL }
    let document = try await GiriEventPageFetcher.document(for: url)
    guard document.lines.contains(where: { giriParticipantHeader($0.text) != nil }) else { throw GiriEventPageFetchError.noParticipants }
    let draft = giriReadEventPage(document, url: sync.url, store: store)
    return giriParticipantPage(draft, includesReserves: event.eventFormat == .live)
}

@MainActor
enum GiriParticipantWatch {
    /// 会を開いた時：確かめている会ならページを読み直す。会が終わっていたら最後に1回だけ読み、確定してもらう状態にする
    /// （自分が行かなかった会は読まずにやめる）。読めなかった時は、その理由を返す。
    static func refresh(eventID: String, store: GiriStore, force: Bool, now: Date = Date()) async -> String? {
        guard let event = store.events.first(where: { $0.id == eventID }), let sync = event.participantSync, sync.isWatching else { return nil }
        let ended = event.hasEnded(now: now)
        if ended && !event.asksParticipantConfirmation {
            store.run { try store.setParticipantWatchState(.stopped, eventIDs: [eventID]) }
            return nil
        }
        if !ended && !force, let checked = sync.checkedAt, now.timeIntervalSince(checked) < 60 { return nil }
        do {
            let page = try await giriFetchParticipantPage(for: event, store: store)
            store.run { try store.recordParticipantPage(eventID: eventID, page: page, at: Date(), state: ended ? GiriParticipantSyncState.confirming : nil) }
            return nil
        } catch {
            if ended { store.run { try store.recordParticipantPage(eventID: eventID, page: nil, state: .confirming) } }
            return error.localizedDescription
        }
    }
}

/// 増減の確認・終わった会の参加者の確定を開く時の値。
struct GiriParticipantReviewItem: Identifiable, Equatable {
    let eventID: String
    var confirming: Bool
    var readFailed = false
    var id: String { eventID + (confirming ? ":confirm" : ":changes") }
}

// MARK: - URLから読み取り（登録画面）

/// ページのURLを入れて読み、読み取りの確認（GiriEventPageReview）に進む。
struct GiriEventPageURLReader: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var reading = false
    @State private var failure: String?
    @State private var page: GiriEventPageDraft?
    let makeDraft: (String, GiriWebDocument) -> GiriEventPageDraft
    let onApply: (GiriEventPageDraft, Bool) -> Void

    init(initialText: String = "", makeDraft: @escaping (String, GiriWebDocument) -> GiriEventPageDraft,
         onApply: @escaping (GiriEventPageDraft, Bool) -> Void) {
        _text = State(initialValue: initialText)
        self.makeDraft = makeDraft
        self.onApply = onApply
    }

    var body: some View {
        if let page {
            GiriEventPageReview(draft: page, onApply: onApply)
        } else {
            Form {
                Section {
                    AppCardSectionTitle(title: "ページのURL", systemImage: "link", accentColor: AppSectionAccent.scan,
                                        infoTitle: "URLから読み取り",
                                        infoMessage: "ツイプラなどのページの文字から、会の名前・日時・会場・主催・参加費・参加者・ルールを読みます。ログインが必要なページは読めません。")
                        .listRowSeparator(.hidden)
                    TextField("https://twipla.jp/events/…", text: $text, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1...3)
                    PasteButton(payloadType: String.self) { values in
                        Task { @MainActor in
                            text = values.first ?? ""
                            failure = nil
                        }
                    }
                    .labelStyle(.titleAndIcon)
                    if let failure {
                        Label(failure, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(AppSectionAccent.ticket)
                    }
                }.appSectionCardStyle(accentColor: AppSectionAccent.scan)
            }
            .appEditorFormStyle()
            .navigationTitle("URLから読み取り")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if reading {
                        ProgressView()
                    } else {
                        Button("読み取る") { read() }
                            .fontWeight(.bold)
                            .disabled(giriEventPageURL(from: text) == nil)
                    }
                }
            }
        }
    }

    private func read() {
        guard let url = giriEventPageURL(from: text) else {
            failure = GiriEventPageFetchError.invalidURL.errorDescription
            return
        }
        reading = true
        failure = nil
        Task {
            do {
                let document = try await GiriEventPageFetcher.document(for: url)
                let draft = makeDraft(url.absoluteString, document)
                guard draft.hasBasicInfo || !draft.participants.isEmpty else { throw GiriEventPageFetchError.noContent }
                page = draft
            } catch {
                failure = error.localizedDescription
            }
            reading = false
        }
    }
}

// MARK: - 詳細の「ページの参加者」

/// 会の詳細の上の方に出す、ページの参加者の確認（会を開いた時に読み直し、増減と反映するかを出す）。
struct GiriParticipantWatchSection: View {
    @EnvironmentObject private var store: GiriStore
    let eventID: String
    @State private var checking = false
    @State private var failure: String?
    @State private var review: GiriParticipantReviewItem?
    @State private var askingStop = false

    private var event: GiriEvent? { store.events.first { $0.id == eventID } }

    var body: some View {
        if let event, let sync = event.participantSync, sync.state == .watching || sync.state == .confirming {
            let changes = giriRosterChanges(sync, participants: event.participants, reserves: event.reserveNames)
            Section {
                GiriEventCardSectionTitle(title: "ページの参加者", systemImage: "arrow.triangle.2.circlepath", accentColor: AppSectionAccent.scan)
                    .overlay(alignment: .trailing) {
                        AppInfoButton(title: "ページの参加者",
                                      message: "この会を開いた時にページを読み直し、増えた人・減った人を出します。反映するかは選べます。会が終わったら参加者を確定し、ページを見るのをやめます。",
                                      tintColor: AppSectionAccent.scan)
                    }
                    .listRowSeparator(.hidden)
                    .task(id: eventID) { await refresh(force: false) }
                    .sheet(item: $review) { item in
                        NavigationStack {
                            GiriParticipantChangesView(eventID: item.eventID, confirming: item.confirming, readFailed: item.readFailed)
                        }
                    }
                    .alert("ページを確かめるのをやめますか？", isPresented: $askingStop) {
                        Button("キャンセル", role: .cancel) {}
                        Button("やめる", role: .destructive) {
                            store.run { try store.setParticipantWatchState(.stopped, eventIDs: [eventID]) }
                        }
                    } message: {
                        Text("参加者は今のまま残ります。")
                    }
                statusRow(sync)
                if sync.state == .confirming {
                    Text("会が終わりました。最後に読んだページの内容で、参加者を確定してください。")
                        .font(.subheadline)
                    Button { review = GiriParticipantReviewItem(eventID: eventID, confirming: true) } label: {
                        Label("参加者を確定する", systemImage: "checkmark.circle")
                    }
                    .tint(accentActionColor)
                } else if changes.isEmpty {
                    Text(sync.checkedAt == nil ? "まだページを確かめていません。" : "ページの参加者と同じです。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    changeSummary(changes)
                    HStack {
                        Button { review = GiriParticipantReviewItem(eventID: eventID, confirming: false) } label: {
                            Text("選んで反映").fontWeight(.semibold)
                        }
                        .buttonStyle(.borderless)
                        .tint(accentActionColor)
                        Spacer(minLength: 8)
                        Button("反映しない") {
                            store.run { try store.markParticipantChangesDecided(eventID: eventID) }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
                Button("ページを確かめるのをやめる", role: .destructive) { askingStop = true }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
            }
            .appEventDetailCardStyle(accentColor: AppSectionAccent.scan)
        }
    }

    @ViewBuilder private func statusRow(_ sync: GiriParticipantSync) -> some View {
        if checking {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("ページを確かめています").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(AppSectionAccent.ticket)
                }
                HStack(spacing: 8) {
                    Text(sync.checkedAt.map { "最後に確かめた時刻：" + GiriDateText.dateTime($0) } ?? "まだ確かめていません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let count = sync.listedCount {
                        Text("ページの参加者\(count)人").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if sync.isWatching {
                        Button("今すぐ確かめる") { Task { await refresh(force: true) } }
                            .buttonStyle(.borderless)
                            .font(.caption.weight(.semibold))
                            .tint(accentActionColor)
                    }
                }
            }
        }
    }

    @ViewBuilder private func changeSummary(_ changes: GiriRosterChanges) -> some View {
        if !changes.joined.isEmpty { summaryRow("参加者に増えた", changes.joined.map(\.name)) }
        if !changes.left.isEmpty { summaryRow("参加者から減った", changes.left) }
        if !changes.reservesJoined.isEmpty { summaryRow("キャンセル待ちに増えた", changes.reservesJoined.map(\.name)) }
        let promoted = Set(changes.joined.map { playerSearchKey($0.name) })
        let reservesLeft = changes.reservesLeft.filter { !promoted.contains(playerSearchKey($0)) }
        if !reservesLeft.isEmpty { summaryRow("キャンセル待ちから減った", reservesLeft) }
    }

    private func summaryRow(_ title: String, _ names: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .frame(width: 132, alignment: .leading)
            Text(names.joined(separator: "・")).font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func refresh(force: Bool) async {
        guard !checking else { return }
        checking = true
        failure = await GiriParticipantWatch.refresh(eventID: eventID, store: store, force: force)
        checking = false
    }
}

// MARK: - 増減の反映・参加者の確定

/// ページの増減を選んで反映する画面。confirming（会が終わった後）は、参加者を直して確定する画面にする。
struct GiriParticipantChangesView: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    let eventID: String
    let confirming: Bool
    var readFailed = false
    /// 反映しない増減（種類と名前のキー）。
    @State private var excluded: Set<String> = []
    /// 確定の画面で外した参加者・足した参加者。
    @State private var removed: Set<String> = []
    @State private var added: [String] = []
    @State private var newName = ""

    private var event: GiriEvent? { store.events.first { $0.id == eventID } }

    private var changes: GiriRosterChanges {
        guard let event, let sync = event.participantSync else { return GiriRosterChanges() }
        return giriRosterChanges(sync, participants: event.participants, reserves: event.reserveNames)
    }

    /// リザーバー（キャンセル待ち）から参加者になった人。参加者に足すかどうかで、リザーバーから外すかも決める。
    private var promotedKeys: Set<String> {
        let left = Set(changes.reservesLeft.map(playerSearchKey))
        return Set(changes.joined.map { playerSearchKey($0.name) }.filter { left.contains($0) })
    }

    private func changeKey(_ kind: String, _ name: String) -> String { kind + ":" + playerSearchKey(name) }

    private var chosen: GiriRosterChanges {
        var value = changes
        let promoted = promotedKeys
        value.joined.removeAll { excluded.contains(changeKey("joined", $0.name)) }
        value.left.removeAll { excluded.contains(changeKey("left", $0)) }
        value.reservesJoined.removeAll { excluded.contains(changeKey("reserveJoined", $0.name)) }
        value.reservesLeft.removeAll { name in
            let key = playerSearchKey(name)
            return promoted.contains(key) ? excluded.contains(changeKey("joined", name)) : excluded.contains(changeKey("reserveLeft", name))
        }
        return value
    }

    /// 反映した後の会（確定の画面では、手で外した・足した参加者も入れる）。
    private var preview: GiriEvent? {
        guard let event else { return nil }
        var value = giriApplyingRosterChanges(event, chosen, isSelf: store.preferences.isSelf)
        if confirming {
            value.participants.removeAll { removed.contains(playerSearchKey($0)) }
            for name in added where !value.participants.contains(where: { playerSearchKey($0) == playerSearchKey(name) }) {
                value.participants.append(name)
            }
        }
        return value
    }

    var body: some View {
        Form {
            if let event {
                Section {
                    AppCardSectionTitle(title: event.title.isEmpty ? "この会" : event.title, systemImage: "calendar", accentColor: AppSectionAccent.live)
                        .listRowSeparator(.hidden)
                    if let day = event.eventDate ?? event.startsAt {
                        Text(GiriDateText.day(day)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if readFailed {
                        Label("ページを読めませんでした。前に読んだ内容で確認します。", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(AppSectionAccent.ticket)
                    }
                    if let checked = event.participantSync?.checkedAt {
                        Text("ページを読んだ時刻：" + GiriDateText.dateTime(checked)).font(.caption).foregroundStyle(.secondary)
                    }
                }.appSectionCardStyle(accentColor: AppSectionAccent.live)
                changesSection
                if confirming, let preview { rosterSections(preview) }
            }
        }
        .appEditorFormStyle()
        .navigationTitle(confirming ? "参加者の確認" : "参加者の増減")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(confirming ? "後で" : "キャンセル") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(confirming ? "確定" : "反映") { save() }
                    .fontWeight(.bold)
                    .disabled(event == nil)
            }
        }
    }

    @ViewBuilder private var changesSection: some View {
        let current = changes
        let promoted = promotedKeys
        Section {
            AppCardSectionTitle(title: "ページの増減", systemImage: "arrow.triangle.2.circlepath", accentColor: AppSectionAccent.scan,
                                infoTitle: "ページの増減",
                                infoMessage: "前に反映するかを決めた時のページと比べて、増えた人・減った人です。選んだものだけ反映します。")
                .listRowSeparator(.hidden)
            if current.isEmpty {
                Text("前に確かめた時から、ページの参加者は変わっていません。").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(current.joined.enumerated()), id: \.offset) { _, entry in
                changeRow(kind: "joined", name: entry.name,
                          label: promoted.contains(playerSearchKey(entry.name)) ? "繰り上げ" : "増えた", color: AppSectionAccent.artist)
            }
            ForEach(Array(current.left.enumerated()), id: \.offset) { _, name in
                changeRow(kind: "left", name: name, label: "減った", color: AppSectionAccent.ticket)
            }
            ForEach(Array(current.reservesJoined.enumerated()), id: \.offset) { _, entry in
                changeRow(kind: "reserveJoined", name: entry.name, label: "キャンセル待ち", color: AppSectionAccent.venue)
            }
            ForEach(Array(current.reservesLeft.filter { !promoted.contains(playerSearchKey($0)) }.enumerated()), id: \.offset) { _, name in
                changeRow(kind: "reserveLeft", name: name, label: "キャンセル待ちから減った", color: AppSectionAccent.ticket)
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.scan)
    }

    private func changeRow(kind: String, name: String, label: String, color: Color) -> some View {
        let key = changeKey(kind, name)
        let isOn = !excluded.contains(key)
        return Button {
            if isOn { excluded.insert(key) } else { excluded.remove(key) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? accentActionColor : Color.secondary)
                Text(name).foregroundStyle(.primary)
                if store.preferences.isSelf(name) { badge("自分", color: AppSectionAccent.favorite) }
                Spacer(minLength: 8)
                badge(label, color: color)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "\(name)：反映する" : "\(name)：反映しない")
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    /// 確定の画面：反映した後の参加者（手で外す・足す）とリザーバー。
    @ViewBuilder private func rosterSections(_ preview: GiriEvent) -> some View {
        Section {
            HStack {
                AppCardSectionTitle(title: "参加者", systemImage: "person.2", accentColor: AppSectionAccent.artist)
                Spacer(minLength: 8)
                Text("\(preview.participants.count)人").font(.subheadline).foregroundStyle(.secondary)
            }.listRowSeparator(.hidden)
            if preview.participants.isEmpty {
                Text("参加者がいません").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(preview.participants.enumerated()), id: \.offset) { _, name in
                HStack(spacing: 10) {
                    Button { remove(name) } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(name)を外す")
                    Text(name)
                    if store.preferences.isSelf(name) { badge("自分", color: AppSectionAccent.favorite) }
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 8) {
                GiriEditorPlayerField(title: "参加者名", text: $newName, compact: true)
                Button("追加") { add() }
                    .buttonStyle(.borderless)
                    .fontWeight(.semibold)
                    .tint(accentActionColor)
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
        if !preview.reserveNames.isEmpty {
            Section {
                AppCardSectionTitle(title: "リザーバー", systemImage: "person.badge.clock", accentColor: AppSectionAccent.artist)
                    .listRowSeparator(.hidden)
                ForEach(Array(preview.reserveNames.enumerated()), id: \.offset) { index, name in
                    HStack(spacing: 8) {
                        Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22, alignment: .trailing)
                        Text(name)
                    }
                }
            }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
        }
    }

    private func remove(_ name: String) {
        let key = playerSearchKey(name)
        if added.contains(where: { playerSearchKey($0) == key }) { added.removeAll { playerSearchKey($0) == key } }
        else { removed.insert(key) }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let key = playerSearchKey(name)
        removed.remove(key)
        if !added.contains(where: { playerSearchKey($0) == key }) { added.append(name) }
        newName = ""
    }

    private func save() {
        guard let value = preview else { return }
        store.run {
            try store.saveParticipantDecision(value, state: confirming ? GiriParticipantSyncState.confirmed : nil)
            playLiveStairSaveFeedback()
            dismiss()
        }
    }
}
