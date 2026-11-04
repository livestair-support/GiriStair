import SwiftUI
import Vision

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
    static func recognizeLines(_ data: Data) async throws -> [GiriOCRLine] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = true
            let handler = VNImageRequestHandler(data: data, options: [:])
            try handler.perform([request])
            let lines = (request.results ?? []).compactMap { observation -> GiriOCRLine? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                let box = observation.boundingBox
                return GiriOCRLine(text: text, midX: Double(box.midX), midY: Double(1 - box.midY))
            }
            guard !lines.isEmpty else { throw GiriParticipantReadError.noText }
            return lines
        }.value
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
    private let lines: [GiriOCRLine]?
    let onAdd: ([String]) -> Void

    init(source: String = "", lines: [GiriOCRLine]? = nil, onAdd: @escaping ([String]) -> Void) {
        _source = State(initialValue: source)
        self.lines = lines
        self.onAdd = onAdd
    }

    /// 照合に使う名前：プレイヤー一覧（自分・別名義を含む）。
    private var knownNames: [String] {
        [store.preferences.selfName] + store.preferences.selfAliases + store.playerDirectory.map(\.name)
    }
    private var selectedNames: [String] {
        var seen = Set<String>()
        return candidates.filter(\.included).map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(giriOCRNameKey($0)).inserted }
    }

    var body: some View {
        Form {
            if previewing {
                ForEach([GiriParticipantSection.participants, .interested, .other], id: \.self) { section in
                    let indices = candidates.indices.filter { candidates[$0].section == section }
                    if !indices.isEmpty || section == .participants { candidateSection(section, indices: indices) }
                }
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
                        candidates = giriParticipantCandidates(text: source, known: knownNames)
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
                    if !previewing { candidates = giriParticipantCandidates(text: source, known: knownNames) }
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
                candidates = giriParticipantCandidates(lines: lines, known: knownNames)
                previewing = true
            }
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
                    Text(candidate.registered != nil ? "登録済み" : "新規")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(candidate.registered != nil ? AppSectionAccent.artist : Color.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background((candidate.registered != nil ? AppSectionAccent.artist : Color.secondary).opacity(0.12))
                        .clipShape(Capsule())
                }
                if !candidate.source.isEmpty && candidate.source != candidate.name {
                    Text("読み取り：" + candidate.source).font(.caption).foregroundStyle(.secondary)
                }
                if candidate.truncated {
                    Text("名前が途中で切れています。続きを入れてください。").font(.caption).foregroundStyle(AppSectionAccent.ticket)
                }
                if let prefix = candidate.suspiciousPrefix, candidate.name.hasPrefix(prefix) {
                    Button("先頭の「\(prefix)」を外す（アイコンの読み違い）") {
                        candidates[index].name = String(candidates[index].name.dropFirst(prefix.count))
                        candidates[index].suspiciousPrefix = nil
                        candidates[index].registered = giriMatchRegisteredName(candidates[index].name, known: knownNames)
                        if let registered = candidates[index].registered { candidates[index].name = registered }
                    }
                    .font(.caption).buttonStyle(.borderless).tint(accentActionColor)
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
