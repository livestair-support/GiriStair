import SwiftUI
import UIKit
import Vision
import ImageIO

enum GiriParticipantReadError: LocalizedError {
    case unreadable
    case noText
    var errorDescription: String? {
        switch self {
        case .unreadable: return "画像を読み込めませんでした。別の画像を選んでください。"
        case .noText: return "画像から文字を読み取れませんでした。文字が鮮明な画像を選んでください。"
        }
    }
}

enum GiriParticipantOCR {
    static func recognize(_ data: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = true
            let handler = VNImageRequestHandler(data: data, options: [:])
            try handler.perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GiriParticipantReadError.noText }
            return text
        }.value
    }

    /// 文字と位置（トーナメント表の並びを決めるため）。位置は 0〜1、上が 0。
    /// ページ全体のような縦長の画面は、小さい文字（参加者の名前など）が読めるように縦に分けて読み取る。
    static func recognizeLines(_ data: Data) async throws -> [GiriOCRLine] {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return try GiriParticipantOCR.recognizeWholeImage(data)
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let orientation = (properties?[kCGImagePropertyOrientation] as? UInt32).flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up
            let width = image.width, height = image.height
            let tileHeight = max(1, Int(Double(width) * 1.5))
            // 回転している写真や、縦長ではない画面はそのまま読む。
            guard orientation == .up, width > 0, height > tileHeight * 5 / 4 else { return try GiriParticipantOCR.recognizeWholeImage(data) }
            let step = max(1, tileHeight * 4 / 5)
            var lines: [GiriOCRLine] = []
            var top = 0
            while top < height {
                let tileTop = min(top, max(0, height - tileHeight))
                let tileRect = CGRect(x: 0, y: tileTop, width: width, height: min(tileHeight, height - tileTop))
                if let tile = image.cropping(to: tileRect) {
                    let isFirst = tileTop == 0, isLast = tileTop + Int(tileRect.height) >= height
                    for observation in try GiriParticipantOCR.observations(in: tile) {
                        guard let text = observation.topCandidates(1).first?.string else { continue }
                        let box = observation.boundingBox
                        // 切れ目にかかった行は、重なっている隣の部分で読む。
                        let fromTop = 1 - box.maxY, fromBottom = box.minY
                        if !isFirst && fromTop < 0.02 { continue }
                        if !isLast && fromBottom < 0.02 { continue }
                        let tileH = Double(tileRect.height)
                        let midY = (Double(tileTop) + (1 - Double(box.midY)) * tileH) / Double(height)
                        lines.append(GiriOCRLine(text: text, midX: Double(box.midX), midY: midY, height: Double(box.height) * tileH / Double(height), minX: Double(box.minX)))
                    }
                }
                if tileTop + tileHeight >= height { break }
                top += step
            }
            let merged = giriMergeTileLines(lines)
            guard !merged.isEmpty else { throw GiriParticipantReadError.noText }
            return merged
        }.value
    }

    private static func textRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        // 既定（画像の高さの1/32）より小さい文字も読む。
        request.minimumTextHeight = 0.01
        return request
    }

    private static func observations(in image: CGImage) throws -> [VNRecognizedTextObservation] {
        let request = textRequest()
        try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
        return request.results ?? []
    }

    private static func recognizeWholeImage(_ data: Data) throws -> [GiriOCRLine] {
        let request = textRequest()
        try VNImageRequestHandler(data: data, options: [:]).perform([request])
        let lines = (request.results ?? []).compactMap { observation -> GiriOCRLine? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return GiriOCRLine(text: text, midX: Double(box.midX), midY: Double(1 - box.midY), height: Double(box.height), minX: Double(box.minX))
        }
        guard !lines.isEmpty else { throw GiriParticipantReadError.noText }
        return lines
    }
}

/// 参加者の一括追加。貼り付けた文章・読み取った画面から、参加者の欄だけを選び、
/// 登録済みのプレイヤーと照合してから追加する（LiveStair の読み取り確認と同じく、反映前に確認する）。
struct GiriParticipantImport: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    @State private var source: String
    @State private var candidates: [GiriParticipantCandidate] = []
    @State private var previewing = false
    @State private var loaded = false
    /// 0.25：ページに書いてある参加者の人数。
    @State private var listedCount: Int?
    private let lines: [GiriOCRLine]?
    /// 今の参加者。同じ人は「追加済み」にして、重ならないようにする。
    private let existing: [String]
    let onAdd: ([String]) -> Void

    init(source: String = "", lines: [GiriOCRLine]? = nil, existing: [String] = [], onAdd: @escaping ([String]) -> Void) {
        _source = State(initialValue: source)
        self.lines = lines
        self.existing = existing
        self.onAdd = onAdd
    }

    /// 照合に使う名前：プレイヤー一覧（自分・別名義を含む）。
    private var knownNames: [String] { giriParticipantKnownNames(store) }
    private var selectedNames: [String] { giriSelectedParticipantNames(candidates) }

    private func read(_ text: String) -> [GiriParticipantCandidate] {
        listedCount = giriListedParticipantCount(text.components(separatedBy: .newlines))
        return giriMarkingAlreadyAdded(giriResolvingAliases(giriParticipantCandidates(text: text, known: knownNames), store: store),
                                existing: giriResolvedNames(existing, store: store))
    }

    var body: some View {
        Form {
            if previewing {
                GiriParticipantCandidateSections(candidates: $candidates, knownNames: knownNames, listedCount: listedCount)
                Section {
                    DisclosureGroup("読み取った原文") {
                        Text(source).font(.footnote.monospaced()).textSelection(.enabled).padding(.vertical, 6)
                    }
                    Button("文章に戻る") { previewing = false }
                }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
            } else {
                Section {
                    AppCardSectionTitle(title: "参加者を読み込む", systemImage: "text.viewfinder", accentColor: AppSectionAccent.artist)
                        .listRowSeparator(.hidden)
                    Text("ツイプラ・noteなどの参加者一覧を貼り付けてください。「参加者」「興味あり」の見出しがあれば、参加者の欄だけを選びます。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    TextEditor(text: $source).frame(minHeight: 220).scrollContentBackground(.hidden)
                    Button("名前を確認") {
                        candidates = read(source)
                        previewing = true
                    }.disabled(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            }
        }
        .appEditorFormStyle()
        .navigationTitle("参加者を一括追加")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(previewing ? "\(selectedNames.count)人を追加" : "追加") {
                    if !previewing { candidates = read(source) }
                    let names = selectedNames
                    guard !names.isEmpty else { return }
                    onAdd(names)
                    dismiss()
                }
                .fontWeight(.bold)
                .disabled(previewing ? selectedNames.isEmpty : source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let lines {
                // 画面の読み取りは、文字の位置から欄を分けてから確認に進む。
                source = lines.sorted { abs($0.midY - $1.midY) < 0.004 ? $0.midX < $1.midX : $0.midY < $1.midY }.map(\.text).joined(separator: "\n")
                listedCount = giriListedParticipantCount(source.components(separatedBy: .newlines))
                candidates = giriMarkingAlreadyAdded(giriResolvingAliases(giriParticipantCandidates(lines: lines, known: knownNames), store: store),
                                                     existing: giriResolvedNames(existing, store: store))
                previewing = true
            }
        }
    }
}

/// 照合に使う名前：プレイヤー一覧（自分を含む）と別名義。よく参加者に出る人を先にする
/// （「…」で切れた名前の候補が複数ある時は、先に並んだ人を選ぶ）。
@MainActor
func giriParticipantKnownNames(_ store: GiriStore) -> [String] {
    var counts: [String: Int] = [:]
    for event in store.events {
        for name in event.participants + event.teams.flatMap(\.members) { counts[playerSearchKey(name), default: 0] += 1 }
    }
    var names = [store.preferences.selfName]
    names.append(contentsOf: store.preferences.selfAliases)
    let players = store.playerDirectory.map(\.name)
    names.append(contentsOf: players.sorted { (counts[playerSearchKey($0)] ?? 0) > (counts[playerSearchKey($1)] ?? 0) })
    // 別名義も照合し、読み取った後で本名義にする。
    for player in store.players { names.append(contentsOf: player.aliases) }
    // 0.29：Xの表示名・IDでも照合し、読み取った後でその人の名前にする。
    // 0.30：リンクのXの名前・IDも含める。
    for player in store.players { names.append(contentsOf: player.xMatchNames) }
    return names
}

/// 別名義で読み取った名前を本名義にする（同じ人が重なったら1つにする）。
@MainActor
func giriResolvingAliases(_ candidates: [GiriParticipantCandidate], store: GiriStore) -> [GiriParticipantCandidate] {
    let owners = store.mergedAliasOwners
    let xOwners = store.xAccountOwners
    var seen = Set<String>()
    var output: [GiriParticipantCandidate] = []
    for candidate in candidates {
        var value = candidate
        if let owner = owners[playerSearchKey(value.name)] ?? xOwners[playerSearchKey(value.name)] {
            value.name = owner
            value.registered = owner
            value.truncated = false
        }
        guard seen.insert(giriOCRNameKey(value.name)).inserted else { continue }
        output.append(value)
    }
    return output
}

/// 今の参加者（別名義は本名義にして比べる）。
@MainActor
func giriResolvedNames(_ names: [String], store: GiriStore) -> [String] {
    let owners = store.mergedAliasOwners
    let xOwners = store.xAccountOwners
    return names.map { owners[playerSearchKey($0)] ?? xOwners[playerSearchKey($0)] ?? $0 }
}

/// 読み取った参加者の確認（参加者・興味あり・不参加などの欄ごと）。参加者の一括追加とイベントページの読み取りで共通。
struct GiriParticipantCandidateSections: View {
    @Binding var candidates: [GiriParticipantCandidate]
    let knownNames: [String]
    /// 0.25：ページに書いてある参加者の人数（分かる時だけ。読み取った人数と比べて出す）。
    var listedCount: Int? = nil

    var body: some View {
        ForEach([GiriParticipantSection.participants, .interested, .other], id: \.self) { section in
            let indices = candidates.indices.filter { candidates[$0].section == section }
            if !indices.isEmpty || section == .participants { candidateSection(section, indices: indices) }
        }
    }

    private func candidateSection(_ section: GiriParticipantSection, indices: [Int]) -> some View {
        Section {
            HStack {
                AppCardSectionTitle(title: section.title, systemImage: section == .participants ? "person.2" : "person.crop.circle.badge.questionmark",
                                    accentColor: AppSectionAccent.artist,
                                    infoTitle: section == .participants ? "読み取りについて" : nil,
                                    infoMessage: section == .participants ? "登録済みのプレイヤーと照合しています。アイコンや「…」の読み違いは直してから追加してください。" : nil)
                Spacer(minLength: 8)
                Text("\(indices.filter { candidates[$0].included }.count)/\(indices.count)人").font(.caption).foregroundStyle(.secondary)
            }.listRowSeparator(.hidden)
            if indices.isEmpty {
                Text("参加者を読み取れませんでした").font(.subheadline).foregroundStyle(.secondary)
            }
            if section == .participants, let listedCount {
                let read = indices.filter { candidates[$0].included }.count
                Label(read == listedCount ? "ページの参加者\(listedCount)人と同じ人数です" : "ページには参加者\(listedCount)人と書いてあります（選んでいるのは\(read)人）",
                      systemImage: read == listedCount ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(read == listedCount ? Color.secondary : AppSectionAccent.ticket)
            }
            ForEach(indices, id: \.self) { index in candidateRow(index) }
            if section == .participants {
                Button {
                    candidates.append(GiriParticipantCandidate(id: (candidates.map(\.id).max() ?? -1) + 1, source: "", name: "", registered: nil,
                                                               truncated: false, suspiciousPrefix: nil, section: .participants, included: true))
                } label: { Label("名前を追加", systemImage: "plus.circle") }
                .tint(accentActionColor)
            }
        }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
    }

    private func candidateRow(_ index: Int) -> some View {
        let candidate = candidates[index]
        return HStack(alignment: .top, spacing: 10) {
            Button { candidates[index].included.toggle() } label: {
                Image(systemName: candidate.included ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(candidate.included ? accentActionColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(candidate.included ? "追加しない" : "追加する")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    TextField("名前", text: nameBinding(index))
                    Text(candidate.alreadyAdded ? "追加済み" : candidate.registered != nil ? "登録済み" : "新規")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(candidate.registered != nil && !candidate.alreadyAdded ? AppSectionAccent.artist : Color.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background((candidate.registered != nil && !candidate.alreadyAdded ? AppSectionAccent.artist : Color.secondary).opacity(0.12))
                        .clipShape(Capsule())
                }
                if candidate.truncated {
                    Text("名前が途中で切れています。続きを入れてください。").font(.caption).foregroundStyle(AppSectionAccent.ticket)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// 名前を直したら、登録済みのプレイヤーと照合し直す（表示は直した名前のまま）。
    private func nameBinding(_ index: Int) -> Binding<String> {
        Binding(get: { candidates.indices.contains(index) ? candidates[index].name : "" }, set: { value in
            guard candidates.indices.contains(index) else { return }
            candidates[index].name = value
            let key = giriOCRNameKey(value)
            candidates[index].registered = knownNames.first { giriOCRNameKey($0) == key && !key.isEmpty }
            candidates[index].truncated = false
        })
    }
}

func giriParseParticipantNames(_ source: String) -> [String] {
    let separators = CharacterSet(charactersIn: "\r\n,，、\t")
    var seen = Set<String>()
    return source.components(separatedBy: separators).compactMap { line in
        var name = line.trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.replacingOccurrences(of: #"^\s*(?:[-・●○■□▪︎•]\s*|[0-9０-９]+[.．)）:：]\s*)"#, with: "", options: .regularExpression)
        if name.hasPrefix("@") { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name.range(of: #"^(?:https?://|www\.)"#, options: [.regularExpression, .caseInsensitive]) == nil,
              name.range(of: #"^(?:参加者(?:一覧)?|参加予定(?:者)?|参加(?:する)?人|参加者名|名前|参加者リスト|キャンセル待ち)(?:\s*(?:[（(]\s*[0-9０-９]+\s*人?[)）]|[0-9０-９]+\s*人))?\s*[:：]?$"#, options: .regularExpression) == nil,
              seen.insert(giriEditorNameKey(name)).inserted else { return nil }
        return name
    }
}

/// イベントページの読み取り結果の確認（LiveStair EventOCRReviewSheet と同じく、反映する前に確認する）。
/// 参加者は当日まで変わるので、今の参加者と重なる人は「追加済み」にして追加しない。
struct GiriEventPageReview: View {
    @EnvironmentObject private var store: GiriStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GiriEventPageDraft
    @State private var replaceExisting = false
    @State private var copied = false
    let onApply: (GiriEventPageDraft, Bool) -> Void

    init(draft: GiriEventPageDraft, onApply: @escaping (GiriEventPageDraft, Bool) -> Void) {
        _draft = State(initialValue: draft)
        self.onApply = onApply
    }

    /// 0.30：参加形式（個人戦・タッグ・チーム戦・即席タッグ・チーム戦）。タッグの読み取り（2人）は残す。
    private var formatChoice: Binding<String> {
        Binding(get: {
            guard let format = draft.tournamentFormat, format != .individual else { return "individual" }
            return draft.impromptuTeams ? "impromptu" : "team"
        }, set: { choice in
            if choice == "individual" {
                draft.tournamentFormat = .individual
                draft.impromptuTeams = false
            } else {
                if draft.tournamentFormat == nil || draft.tournamentFormat == .individual { draft.tournamentFormat = .team }
                draft.impromptuTeams = choice == "impromptu"
            }
        })
    }

    var body: some View {
        Form {
            Section {
                AppCardSectionTitle(title: "基本情報", systemImage: "slider.horizontal.3", accentColor: AppSectionAccent.live)
                    .listRowSeparator(.hidden)
                valueRow("会の名前", draft.title)
                // 0.29：ページの書き方から推した会の種類・参加形式。ここで選び直せる。
                Picker(selection: Binding(get: { draft.meetingKind ?? "casual" }, set: { draft.meetingKind = $0 == "casual" ? nil : $0 })) {
                    ForEach(["casual", "tournament", "project", "kumite", "show"], id: \.self) { Text(giriMeetingKindTitle($0)).tag($0) }
                } label: { reviewLabel("会の種類") }
                .pickerStyle(.menu).tint(.primary)
                if draft.meetingKind == "tournament" {
                    // 0.30：タッグとチーム戦は人数だけの違いなので「タッグ・チーム戦」にまとめ、即席を分ける。
                    Picker(selection: formatChoice) {
                        Text("個人戦").tag("individual")
                        Text("タッグ・チーム戦").tag("team")
                        Text("即席タッグ・チーム戦").tag("impromptu")
                    } label: { reviewLabel("参加形式") }
                    .pickerStyle(.menu).tint(.primary)
                }
                valueRow("日付", draft.date.map { GiriDateText.day($0) } ?? "")
                valueRow("開場", clockText(draft.opens))
                valueRow("開始", clockText(draft.start))
                valueRow("終了", clockText(draft.end))
                valueRow("会場", draft.venue)
                if !draft.venueRoom.isEmpty { valueRow("部屋", draft.venueRoom) }
                valueRow("主催", draft.organizer)
                // 0.30：説明に書いてあった共催。
                if !draft.coOrganizers.isEmpty { valueRow("共催", draft.coOrganizers.joined(separator: "・")) }
                valueRow("参加費", draft.fee.map { "\($0)円" } ?? "")
            }.appSectionCardStyle(accentColor: AppSectionAccent.live)
            GiriParticipantCandidateSections(candidates: $draft.participants, knownNames: giriParticipantKnownNames(store), listedCount: draft.listedParticipantCount)
            // 0.29：説明・コメントに書いてあったチーム（タッグ）。
            if !draft.teams.isEmpty {
                Section {
                    AppCardSectionTitle(title: draft.tournamentFormat == .pair ? "タッグ" : "チーム", systemImage: "person.3", accentColor: AppSectionAccent.artist)
                        .listRowSeparator(.hidden)
                    ForEach(draft.teams) { team in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(team.name).font(.subheadline.weight(.semibold))
                            Text(team.members.joined(separator: "・")).font(.caption).foregroundStyle(.secondary)
                        }
                        .swipeActions { Button("外す", role: .destructive) { draft.teams.removeAll { $0.id == team.id } } }
                    }
                }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            }
            // 0.29：説明に書いてあったルール（反映すると、保存する時にルール一覧へ登録する）。
            if let rule = draft.rule {
                Section {
                    AppCardSectionTitle(title: "ルール", systemImage: "list.bullet.rectangle", accentColor: AppSectionAccent.ticket)
                        .listRowSeparator(.hidden)
                    GiriRuleDetailRows(rule: rule)
                    Button("このルールは使わない", role: .destructive) { draft.rule = nil }.buttonStyle(.borderless).font(.subheadline)
                }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
            }
            Section {
                Toggle("入力済みの内容も置き換える", isOn: $replaceExisting).tint(AppSectionAccent.scan)
                Text(replaceExisting ? "読み取った内容を優先して反映します。読み取れなかった項目は、今の入力が残ります。"
                                     : "空欄への入力と、重ならない参加者の追加を中心に反映します。")
                    .font(.caption).foregroundStyle(.secondary)
            }.appSectionCardStyle(accentColor: AppSectionAccent.scan)
            Section {
                DisclosureGroup("読み取った原文") {
                    Text(draft.recognizedText).font(.footnote.monospaced()).textSelection(.enabled).padding(.vertical, 6)
                    Button {
                        UIPasteboard.general.string = draft.recognizedText
                        copied = true
                    } label: {
                        Label(copied ? "コピーしました" : "読み取り結果をコピー", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }.appSectionCardStyle(accentColor: AppSectionAccent.memo)
        }
        .appEditorFormStyle()
        .navigationTitle("イベントページOCR")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("反映") {
                    onApply(draft, replaceExisting)
                    dismiss()
                }
                .fontWeight(.bold)
            }
        }
    }

    private func reviewLabel(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
    }

    /// LiveStair reviewValueRow：読み取れなかった項目は灰色で出す。
    private func valueRow(_ title: String, _ value: String) -> some View {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(text.isEmpty ? "読み取れませんでした" : text)
                .foregroundStyle(text.isEmpty ? Color.secondary : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func clockText(_ clock: GiriClock?) -> String {
        guard let clock else { return "" }
        return "\(clock.hour):" + String(format: "%02d", clock.minute)
    }
}
